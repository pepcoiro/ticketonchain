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

    receive() external payable {}

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
        assertEq(alice.balance, saldoPrima - 1 ether);

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

    function testAnnullamentoConBigliettoInRivenditaRimborsaIlVenditoreEBruciaNFT() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        uint256 saldoPrima = alice.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);

        vm.prank(alice);
        nft.approve(address(mercato), 1);

        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);

        mercato.annullaEvento(idEvento);

        assertEq(alice.balance, saldoPrima);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertFalse(mercato.rivendite(1).attivo);
        vm.expectRevert();
        nft.ownerOf(1);
    }

    function testRivenditaEAnnullamentoRimborsanoIlPossessoreAttuale() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        uint256 saldoAlicePrima = alice.balance;
        uint256 saldoBobPrima = bob.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);

        vm.prank(alice);
        nft.approve(address(mercato), 1);

        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);

        vm.prank(bob);
        mercato.acquistaRivendita{value: 1 ether}(1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(mercato.saldiPrelevabili(alice), 0.975 ether);

        mercato.annullaEvento(idEvento);

        assertEq(bob.balance, saldoBobPrima);
        assertEq(alice.balance, saldoAlicePrima - 1 ether);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.ricaviEventoBloccati(idEvento), 0);
        assertEq(mercato.commissioniEventoBloccate(idEvento), 0);
        assertEq(mercato.commissioniAccumulate(), 0.025 ether);
        vm.expectRevert();
        nft.ownerOf(1);
    }
}
