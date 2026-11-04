# TicketOnChain

**TicketOnChain** è un progetto Web3 per la creazione, l'acquisto e la rivendita di biglietti rappresentati da NFT ERC-721.

Il progetto è **agent-native**: non mantiene un frontend web tradizionale. Gli agenti AI possono consultare eventi, biglietti e annunci di rivendita tramite un server [Model Context Protocol (MCP)](mcp/README.md), che legge i dati direttamente dalla blockchain.

> **Stato del progetto:** prototipo in sviluppo. Il server MCP attuale è di sola lettura: non firma né invia transazioni. I contratti e il servizio non devono essere usati per gestire fondi reali prima di una revisione indipendente e di una verifica completa su rete di prova.

## Indice

- [Architettura](#architettura)
- [Funzionalità](#funzionalità)
- [Regole economiche](#regole-economiche)
- [Amministrazione e sicurezza](#amministrazione-e-sicurezza)
- [Struttura del repository](#struttura-del-repository)
- [Avvio rapido](#avvio-rapido)
- [Server MCP](#server-mcp)
- [Verifiche e limiti](#verifiche-e-limiti)
- [Documentazione legale](#documentazione-legale)

## Architettura

```text
Utente
  |
  v
Agente AI / client MCP
  |
  v
TicketOnChain MCP  ---- viem + RPC ----> Ethereum
                                      |       |
                                      v       v
                                MercatoTicket  TicketOnChain
```

Il sistema è composto da:

- **`TicketOnChain.sol`**: contratto NFT ERC-721. Il mercato autorizzato crea e distrugge i biglietti e controlla i trasferimenti.
- **`MercatoTicket.sol`**: gestisce eventi, acquisti, rivendite, ingressi, commissioni, saldi e rimborsi.
- **Server MCP**: espone agli agenti strumenti standard per leggere i dati dei contratti. Non custodisce chiavi private e non invia transazioni.

## Funzionalità

- Creazione eventi da parte di organizzatori autorizzati.
- Acquisto di biglietti NFT.
- Rivendita vincolata al prezzo originariamente pagato.
- Sospensione separata delle vendite iniziali e della rivendita.
- Convalida on-chain degli ingressi, utilizzabile una sola volta per biglietto.
- Due politiche di rimborso selezionabili dall'organizzatore.
- Accredito dei rimborsi e degli incassi su saldi prelevabili.
- Consultazione tramite MCP di eventi, biglietti, wallet e annunci di rivendita.

## Regole economiche

### Prezzi e commissioni

La commissione predefinita è **1,5%** (150 punti base), applicata sia agli acquisti iniziali sia alle rivendite. L'acquirente la paga in aggiunta al prezzo del biglietto. La commissione può essere modificata dall'amministratore fino a un massimo del 10%.

Le gas fee della rete sono separate dalla commissione TicketOnChain e vengono pagate dal wallet che invia la transazione.

### Rivendita

- Il prezzo di rivendita deve essere esattamente uguale al prezzo originario del biglietto.
- Il venditore riceve il prezzo intero; la commissione viene pagata in aggiunta dall'acquirente.
- Il biglietto resta custodito dal contratto di mercato fino alla vendita o all'annullamento dell'annuncio.
- La rivendita può essere disabilitata dall'organizzatore per il singolo evento.

### Politiche di rimborso

Alla creazione dell'evento l'organizzatore sceglie una delle due politiche:

- **`FondiBloccati` (0):** il prezzo dei biglietti iniziali resta nel contratto fino all'inizio dell'evento. Se l'organizzatore annulla prima dell'inizio, il contratto avvia automaticamente i rimborsi.
- **`IncassiAnticipati` (1):** il prezzo dei biglietti iniziali diventa subito prelevabile dall'organizzatore. In caso di annullamento, l'organizzatore deve versare nel contratto l'intero importo dei prezzi iniziali venduti per finanziare i rimborsi.

I rimborsi sono elaborati in lotti tecnici da massimo 20 biglietti per transazione. Gli importi vengono accreditati come saldi prelevabili: il beneficiario deve poi chiamare `prelevaSaldo()`. La commissione TicketOnChain non è inclusa nel rimborso.

## Amministrazione e sicurezza

- Le funzioni amministrative sono protette da `onlyOwner`.
- **Non esistono cooldown o governance delay amministrativi:** autorizzazioni, modifiche delle commissioni, cambio del destinatario delle commissioni, prelievo delle commissioni e sospensione/riattivazione del mercato sono immediati per il proprietario.
- La sospensione del mercato è quindi disponibile anche per la risposta immediata a un incidente.
- Il trasferimento della proprietà usa `Ownable2Step`: il nuovo proprietario deve accettare il passaggio.
- La rinuncia alla proprietà amministrativa è disabilitata.
- Le regole temporali degli eventi restano distinte dai ritardi amministrativi: gli acquisti e le rivendite si chiudono all'inizio dell'evento e la convalida degli ingressi è consentita nella finestra dell'evento.

Queste misure non garantiscono l'assenza di vulnerabilità e non sostituiscono un audit indipendente.

## Struttura del repository

```text
.
├── contracts/
│   ├── MercatoTicket.sol
│   └── TicketOnChain.sol
├── test/
│   ├── MercatoTicketPermessi.t.sol
│   ├── MercatoTicketFuzzSicurezza.t.sol
│   ├── MercatoTicketInvariant.t.sol
│   ├── MercatoTicketReentrancy.t.sol
│   ├── MercatoTicketRimborsi.t.sol
│   └── TicketOnChainSicurezza.t.sol
├── mcp/
│   ├── src/server.js
│   ├── .env.example
│   └── README.md
├── docs/
│   └── CONDIZIONI-D-USO-BOZZA.md
├── foundry.toml
└── README.md
```

## Avvio rapido

### Requisiti

- [Foundry](https://book.getfoundry.sh/)
- Git
- Node.js 22+ e npm per il server MCP

### Contratti e test

Dalla root del repository:

```bash
forge install foundry-rs/forge-std@v1.9.7
forge install OpenZeppelin/openzeppelin-contracts@v5.1.0
forge build
forge test -vvv
```

Per eseguire anche 1.000 iterazioni per ciascun test fuzz:

```bash
forge test -vvv --fuzz-runs 1000
```

### Server MCP

La guida completa per configurazione, trasporto STDIO, Streamable HTTP e MCP Inspector è in [mcp/README.md](mcp/README.md).

In breve:

```bash
cd mcp
cp .env.example .env
# Configura RPC_URL, MARKET_ADDRESS e NFT_ADDRESS
npm install
npm run check
npm start
```

Per provare gli strumenti con MCP Inspector:

```bash
npm run inspect
```

Il server espone attualmente strumenti di consultazione: ricerca eventi, dettagli evento, dettagli biglietto, panoramica wallet, annunci di rivendita e preventivo informativo di acquisto. Il preventivo non invia una transazione.

## Verifiche e limiti

La GitHub Actions esegue compilazione Foundry, test unitari/fuzz, coverage e analisi statica Slither. I test automatici sono controlli di regressione: **non equivalgono a un audit** e non dimostrano che i contratti siano privi di vulnerabilità.

Limiti attuali da tenere presenti:

- Il server MCP è read-only: acquisti, creazione eventi, rivendite, convalida, prelievi e rimborsi non sono ancora eseguibili tramite MCP.
- Il limite è di 6 biglietti cumulativi per wallet e per evento, non per persona; wallet diversi possono aggirarlo.
- La ricerca MCP usa scansioni di ID progressivi e il limite configurabile `MCP_MAX_SCAN`; non è un indicizzatore storico completo.
- L'integrazione di un sistema di identità è rimandata.
- Prima di un utilizzo reale servono revisione indipendente, test su rete di prova, verifica delle procedure operative e revisione legale.

## Documentazione legale

La bozza delle condizioni d'uso è disponibile in [docs/CONDIZIONI-D-USO-BOZZA.md](docs/CONDIZIONI-D-USO-BOZZA.md). È un documento di lavoro e non deve essere pubblicato come testo definitivo senza revisione legale.

Prima del lancio in Italia occorre verificare, tra gli altri aspetti, gli obblighi informativi dell'organizzatore e della piattaforma, il regime applicabile al secondary ticketing e l'eventuale disciplina dei servizi di pagamento. Le diciture del progetto non eliminano obblighi inderogabili né garantiscono un'esenzione da responsabilità.
