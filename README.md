# TicketOnChain

Progetto Web3 per la creazione, l'acquisto e la rivendita regolamentata di biglietti NFT.

## Contratti

- `contracts/TicketOnChain.sol`: NFT ERC-721 dei biglietti. Solo il mercato configurato può creare o trasferire NFT tra proprietari.
- `contracts/MercatoTicket.sol`: registrazione e annullamento eventi, vendita iniziale, custodia dei biglietti in rivendita, acquisti e gestione dei saldi e delle commissioni.

## Controlli di sicurezza del mercato

- L'amministratore può sospendere temporaneamente le nuove vendite con `sospendiMercato()` e riattivarle con `riattivaMercato()`.
- Durante la sospensione non si possono creare eventi, acquistare biglietti nuovi, mettere biglietti in rivendita o comprare rivendite.
- La sospensione non blocca i prelievi dei saldi già maturati, la convalida degli ingressi o l'annullamento di un annuncio per restituire il biglietto al venditore.
- Gli aggiornamenti dei saldi e delle commissioni nell'acquisto iniziale vengono eseguiti prima della chiamata al contratto NFT; se la creazione dell'NFT fallisce, l'intera transazione viene annullata.

Questi accorgimenti non sostituiscono una revisione indipendente del codice. Il contratto non è pronto per la rete principale finché non sarà compilato, testato e sottoposto a revisione.

## Data dell'evento e chiusura delle vendite

Ogni evento deve essere creato con un timestamp Unix futuro che indica la data e l'ora di inizio. Il mercato blocca gli acquisti iniziali e le rivendite quando l'evento è iniziato. Il timestamp è espresso in secondi, non in millisecondi. La funzione `creaEvento` richiede quindi anche il parametro `timestampInizio`.

## Organizzatori autorizzati

Solo gli indirizzi autorizzati dall'amministratore possono creare eventi. L'indirizzo che distribuisce il contratto del mercato è autorizzato automaticamente. L'amministratore può autorizzare o revocare altri indirizzi con `impostaOrganizzatore(indirizzo, true/false)`.

La revoca impedisce all'indirizzo di creare nuovi eventi, ma non cambia automaticamente i permessi relativi agli eventi che ha già creato.

## Limite temporaneo per gli acquisti

L'integrazione Proof of Humanity è stata rimossa temporaneamente. Per ora il contratto applica un limite cumulativo di 6 biglietti per wallet e per evento, sia per gli acquisti iniziali sia per le rivendite. Il conteggio non diminuisce quando un biglietto viene rivenduto.

**Limite noto:** senza un sistema d'identità, una persona può aggirare il limite usando wallet diversi. Il limite attuale è quindi per wallet, non per persona. Un sistema di verifica dell'identità verrà valutato e integrato in una fase successiva.

## Regole di rivendita

La rivendita è consentita esclusivamente al prezzo originariamente pagato per quel biglietto: non sono ammessi né sovrapprezzi né sconti. Il prezzo originario viene registrato on-chain al momento del primo acquisto e resta invariato nelle rivendite successive. La rivendita non restituisce capacità di acquisto al wallet del venditore.

## Fondi, annullamenti e rimborsi

I ricavi delle vendite iniziali e le relative commissioni restano accantonati fino all'inizio dell'evento. L'organizzatore può sbloccare i ricavi con `prelevaRicaviEvento(idEvento)) soltanto dall'orario di inizio in poi. Le commissioni iniziali diventano prelevabili nello stesso momento.

L'organizzatore può annullare l'evento soltanto prima dell'orario di inizio. In caso di annullamento, il proprietario attuale di ciascun biglietto può chiamare `richiediRimborso(idBiglietto)`: riceve il prezzo originario in ETH e il biglietto NFT viene distrutto. Ogni biglietto può essere rimborsato una sola volta. Se il biglietto è custodito dal mercato in una rivendita, il venditore deve prima annullare l'annuncio per riottenere il biglietto.

I ricavi iniziali non vengono versati all'organizzatore prima dell'evento, così rimangono disponibili per finanziare i rimborsi. Le somme pagate nelle rivendite vengono invece accreditate al venditore come saldo prelevabile; i rimborsi per annullamento sono coperti dall'accantonamento della vendita iniziale. Gli eventi annullati non sbloccano i ricavi iniziali né le commissioni iniziali.

Questa è una logica di rimborso on-chain iniziale e non sostituisce la definizione delle condizioni contrattuali, la verifica della solvibilità in tutti i casi limite e una revisione indipendente prima della rete principale.

I nomi delle funzioni e i commenti del progetto sono in italiano per rendere il codice più comprensibile durante lo sviluppo.

## Sviluppo

In questa fase il progetto è dedicato all'implementazione dei contratti. Le verifiche automatiche e i test verranno reintrodotti in una fase successiva, quando le funzionalità principali saranno completate.

## Ordine di pubblicazione su una rete di prova

1. Pubblica `TicketOnChain`.
2. Pubblica `MercatoTicket` passando al costruttore l'indirizzo del contratto NFT.
3. Dal proprietario di `TicketOnChain`, esegui `impostaMercato(indirizzoMercato)`.
4. L'amministratore autorizza gli organizzatori tramite `impostaOrganizzatore(indirizzo, true)`.
5. Crea un evento e prova acquisto, approvazione, rivendita e prelievo quando la fase di test verrà avviata.

**Attenzione:** l'indirizzo del mercato può essere impostato una sola volta. Controlla l'indirizzo prima di confermare la transazione.

## Metadati

Per un evento con URI base `ipfs://CID/`, il mercato associa al biglietto con identificativo 12 l'URI `ipfs://CID/12.json`. I file JSON devono esistere e rispettare il formato dei metadati NFT previsto dal progetto.

## Stato

Prototipo in sviluppo. La verifica dell'identità è rimandata; il limite attuale è applicato per wallet. Test e verifiche saranno affrontati successivamente.
