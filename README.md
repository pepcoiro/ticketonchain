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

La suite di invarianti verifica la copertura contabile delle passività in entrambe le modalità, includendo saldi prelevabili, commissioni accumulate e riserve lorde di rimborso. I ricavi e le commissioni ancora bloccati non vengono sommati una seconda volta, perché sono già coperti dalla riserva lorda. I controlli automatici non equivalgono a un audit indipendente.

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


## Guida frontend: funzioni ed eventi disponibili

Questa sezione è un inventario pratico delle funzioni esposte dai contratti. Le funzioni di lettura possono essere consultate senza inviare una transazione; quelle che modificano lo stato richiedono una transazione firmata dal wallet e, quando previsto, ETH. Le funzioni con permessi limitati possono essere chiamate soltanto dagli indirizzi autorizzati.

### 1. Contratto `MercatoTicket`

È il contratto principale da collegare all'interfaccia: gestisce eventi, acquisti, rivendite, ingressi, saldi e rimborsi.

#### Consultazione dei dati

| Funzione pubblica | A cosa serve nel frontend |
|---|---|
| `eventi(idEvento)` | Legge i dati dell'evento: organizzatore, nome, URI metadati, inizio/fine, politica di rimborso, prezzo, quantità massima, biglietti venduti, stato attivo e annullato. |
| `prossimoIdEvento()` | Legge il prossimo identificativo evento da assegnare. |
| `prossimoIdBiglietto()` | Legge il prossimo identificativo globale dei biglietti. |
| `contrattoBiglietti()` | Restituisce l'indirizzo del contratto NFT associato al mercato. |
| `LIMITE_BIGLIETTI_PER_WALLET()` | Legge il limite cumulativo di acquisti per wallet e per evento: attualmente 6. |
| `MASSIMO_RIMBORSI_PER_BATCH()` | Legge il limite massimo di biglietti elaborabili in un singolo lotto di rimborso: attualmente 20. |
| `commissionePuntiBase()` | Legge la commissione corrente in punti base: 250 equivale al 2,5%. |
| `organizzatoriAutorizzati(indirizzo)` | Verifica se un indirizzo è autorizzato a creare eventi. |
| `bigliettiAcquistatiPerWallet(idEvento, wallet)` | Legge quanti acquisti sono stati conteggiati per quel wallet e quell'evento. Il conteggio è cumulativo e non diminuisce dopo una rivendita. |
| `saldiPrelevabili(indirizzo)` | Legge il saldo ETH prelevabile da un indirizzo, inclusi eventuali importi accreditati per rimborsi. |
| `commissioniAccumulate()` | Legge le commissioni attualmente disponibili per il proprietario del mercato. |
| `ricaviEventoBloccati(idEvento)` | Legge i ricavi netti ancora bloccati per un evento con politica `FondiBloccati`. |
| `fondiRimborsoEvento(idEvento)` | Legge i fondi attualmente destinati ai rimborsi dell'evento. |
| `totaleVenditeEvento(idEvento)` | Legge il totale lordo incassato dalle vendite iniziali. |
| `commissioniEventoBloccate(idEvento)` | Legge le commissioni iniziali ancora bloccate per l'evento. |
| `commissioneAcquistoOriginale(idBiglietto)` | Legge la commissione registrata al momento dell'acquisto iniziale di quel biglietto. |
| `prezzoAcquistoOriginale(idBiglietto)` | Legge il prezzo originario del biglietto, usato anche per vincolare il prezzo di rivendita e calcolare il rimborso. |
| `eventoDelBiglietto(idBiglietto)` | Restituisce l'evento a cui appartiene il biglietto. |
| `rivendite(idBiglietto)` | Legge venditore, prezzo e stato dell'annuncio di rivendita. |
| `rivenditaAttiva(idEvento)` | Verifica se la rivendita è abilitata per un evento. |
| `ingressiUtilizzati(idBiglietto)` | Verifica se il biglietto è già stato convalidato all'ingresso. |
| `validatoriIngresso(idEvento, indirizzo)` | Verifica se un indirizzo può convalidare gli ingressi per quell'evento. |
| `bigliettiRimborsati(idBiglietto)` | Verifica se un biglietto è già stato rimborsato. |
| `rimborsiCollettiviAvviati(idEvento)` | Verifica se la procedura di rimborso collettivo è stata avviata. |
| `cursoreRimborsiEvento(idEvento)` | Legge la posizione raggiunta dall'elaborazione dei rimborsi a lotti. |
| `bigliettiDaRimborsare(idEvento)` | Restituisce quanti biglietti restano da esaminare nella procedura di rimborso. |
| `paused()` | Verifica se il mercato è temporaneamente sospeso. |
| `owner()` / `pendingOwner()` | Legge il proprietario amministrativo attuale e l'eventuale nuovo proprietario in attesa di accettazione. |

#### Azioni degli utenti e degli organizzatori

| Funzione | Chi può usarla e cosa fa |
|---|---|
| `creaEvento(nomeEvento, uriMetadatiBase, prezzoBiglietto, quantitaMassima, timestampInizio, timestampFine, politicaRimborso)` | Un organizzatore autorizzato crea un evento. Il prezzo è espresso in wei; le date sono timestamp Unix in secondi; la politica è `FondiBloccati = 0` oppure `IncassiAnticipati = 1`. L'URI base deve terminare con `/`. |
| `aggiornaEvento(idEvento, nuovoPrezzo, attivo)` | L'organizzatore modifica il prezzo o sospende le vendite prima dell'inizio dell'evento. |
| `impostaRivendita(idEvento, attiva)` | L'organizzatore abilita o disabilita il mercato secondario prima dell'inizio. |
| `acquistaBiglietto(idEvento)` | Acquista un biglietto iniziale inviando esattamente il prezzo richiesto in ETH. |
| `mettiInRivendita(idBiglietto, prezzoRichiesto)` | Il proprietario pubblica un annuncio al prezzo originario. Prima deve autorizzare il contratto di mercato sul contratto NFT con `approve` oppure `setApprovalForAll`. |
| `annullaRivendita(idBiglietto)` | Il venditore ritira un annuncio attivo e recupera il proprio NFT. |
| `acquistaRivendita(idBiglietto)` | Acquista un biglietto già messo in rivendita, pagando il prezzo esatto dell'annuncio. |
| `prelevaSaldo()` | L'utente preleva sul proprio wallet il saldo ETH disponibile a suo nome. È lo stesso meccanismo usato per incassi da rivendita e accrediti di rimborso. |
| `prelevaRicaviEvento(idEvento)` | L'organizzatore preleva i ricavi netti bloccati, dopo l'inizio dell'evento, solo se è stata scelta la politica `FondiBloccati` e l'evento non è annullato. |
| `impostaValidatoreIngresso(idEvento, validatore, autorizzato)` | L'organizzatore autorizza o revoca un addetto alla convalida degli ingressi. |
| `validaIngresso(idBiglietto)` | L'organizzatore o un validatore autorizzato registra l'ingresso. È consentito solo durante la finestra temporale dell'evento; un biglietto può essere usato una sola volta. |
| `annullaEvento(idEvento)` | L'organizzatore annulla l'evento. Con `FondiBloccati` avvia automaticamente i rimborsi; con `IncassiAnticipati` l'organizzatore deve finanziare separatamente il rimborso collettivo. |
| `avviaRimborsiCollettivi(idEvento)` | Solo l'organizzatore di un evento annullato con `IncassiAnticipati` può avviare i rimborsi, versando in una sola volta l'intero importo lordo delle vendite iniziali. |
| `processaRimborsiEvento(idEvento, quantita)` | Prosegue i rimborsi già avviati. Può chiamarla qualsiasi indirizzo; `quantita` deve essere tra 1 e 20. Il frontend/servizio deve ripetere le chiamate fino al completamento. |

#### Azioni riservate all'amministratore del mercato

| Funzione | A cosa serve |
|---|---|
| `impostaOrganizzatore(organizzatore, autorizzato)` | Autorizza o revoca un indirizzo che può creare nuovi eventi. |
| `sospendiMercato()` | Sospende temporaneamente le operazioni di vendita. |
| `riattivaMercato()` | Riattiva le operazioni di vendita. |
| `impostaCommissione(nuovaCommissionePuntiBase)` | Modifica la commissione, con limite massimo del 10% (1.000 punti base). |
| `prelevaCommissioni(destinatario)` | Preleva le commissioni accumulate verso l'indirizzo scelto. |
| `transferOwnership(nuovoProprietario)` | Avvia il trasferimento della proprietà amministrativa in due passaggi. |
| `acceptOwnership()` | Il nuovo proprietario completa il trasferimento. |
| `renounceOwnership()` | Presente per compatibilità con il sistema di proprietà, ma è disabilitata e termina con errore. |

#### Eventi emessi da `MercatoTicket`

Il frontend può ascoltare questi eventi in tempo reale e/o leggerli dai log della blockchain per aggiornare schermate, cronologia e notifiche.

| Evento | Quando viene emesso |
|---|---|
| `EventoCreato` | Un evento viene creato, con identificativo, organizzatore, nome, prezzo, quantità, date e politica di rimborso. |
| `EventoAggiornato` | L'organizzatore aggiorna prezzo o stato delle vendite. |
| `EventoAnnullato` | Un evento viene annullato. |
| `BigliettoAcquistato` | Viene completato un acquisto iniziale. |
| `BigliettoMessoInVendita` | Un biglietto viene messo in rivendita. |
| `RivenditaAnnullata` | Un annuncio viene ritirato e il biglietto restituito al venditore. |
| `BigliettoRivenduto` | Un acquisto sul mercato secondario viene completato; include venditore, acquirente, prezzo e commissione. |
| `SaldoPrelevato` | Un utente preleva il proprio saldo. |
| `CommissioniPrelevate` | Il proprietario preleva le commissioni. |
| `CommissioneAggiornata` | La commissione del mercato viene modificata. |
| `OrganizzatoreAutorizzato` | Un indirizzo viene autorizzato o revocato come organizzatore. |
| `RimborsoEseguito` | Un biglietto è stato elaborato per il rimborso; indica destinatario e importo accreditato. |
| `RimborsiCollettiviAvviati` | È stata avviata la procedura collettiva, con importo finanziato. |
| `AvanzamentoRimborsi` | Comunica quanti biglietti sono stati elaborati, quanti sono totali e se la procedura è completata. |
| `RicaviEventoSbloccati` | I ricavi bloccati vengono resi disponibili all'organizzatore. |
| `AcquistoWalletRegistrato` | Aggiorna il conteggio cumulativo di acquisti per wallet ed evento. |
| `IngressoValidato` | Un biglietto viene convalidato all'ingresso. |
| `ValidatoreIngressoImpostato` | Un addetto viene autorizzato o revocato per un evento. |
| `Paused` / `Unpaused` | Il mercato viene sospeso o riattivato. |
| `OwnershipTransferStarted` / `OwnershipTransferred` | Inizia o si completa il trasferimento della proprietà amministrativa. |

### 2. Contratto NFT `TicketOnChain`

Questo contratto rappresenta i biglietti come NFT ERC-721. La maggior parte delle operazioni quotidiane passa dal mercato; il frontend può comunque consultare i dati NFT e deve usare le approvazioni ERC-721 prima di mettere un biglietto in rivendita.

#### Consultazione

| Funzione | A cosa serve |
|---|---|
| `name()` / `symbol()` | Legge il nome e il simbolo della collezione NFT. |
| `mercato()` | Legge l'indirizzo del mercato autorizzato. |
| `ownerOf(idBiglietto)` | Legge il proprietario attuale del biglietto. |
| `balanceOf(indirizzo)` | Legge quanti NFT possiede un indirizzo. |
| `tokenURI(idBiglietto)` | Legge l'URI dei metadati del biglietto. |
| `getApproved(idBiglietto)` | Legge l'indirizzo approvato a trasferire quel singolo NFT. |
| `isApprovedForAll(proprietario, operatore)` | Verifica se un operatore è autorizzato a gestire tutti gli NFT del proprietario. |
| `supportsInterface(interfaccia)` | Verifica il supporto alle interfacce standard ERC-165/ERC-721. |
| `owner()` / `pendingOwner()` | Legge il proprietario amministrativo e l'eventuale nuovo proprietario in attesa. |

#### Operazioni NFT

| Funzione | A cosa serve |
|---|---|
| `approve(operatore, idBiglietto)` | Autorizza un operatore a trasferire uno specifico NFT. Serve, per esempio, per mettere un biglietto in rivendita. |
| `setApprovalForAll(operatore, approvato)` | Autorizza o revoca un operatore per tutti gli NFT del wallet. È più ampia dell'approvazione singola: l'interfaccia deve spiegarlo chiaramente. |
| `safeTransferFrom(proprietario, destinatario, idBiglietto)` | Funzione ERC-721 standard, ma i trasferimenti diretti tra utenti sono bloccati dal contratto: devono passare dal mercato. Il mercato la usa per prendere in custodia e consegnare i biglietti. |
| `safeTransferFrom(proprietario, destinatario, idBiglietto, dati)` | Variante ERC-721 con dati aggiuntivi; valgono le stesse restrizioni ai trasferimenti diretti. |
| `transferFrom(proprietario, destinatario, idBiglietto)` | Funzione ERC-721 standard, ma i trasferimenti diretti tra proprietari sono bloccati. Non va usata dal frontend per trasferire un biglietto tra utenti. |
| `impostaMercato(indirizzoMercato)` | Il proprietario configura il mercato autorizzato. Può essere eseguita una sola volta: controllare l'indirizzo prima di confermare. |
| `transferOwnership(nuovoProprietario)` / `acceptOwnership()` | Trasferimento amministrativo in due passaggi. |
| `creaBiglietto(destinatario, identificativoBiglietto, indirizzoMetadati)` | Funzione tecnica riservata al mercato autorizzato. Il frontend ordinario non deve chiamarla direttamente. |
| `distruggiBiglietto(identificativoBiglietto)` | Funzione tecnica riservata al mercato, usata durante i rimborsi per distruggere l'NFT rimborsato. |
| `renounceOwnership()` | Disabilitata: la chiamata termina con errore. |

#### Eventi del contratto NFT

| Evento | Quando viene emesso |
|---|---|
| `Transfer` | Creazione, trasferimento o distruzione di un NFT secondo ERC-721. |
| `Approval` | Approvazione o modifica dell'operatore di un singolo NFT. |
| `ApprovalForAll` | Approvazione o revoca di un operatore per tutti gli NFT di un wallet. |
| `MercatoImpostato` | Viene configurato l'indirizzo del mercato. |
| `BigliettoCreato` | Viene creato un biglietto, con ID, destinatario e URI dei metadati. |
| `OwnershipTransferStarted` / `OwnershipTransferred` | Inizia o si completa il trasferimento della proprietà amministrativa. |

### 3. Indicazioni pratiche per costruire il frontend

- **Esplora eventi:** leggere gli eventi tramite `eventi(idEvento)` e usare `prossimoIdEvento()` come limite di scansione, ricordando che gli identificativi partono da 1. Per una lista completa e una ricerca efficiente conviene indicizzare gli eventi `EventoCreato`; il contratto non espone una funzione che restituisca tutti gli eventi in un unico array.
- **Dettaglio evento:** mostrare prezzo, disponibilità (`quantitaMassima - bigliettiVenduti)), date, stato, organizzatore e politica di rimborso prima dell'acquisto.
- **Wallet e biglietti posseduti:** usare gli eventi `BigliettoAcquistato`/`BigliettoRivenduto` e le funzioni NFT `ownerOf` e `tokenURI`. Il contratto non espone una funzione che restituisca direttamente tutti i biglietti di un wallet.
- **Prezzi:** i valori monetari sono espressi in wei; convertire in ETH per la visualizzazione e usare una conversione precisa per i pagamenti. Le date sono timestamp Unix in secondi.
- **Rivendita:** verificare la proprietà NFT e lo stato dell'evento, chiedere l'approvazione ERC-721 e poi chiamare `mettiInRivendita`. Il prezzo richiesto deve essere esattamente il prezzo originario.
- **Rimborsi:** non esiste una richiesta individuale di rimborso da parte dell'acquirente. Il frontend deve mostrare lo stato dei rimborsi collettivi e, quando necessario, proseguire i lotti con `processaRimborsiEvento` fino a quando `bigliettiDaRimborsare` restituisce 0. Gli importi rimborsati diventano saldi prelevabili: il destinatario deve poi chiamare `prelevaSaldo()`.
- **Ingressi:** mostrare lo stato di utilizzo del biglietto e consentire `validaIngresso` solo agli organizzatori o ai validatori autorizzati. La blockchain impedisce una seconda convalida.
- **Permessi:** prima di mostrare azioni amministrative o dell'organizzatore, confrontare l'indirizzo con `owner()`, `eventi(idEvento).organizzatore`, `organizzatoriAutorizzati` e `validatoriIngresso`, secondo il caso. I controlli grafici non sostituiscono i controlli dei contratti.
- **Eventi e aggiornamenti:** ascoltare gli eventi della blockchain per aggiornare l'interfaccia, ma verificare sempre lo stato corrente del contratto prima di considerare conclusa un'operazione.
- **Funzioni standard di proprietà:** entrambi i contratti ereditano il trasferimento amministrativo in due passaggi da OpenZeppelin. Le chiamate `transferOwnership` e `acceptOwnership` sono disponibili solo per gli indirizzi previsti dal relativo meccanismo.

Questo inventario descrive le funzioni presenti nel codice sorgente. Prima dell'integrazione reale, generare l'ABI dai contratti compilati e verificare nomi, tipi e overload contro l'ABI effettiva. Il contratto resta un prototipo in sviluppo e questa documentazione non costituisce un audit di sicurezza.
