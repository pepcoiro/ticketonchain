// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
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
contract MercatoTicket is Ownable, ReentrancyGuard, IERC721Receiver {
    using Strings for uint256;

    /// @notice Contratto NFT utilizzato per creare e trasferire i biglietti.
    TicketOnChain public immutable contrattoBiglietti;

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

    struct Evento {
        address organizzatore;
        string nome;
        string uriMetadatiBase;
        uint256 prezzo;
        uint256 quantitaMassima;
        uint256 bigliettiVenduti;
        bool attivo;
    }

    struct AnnuncioRivendita {
        address venditore;
        uint256 prezzo;
        bool attivo;
    }

    /// @notice Dati degli eventi registrati nel mercato.
    mapping(uint256 idEvento => Evento dati) public eventi;

    /// @notice Evento di appartenenza per ciascun biglietto creato dal mercato.
    mapping(uint256 idBiglietto => uint256 idEvento) public eventoDelBiglietto;

    /// @notice Annunci di rivendita indicizzati per identificativo del biglietto.
    mapping(uint256 idBiglietto => AnnuncioRivendita annuncio) public rivendite;

    /// @notice Indica se un biglietto è già stato utilizzato per entrare all'evento.
    mapping(uint256 idBiglietto => bool utilizzato) public ingressiUtilizzati;

    event EventoCreato(
        uint256 indexed idEvento,
        address indexed organizzatore,
        string nome,
        uint256 prezzo,
        uint256 quantitaMassima
    );
    event EventoAggiornato(uint256 indexed idEvento, bool attivo, uint256 prezzo);
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
    event IngressoValidato(uint256 indexed idEvento, uint256 indexed idBiglietto, address indexed validatore);

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
    }

    /**
     * @notice Registra un evento e mette in vendita i suoi biglietti.
     * @param nomeEvento Nome leggibile dell'evento.
     * @param uriMetadatiBase URI che termina con "/" e contiene i file JSON dei biglietti.
     *        Per esempio, "ipfs://CID/": il biglietto 12 userà "ipfs://CID/12.json".
     * @param prezzoBiglietto Prezzo di un biglietto in ETH (espresso in wei).
     * @param quantitaMassima Numero totale di biglietti emettibili per l'evento.
     */
    function creaEvento(
        string calldata nomeEvento,
        string calldata uriMetadatiBase,
        uint256 prezzoBiglietto,
        uint256 quantitaMassima
    ) external returns (uint256 idEvento) {
        require(bytes(nomeEvento).length > 0, "MercatoTicket: nome vuoto");
        require(bytes(uriMetadatiBase).length > 0, "MercatoTicket: URI metadati vuoto");
        require(prezzoBiglietto > 0, "MercatoTicket: prezzo non valido");
        require(quantitaMassima > 0, "MercatoTicket: quantita non valida");

        idEvento = prossimoIdEvento;
        prossimoIdEvento += 1;

        eventi[idEvento] = Evento({
            organizzatore: msg.sender,
            nome: nomeEvento,
            uriMetadatiBase: uriMetadatiBase,
            prezzo: prezzoBiglietto,
            quantitaMassima: quantitaMassima,
            bigliettiVenduti: 0,
            attivo: true
        });

        emit EventoCreato(
            idEvento,
            msg.sender,
            nomeEvento,
            prezzoBiglietto,
            quantitaMassima
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
     * @notice Acquista un biglietto nuovo pagando in ETH.
     * @dev La commissione viene accantonata e il ricavo netto diventa prelevabile
     *      dall'organizzatore. Il pagamento non viene inviato direttamente durante
     *      l'acquisto, riducendo il rischio di chiamate esterne non necessarie.
     */
    function acquistaBiglietto(uint256 idEvento) external payable nonReentrant {
        Evento storage evento = eventi[idEvento];
        require(evento.organizzatore != address(0), "MercatoTicket: evento inesistente");
        require(evento.attivo, "MercatoTicket: vendite sospese");
        require(
            evento.bigliettiVenduti < evento.quantitaMassima,
            "MercatoTicket: biglietti esauriti"
        );
        require(msg.value == evento.prezzo, "MercatoTicket: importo non corretto");

        uint256 idBiglietto = prossimoIdBiglietto;
        prossimoIdBiglietto += 1;
        evento.bigliettiVenduti += 1;

        // Registra prima l'appartenenza del biglietto, poi crea l'NFT.
        eventoDelBiglietto[idBiglietto] = idEvento;
        string memory uriBiglietto = string.concat(
            evento.uriMetadatiBase,
            idBiglietto.toString(),
            ".json"
        );
        contrattoBiglietti.creaBiglietto(msg.sender, idBiglietto, uriBiglietto);

        uint256 commissione = (msg.value * commissionePuntiBase) / 10_000;
        saldiPrelevabili[evento.organizzatore] += msg.value - commissione;
        commissioniAccumulate += commissione;

        emit BigliettoAcquistato(idEvento, idBiglietto, msg.sender, msg.value);
    }

    /**
     * @notice Mette in rivendita un biglietto già acquistato.
     * @dev Il venditore deve prima autorizzare questo contratto NFT con
     *      approve() oppure setApprovalForAll(). Il biglietto viene custodito
     *      dal mercato fino all'acquisto o all'annullamento dell'annuncio.
     */
    function mettiInRivendita(
        uint256 idBiglietto,
        uint256 prezzoRichiesto
    ) external nonReentrant {
        require(eventoDelBiglietto[idBiglietto] != 0, "MercatoTicket: biglietto non riconosciuto");
        require(
            contrattoBiglietti.ownerOf(idBiglietto) == msg.sender,
            "MercatoTicket: non sei proprietario"
        );
        require(prezzoRichiesto > 0, "MercatoTicket: prezzo non valido");
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
    function acquistaRivendita(uint256 idBiglietto) external payable nonReentrant {
        AnnuncioRivendita memory annuncio = rivendite[idBiglietto];
        require(annuncio.attivo, "MercatoTicket: annuncio non attivo");
        require(msg.sender != annuncio.venditore, "MercatoTicket: non puoi acquistare il tuo biglietto");
        require(msg.value == annuncio.prezzo, "MercatoTicket: importo non corretto");
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
     * @notice Registra l'ingresso di un biglietto all'evento.
     * @dev In questa prima versione soltanto l'organizzatore dell'evento può
     *      convalidare l'ingresso. Un biglietto in custodia per la rivendita non
     *      può essere convalidato e un biglietto già usato non può entrare di nuovo.
     */
    function validaIngresso(uint256 idBiglietto) external {
        uint256 idEvento = eventoDelBiglietto[idBiglietto];
        require(idEvento != 0, "MercatoTicket: biglietto non riconosciuto");

        Evento storage evento = eventi[idEvento];
        require(
            evento.organizzatore == msg.sender,
            "MercatoTicket: solo organizzatore"
        );
        require(!ingressiUtilizzati[idBiglietto], "MercatoTicket: ingresso gia utilizzato");
        require(
            contrattoBiglietti.ownerOf(idBiglietto) != address(this),
            "MercatoTicket: biglietto in rivendita"
        );

        ingressiUtilizzati[idBiglietto] = true;
        emit IngressoValidato(idEvento, idBiglietto, msg.sender);
    }

    /**
     * @notice Preleva il saldo accumulato da vendite iniziali o rivendite.
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
