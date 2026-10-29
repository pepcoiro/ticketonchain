// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";

contract TicketOnChainSicurezzaTest is Test {
    TicketOnChain private nft;
    MercatoTicket private mercato;
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function setUp() public {
        nft = new TicketOnChain();
        mercato = new MercatoTicket(address(nft));
        nft.impostaMercato(address(mercato));
        vm.deal(alice, 10 ether);
    }

    function _compraBiglietto() internal returns (uint256 idEvento) {
        idEvento = mercato.creaEvento(
            "Evento sicurezza",
            "ipfs://cid/",
            1 ether,
            2,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);
    }

    function testSoloProprietarioPuoConfigurareMercato() public {
        TicketOnChain altroNft = new TicketOnChain();
        vm.prank(alice);
        vm.expectRevert();
        altroNft.impostaMercato(address(mercato));
    }

    function testRinunciaAllaProprietaEImpedita() public {
        vm.expectRevert("TicketOnChain: rinuncia proprieta disabilitata");
        nft.renounceOwnership();
        vm.expectRevert("MercatoTicket: rinuncia proprieta disabilitata");
        mercato.renounceOwnership();
    }

    function testIdentificativoBigliettoNonPuoEssereRiutilizzato() public {
        vm.prank(address(mercato));
        nft.creaBiglietto(alice, 777, "ipfs://cid/777.json");
        vm.prank(address(mercato));
        vm.expectRevert("TicketOnChain: biglietto gia esistente");
        nft.creaBiglietto(bob, 777, "ipfs://cid/altro.json");
        assertEq(nft.ownerOf(777), alice);
        assertEq(nft.tokenURI(777), "ipfs://cid/777.json");
    }

    function testSoloMercatoPuoCreareBiglietti() public {
        vm.expectRevert("TicketOnChain: solo il mercato");
        nft.creaBiglietto(alice, 777, "ipfs://cid/777.json");
    }

    function testSoloMercatoPuoDistruggereBiglietti() public {
        _compraBiglietto();
        vm.expectRevert("TicketOnChain: solo il mercato");
        nft.distruggiBiglietto(1);
        assertEq(nft.ownerOf(1), alice);
    }

    function testImpostazioneMercatoSoloUnaVolta() public {
        vm.expectRevert("TicketOnChain: mercato gia impostato");
        nft.impostaMercato(address(0x1234));
    }

    function testImpostazioneMercatoRifiutaIndirizziNonValidi() public {
        TicketOnChain altroNft = new TicketOnChain();
        vm.expectRevert("TicketOnChain: indirizzo del mercato non valido");
        altroNft.impostaMercato(address(0));
        vm.expectRevert("TicketOnChain: indirizzo del mercato non valido");
        altroNft.impostaMercato(alice);
    }

    function testTokenUriEProprietarioSonoInvalidatiDopoRimborso() public {
        uint256 idEvento = _compraBiglietto();
        assertEq(nft.tokenURI(1), "ipfs://cid/1.json");
        mercato.annullaEvento(idEvento);
        vm.expectRevert();
        nft.ownerOf(1);
        vm.expectRevert();
        nft.tokenURI(1);
    }

    function testProprietarioNonPuoTrasferireDirettamenteNFT() public {
        _compraBiglietto();
        vm.prank(alice);
        vm.expectRevert("TicketOnChain: trasferimento consentito solo tramite mercato");
        nft.transferFrom(alice, bob, 1);
    }

    function testApprovazioneNonPermetteTrasferimentoDirettoTramiteOperatore() public {
        _compraBiglietto();
        vm.prank(alice);
        nft.approve(bob, 1);
        vm.prank(bob);
        vm.expectRevert("TicketOnChain: trasferimento consentito solo tramite mercato");
        nft.transferFrom(alice, bob, 1);
        assertEq(nft.ownerOf(1), alice);
    }

    function testMintRifiutaDestinatarioNulloEUriVuoto() public {
        vm.prank(address(mercato));
        vm.expectRevert("TicketOnChain: destinatario non valido");
        nft.creaBiglietto(address(0), 77, "ipfs://cid/77.json");

        vm.prank(address(mercato));
        vm.expectRevert("TicketOnChain: indirizzo metadati vuoto");
        nft.creaBiglietto(alice, 77, "");
    }
}
