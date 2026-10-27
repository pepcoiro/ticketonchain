// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TicketOnChain
 * @notice Rappresenta un biglietto per eventi come NFT sulla blockchain.
 * @dev Solo il contratto del mercato può creare biglietti e trasferirli tra
 *      proprietari. Questo permette al mercato di applicare le regole di rivendita.
 *
 *      Prima della pubblicazione su una rete reale, aggiungere ed eseguire test.
 */
contract TicketOnChain is ERC721, Ownable {
    /// @notice Indirizzo del contratto del mercato autorizzato.
    address public mercato;

    /// @dev Associa a ogni identificativo del biglietto il suo indirizzo dei metadati.
    mapping(uint256 identificativoBiglietto => string indirizzoMetadati)
        private _indirizziMetadati;

    /// @notice Emesso quando viene configurato il contratto del mercato.
    event MercatoImpostato(address indicizzato indirizzoMercato);

    /// @notice Emesso quando viene creato un biglietto.
    event BigliettoCreato(
        uint256 indicizzato identificativoBiglietto,
        address indicizzato destinatario,
        string indirizzoMetadati
    );

    constructor()
        ERC721("TicketOnChain", "TICKET")
        Ownable(msg.sender)
    {}

    /// @dev Limita l'esecuzione alle chiamate provenienti dal mercato autorizzato.
    modifier soloMercato() {
        require(msg.sender == mercato, "TicketOnChain: solo il mercato");
        _;
    }

    /**
     * @notice Imposta l'indirizzo del contratto del mercato.
     * @dev Può farlo soltanto il proprietario e soltanto una volta.
     */
    function impostaMercato(address indirizzoMercato) external onlyOwner {
        require(mercato == address(0), "TicketOnChain: mercato gia impostato");
        require(
            indirizzoMercato != address(0),
            "TicketOnChain: indirizzo del mercato non valido"
        );

        mercato = indirizzoMercato;
        emit MercatoImpostato(indirizzoMercato);
    }

    /**
     * @notice Crea un NFT che rappresenta un biglietto e lo assegna al destinatario.
     * @dev Solo il mercato autorizzato può creare biglietti.
     * @param destinatario Indirizzo del primo proprietario del biglietto.
     * @param identificativoBiglietto Numero univoco del biglietto.
     * @param indirizzoMetadati Indirizzo che contiene i metadati del biglietto.
     */
    function creaBiglietto(
        address destinatario,
        uint256 identificativoBiglietto,
        string calldata indirizzoMetadati
    ) external soloMercato {
        require(
            destinatario != address(0),
            "TicketOnChain: destinatario non valido"
        );
        require(
            bytes(indirizzoMetadati).length > 0,
            "TicketOnChain: indirizzo metadati vuoto"
        );

        _indirizziMetadati[identificativoBiglietto] = indirizzoMetadati;
        _safeMint(destinatario, identificativoBiglietto);

        emit BigliettoCreato(
            identificativoBiglietto,
            destinatario,
            indirizzoMetadati
        );
    }

    /**
     * @notice Restituisce l'indirizzo dei metadati associati a un biglietto.
     * @param identificativoBiglietto Numero del biglietto da consultare.
     */
    function tokenURI(
        uint256 identificativoBiglietto
    ) public view override returns (string memory) {
        _requireOwned(identificativoBiglietto);
        return _indirizziMetadati[identificativoBiglietto];
    }

    /**
     * @dev Impedisce il trasferimento diretto tra utenti: i trasferimenti
     *      da un proprietario a un altro devono passare dal mercato.
     *      La creazione e la distruzione non sono bloccate da questa regola.
     */
    function _update(
        address destinatario,
        uint256 identificativoBiglietto,
        address autorizzazione
    ) internal override returns (address) {
        address proprietarioPrecedente = _ownerOf(identificativoBiglietto);

        if (
            proprietarioPrecedente != address(0) &&
            destinatario != address(0)
        ) {
            require(
                msg.sender == mercato,
                "TicketOnChain: trasferimento consentito solo tramite mercato"
            );
        }

        return super._update(
            destinatario,
            identificativoBiglietto,
            autorizzazione
        );
    }
}
