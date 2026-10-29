# TicketOnChain

Progetto Web3 per la creazione, l'acquisto e la rivendita regolamentata di biglietti NFT.

## Responsabilità, trasparenza e condizioni d'uso

La bozza delle condizioni d'uso è disponibile in [docs/CONDIZIONI-D-USO-BOZZA.md](docs/CONDIZIONI-D-USO-BOZZA.md). È un documento di lavoro e non deve essere pubblicato come testo definitivo senza revisione legale.

Prima del lancio, l'interfaccia deve:
- identificare chiaramente l'organizzatore/venditore e mostrare i suoi contatti e le informazioni obbligatorie;
- mostrare prima del pagamento il prezzo totale, le commissioni e la politica di rimborso scelta;
- registrare la versione delle condizioni accettate dall'organizzatore e rendere consultabili le condizioni dell'acquisto;
- distinguere assistenza tecnica della piattaforma e richieste relative all'evento;
- prevedere un canale per segnalazioni, eventi sospetti e informazioni potenzialmente illecite.

L'obiettivo è che TicketOnChain non anticipi denaro proprio per i rimborsi e che i ruoli siano effettivamente separati. Le diciture non possono eliminare obblighi inderogabili né garantire un'esenzione assoluta da responsabilità. Prima del lancio in Italia va verificato in particolare il regime applicabile al secondary ticketing e all'intermediazione di pagamenti.

## Contratti

- `contracts/TicketOnChain.sol`: NFT ERC-721 dei biglietti. Solo il mercato configurato può creare o trasferire NFT tra proprietari.
- `contracts/MercatoTicket.sol`: registrazione e annullamento eventi, vendita iniziale, custodia dei biglietti in rivendita, acquisti e gestione dei saldi e delle commissioni.

I contratti usano il trasferimento di proprietà a due passaggi (`Ownable2Step`) e impediscono la rinuncia definitiva alla proprietà amministrativa. Gli indirizzi configurati per il contratto NFT e il mercato devono contenere codice. Queste misure riducono il rischio di errori di configurazione, ma non sostituiscono test e revisione indipendente.

## Controlli di sicurezza del mercato

- L'amministratore può sospendere temporaneamente le nuove vendite con `sospendiMercato()` e riattivarle con `riattivaMercato()`.
- Durante la sospensione non si possono creare eventi, acquistare biglietti nuovi, mettere biglietti in rivendita o comprare rivendite.
- La sospensione non blocca i prelievi dei saldi già maturati, la convalida degli ingressi o l'annullamento di un annuncio per restituire il biglietto al venditore.
- Gli aggiornamenti dei saldi e delle commissioni nell'acquisto iniziale vengono eseguiti prima della chiamata al contratto NFT; se la creazione dell'NFT fallisce, l'intera transazione viene annullata.

Questi accorgimenti non sostituiscono una revisione indipendente del codice. La suite automatizzata è una verifica di regressione, non un audit e non garantisce l'assenza di vulnerabilità.

## Data dell'evento e chiusura delle vendite

Ogni evento deve essere creato con due timestamp Unix futuri: `timestampInizio` e `timestampFine`, espressi in secondi. La fine deve essere successiva all'inizio. Acquisti e rivendite si chiudono all'inizio; la convalida degli ingressi è possibile solo tra inizio e fine. Il prezzo e lo stato delle vendite possono essere modificati dall'organizzatore solo prima dell'inizio.

## Organizzatori autorizzati

Solo gli indirizzi autorizzati dall'amministratore possono creare eventi. L'indirizzo che distribuisce il contratto del mercato è autorizzato automaticamente. L'amministratore può autorizzare o revocare altri indirizzi con `impostaOrganizzatore(indirizzo, true/false)`.

La revoca impedisce all'indirizzo di creare nuovi eventi, ma non cambia automaticamente i permessi relativi agli eventi che ha già creato.

## Convalida degli ingressi

L'organizzatore può autorizzare o revocare gli addetti all'ingresso per ogni evento con `impostaValidatoreIngresso(idEvento, indirizzo, true/false)`. Solo l'organizzatore può gestire questo elenco. Gli addetti possono convalidare i biglietti soltanto tra l'orario di inizio e quello di fine dell'evento; ogni biglietto può essere convalidato una sola volta. L'organizzatore può continuare a convalidare direttamente.

## Limite temporaneo per gli acquisti

L'integrazione Proof of Humanity è stata rimossa temporaneamente. Per ora il contratto applica un limite cumulativo di 6 biglietti per wallet e per evento, sia per gli acquisti iniziali sia per le rivendite. Il conteggio non diminuisce quando un biglietto viene rivenduto.

**Limite noto:** senza un sistema d'identità, una persona può aggirare il limite usando wallet diversi. Il limite attuale è quindi per wallet, non per persona. Un sistema di verifica dell'identità verrà valutato e integrato in una fase successiva.

## Regole di rivendita

La rivendita può essere sospesa separatamente dalle vendite iniziali tramite `impostaRivendita(idEvento, false)`. La sospensione non impedisce al venditore di annullare un annuncio già attivo e recuperare il biglietto. Alla creazione dell'evento la rivendita è abilitata per impostazione predefinita.

La rivendita è consentita esclusivamente al prezzo originariamente pagato per quel biglietto: non sono ammessi né sovrapprezzi né sconti. Il prezzo originario viene registrato on-chain al momento del primo acquisto e resta invariato nelle rivendite successive. La rivendita non restituisce capacità di acquisto al wallet del venditore.

## Politica di rimborso scelta dall'organizzatore

Alla creazione dell'evento, l'organizzatore deve scegliere il parametro `politicaRimborso`:

- `FondiBloccati` (valore enum `0`): gli incassi netti, le commissioni e la riserva per i rimborsi restano nel contratto fino all'inizio dell'evento. Se l'organizzatore annulla prima dell'inizio, il contratto avvia automaticamente i rimborsi collettivi. Per contenere il gas, la procedura elabora al massimo 20 biglietti per transazione; l'interfaccia/servizio deve proseguire automaticamente i lotti chiamando `processaRimborsiEvento` fino al completamento. Questo numero è un limite tecnico per transazione, non un limite ai biglietti dell'evento. Se un annuncio di rivendita è ancora aperto, il venditore è il possessore economico del biglietto; se la rivendita è stata completata, il rimborso spetta al nuovo proprietario. Ogni biglietto rimborsato viene distrutto.
- `IncassiAnticipati` (valore enum `1`): il netto della vendita diventa subito prelevabile dall'organizzatore e la commissione diventa subito disponibile alla piattaforma. Se l'evento viene annullato prima della fine, l'organizzatore è responsabile di accedere al sito e avviare il rimborso collettivo, versando nel contratto l'intero importo lordo delle vendite tramite `avviaRimborsiCollettivi(idEvento)`. TicketOnChain non custodisce quegli incassi e non anticipa denaro. Se l'organizzatore non versa i fondi, il rimborso on-chain non può essere eseguito. L'elaborazione prosegue a lotti tecnici con `processaRimborsiEvento`; l'interfaccia deve continuare i lotti automaticamente e gli acquirenti non devono presentare richieste. Se il pagamento diretto a un wallet fallisce, l'importo viene accreditato nel suo saldo prelevabile.

La scelta è registrata nell'evento e non può essere cambiata con le funzioni attuali. Non è previsto un rimborso automatico per semplice ripensamento dell'acquirente. L'interfaccia deve mostrare la politica prima dell'acquisto e mantenere una dicitura coerente:

**FondiBloccati:** «In caso di annullamento, il contratto avvia automaticamente il rimborso del prezzo del biglietto. Gli incassi sono custoditi nel contratto fino all'inizio dell'evento.»

**IncassiAnticipati:** «L'organizzatore riceve subito gli incassi ed è responsabile dei rimborsi in caso di annullamento. TicketOnChain non trattiene né anticipa il denaro per questo evento. Per avviare i rimborsi, l'organizzatore deve accedere al sito e versare nel contratto l'intero importo lordo dei biglietti venduti. Se non versa i fondi necessari, il rimborso on-chain non può essere eseguito.»

La piattaforma non anticipa fondi propri. La dicitura informativa non elimina eventuali obblighi legali dell'organizzatore o della piattaforma: condizioni d'uso e comunicazioni agli acquirenti devono essere verificate rispetto alla normativa applicabile.

La modalità `FondiBloccati` riguarda gli incassi iniziali; le somme pagate per le rivendite vengono accreditate al venditore come saldo prelevabile. La cancellazione con `IncassiAnticipati` è consentita fino alla fine prevista dell'evento; dopo l'annullamento l'organizzatore può avviare i rimborsi anche se l'evento è già iniziato. Con `FondiBloccati`, l'annullamento resta consentito solo prima dell'inizio, perché gli incassi possono essere sbloccati da quel momento. La suite Foundry copre acquisti, rivendite, annullamenti, rimborsi, permessi, pause, prelievi, test fuzz, scenari avversariali e invarianti; resta una suite di regressione, non un audit indipendente.

I nomi delle funzioni e i commenti del progetto sono in italiano per rendere il codice più comprensibile durante lo sviluppo.

## Sviluppo e controlli automatici

Il progetto è un prototipo in verifica. La CI compila i contratti, esegue la suite Foundry (test funzionali, fuzz, test avversariali e invarianti) e analizza il codice con Slither. I rimborsi vengono accreditati come saldi prelevabili, senza inviare ETH direttamente ai wallet durante l'elaborazione del lotto: ogni destinatario deve effettuare una transazione separata per prelevare il saldo. Questo evita callback ostili e griefing tramite consumo di gas durante i rimborsi.

La contabilità della modalità IncassiAnticipati richiede ancora una verifica specifica: se i crediti dell'organizzatore e le commissioni maturate restano prelevabili dopo il finanziamento dei rimborsi, possono coesistere con la passività dei rimborsi. Prima del deploy va definito e verificato come queste passività si coordinano; nessuna regola economica viene modificata da questa nota. I controlli automatici non equivalgono a un audit indipendente.

## Ordine di pubblicazione su una rete di prova

1. Pubblica `TicketOnChain`.
2. Pubblica `MercatoTicket` passando al costruttore l'indirizzo del contratto NFT.
3. Dal proprietario di `TicketOnChain`, esegui `impostaMercato(indirizzoMercato)`.
4. L'amministratore autorizza gli organizzatori tramite `impostaOrganizzatore(indirizzo, true)`.
5. Crea un evento e verifica acquisto, approvazione, rivendita, annullamento, rimborso e prelievo sulla rete di prova.

**Attenzione:** l'indirizzo del mercato può essere impostato una sola volta. Controlla l'indirizzo prima di confermare la transazione.

## Metadati

Per un evento con URI base `ipfs://CID/`, il mercato assegna i metadati usando un progressivo indipendente per evento, a partire da 1: il primo biglietto di ogni evento usa `ipfs://CID/1.json`, il secondo `ipfs://CID/2.json` e così via. Il token ID NFT resta invece globale e univoco. L'URI base deve terminare con `/`. I file JSON devono esistere e rispettare il formato dei metadati NFT previsto dal progetto.

## Stato

Prototipo in sviluppo. La verifica dell'identità è rimandata; il limite attuale è applicato per wallet. La CI esegue una suite Foundry con test funzionali, test fuzz, scenari avversariali e invarianti stateful, oltre ad analisi statica Slither con soglia di fallimento per finding ad alta gravità. Il superamento dei controlli automatici non equivale a un audit indipendente: il contratto non deve essere considerato pronto per la mainnet finché non sarà sottoposto a revisione indipendente e testato su rete di prova.
