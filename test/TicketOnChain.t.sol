// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";

contract TicketOnChainTest is Test {
    TicketOnChain private biglietti;
    MercatoTicket private mercato;

    address private organizzatore = address(0xA11CE);
    address private acquirente = address(0xB0B);

    function setUp() public {
        biglietti = new TicketOnChain();
        mercato = new MercatoTicket(address(biglietti));
        biglietti.impostaMercato(address(mercato));
    }

    function testSoloMercatoPuoCreareBiglietti() public {
        vm.expectRevert();
        biglietti.creaBiglietto(acquirente, 1, "ipfs://CID/1.json");
    }

    function testIlProprietarioImpostaIlMercatoUnaSolaVolta() public {
        vm.expectRevert();
        biglietti.impostaMercato(address(0x1234));
    }

    function testCreazioneBigliettoAssegnaProprietarioEURI() public {
        vm.deal(acquirente, 2 ether);

        vm.prank(organizzatore);
        mercato.creaEvento("Concerto di prova", "ipfs://CID/", 1 ether, 2);

        vm.prank(acquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        assertEq(biglietti.ownerOf(1), acquirente);
        assertEq(biglietti.tokenURI(1), "ipfs://CID/1.json");
    }

    function testNonSiPuoCreareDueVolteLoStessoIdentificativo() public {
        vm.deal(acquirente, 3 ether);

        vm.prank(organizzatore);
        mercato.creaEvento("Concerto di prova", "ipfs://CID/", 1 ether, 3);

        vm.prank(acquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        // Un secondo evento non deve poter riutilizzare l'identificativo NFT già emesso.
        vm.prank(organizzatore);
        mercato.creaEvento("Altro concerto", "ipfs://ALTRO/", 1 ether, 2);

        vm.prank(acquirente);
        mercato.acquistaBiglietto{value: 1 ether}(2);

        assertEq(biglietti.ownerOf(1), acquirente);
        assertEq(biglietti.ownerOf(2), acquirente);
        assertEq(biglietti.tokenURI(1), "ipfs://CID/1.json");
        assertEq(biglietti.tokenURI(2), "ipfs://ALTRO/2.json");
    }

    function testTrasferimentoDirettoTraUtentiVietato() public {
        vm.deal(acquirente, 2 ether);

        vm.prank(organizzatore);
        mercato.creaEvento("Concerto di prova", "ipfs://CID/", 1 ether, 1);

        vm.prank(acquirente);
        mercato.acquistaBiglietto{value: 1 ether}(1);

        vm.prank(acquirente);
        vm.expectRevert();
        biglietti.transferFrom(acquirente, address(0xCAFE), 1);
    }
}
