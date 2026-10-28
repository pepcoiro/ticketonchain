# TicketOnChain

Progetto Web3 per la creazione, l'acquisto e la rivendita regolamentata di biglietti NFT.

## Contratti

- `contracts/TicketOnChain.sol`: NFT ERC-721 dei biglietti. Solo il mercato configurato può creare o trasferire NFT tra proprietari.
- `contracts/MercatoTicket.sol`: registrazione eventi, vendita iniziale, custodia dei biglietti in rivendita, acquisti e gestione dei saldi e delle commissioni.

I nomi delle funzioni e i commenti del progetto sono in italiano per rendere il codice più comprensibile durante lo sviluppo.

## Configurazione locale

Il progetto usa Foundry e OpenZeppelin Contracts 5.

1. Installa [Foundry](https://book.getfoundry.sh/getting-started/installation).
2. Dalla cartella del progetto, installa le dipendenze:

```bash
forge install OpenZeppelin/openzeppelin-contracts@v5.0.2 --no-commit
forge install foundry-rs/forge-std --no-commit
```

3. Esegui i test:

```bash
forge test -vv
```

## Ordine di pubblicazione su una rete di prova

1. Pubblica `TicketOnChain`.
2. Pubblica `MercatoTicket` passando al costruttore l'indirizzo del contratto NFT.
3. Dal proprietario di `TicketOnChain`, esegui `impostaMercato(indirizzoMercato)`.
4. Crea un evento e prova acquisto, approvazione, rivendita e prelievo.

**Attenzione:** l'indirizzo del mercato può essere impostato una sola volta. Controlla l'indirizzo prima di confermare la transazione. Non usare fondi reali finché compilazione, test e revisione di sicurezza non sono completati.

## Metadati

Per un evento con URI base `ipfs://CID/`, il mercato associa al biglietto con identificativo 12 l'URI `ipfs://CID/12.json`. I file JSON devono esistere e rispettare il formato dei metadati NFT previsto dal progetto.

## Stato

Prototipo in sviluppo. I test sono stati aggiunti al repository, ma devono essere eseguiti in un ambiente con Foundry e le dipendenze installate prima di considerare il codice verificato.
