# TicketOnChain

Progetto Web3 per la creazione, l'acquisto e la rivendita regolamentata di biglietti NFT.

## Contratti

- `contracts/TicketOnChain.sol`: NFT ERC-721 dei biglietti. Solo il mercato configurato può creare o trasferire NFT tra proprietari.
- `contracts/MercatoTicket.sol`: registrazione e annullamento eventi, vendita iniziale, custodia dei biglietti in rivendita, acquisti e gestione dei saldi e delle commissioni.

## Verifica delle persone e limite di acquisto

Il mercato richiede la verifica tramite il registro Cross-Chain Proof of Humanity v2. Prima di abilitare le vendite, il proprietario deve chiamare `impostaVerificatoreUmanita(indirizzo)` con l'indirizzo ufficiale del registro cross-chain corretto per la rete di deployment. L'indirizzo può essere impostato una sola volta; gli acquisti iniziali e le rivendite sono bloccati se il registro non è configurato o se l'acquirente non risulta una persona verificata.

Ogni persona può acquistare al massimo 6 biglietti per evento. Il conteggio è associato all'identificativo umano restituito da `humanityOf(wallet)`, non al singolo wallet, e si applica sia agli acquisti iniziali sia alle rivendite. È un conteggio cumulativo: vendere o trasferire un biglietto non restituisce capacità di acquisto.

La rivendita è consentita esclusivamente al prezzo originariamente pagato per quel biglietto: non sono ammessi né sovrapprezzi né sconti. Il prezzo originario viene registrato on-chain al momento del primo acquisto e resta invariato nelle rivendite successive.

La verifica on-chain riduce l'aggiramento del limite tramite wallet multipli, ma non elimina ogni possibile frode e dipende dalla correttezza, disponibilità e semantica del registro esterno. Prima del deployment occorre confermare l'indirizzo del registro per la rete scelta e testare l'integrazione.

## Annullamento degli eventi

L'organizzatore può annullare definitivamente un evento tramite `annullaEvento(idEvento)`. L'annullamento blocca nuove vendite, nuove rivendite e la convalida degli ingressi. Non è previsto un rimborso automatico dal contratto: la gestione dei rimborsi è a carico dell'organizzatore, secondo le condizioni applicabili. La piattaforma non anticipa fondi propri.

I nomi delle funzioni e i commenti del progetto sono in italiano per rendere il codice più comprensibile durante lo sviluppo.

## Sviluppo

In questa fase il progetto è dedicato all'implementazione dei contratti. Le verifiche automatiche e i test verranno reintrodotti in una fase successiva.

## Ordine di pubblicazione su una rete di prova

1. Pubblica `TicketOnChain`.
2. Pubblica `MercatoTicket` passando al costruttore l'indirizzo del contratto NFT.
3. Dal proprietario di `TicketOnChain`, esegui `impostaMercato(indirizzoMercato)`.
4. Crea un evento e prova acquisto, approvazione, rivendita e prelievo.

**Attenzione:** l'indirizzo del mercato può essere impostato una sola volta. Controlla l'indirizzo prima di confermare la transazione.

## Metadati

Per un evento con URI base `ipfs://CID/`, il mercato associa al biglietto con identificativo 12 l'URI `ipfs://CID/12.json`. I file JSON devono esistere e rispettare il formato dei metadati NFT previsto dal progetto.

## Stato

Prototipo in sviluppo. In questa fase si stanno implementando le funzionalità dei contratti; test e verifiche saranno affrontati successivamente.
