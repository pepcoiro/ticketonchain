// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract MercatoTicketFuzzSicurezzaTest is Test {
    MercatoTicket private mercato;
    TicketOnChain private nft;
    address private alice = address(0xA11CE);

    function setUp() public {
        nft = new TicketOnChain();
        mercato = new MercatoTicket(address(nft));
        nft.impostaMercato(address(mercato));
    }

    function _creaEvento(
        MercatoTicket.PoliticaRimborso politica,
        uint256 prezzo
    ) internal returns (uint256) {
        return mercato.creaEvento(
            "Evento fuzz",
            "ipfs://fuzz/",
            prezzo,
            2,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            politica
        );
    }

    function testFuzzFondiBloccatiRimborsaPrezzoIntegrale(
        uint96 prezzoRaw,
        uint16 commissioneRaw
    ) public {
        uint256 prezzo = bound(uint256(prezzoRaw), 1, 10 ether);
        uint256 commissione = bound(uint256(commissioneRaw), 0, 1_000);
        mercato.impostaCommissione(commissione);
        uint256 idEvento = _creaEvento(
            MercatoTicket.PoliticaRimborso.FondiBloccati,
            prezzo
        );
        vm.deal(alice, prezzo);
        uint256 saldoIniziale = alice.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: prezzo}(idEvento);
        assertEq(mercato.fondiRimborsoEvento(idEvento), prezzo);
        assertEq(
            mercato.ricaviEventoBloccati(idEvento) +
                mercato.commissioniEventoBloccate(idEvento),
            prezzo
        );

        mercato.annullaEvento(idEvento);

        assertEq(alice.balance, saldoIniziale - prezzo);
        assertEq(mercato.saldiPrelevabili(alice), prezzo);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
        assertEq(mercato.ricaviEventoBloccati(idEvento), 0);
        assertEq(mercato.commissioniEventoBloccate(idEvento), 0);
    }

    function testFuzzIncassiAnticipatiRichiedeEsattamenteIlLordo(
        uint96 prezzoRaw,
        uint16 commissioneRaw
    ) public {
        uint256 prezzo = bound(uint256(prezzoRaw), 1, 10 ether);
        uint256 commissione = bound(uint256(commissioneRaw), 0, 1_000);
        mercato.impostaCommissione(commissione);
        uint256 idEvento = _creaEvento(
            MercatoTicket.PoliticaRimborso.IncassiAnticipati,
            prezzo
        );
        vm.deal(alice, prezzo);
        uint256 saldoIniziale = alice.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: prezzo}(idEvento);
        assertEq(mercato.saldiPrelevabili(address(this)), prezzo - (prezzo * commissione / 10_000));
        assertEq(mercato.commissioniAccumulate(), prezzo * commissione / 10_000);

        mercato.annullaEvento(idEvento);

        vm.expectRevert("MercatoTicket: versare l'intero importo delle vendite");
        mercato.avviaRimborsiCollettivi{value: prezzo - 1}(idEvento);

        mercato.avviaRimborsiCollettivi{value: prezzo}(idEvento);
        assertEq(alice.balance, saldoIniziale - prezzo);
        assertEq(mercato.saldiPrelevabili(alice), prezzo);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
    }
}
