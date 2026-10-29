// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract MercatoTicketRimborsiTest is Test {
    MercatoTicket private mercato;
    TicketOnChain private nft;

    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function setUp() public {
        vm.deal(address(this), 100 ether);
        nft = new TicketOnChain();
        mercato = new MercatoTicket(address(nft));
        nft.impostaMercato(address(mercato));
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
    }

    function _creaEvento(
        MercatoTicket.PoliticaRimborso politica,
        uint256 quantita
    ) internal returns (uint256) {
        return mercato.creaEvento(
            "Evento di test",
            "ipfs://cid/",
            1 ether,
            quantita,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            politica
        );
    }

    function testAnnullamentoFondiBloccatiRimborsaAutomaticamente() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 2);
        uint256 saldoPrima = alice.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);

        mercato.annullaEvento(idEvento);

        assertEq(alice.balance, saldoPrima);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
        assertEq(mercato.bigliettiDaRimborsare(idEvento), 0);
    }

    function testIncassiAnticipatiRichiedeFinanziamentoOrganizzatore() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 2);
        uint256 saldoPrima = alice.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);

        // Simula l'organizzatore che preleva gli incassi prima dell'annullamento.
        mercato.prelevaSaldo();
        mercato.annullaEvento(idEvento);

        assertFalse(mercato.bigliettiRimborsati(1));
        assertEq(alice.balance, saldoPrima);

        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);

        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(alice.balance, saldoPrima);
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
    }

    function testRimborsiOltreVentiBigliettiProcedonoALotti() public {
        uint256 quantita = 21;
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, quantita);
        address[] memory acquirenti = new address[](quantita);

        for (uint256 i = 0; i < quantita; i++) {
            address acquirente = address(uint160(1000 + i));
            acquirenti[i] = acquirente;
            vm.deal(acquirente, 2 ether);
            vm.prank(acquirente);
            mercato.acquistaBiglietto{value: 1 ether}(idEvento);
        }

        mercato.annullaEvento(idEvento);

        assertEq(mercato.cursoreRimborsiEvento(idEvento), 20);
        assertTrue(mercato.bigliettiRimborsati(20));
        assertFalse(mercato.bigliettiRimborsati(21));

        mercato.processaRimborsiEvento(idEvento, 1);

        assertEq(mercato.cursoreRimborsiEvento(idEvento), 21);
        for (uint256 i = 1; i <= quantita; i++) {
            assertTrue(mercato.bigliettiRimborsati(i));
        }
    }
}
