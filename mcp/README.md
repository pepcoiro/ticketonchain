# TicketOnChain MCP

TicketOnChain è un servizio **agent-native**: gli agenti AI usano i contratti Solidity esistenti tramite Model Context Protocol (MCP). Non è previsto un frontend web.

## Strumenti disponibili

- `search_events`
- `get_event_details`
- `get_ticket_details`
- `get_wallet_overview`
- `search_resale_listings`
- `quote_ticket_purchase`

Le letture interrogano direttamente la blockchain. In questa prima versione non vengono inviate transazioni: le operazioni di scrittura richiederanno un flusso di autorizzazione e firma compatibile con wallet esterni.

## Requisiti e configurazione

- Node.js 22+
- npm
- RPC Ethereum
- Contratti TicketOnChain e MercatoTicket distribuiti sulla stessa rete

Da Linux Mint, nella cartella del repository:

```bash
cd mcp
cp .env.example .env
nano .env
```

Imposta `RPC_URL`, `MARKET_ADDRESS` e `NFT_ADDRESS`. Per i primi test usa Sepolia e gli indirizzi effettivamente distribuiti su Sepolia: gli indirizzi di un'altra rete non funzionano.

Installa e verifica:

```bash
npm install
npm run check
```

## Test locale con MCP Inspector (stdio)

Avvia:

```bash
npm start
```

In un secondo terminale:

```bash
npm run inspect
```

Apri l'indirizzo mostrato da Inspector, premi **Connect** e vai in **Tools**. Prova:
1. `search_events` con `limit=10`;
2. `get_event_details` con un ID restituito;
3. `get_ticket_details` con un ID di biglietto esistente;
4. `get_wallet_overview` con un indirizzo pubblico;
5. `search_resale_listings`;
6. `quote_ticket_purchase` con l'ID di un evento e, facoltativamente, un wallet di test.

Non serve un wallet per provare gli strumenti di consultazione.

## Collegare un agente tramite stdio

Configura il client MCP dell'agente per avviare:
- comando: `node`;
- argomento: percorso assoluto a `mcp/src/server.js`;
- directory di lavoro: `mcp`;
- variabili d'ambiente: quelle definite nel file `.env`.

La configurazione specifica cambia tra ChatGPT, Claude, IDE e altri host; il server espone strumenti MCP standard e non dipende dal modello AI.

## Streamable HTTP per client remoti

Per provare HTTP in locale, modifica `.env`:

```env
MCP_TRANSPORT=http
MCP_HOST=127.0.0.1
MCP_PORT=3333
```

Avvia `npm start`. Endpoint MCP: `http://127.0.0.1:3333/mcp`.

Per un endpoint accessibile da Internet:
- imposta `MCP_HOST=0.0.0.0`;
- imposta `MCP_AUTH_TOKEN` con almeno 32 caratteri casuali;
- termina HTTPS su un reverse proxy;
- non esporre il server senza autenticazione.

Il bearer token è una protezione iniziale per test e deploy privati, non un sistema di identità per utenti finali. Prima di un servizio pubblico serve OAuth 2.1, autorizzazione per utente, rate limiting e logging.

## Limiti noti

- Non effettua deploy e non sceglie automaticamente la rete.
- ERC-721 non implementa ERC721Enumerable: il wallet overview mostra il conteggio, non gli ID posseduti.
- Ricerca eventi e rivendite usa ID progressivi e rispetta `MCP_MAX_SCAN`.
- Le scritture (creazione eventi, acquisto, rivendita, convalida, prelievi e rimborsi) saranno aggiunte dopo aver definito l'autorizzazione del wallet dell'utente.
- Il limite di acquisto del contratto è per wallet, non per persona.
- Il progetto Solidity è un prototipo; i test automatici non sostituiscono un audit indipendente.

## Architettura

```text
AI agent
   | MCP stdio (locale) / Streamable HTTP (remoto)
   v
TicketOnChain MCP
   | viem + RPC
   v
MercatoTicket + TicketOnChain
   |
   v
Ethereum
```
