// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";

contract MercatoTicketTest is Test {
    TicketOnChain private biglietti;
    MercatoTicket private mercato;

    address private organizzatore = address(0xA11CE);
    address private primoAcquirente = address(0xB0B);
    address private secondoAcquirente = address(0xCAFE);

    function setUp() public {
        biglietti = new TicketOnChain();
        mercato = new MercatoTicket(address(biglietti));
        biglietti.impostaMercato(address(mercato));

        vm.deal(organizzatore, 10 ether);
        vm.deal(primoAcquirente, 10 ether);
        vm.deal(secondoAcquirente, 10 ether);

        vm.prank(organizzatore);
        mercato.creaEvento("Festival", "ipfs://FESTIVAL/", 1 ether, 2);
    }

    function testAcquistoDistribuisceRicavoECommissione() public {
        vm.prank(primoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        assertEq(biglietti.ownerOf(1), primoAcquirente);
        assertEq(mercato.saldiPrelevabili(organizzatore), 0.975 ether);
        assertEq(mercato.commissioniAccumulate(), 0.025 ether);
    }

    function testPagamentoConImportoErratoVieneRifiutato() public {
        vm.prank(primoAcquirente);
        vm.expectRevert();
        mercato.acquistaBiglietto{value: 0.5 ether}(1);
    }

    function testNonSiPossonoVenderePiuBigliettiDellaQuantitaMassima() public {
        vm.prank(primoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(secondoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(address(0xD00D));
        vm.deal(address(0xD00D), 2 ether);
        vm.expectRevert();
        mercato.acquistaBiglietto{value: 1 ether}(1);
    }

    function testRivenditaCustodisceENuovamenteAssegnaBiglietto() public {
        vm.prank(primoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(primoAcquirente);
        biglietti.approve(address(mercato), 1);

        vm.prank(primoAcquirente);
        mercato.mettiInRivendita(1, 2 ether);

        assertEq(biglietti.ownerOf(1), address(mercato));

        vm.prank(secondoAcquirente);
        mercato.acquistaRivendita{value: 2 ether}(1);

        assertEq(biglietti.ownerOf(1), secondoAcquirente);
        assertEq(mercato.saldiPrelevabili(primoAcquirente), 1.95 ether);
        assertEq(mercato.commissioniAccumulate(), 0.075 ether);
    }

    function testIlVenditorePuoAnnullareLaRivendita() public {
        vm.prank(primoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(primoAcquirente);
        biglietti.approve(address(mercato), 1);

        vm.prank(primoAcquirente);
        mercato.mettiInRivendita(1, 2 ether);

        vm.prank(primoAcquirente);
        mercato.annullaRivendita(1);

        assertEq(biglietti.ownerOf(1), primoAcquirente);
        (,, bool attivo) = mercato.rivendite(1);
        assertFalse(attivo);
    }

    function testOrganizzatorePuoConvalidareIngressoUnaSolaVolta() public {
        vm.prank(primoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(organizzatore);
        mercato.validaIngresso(1);

        assertTrue(mercato.ingressiUtilizzati(1));

        vm.prank(organizzatore);
        vm.expectRevert();
        mercato.validaIngresso(1);
    }

    function testUnUtenteNonPuoConvalidareIngressi() public {
        vm.prank(primoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(primoAcquirente);
        vm.expectRevert();
        mercato.validaIngresso(1);
    }

    function testBigliettoInRivenditaNonPuoEssereConvalidato() public {
        vm.prank(primoAcquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(primoAcquirente);
        biglietti.approve(address(mercato), 1);

        vm.prank(primoAcquirente);
        mercato.mettiInRivendita(1, 2 ether);

        vm.prank(organizzatore);
        vm.expectRevert();
        mercato.validaIngresso(1);
    }

    function testOrganizzatorePuoAnnullareEventoEBloccareLeVendite() public {
        vm.prank(organizzatore);
        mercato.annullaEvento(1);

        (,,,,,, bool attivo, bool annullato) = mercato.eventi(1);
        assertFalse(attivo);
        assertTrue(annullato);

        vm.prank(primoAcquirente);
        vm.expectRevert();
        mercato.acquistaBiglietto{value: 1 ether}(1);
    }

    function testSoloOrganizzatorePuoAnnullareEvento() public {
        vm.prank(primoAcquirente);
        vm.expectRevert();
        mercato.annullaEvento(1);
    }

    function testEventoAnnullatoNonPuoEssereRiattivato() public {
        vm.prank(organizzatore);
        mercato.annullaEvento(1);

        vm.prank(organizzatore);
        vm.expectRevert();
        mercato.aggiornaEvento(1, 1 ether, true);
    }

    function testSoloProprietarioModificaCommissione() public {
        vm.prank(primoAcquirente);
        vm.expectRevert();
        mercato.impostaCommissione(500);
    }
}
