// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {TicketOnChain} from "./TicketOnChain.sol";

/**
 * @title MercatoTicket
 * @notice Gestisce la creazione degli eventi, la vendita iniziale e la rivendita
 *         dei biglietti NFT di TicketOnChain.
 * @dev Il contratto NFT deve essere configurato per autorizzare questo mercato
 *      prima che sia possibile creare o trasferire biglietti.
 *
 *      Questo è un primo contratto applicativo: va compilato e testato prima
 *      di essere utilizzato su una rete reale.
 */
contract MercatoTicket is Ownable2Step, ReentrancyGuard, Pausable, IERC721Receiver {
    using Strings for uint256;

    /// @notice Contratto NFT utilizzato per creare e trasferire i biglietti.
    TicketOnChain public immutable contrattoBiglietti;

    /// @notice Numero massimo di biglietti acquistabili da un wallet per evento.
    /// @dev Limite temporaneo: senza un sistema di identità, wallet diversi non sono collegabili.
    uint256 public constant LIMITE_BIGLIETTI_PER_WALLET = 6;

    /// @notice Numero massimo di rimborsi elaborati in una singola transazione.
    uint256 public constant MASSIMO_RIMBORSI_PER_BATCH = 20;

    /// @notice Conteggio cumulativo degli acquisti per wallet ed evento.
    /// @dev Il conteggio non diminuisce quando un biglietto viene rivenduto.
    mapping(uint256 idEvento => mapping(address wallet => uint256 quantita))
        public bigliettiAcquistatiPerWallet;

    /// @notice Indica quali indirizzi sono autorizzati dall'amministratore a creare eventi.
    mapping(address organizzatore => bool autorizzato) public organizzatoriAutorizzati;

    /// @notice Commissione applicata alle vendite, espressa in punti base.
    /// @dev 100 punti base corrispondono all'1%; 1.000 corrispondono al 10%.
    uint256 public commissionePuntiBase = 150;

    /// @notice Prossimo identificativo disponibile per un evento.
    uint256 public prossimoIdEvento = 1;

    /// @notice Prossimo identificativo disponibile per un biglietto.
    uint256 public prossimoIdBiglietto = 1;

    /// @dev Denaro prelevabile da organizzatori e venditori.
    mapping(address beneficiario => uint256 importo) public saldiPrelevabili;

    /// @notice Commissioni TOC maturate immediatamente su ogni vendita iniziale e rivendita.
    /// @dev Diventano subito prelevabili dalla piattaforma tramite prelevaCommissioni().
    uint256 public commissioniAccumulate;

    /// @notice Prezzo dei biglietti delle vendite iniziali bloccato fino all'inizio dell'evento.
    mapping(uint256 idEvento => uint256 importo) public ricaviEventoBloccati;

    /// @notice Fondi accantonati per rimborsare i biglietti in caso di annullamento.
    mapping(uint256 idEvento => uint256 importo) public fondiRimborsoEvento;

    /// @notice Somma dei prezzi dei biglietti venduti inizialmente, esclusi i costi TOC.
    /// @dev È l'importo che l'organizzatore deve finanziare in caso di rimborso collettivo con IncassiAnticipati.
    mapping(uint256 idEvento => uint256 importo) public totaleVenditeEvento;

    /// @notice Elenco dei biglietti venduti per ogni evento, usato per i rimborsi a lotti.
    mapping(uint256 idEvento => uint256[] identificativi) private _bigliettiEvento;

    /// @notice Posizione del prossimo biglietto da esaminare nella procedura di rimborso.
    mapping(uint256 idEvento => uint256 posizione) public cursoreRimborsiEvento;

    /// @notice Indica che la procedura di rimborso collettivo è stata avviata.
    mapping(uint256 idEvento => bool avviata) public rimborsiCollettiviAvviati;

    /// @notice Commissione TOC effettivamente pagata per ciascun acquisto iniziale.
    /// @dev È informativa e non viene mai inclusa nel rimborso del biglietto.
    mapping(uint256 idBiglietto => uint256 importo) public commissioneAcquistoOriginale;

     /// @notice Indica se il biglietto è già stato rimborsato.
    mapping(uint256 idBiglietto => bool rimborsato) public bigliettiRimborsati;

    /// @notice Politica economica scelta dall'organizzatore alla creazione dell'evento.
    /// FondiBloccati: incassi custoditi fino all'inizio; IncassiAnticipati: prelievo immediato.
    enum PoliticaRimborso { FondiBloccati, IncassiAnticipati }

    struct Evento {
        address organizzatore;
        string nome;
        string uriMetadatiBase;
        uint256 timestampInizio;
        uint256 timestampFine;
        PoliticaRimborso politicaRimborso;
        uint256 prezzo;
        uint256 quantitaMassima;
        uint256 bigliettiVenduti;
        bool attivo;
        bool annullato;
    }

    struct AnnuncioRivendita {
        address venditore;
        uint256 prezzo;
        bool attivo;
    }

    /// @notice Dati degli eventi registrati nel mercato.
    mapping(uint256 idEvento => Evento dati) public eventi;

    /// @notice Addetti autorizzati dall'organizzatore a convalidare gli ingressi.
    mapping(uint256 idEvento => mapping(address validatore => bool autorizzato)) public validatoriIngresso;

    /// @notice Evento di appartenenza per ciascun biglietto creato dal mercato.
    mapping(uint256 idBiglietto => uint256 idEvento) public eventoDelBiglietto;

    /// @notice Annunci di rivendita indicizzati per identificativo del biglietto.
    mapping(uint256 idBiglietto => AnnuncioRivendita annuncio) public rivendite;

    /// @notice Indica se il mercato secondario è abilitato per ciascun evento.
    mapping(uint256 idEvento => bool attivo) public rivenditaAttiva;

    /// @notice Prezzo originario pagato per ciascun biglietto, invariabile nelle rivendite.
    mapping(uint256 idBiglietto => uint256 prezzo) public prezzoAcquistoOriginale;

    /// @notice Indica se un biglietto è già stato utilizzato per entrare all'evento.
    mapping(uint256 idBiglietto => bool utilizzato) public ingressiUtilizzati;

    event EventoCreato(
        uint256 indexed idEvento,
        address indexed organizzatore,
        string nome,
        uint256 prezzo,
        uint256 quantitaMassima,
        uint256 timestampInizio,
        uint256 timestampFine,
        PoliticaRimborso politicaRimborso
    );
    event EventoAggiornato(uint256 indexed idEvento, bool attivo, uint256 prezzo);
    event EventoAnnullato(uint256 indexed idEvento, address indexed organizzatore);
    event BigliettoAcquistato(
        uint256 indexed idEvento,
        uint256 indexed idBiglietto,
        address indexed acquirente,
        uint256 prezzo
    );
    event BigliettoMessoInVendita(
        uint256 indexed idBiglietto,
        address indexed venditore,
        uint256 prezzo
    );
    event RivenditaAnnullata(uint256 indexed idBiglietto, address indexed venditore);
    event BigliettoRivenduto(
        uint256 indexed idBiglietto,
        address indexed venditore,
        address indexed acquirente,
        uint256 prezzo,
        uint256 commissione
    );
    event SaldoPrelevato(address indexed beneficiario, uint256 importo);
    event CommissioniPrelevate(address indexed destinatario, uint256 importo);
    event CommissioneAggiornata(uint256 vecchiaCommissione, uint256 nuovaCommissione);
    event OrganizzatoreAutorizzato(address indexed organizzatore, bool autorizzato);
    event RimborsoEseguito(uint256 indexed idEvento, uint256 indexed idBiglietto, address indexed destinatario, uint256 importo);
    event RimborsiCollettiviAvviati(uint256 indexed idEvento, address indexed organizzatore, uint256 fondiVersati);
    event AvanzamentoRimborsi(uint256 indexed idEvento, uint256 elaborati, uint256 totali, bool completati);
    event RicaviEventoSbloccati(uint256 indexed idEvento, address indexed organizzatore, uint256 importo);
    event AcquistoWalletRegistrato(
        uint256 indexed idEvento,
        address indexed acquirente,
        uint256 quantitaTotale
    );
    event IngressoValidato(uint256 indexed idEvento, uint256 indexed idBiglietto, address indexed validatore);
    event ValidatoreIngressoImpostato(uint256 indexed idEvento, address indexed validatore, bool autorizzato);

    /**
     * @notice Conferma la ricezione dei biglietti trasferiti in custodia al mercato.
     * @dev ERC-721 richiede questa funzione quando si usa safeTransferFrom verso
     *      un contratto. Accettiamo soltanto NFT provenienti dal nostro contratto.
     */
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external view override returns (bytes4) {
        require(
            msg.sender == address(contrattoBiglietti),
            "MercatoTicket: NFT non riconosciuto"
        );
        return IERC721Receiver.onERC721Received.selector;
    }

    constructor(address indirizzoContrattoBiglietti) Ownable(msg.sender) {
        require(
            indirizzoContrattoBiglietti != address(0) && indirizzoContrattoBiglietti.code.length > 0,
            "MercatoTicket: indirizzo NFT non valido"
        );
        contrattoBiglietti = TicketOnChain(indirizzoContrattoBiglietti);
        organizzatoriAutorizzati[msg.sender] = true;
        emit OrganizzatoreAutorizzato(msg.sender, true);
    }

    /// @notice Impedisce la rinuncia irreversibile alla proprietà amministrativa.
    function renounceOwnership() public override onlyOwner {
        revert("MercatoTicket: rinuncia proprieta disabilitata");
    }

    /**
     * @notice Sospende temporaneamente le operazioni di vendita in caso di emergenza.
     * @dev Non blocca prelievi, convalida ingressi o annullamento degli annunci.
     */
    function sospendiMercato() external onlyOwner {
        _pause();
    }

    /**
     * @notice Riattiva le operazioni di vendita dopo la risoluzione del problema.
     */
    function riattivaMercato() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Autorizza o revoca un organizzatore.
     * @dev Solo il proprietario del mercato può gestire l'elenco degli organizzatori.
     */
    function impostaOrganizzatore(address organizzatore, bool autorizzato) external onlyOwner {
        require(organizzatore != address(0), "MercatoTicket: organizzatore non valido");
        organizzatoriAutorizzati[organizzatore] = autorizzato;
        emit OrganizzatoreAutorizzato(organizzatore, autorizzato);
    }

    /**
     * @notice Registra un evento e mette in vendita i suoi biglietti.
     * @param nomeEvento Nome leggibile dell'evento.
     * @param uriMetadatiBase URI che termina con "/" e contiene i file JSON dei biglietti.
     *        Per esempio, "ipfs://CID/": il primo biglietto di ogni evento usa "ipfs://CID/1.json".
     *        Il progressivo dei metadati è indipendente dal token ID globale.
     * @param prezzoBiglietto Prezzo di un biglietto in ETH (espresso in wei).
     * @param quantitaMassima Numero totale di biglietti emettibili per l'evento.
     * @param timestampInizio Data e ora di inizio dell'evento come timestamp Unix in secondi.
     * @param timestampFine Data e ora di fine dell'evento come timestamp Unix in secondi.
     * @param politicaRimborso FondiBloccati oppure IncassiAnticipati, scelta dall'organizzatore.
     */
    function creaEvento(
        string calldata nomeEvento,
        string calldata uriMetadatiBase,
        uint256 prezzoBiglietto,
        uint256 quantitaMassima,
        uint256 timestampInizio,
        uint256 timestampFine,
        PoliticaRimborso politicaRimborso
    ) external whenNotPaused returns (uint256 idEvento) {
        require(
            organizzatoriAutorizzati[msg.sender],
            "MercatoTicket: organizzatore non autorizzato"
        );
        require(bytes(nomeEvento).length > 0, "MercatoTicket: nome vuoto");
        require(bytes(uriMetadatiBase).length > 0, "MercatoTicket: URI metadati vuoto");
        require(bytes(uriMetadatiBase)[bytes(uriMetadatiBase).length - 1] == bytes1("/"), "MercatoTicket: URI base deve terminare con /");
        require(prezzoBiglietto > 0, "MercatoTicket: prezzo non valido");
        require(quantitaMassima > 0, "MercatoTicket: quantita non valida");
        require(timestampInizio > block.timestamp, "MercatoTicket: data evento non futura");
        require(timestampFine > timestampInizio, "MercatoTicket: data fine non valida");

        idEvento = prossimoIdEvento;
        prossimoIdEvento += 1;

        rivenditaAttiva[idEvento] = true;

        eventi[idEvento] = Evento({
            organizzatore: msg.sender,
            nome: nomeEvento,
            uriMetadatiBase: uriMetadatiBase,
            timestampInizio: timestampInizio,
            timestampFine: timestampFine,
            politicaRimborso: politicaRimborso,
            prezzo: prezzoBiglietto,
            quantitaMassima: quantitaMassima,
            bigliettiVenduti: 0,
            attivo: true,
            annullato: false
        });

        emit EventoCreato(
            idEvento,
            msg.sender,
            nomeEvento,
            prezzoBiglietto,
            quantitaMassima,
            timestampInizio,
            timestampFine,
            politicaRimborso
        );
    }

    /**
     * @notice Permette all'organizzatore di modificare il prezzo o sospendere le vendite.
     * @dev Non permette di riattivare un evento dopo che tutti i biglietti sono stati venduti.
     */
    function aggiornaEvento(
        uint256 idEvento,
        uint256 nuovoPrezzo,
        bool attivo
    ) external {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore == msg.sender, "MercatoTicket: non sei organizzatore");
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(block.timestamp < evento.timestampInizio, "MercatoTicket: evento gia iniziato");
        require(nuovoPrezzo > 0, "MercatoTicket: prezzo non valido");
        require(
            evento.bigliettiVenduti < evento.quantitaMassima || !attivo,
            "MercatoTicket: tutti i biglietti sono stati venduti"
        );

        evento.prezzo = nuovoPrezzo;
        evento.attivo = attivo;

        emit EventoAggiornato(idEvento, attivo, nuovoPrezzo);
    }

    /**
     * @notice Abilita o disabilita separatamente il mercato secondario di un evento.
     * @dev Disabilitare la rivendita non impedisce al venditore di annullare un annuncio già attivo.
     */
    function impostaRivendita(uint256 idEvento, bool attiva) external {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore == msg.sender, "MercatoTicket: non sei organizzatore");
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(block.timestamp < evento.timestampInizio, "MercatoTicket: evento gia iniziato");
        rivenditaAttiva[idEvento] = attiva;
    }

    /**
     * @notice Annulla definitivamente un evento.
     * @dev L'annullamento blocca vendite, rivendite e convalida ingressi.
     *      Con FondiBloccati i possessori possono richiedere il rimborso dai fondi
     *      custoditi. Con IncassiAnticipati il contratto non garantisce rimborsi on-chain.
     */
    function annullaEvento(uint256 idEvento) external nonReentrant {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore == msg.sender, "MercatoTicket: non sei organizzatore");
        require(!evento.annullato, "MercatoTicket: evento gia annullato");
        require(block.timestamp < evento.timestampFine, "MercatoTicket: evento gia terminato");
        require(
            evento.politicaRimborso == PoliticaRimborso.IncassiAnticipati ||
                block.timestamp < evento.timestampInizio,
            "MercatoTicket: evento gia iniziato"
        );

        evento.annullato = true;
        evento.attivo = false;

        emit EventoAnnullato(idEvento, msg.sender);

        if (evento.politicaRimborso == PoliticaRimborso.FondiBloccati) {
            // I fondi sono già custoditi: l'annullamento avvia automaticamente i rimborsi.
            rimborsiCollettiviAvviati[idEvento] = true;
            _processaRimborsiEvento(idEvento, MASSIMO_RIMBORSI_PER_BATCH);
        }
    }

    /**
     * @notice Acquista un biglietto nuovo pagando prezzo e commissione TOC in ETH.
     * @dev Prezzo e commissione sono contabilizzati separatamente; la commissione
     *      diventa subito disponibile alla piattaforma. La gas fee è pagata dal wallet
     *      alla rete e non è inclusa in msg.value.
     */
    function acquistaBiglietto(uint256 idEvento) external payable whenNotPaused nonReentrant {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore != address(0), "MercatoTicket: evento inesistente");
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(evento.attivo, "MercatoTicket: vendite sospese");
        require(block.timestamp < evento.timestampInizio, "MercatoTicket: evento gia iniziato");
        require(
            evento.bigliettiVenduti < evento.quantitaMassima,
            "MercatoTicket: biglietti esauriti"
        );
        uint256 commissione = (evento.prezzo * commissionePuntiBase) / 10_000;
        require(msg.value == evento.prezzo + commissione, "MercatoTicket: importo non corretto");

        _registraAcquistoWallet(idEvento, msg.sender);

        uint256 idBiglietto = prossimoIdBiglietto;
        prossimoIdBiglietto += 1;
        evento.bigliettiVenduti += 1;
        _bigliettiEvento[idEvento].push(idBiglietto);
        totaleVenditeEvento[idEvento] += evento.prezzo;

        // Registra prima l'appartenenza del biglietto, poi crea l'NFT.
        eventoDelBiglietto[idBiglietto] = idEvento;
        prezzoAcquistoOriginale[idBiglietto] = msg.value;
        uint256 numeroBigliettoEvento = evento.bigliettiVenduti;
        string memory uriBiglietto = string.concat(
            evento.uriMetadatiBase,
            numeroBigliettoEvento.toString(),
            ".json"
        );
        // Aggiorna prima lo stato e i saldi, prima della chiamata esterna al contratto NFT.
        commissioneAcquistoOriginale[idBiglietto] = commissione;
        // La commissione è separata dal prezzo del biglietto e diventa subito
        // disponibile alla piattaforma, indipendentemente dalla politica di rimborso.
        commissioniAccumulate += commissione;
        if (evento.politicaRimborso == PoliticaRimborso.FondiBloccati) {
            ricaviEventoBloccati[idEvento] += evento.prezzo;
            fondiRimborsoEvento[idEvento] += evento.prezzo;
        } else {
            // L'organizzatore riceve il prezzo intero del biglietto, senza la commissione TOC.
            saldiPrelevabili[evento.organizzatore] += evento.prezzo;
        }

        // Se la creazione dell'NFT fallisce, l'intera transazione viene annullata.
        contrattoBiglietti.creaBiglietto(msg.sender, idBiglietto, uriBiglietto);

        emit BigliettoAcquistato(idEvento, idBiglietto, msg.sender, msg.value);
    }

    /**
     * @notice Mette in rivendita un biglietto già acquistato esclusivamente al prezzo originario.
     * @dev Il prezzo di rivendita non può essere superiore né inferiore al prezzo pagato inizialmente.
     *      Il venditore deve prima autorizzare questo contratto NFT con
     *      approve() oppure setApprovalForAll(). Il biglietto viene custodito
     *      dal mercato fino all'acquisto o all'annullamento dell'annuncio.
     */
    function mettiInRivendita(
        uint256 idBiglietto,
        uint256 prezzoRichiesto
    ) external whenNotPaused nonReentrant {
        require(eventoDelBiglietto[idBiglietto] != 0, "MercatoTicket: biglietto non riconosciuto");
        require(
            contrattoBiglietti.ownerOf(idBiglietto) == msg.sender,
            "MercatoTicket: non sei proprietario"
        );
        Evento storage evento = eventi[eventoDelBiglietto[idBiglietto]];
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(rivenditaAttiva[eventoDelBiglietto[idBiglietto]], "MercatoTicket: rivendita sospesa");
        require(block.timestamp < evento.timestampInizio, "MercatoTicket: evento gia iniziato");
        require(prezzoRichiesto > 0, "MercatoTicket: prezzo non valido");
        require(
            prezzoRichiesto == prezzoAcquistoOriginale[idBiglietto],
            "MercatoTicket: rivendita solo al prezzo originale"
        );
        require(!ingressiUtilizzati[idBiglietto], "MercatoTicket: biglietto gia utilizzato");
        require(!rivendite[idBiglietto].attivo, "MercatoTicket: annuncio gia attivo");

        // Il trasferimento fallisce se il proprietario non ha autorizzato il mercato.
        contrattoBiglietti.safeTransferFrom(msg.sender, address(this), idBiglietto);

        rivendite[idBiglietto] = AnnuncioRivendita({
            venditore: msg.sender,
            prezzo: prezzoRichiesto,
            attivo: true
        });

        emit BigliettoMessoInVendita(idBiglietto, msg.sender, prezzoRichiesto);
    }

    /**
     * @notice Annulla un annuncio e restituisce il biglietto al venditore.
     */
    function annullaRivendita(uint256 idBiglietto) external nonReentrant {
        AnnuncioRivendita memory annuncio = rivendite[idBiglietto];
        require(annuncio.attivo, "MercatoTicket: annuncio non attivo");
        require(annuncio.venditore == msg.sender, "MercatoTicket: non sei venditore");

        delete rivendite[idBiglietto];
        contrattoBiglietti.safeTransferFrom(address(this), msg.sender, idBiglietto);

        emit RivenditaAnnullata(idBiglietto, msg.sender);
    }

    /**
     * @notice Acquista un biglietto custodito dal mercato per una rivendita.
     * @dev L'acquirente paga prezzo più commissione; il venditore riceve il prezzo intero.
     */
    function acquistaRivendita(uint256 idBiglietto) external payable whenNotPaused nonReentrant {
        AnnuncioRivendita memory annuncio = rivendite[idBiglietto];
        require(annuncio.attivo, "MercatoTicket: annuncio non attivo");
        Evento storage evento = eventi[eventoDelBiglietto[idBiglietto]];
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(rivenditaAttiva[eventoDelBiglietto[idBiglietto]], "MercatoTicket: rivendita sospesa");
        require(block.timestamp < evento.timestampInizio, "MercatoTicket: evento gia iniziato");
        require(msg.sender != annuncio.venditore, "MercatoTicket: non puoi acquistare il tuo biglietto");
        uint256 commissione = (annuncio.prezzo * commissionePuntiBase) / 10_000;
        require(msg.value == annuncio.prezzo + commissione, "MercatoTicket: importo non corretto");
        _registraAcquistoWallet(eventoDelBiglietto[idBiglietto], msg.sender);
        require(
            contrattoBiglietti.ownerOf(idBiglietto) == address(this),
            "MercatoTicket: biglietto non custodito dal mercato"
        );

        delete rivendite[idBiglietto];

        saldiPrelevabili[annuncio.venditore] += annuncio.prezzo;
        commissioniAccumulate += commissione;

        contrattoBiglietti.safeTransferFrom(address(this), msg.sender, idBiglietto);

        emit BigliettoRivenduto(
            idBiglietto,
            annuncio.venditore,
            msg.sender,
            msg.value,
            commissione
        );
    }

    /**
     * @notice Autorizza o revoca un addetto alla convalida degli ingressi.
     * @dev Solo l'organizzatore dell'evento può gestire i propri validatori.
     */
    function impostaValidatoreIngresso(uint256 idEvento, address validatore, bool autorizzato) external {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore == msg.sender, "MercatoTicket: non sei organizzatore");
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(block.timestamp < evento.timestampFine, "MercatoTicket: evento terminato");
        require(validatore != address(0), "MercatoTicket: validatore non valido");
        validatoriIngresso[idEvento][validatore] = autorizzato;
        emit ValidatoreIngressoImpostato(idEvento, validatore, autorizzato);
    }

    /**
     * @notice Registra l'ingresso di un biglietto all'evento.
     * @dev Possono convalidare l'organizzatore e i validatori autorizzati.
     *      La convalida è ammessa soltanto nella finestra temporale dell'evento.
     *      Un biglietto in rivendita o già utilizzato non può essere convalidato.
     */
    function validaIngresso(uint256 idBiglietto) external {
        uint256 idEvento = eventoDelBiglietto[idBiglietto];
        require(idEvento != 0, "MercatoTicket: biglietto non riconosciuto");

        Evento storage evento = eventi[idEvento];
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(
            evento.organizzatore == msg.sender || validatoriIngresso[idEvento][msg.sender],
            "MercatoTicket: non sei un validatore autorizzato"
        );
        require(block.timestamp >= evento.timestampInizio, "MercatoTicket: evento non iniziato");
        require(block.timestamp <= evento.timestampFine, "MercatoTicket: evento terminato");
        require(!ingressiUtilizzati[idBiglietto], "MercatoTicket: ingresso gia utilizzato");
        require(
            contrattoBiglietti.ownerOf(idBiglietto) != address(this),
            "MercatoTicket: biglietto in rivendita"
        );

        ingressiUtilizzati[idBiglietto] = true;
        emit IngressoValidato(idEvento, idBiglietto, msg.sender);
    }

    /**
     * @dev Registra l'acquisto nel limite cumulativo per wallet ed evento.
     *      È un controllo temporaneo: non impedisce a una stessa persona di usare
     *      wallet diversi. L'integrazione di un sistema d'identità verrà aggiunta
     *      in una fase successiva.
     */
    function _registraAcquistoWallet(
        uint256 idEvento,
        address acquirente
    ) internal {
        uint256 quantitaAggiornata =
            bigliettiAcquistatiPerWallet[idEvento][acquirente] + 1;
        require(
            quantitaAggiornata <= LIMITE_BIGLIETTI_PER_WALLET,
            "MercatoTicket: limite di 6 biglietti per wallet superato"
        );

        bigliettiAcquistatiPerWallet[idEvento][acquirente] = quantitaAggiornata;
        emit AcquistoWalletRegistrato(
            idEvento,
            acquirente,
            quantitaAggiornata
        );
    }

    /**
     * @notice Preleva il saldo accumulato da vendite iniziali o rivendite.
     * @dev Il saldo viene azzerato prima dell'invio per impedire doppi prelievi.
     */
    function prelevaRicaviEvento(uint256 idEvento) external nonReentrant {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore == msg.sender, "MercatoTicket: non sei organizzatore");
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(block.timestamp >= evento.timestampInizio, "MercatoTicket: evento non iniziato");
        require(evento.politicaRimborso == PoliticaRimborso.FondiBloccati, "MercatoTicket: incassi gia disponibili all'organizzatore");

        uint256 importo = ricaviEventoBloccati[idEvento];
        require(importo > 0, "MercatoTicket: nessun ricavo da prelevare");
        ricaviEventoBloccati[idEvento] = 0;
        saldiPrelevabili[msg.sender] += importo;
         fondiRimborsoEvento[idEvento] = 0;

        emit RicaviEventoSbloccati(idEvento, msg.sender, importo);
    }

    /**
     * @notice L'organizzatore finanzia e avvia i rimborsi collettivi per un evento
     *         annullato che ha scelto la modalità IncassiAnticipati.
     * @dev Deve versare l'intero importo lordo venduto; nessun acquirente deve
     *      presentare una richiesta individuale. La procedura viene elaborata a lotti.
     */
    function avviaRimborsiCollettivi(uint256 idEvento) external payable nonReentrant {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore == msg.sender, "MercatoTicket: non sei organizzatore");
        require(evento.annullato, "MercatoTicket: evento non annullato");
        require(evento.politicaRimborso == PoliticaRimborso.IncassiAnticipati, "MercatoTicket: rimborsi gia coperti dai fondi bloccati");
        require(!rimborsiCollettiviAvviati[idEvento], "MercatoTicket: rimborsi gia avviati");
        require(msg.value == totaleVenditeEvento[idEvento], "MercatoTicket: versare l'intero importo delle vendite");

        fondiRimborsoEvento[idEvento] = msg.value;
        rimborsiCollettiviAvviati[idEvento] = true;
        emit RimborsiCollettiviAvviati(idEvento, msg.sender, msg.value);
        _processaRimborsiEvento(idEvento, MASSIMO_RIMBORSI_PER_BATCH);
    }

    /**
     * @notice Prosegue i rimborsi collettivi già avviati, senza richiedere azioni agli acquirenti.
     * @dev È permissionless per consentire all'interfaccia o a un servizio automatico
     *      di elaborare più lotti senza una transazione illimitata per eventi grandi.
     */
    function processaRimborsiEvento(uint256 idEvento, uint256 quantita) external nonReentrant {
        require(rimborsiCollettiviAvviati[idEvento], "MercatoTicket: rimborsi non avviati");
        require(quantita > 0 && quantita <= MASSIMO_RIMBORSI_PER_BATCH, "MercatoTicket: dimensione lotto non valida");
        _processaRimborsiEvento(idEvento, quantita);
    }

    function _processaRimborsiEvento(uint256 idEvento, uint256 quantita) internal {
        uint256[] storage biglietti = _bigliettiEvento[idEvento];
        uint256 posizione = cursoreRimborsiEvento[idEvento];
        uint256 fine = posizione + quantita;
        if (fine > biglietti.length) fine = biglietti.length;

        while (posizione < fine) {
            uint256 idBiglietto = biglietti[posizione];
            posizione++;
            if (bigliettiRimborsati[idBiglietto]) continue;

            address proprietario = contrattoBiglietti.ownerOf(idBiglietto);
            address destinatario = proprietario;
            if (proprietario == address(this)) {
                AnnuncioRivendita memory annuncio = rivendite[idBiglietto];
                require(annuncio.attivo, "MercatoTicket: biglietto in custodia senza annuncio");
                destinatario = annuncio.venditore;
                delete rivendite[idBiglietto];
            }

            uint256 importo = prezzoAcquistoOriginale[idBiglietto];
            require(fondiRimborsoEvento[idEvento] >= importo, "MercatoTicket: fondi rimborso insufficienti");
            bigliettiRimborsati[idBiglietto] = true;
            fondiRimborsoEvento[idEvento] -= importo;

            Evento storage evento = eventi[idEvento];
            if (evento.politicaRimborso == PoliticaRimborso.FondiBloccati) {
                ricaviEventoBloccati[idEvento] -= importo;
            }

            contrattoBiglietti.distruggiBiglietto(idBiglietto);

            // Pull payment: nessuna chiamata esterna al destinatario durante il rimborso.
            // Evita griefing tramite consumo di gas e impedisce callback/rientranza dal wallet.
            saldiPrelevabili[destinatario] += importo;
            emit RimborsoEseguito(idEvento, idBiglietto, destinatario, importo);
        }

        cursoreRimborsiEvento[idEvento] = posizione;
        emit AvanzamentoRimborsi(idEvento, posizione, biglietti.length, posizione == biglietti.length);
    }

    /**
     * @notice Restituisce il numero di biglietti ancora da elaborare per un evento.
     */
    function bigliettiDaRimborsare(uint256 idEvento) external view returns (uint256) {
        return _bigliettiEvento[idEvento].length - cursoreRimborsiEvento[idEvento];
    }

    /*
     * Non esiste una funzione di rimborso individuale: i rimborsi sono collettivi.
     */

    /**
     * @notice Preleva il saldo disponibile del chiamante.
     * @dev Il saldo viene azzerato prima dell'invio per impedire doppi prelievi.
     */
    function prelevaSaldo() external nonReentrant {
        uint256 importo = saldiPrelevabili[msg.sender];
        require(importo > 0, "MercatoTicket: saldo vuoto");

        saldiPrelevabili[msg.sender] = 0;
        (bool riuscito, ) = payable(msg.sender).call{value: importo}("");
        require(riuscito, "MercatoTicket: trasferimento ETH fallito");

        emit SaldoPrelevato(msg.sender, importo);
    }

    /**
     * @notice Preleva le commissioni accumulate verso un indirizzo scelto.
     * @dev Solo il proprietario del mercato può prelevare le commissioni.
     */
    function prelevaCommissioni(address destinatario) external onlyOwner nonReentrant {
        require(destinatario != address(0), "MercatoTicket: destinatario non valido");
        uint256 importo = commissioniAccumulate;
        require(importo > 0, "MercatoTicket: nessuna commissione");

        commissioniAccumulate = 0;
        (bool riuscito, ) = payable(destinatario).call{value: importo}("");
        require(riuscito, "MercatoTicket: trasferimento ETH fallito");

        emit CommissioniPrelevate(destinatario, importo);
    }

    /**
     * @notice Aggiorna la commissione del mercato.
     * @dev Limite massimo del 10% per evitare impostazioni eccessive accidentali.
     */
    function impostaCommissione(uint256 nuovaCommissionePuntiBase) external onlyOwner {
        require(nuovaCommissionePuntiBase <= 1_000, "MercatoTicket: commissione oltre il 10%");

        uint256 vecchiaCommissione = commissionePuntiBase;
        commissionePuntiBase = nuovaCommissionePuntiBase;

        emit CommissioneAggiornata(vecchiaCommissione, nuovaCommissionePuntiBase);
    }
}
