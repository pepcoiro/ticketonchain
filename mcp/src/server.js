import "dotenv/config";
import { createServer } from "node:http";
import { McpServer, createMcpHandler } from "@modelcontextprotocol/server";
import { toNodeHandler, localhostHostValidation, localhostOriginValidation } from "@modelcontextprotocol/node";
import { serveStdio } from "@modelcontextprotocol/server/stdio";
import { createPublicClient, formatEther, http, isAddress, parseAbi } from "viem";
import { z } from "zod";

const MARKET = process.env.MARKET_ADDRESS;
const NFT = process.env.NFT_ADDRESS;
const RPC = process.env.RPC_URL;
const MAX_SCAN = Math.min(Math.max(Number(process.env.MCP_MAX_SCAN || 100), 1), 500);
const client = RPC ? createPublicClient({ transport: http(RPC) }) : null;

const marketAbi = parseAbi([
  "function eventi(uint256) view returns (address organizzatore,string nome,string uriMetadatiBase,uint256 timestampInizio,uint256 timestampFine,uint8 politicaRimborso,uint256 prezzo,uint256 quantitaMassima,uint256 bigliettiVenduti,bool attivo,bool annullato)",
  "function prossimoIdEvento() view returns (uint256)",
  "function prossimoIdBiglietto() view returns (uint256)",
  "function commissionePuntiBase() view returns (uint256)",
  "function LIMITE_BIGLIETTI_PER_WALLET() view returns (uint256)",
  "function bigliettiAcquistatiPerWallet(uint256,address) view returns (uint256)",
  "function saldiPrelevabili(address) view returns (uint256)",
  "function rivendite(uint256) view returns (address venditore,uint256 prezzo,bool attivo)",
  "function rivenditaAttiva(uint256) view returns (bool)",
  "function ingressiUtilizzati(uint256) view returns (bool)",
  "function bigliettiRimborsati(uint256) view returns (bool)",
  "function prezzoAcquistoOriginale(uint256) view returns (uint256)",
  "function eventoDelBiglietto(uint256) view returns (uint256)",
  "function paused() view returns (bool)"
]);
const nftAbi = parseAbi([
  "function ownerOf(uint256) view returns (address)",
  "function tokenURI(uint256) view returns (string)",
  "function balanceOf(address) view returns (uint256)"
]);
const addressSchema = z.string().refine(isAddress, "Indirizzo Ethereum non valido");
const idSchema = z.number().int().positive().safe();

function requireConfig() {
  if (!client || !RPC) throw new Error("Imposta RPC_URL nel file mcp/.env.");
  if (!MARKET || !isAddress(MARKET)) throw new Error("Imposta un MARKET_ADDRESS valido nel file mcp/.env.");
  if (!NFT || !isAddress(NFT)) throw new Error("Imposta un NFT_ADDRESS valido nel file mcp/.env.");
}
function result(data) {
  return { content: [{ type: "text", text: JSON.stringify(data, (_, value) => typeof value === "bigint" ? value.toString() : value, 2) }] };
}
function safeTool(server, name, config, fn) {
  server.registerTool(name, config, async (args) => {
    try {
      requireConfig();
      return result(await fn(args));
    } catch (error) {
      return { isError: true, content: [{ type: "text", text: error instanceof Error ? error.message : String(error) }] };
    }
  });
}
async function readMarket(functionName, args = []) {
  return client.readContract({ address: MARKET, abi: marketAbi, functionName, args });
}
async function readEvent(id) {
  const row = await readMarket("eventi", [BigInt(id)]);
  const [organizer, name, metadataURI, start, end, refundPolicy, price, capacity, sold, active, cancelled] = row;
  return {
    id: Number(id), organizer, name, metadataURI,
    startUnix: start.toString(), endUnix: end.toString(),
    start: new Date(Number(start) * 1000).toISOString(),
    end: new Date(Number(end) * 1000).toISOString(),
    refundPolicy: Number(refundPolicy) === 0 ? "FondiBloccati" : "IncassiAnticipati",
    priceWei: price.toString(), priceEth: formatEther(price),
    capacity: Number(capacity), sold: Number(sold),
    available: Number(capacity - sold), active, cancelled
  };
}
function makeServer() {
  const server = new McpServer({
    name: "ticketonchain",
    version: "0.1.0",
    instructions: "TicketOnChain è un servizio di biglietteria su Ethereum. Verifica sempre i dati on-chain prima di rispondere. Gli strumenti di questa versione sono di sola lettura: non dichiarare mai completati acquisti o prenotazioni."
  });

  safeTool(server, "search_events", {
    description: "Cerca eventi registrati nel contratto TicketOnChain.",
    inputSchema: z.object({
      query: z.string().optional(),
      fromId: idSchema.optional(),
      limit: z.number().int().min(1).max(25).default(10),
      includeInactive: z.boolean().default(false)
    })
  }, async ({ query, fromId = 1, limit, includeInactive }) => {
    const next = await readMarket("prossimoIdEvento");
    const last = next - 1n;
    if (last < 1n) return { results: [], totalKnown: 0 };
    const start = BigInt(fromId);
    const end = last < start + BigInt(MAX_SCAN) - 1n ? last : start + BigInt(MAX_SCAN) - 1n;
    const needle = query?.trim().toLocaleLowerCase("it-IT");
    const results = [];
    for (let id = start; id <= end && results.length < limit; id++) {
      const event = await readEvent(id);
      if (!includeInactive && (!event.active || event.cancelled || event.available === 0)) continue;
      if (needle && !event.name.toLocaleLowerCase("it-IT").includes(needle)) continue;
      results.push(event);
    }
    return { results, scannedFrom: start.toString(), scannedTo: end.toString(), totalKnown: Number(last), truncated: end < last };
  });

  safeTool(server, "get_event_details", {
    description: "Legge i dettagli aggiornati di un evento, le commissioni e lo stato della rivendita.",
    inputSchema: z.object({ eventId: idSchema })
  }, async ({ eventId }) => {
    const [event, fee, paused, resale] = await Promise.all([
      readEvent(eventId), readMarket("commissionePuntiBase"), readMarket("paused"), readMarket("rivenditaAttiva", [BigInt(eventId)])
    ]);
    return { ...event, feeBasisPoints: Number(fee), feePercent: Number(fee) / 100, marketPaused: paused, resaleEnabled: resale };
  });

  safeTool(server, "get_ticket_details", {
    description: "Verifica proprietario, metadati e stato di un biglietto NFT.",
    inputSchema: z.object({ ticketId: idSchema })
  }, async ({ ticketId }) => {
    const [owner, tokenURI, eventId, price, used, refunded, resale] = await Promise.all([
      client.readContract({ address: NFT, abi: nftAbi, functionName: "ownerOf", args: [BigInt(ticketId)] }),
      client.readContract({ address: NFT, abi: nftAbi, functionName: "tokenURI", args: [BigInt(ticketId)] }),
      readMarket("eventoDelBiglietto", [BigInt(ticketId)]),
      readMarket("prezzoAcquistoOriginale", [BigInt(ticketId)]),
      readMarket("ingressiUtilizzati", [BigInt(ticketId)]),
      readMarket("bigliettiRimborsati", [BigInt(ticketId)]),
      readMarket("rivendite", [BigInt(ticketId)])
    ]);
    const [seller, resalePrice, resaleActive] = resale;
    return {
      ticketId, owner, tokenURI, eventId: Number(eventId),
      originalPriceWei: price.toString(), originalPriceEth: formatEther(price),
      entryUsed: used, refunded,
      resaleActive, resaleSeller: resaleActive ? seller : null,
      resalePriceWei: resaleActive ? resalePrice.toString() : null
    };
  });

  safeTool(server, "get_wallet_overview", {
    description: "Mostra saldo ETH, numero di NFT posseduti e saldo prelevabile registrato nel mercato.",
    inputSchema: z.object({ walletAddress: addressSchema })
  }, async ({ walletAddress }) => {
    const [balance, tickets, withdrawable] = await Promise.all([
      client.getBalance({ address: walletAddress }),
      client.readContract({ address: NFT, abi: nftAbi, functionName: "balanceOf", args: [walletAddress] }),
      readMarket("saldiPrelevabili", [walletAddress])
    ]);
    return {
      walletAddress, ethBalanceWei: balance.toString(), ethBalance: formatEther(balance),
      ticketCount: Number(tickets), withdrawableWei: withdrawable.toString(), withdrawableEth: formatEther(withdrawable),
      note: "Il contratto NFT non implementa ERC721Enumerable: questo strumento restituisce il conteggio, non gli ID dei biglietti."
    };
  });

  safeTool(server, "search_resale_listings", {
    description: "Cerca biglietti attualmente in rivendita, entro il limite di scansione configurato.",
    inputSchema: z.object({
      eventId: idSchema.optional(),
      fromTicketId: idSchema.optional(),
      limit: z.number().int().min(1).max(25).default(10)
    })
  }, async ({ eventId, fromTicketId = 1, limit }) => {
    const next = await readMarket("prossimoIdBiglietto");
    const last = next - 1n;
    if (last < 1n) return { results: [], totalKnown: 0 };
    const start = BigInt(fromTicketId);
    const end = last < start + BigInt(MAX_SCAN) - 1n ? last : start + BigInt(MAX_SCAN) - 1n;
    const results = [];
    for (let id = start; id <= end && results.length < limit; id++) {
      const [seller, price, active] = await readMarket("rivendite", [id]);
      if (!active) continue;
      const relatedEvent = await readMarket("eventoDelBiglietto", [id]);
      if (eventId !== undefined && relatedEvent !== BigInt(eventId)) continue;
      results.push({ ticketId: Number(id), eventId: Number(relatedEvent), seller, priceWei: price.toString(), priceEth: formatEther(price) });
    }
    return { results, scannedFrom: start.toString(), scannedTo: end.toString(), totalKnown: Number(last), truncated: end < last };
  });

  safeTool(server, "quote_ticket_purchase", {
    description: "Calcola prezzo e commissione correnti per un biglietto. Non effettua acquisti.",
    inputSchema: z.object({ eventId: idSchema, buyerAddress: addressSchema.optional() })
  }, async ({ eventId, buyerAddress }) => {
    const [event, fee, paused] = await Promise.all([readEvent(eventId), readMarket("commissionePuntiBase"), readMarket("paused")]);
    if (paused || !event.active || event.cancelled || event.available <= 0) throw new Error("Evento non acquistabile.");
    if (BigInt(event.startUnix) <= BigInt(Math.floor(Date.now() / 1000))) throw new Error("Le vendite sono chiuse: l'evento è iniziato.");
    const price = BigInt(event.priceWei);
    const feeAmount = price * fee / 10000n;
    let walletLimit = null;
    if (buyerAddress) {
      const [count, maximum] = await Promise.all([
        readMarket("bigliettiAcquistatiPerWallet", [BigInt(eventId), buyerAddress]),
        readMarket("LIMITE_BIGLIETTI_PER_WALLET")
      ]);
      walletLimit = { purchased: Number(count), maximum: Number(maximum), remaining: Number(maximum - count) };
      if (count >= maximum) throw new Error("Il wallet ha raggiunto il limite cumulativo per evento.");
    }
    return {
      eventId, eventName: event.name,
      ticketPriceWei: price.toString(), ticketPriceEth: formatEther(price),
      tocFeeWei: feeAmount.toString(), tocFeeEth: formatEther(feeAmount),
      totalWei: (price + feeAmount).toString(), totalEth: formatEther(price + feeAmount),
      feePercent: Number(fee) / 100,
      gas: "Escluso: viene stimato dal wallet al momento della transazione.",
      walletLimit
    };
  });

  return server;
}

const transport = (process.env.MCP_TRANSPORT || "stdio").toLowerCase();

if (transport === "stdio") {
  const handle = serveStdio(makeServer);
  console.error("TicketOnChain MCP avviato su stdio.");
  process.on("SIGINT", () => void handle.close());
} else if (transport === "http") {
  const host = process.env.MCP_HOST || "127.0.0.1";
  const port = Number(process.env.MCP_PORT || 3333);
  const token = process.env.MCP_AUTH_TOKEN;
  const loopback = ["127.0.0.1", "localhost", "::1"].includes(host);

  if (!loopback && (!token || token.length < 32)) {
    throw new Error("Per un bind pubblico configura MCP_AUTH_TOKEN con almeno 32 caratteri e termina TLS su un reverse proxy HTTPS.");
  }

  const handler = createMcpHandler(makeServer);
  const nodeHandler = toNodeHandler(handler);
  const validateHost = loopback ? localhostHostValidation() : null;
  const validateOrigin = loopback ? localhostOriginValidation() : null;

  const httpServer = createServer((req, res) => {
    if (req.url?.split("?")[0] !== "/mcp") {
      res.writeHead(404).end("Not found");
      return;
    }
    if (validateHost && !validateHost(req, res)) return;
    if (validateOrigin && !validateOrigin(req, res)) return;
    if (token && req.headers.authorization !== "Bearer " + token) {
      res.writeHead(401, { "WWW-Authenticate": "Bearer" }).end("Unauthorized");
      return;
    }
    void nodeHandler(req, res);
  });

  httpServer.listen(port, host, () => {
    console.error("TicketOnChain MCP Streamable HTTP su http://" + host + ":" + port + "/mcp");
  });
} else {
  throw new Error("MCP_TRANSPORT deve essere 'stdio' oppure 'http'.");
}
