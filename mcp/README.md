# TicketOnChain MCP

TicketOnChain è un servizio **agent-native**: gli agenti AI usano i contratti Solidity esistenti tramite Model Context Protocol (MCP). Non è previsto un frontend web.

## Strumenti disponibili (prima versione, sola lettura)

- `search_events`
- `get_event_details`
- `get_ticket_details`
- `get_wallet_overview`
- `search_resale_listings`
- `quote_ticket_purchase`

Il server interroga direttamente i contratti tramite viem e un RPC Ethereum. In questa prima versione non invia transazioni e non gestisce chiavi private. Le operazioni di scrittura richiederanno un flusso di autorizzazione e firma compatibile con wallet esterni.

## Requisiti e configurazione

- Node.js 22+
- npm
- RPC Ethereum
- Contratti TicketOnChain e MercatoTicket già distribuiti sulla stessa rete

Da Linux Mint, nella cartella del repository:

```bash
cd mcp
cp .env.example .env
nano .env
```

Imposta `RPC_URL`, `MARKET_ADDRESS` e `NFT_ADDRESS`. Per i primi test usa Sepolia e gli indirizzi effettivamente distribuiti su Sepolia: gli indirizzi di un'altra rete non funzionano.

Installa e avvia:

```bash
npm install
npm run check
npm start
```

Il server usa stdio: il processo resta in attesa di un client MCP. I log sono scritti su stderr, stdout è riservato al protocollo.

## Test con MCP Inspector

Apri un secondo terminale:

```bash
cd mcp
npm run inspect
```

Apri l'indirizzo locale mostrato da Inspector, premi **Connect** e vai nella scheda **Tools**. Prova:
1. `search_events` con `limit=10`;
2. `get_event_details` con un ID restituito;
3. `quote_ticket_purchase` con un ID evento e, facoltativamente, un wallet Sepolia;
4. `get_wallet_overview` con un indirizzo pubblico;
5. `search_resale_listings`.

Non serve un wallet per provare gli strumenti di lettura. Per la quotazione, il wallet è facoltativo e serve solo a verificare il limite cumulativo per indirizzo.

## Collegamento a un agente

Configura il client MCP dell'agente per avviare:
- comando: `node`;
- argomento: percorso assoluto a `mcp/src/server.js`;
- directory di lavoro: `mcp`;
- variabili d'ambiente: quelle del file `.env`.

La configurazione specifica cambia tra ChatGPT, Claude, IDE e altri host; il server espone strumenti MCP standard e non dipende dal modello AI.

## Limiti noti

- Non esegue deploy e non sceglie automaticamente la rete.
- ERC-721 non implementa ERC721Enumerable: il wallet overview mostra il conteggio, non gli ID posseduti.
- Ricerca eventi e rivendite usa ID progressivi e rispetta `MCP_MAX_SCAN`.
- Le scritture (creazione eventi, acquisto, rivendita, convalida, prelievi e rimborsi) saranno aggiunte dopo aver definito l'autorizzazione del wallet dell'utente.
- Il limite di acquisto del contratto è per wallet, non per persona.
- Il progetto Solidity è un prototipo; i test automatici non sostituiscono un audit indipendente.

## Architettura

```text
AI agent
   | MCP stdio
   v
TicketOnChain MCP
   | viem + RPC
   v
MercatoTicket + TicketOnChain
   |
   v
Ethereum
```
