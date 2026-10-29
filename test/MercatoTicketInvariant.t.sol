// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract GestoreMercatoInvariant {
    MercatoTicket public immutable mercato;
    uint256[] private _eventiCreati;

    constructor(MercatoTicket mercato_) {
        mercato = mercato_;
    }

    receive() external payable {}

    function creaECompra(uint96 prezzoRaw) external {
        uint256 prezzo = uint256(prezzoRaw) % 1 gwei + 1;
        uint256 idEvento = mercato.creaEvento(
            "Evento invariant",
            "ipfs://invariant/",
            prezzo,
            1,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );
        _eventiCreati.push(idEvento);
        mercato.acquistaBiglietto{value: prezzo}(idEvento);
    }

    function annullaUltimoEvento() external {
        uint256 quantita = _eventiCreati.length;
        if (quantita == 0) return;
        try mercato.annullaEvento(_eventiCreati[quantita - 1]) {} catch {}
    }

    function processaUltimoLotto(uint8 quantitaRaw) external {
        uint256 quantitaEventi = _eventiCreati.length;
        if (quantitaEventi == 0) return;
        uint256 idEvento = _eventiCreati[quantitaEventi - 1];
        uint256 quantita = uint256(quantitaRaw) % 20 + 1;
        try mercato.processaRimborsiEvento(idEvento, quantita) {} catch {}
    }

    function numeroEventi() external view returns (uint256) {
        return _eventiCreati.length;
    }

    function eventoCreato(uint256 indice) external view returns (uint256) {
        return _eventiCreati[indice];
    }
}

contract MercatoTicketInvariantTest is Test, StdInvariant {
    MercatoTicket private mercato;
    TicketOnChain private nft;
    GestoreMercatoInvariant private gestore;

    function setUp() public {
        nft = new TicketOnChain();
        mercato = new MercatoTicket(address(nft));
        nft.impostaMercato(address(mercato));
        gestore = new GestoreMercatoInvariant(mercato);
        mercato.impostaOrganizzatore(address(gestore), true);
        vm.deal(address(gestore), 100 ether);
        targetContract(address(gestore));
    }

    function invariantBigliettiRimborsatiSonoDistrutti() public view {
        uint256 prossimo = mercato.prossimoIdBiglietto();
        for (uint256 idBiglietto = 1; idBiglietto < prossimo; idBiglietto++) {
            (bool esiste, ) = address(nft).staticcall(
                abi.encodeWithSelector(nft.ownerOf.selector, idBiglietto)
            );
            if (mercato.bigliettiRimborsati(idBiglietto)) {
                assertFalse(esiste, "biglietto rimborsato ancora esistente");
            } else {
                assertTrue(esiste, "biglietto non rimborsato inesistente");
            }
        }
    }

    function invariantFondiBloccatiSonoSempreCoperti() public view {
        uint256 riserveTotali;
        uint256 numeroEventi = gestore.numeroEventi();
        for (uint256 i = 0; i < numeroEventi; i++) {
            riserveTotali += mercato.fondiRimborsoEvento(gestore.eventoCreato(i));
        }
        assertGe(address(mercato).balance, riserveTotali, "riserve rimborsi non coperte");
    }
}
