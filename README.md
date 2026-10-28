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

La rivendita è consentita esclusivamente al prezzo originariamente pagato per quel biglietto: non sono ammessi né sovrapprezzi né sconti. Il prezzo originario viene registrato on-chain al momento del primo acquisto e resta invariato nelle rivendite successive. La rivendita non restituisce capacità di acquisto al wallet del venditore.

## Politica di rimborso scelta dall'organizzatore

Alla creazione dell'evento, l'organizzatore deve scegliere il parametro `politicaRimborso`:

- `FondiBloccati` (valore enum `0`): gli incassi netti e le commissioni restano nel contratto fino all'inizio dell'evento. L'organizzatore può sbloccare gli incassi con `prelevaRicaviEvento(idEvento)` solo dall'orario di inizio. Se l'evento viene annullato prima dell'inizio, i possessori attuali dei biglietti possono richiedere on-chain il prezzo originario con `richiediRimborso(idBiglietto)`. Il biglietto NFT viene distrutto dopo il rimborso. Se è in custodia per una rivendita, il venditore deve prima annullare l'annuncio.
- `IncassiAnticipati` (valore enum `1`): il netto della vendita diventa subito prelevabile dall'organizzatore e la commissione diventa subito disponibile alla piattaforma. In questa modalità il contratto non accantona fondi per i rimborsi e `richiediRimborso` non è disponibile. Eventuali rimborsi devono essere gestiti dall'organizzatore al di fuori del rimborso automatico del contratto.

La scelta è registrata nell'evento e non può essere cambiata con le funzioni attuali. L'interfaccia deve mostrare la politica prima dell'acquisto e mantenere una dicitura coerente:

**FondiBloccati:** «In caso di annullamento, è previsto il rimborso del prezzo del biglietto. Gli incassi sono custoditi nel contratto fino all'inizio dell'evento.»

**IncassiAnticipati:** «L'organizzatore può prelevare gli incassi prima dell'evento. In caso di annullamento, non è prevista una garanzia automatica di rimborso finanziata dalla piattaforma.»

La piattaforma non anticipa fondi propri. La dicitura informativa non elimina eventuali obblighi legali dell'organizzatore o della piattaforma: condizioni d'uso e comunicazioni agli acquirenti devono essere verificate rispetto alla normativa applicabile.

La modalità `FondiBloccati` riguarda gli incassi iniziali; le somme pagate per le rivendite vengono accreditate al venditore come saldo prelevabile. Questa implementazione non è stata compilata né testata in questa fase.

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
