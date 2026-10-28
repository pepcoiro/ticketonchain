// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
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
contract MercatoTicket is Ownable, ReentrancyGuard, Pausable, IERC721Receiver {
    using Strings for uint256;

    /// @notice Contratto NFT utilizzato per creare e trasferire i biglietti.
    TicketOnChain public immutable contrattoBiglietti;

    /// @notice Numero massimo di biglietti acquistabili da un wallet per evento.
    /// @dev Limite temporaneo: senza un sistema di identità, wallet diversi non sono collegabili.
    uint256 public constant LIMITE_BIGLIETTI_PER_WALLET = 6;

    /// @notice Conteggio cumulativo degli acquisti per wallet ed evento.
    /// @dev Il conteggio non diminuisce quando un biglietto viene rivenduto.
    mapping(uint256 idEvento => mapping(address wallet => uint256 quantita))
        public bigliettiAcquistatiPerWallet;

    /// @notice Indica quali indirizzi sono autorizzati dall'amministratore a creare eventi.
    mapping(address organizzatore => bool autorizzato) public organizzatoriAutorizzati;

    /// @notice Commissione applicata alle vendite, espressa in punti base.
    /// @dev 100 punti base corrispondono all'1%; 1.000 corrispondono al 10%.
    uint256 public commissionePuntiBase = 250;

    /// @notice Prossimo identificativo disponibile per un evento.
    uint256 public prossimoIdEvento = 1;

    /// @notice Prossimo identificativo disponibile per un biglietto.
    uint256 public prossimoIdBiglietto = 1;

    /// @dev Denaro prelevabile da organizzatori e venditori.
    mapping(address beneficiario => uint256 importo) public saldiPrelevabili;

    /// @notice Commissioni accumulate e prelevabili dal proprietario del mercato.
    uint256 public commissioniAccumulate;

    /// @notice Ricavi netti delle vendite iniziali bloccati fino all'inizio dell'evento.
    mapping(uint256 idEvento => uint256 importo) public ricaviEventoBloccati;

    /// @notice Fondi accantonati per rimborsare i biglietti in caso di annullamento.
    mapping(uint256 idEvento => uint256 importo) public fondiRimborsoEvento;

    /// @notice Commissioni iniziali accantonate fino all'inizio dell'evento.
    mapping(uint256 idEvento => uint256 importo) public commissioniEventoBloccate;

    /// @notice Indica se il biglietto è già stato rimborsato.
    mapping(uint256 idBiglietto => bool rimborsato) public bigliettiRimborsati;

    struct Evento {
        address organizzatore;
        string nome;
        string uriMetadatiBase;
        uint256 timestampInizio;
        uint256 timestampFine;
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
        uint256 timestampFine
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
    event RimborsoRichiesto(uint256 indexed idEvento, uint256 indexed idBiglietto, address indexed destinatario, uint256 importo);
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
            indirizzoContrattoBiglietti != address(0),
            "MercatoTicket: indirizzo NFT non valido"
        );
        contrattoBiglietti = TicketOnChain(indirizzoContrattoBiglietti);
        organizzatoriAutorizzati[msg.sender] = true;
        emit OrganizzatoreAutorizzato(msg.sender, true);
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
     *        Per esempio, "ipfs://CID/": il biglietto 12 userà "ipfs://CID/12.json".
     * @param prezzoBiglietto Prezzo di un biglietto in ETH (espresso in wei).
     * @param quantitaMassima Numero totale di biglietti emettibili per l'evento.
     * @param timestampInizio Data e ora di inizio dell'evento come timestamp Unix in secondi.
     * @param timestampFine Data e ora di fine dell'evento come timestamp Unix in secondi.
     */
    function creaEvento(
        string calldata nomeEvento,
        string calldata uriMetadatiBase,
        uint256 prezzoBiglietto,
        uint256 quantitaMassima,
        uint256 timestampInizio,
        uint256 timestampFine
    ) external whenNotPaused returns (uint256 idEvento) {
        require(
            organizzatoriAutorizzati[msg.sender],
            "MercatoTicket: organizzatore non autorizzato"
        );
        require(bytes(nomeEvento).length > 0, "MercatoTicket: nome vuoto");
        require(bytes(uriMetadatiBase).length > 0, "MercatoTicket: URI metadati vuoto");
        require(prezzoBiglietto > 0, "MercatoTicket: prezzo non valido");
        require(quantitaMassima > 0, "MercatoTicket: quantita non valida");
        require(timestampInizio > block.timestamp, "MercatoTicket: data evento non futura");
        require(timestampFine > timestampInizio, "MercatoTicket: data fine non valida");

        idEvento = prossimoIdEvento;
        prossimoIdEvento += 1;

        eventi[idEvento] = Evento({
            organizzatore: msg.sender,
            nome: nomeEvento,
            uriMetadatiBase: uriMetadatiBase,
            timestampInizio: timestampInizio,
            timestampFine: timestampFine,
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
            timestampFine
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
     * @notice Annulla definitivamente un evento.
     * @dev L'annullamento blocca vendite, rivendite e convalida ingressi.
     *      Non esegue rimborsi automatici: la gestione dei rimborsi resta a carico
     *      dell'organizzatore, secondo le condizioni applicabili.
     */
    function annullaEvento(uint256 idEvento) external {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore == msg.sender, "MercatoTicket: non sei organizzatore");
        require(!evento.annullato, "MercatoTicket: evento gia annullato");
        require(block.timestamp < evento.timestampInizio, "MercatoTicket: evento gia iniziato");

        evento.annullato = true;
        evento.attivo = false;

        // I ricavi e le commissioni iniziali restano accantonati per consentire i rimborsi.
        emit EventoAnnullato(idEvento, msg.sender);
    }

    /**
     * @notice Acquista un biglietto nuovo pagando in ETH.
     * @dev La commissione viene accantonata e il ricavo netto diventa prelevabile
     *      dall'organizzatore. Il pagamento non viene inviato direttamente durante
     *      l'acquisto, riducendo il rischio di chiamate esterne non necessarie.
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
        require(msg.value == evento.prezzo, "MercatoTicket: importo non corretto");

        _registraAcquistoWallet(idEvento, msg.sender);

        uint256 idBiglietto = prossimoIdBiglietto;
        prossimoIdBiglietto += 1;
        evento.bigliettiVenduti += 1;

        // Registra prima l'appartenenza del biglietto, poi crea l'NFT.
        eventoDelBiglietto[idBiglietto] = idEvento;
        prezzoAcquistoOriginale[idBiglietto] = msg.value;
        string memory uriBiglietto = string.concat(
            evento.uriMetadatiBase,
            idBiglietto.toString(),
            ".json"
        );
        // Aggiorna prima lo stato e i saldi, prima della chiamata esterna al contratto NFT.
        uint256 commissione = (msg.value * commissionePuntiBase) / 10_000;
        ricaviEventoBloccati[idEvento] += msg.value - commissione;
        commissioniEventoBloccate[idEvento] += commissione;
        fondiRimborsoEvento[idEvento] += msg.value;

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
        require(evento.attivo, "MercatoTicket: vendite sospese");
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
     * @dev Il venditore riceve un saldo prelevabile al netto della commissione.
     */
    function acquistaRivendita(uint256 idBiglietto) external payable whenNotPaused nonReentrant {
        AnnuncioRivendita memory annuncio = rivendite[idBiglietto];
        require(annuncio.attivo, "MercatoTicket: annuncio non attivo");
        Evento storage evento = eventi[eventoDelBiglietto[idBiglietto]];
        require(!evento.annullato, "MercatoTicket: evento annullato");
        require(evento.attivo, "MercatoTicket: vendite sospese");
        require(block.timestamp < evento.timestampInizio, "MercatoTicket: evento gia iniziato");
        require(msg.sender != annuncio.venditore, "MercatoTicket: non puoi acquistare il tuo biglietto");
        require(msg.value == annuncio.prezzo, "MercatoTicket: importo non corretto");
        _registraAcquistoWallet(eventoDelBiglietto[idBiglietto], msg.sender);
        require(
            contrattoBiglietti.ownerOf(idBiglietto) == address(this),
            "MercatoTicket: biglietto non custodito dal mercato"
        );

        delete rivendite[idBiglietto];

        uint256 commissione = (msg.value * commissionePuntiBase) / 10_000;
        saldiPrelevabili[annuncio.venditore] += msg.value - commissione;
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

        uint256 importo = ricaviEventoBloccati[idEvento];
        require(importo > 0, "MercatoTicket: nessun ricavo da prelevare");
        ricaviEventoBloccati[idEvento] = 0;
        saldiPrelevabili[msg.sender] += importo;
        commissioniAccumulate += commissioniEventoBloccate[idEvento];
        commissioniEventoBloccate[idEvento] = 0;
        fondiRimborsoEvento[idEvento] = 0;

        emit RicaviEventoSbloccati(idEvento, msg.sender, importo);
    }

    function richiediRimborso(uint256 idBiglietto) external nonReentrant {
        uint256 idEvento = eventoDelBiglietto[idBiglietto];
        require(idEvento != 0, "MercatoTicket: biglietto non riconosciuto");
        Evento storage evento = eventi[idEvento];
        require(evento.annullato, "MercatoTicket: evento non annullato");
        require(!bigliettiRimborsati[idBiglietto], "MercatoTicket: biglietto gia rimborsato");
        require(
            contrattoBiglietti.ownerOf(idBiglietto) == msg.sender,
            "MercatoTicket: solo proprietario del biglietto"
        );

        uint256 importo = prezzoAcquistoOriginale[idBiglietto];
        require(fondiRimborsoEvento[idEvento] >= importo, "MercatoTicket: fondi rimborso insufficienti");

        bigliettiRimborsati[idBiglietto] = true;
        fondiRimborsoEvento[idEvento] -= importo;
        contrattoBiglietti.distruggiBiglietto(idBiglietto);

        (bool riuscito, ) = payable(msg.sender).call{value: importo}("");
        require(riuscito, "MercatoTicket: trasferimento rimborso fallito");

        emit RimborsoRichiesto(idEvento, idBiglietto, msg.sender, importo);
    }

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
