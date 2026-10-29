// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract PortafoglioCheRifiutaETH {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function compra(MercatoTicket mercato, uint256 idEvento) external payable {
        mercato.acquistaBiglietto{value: msg.value}(idEvento);
    }

    receive() external payable {
        revert("ricezione rifiutata");
    }
}

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
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);

        mercato.annullaEvento(idEvento);

        assertEq(alice.balance, saldoPrima - 1.015 ether);
        assertEq(mercato.saldiPrelevabili(alice), 1 ether);
        vm.prank(alice);
        mercato.prelevaSaldo();
        assertEq(alice.balance, saldoPrima - 0.015 ether);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
        assertEq(mercato.bigliettiDaRimborsare(idEvento), 0);
    }

    function testIncassiAnticipatiRichiedeFinanziamentoOrganizzatore() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 2);
        uint256 saldoPrima = alice.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);

        // Simula l'organizzatore che preleva gli incassi prima dell'annullamento.
        mercato.prelevaSaldo();
        mercato.annullaEvento(idEvento);

        assertFalse(mercato.bigliettiRimborsati(1));
        assertEq(alice.balance, saldoPrima - 1 ether);

        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);

        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(alice.balance, saldoPrima - 1 ether);
        assertEq(mercato.saldiPrelevabili(alice), 1 ether);
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
            mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
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
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);

        vm.prank(alice);
        nft.approve(address(mercato), 1);

        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);

        mercato.annullaEvento(idEvento);

        assertEq(alice.balance, saldoPrima - 1 ether);
        assertEq(mercato.saldiPrelevabili(alice), 1 ether);
        assertTrue(mercato.bigliettiRimborsati(1));
        (address venditore, uint256 prezzoRivendita, bool annuncioAttivo) = mercato.rivendite(1);
        assertEq(venditore, address(0));
        assertEq(prezzoRivendita, 0);
        assertFalse(annuncioAttivo);
        vm.expectRevert();
        nft.ownerOf(1);
    }

    function testRivenditaEAnnullamentoRimborsanoIlPossessoreAttuale() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        uint256 saldoAlicePrima = alice.balance;
        uint256 saldoBobPrima = bob.balance;

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);

        vm.prank(alice);
        nft.approve(address(mercato), 1);

        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);

        vm.prank(bob);
        mercato.acquistaRivendita{value: 1.015 ether}(1);

        assertEq(nft.ownerOf(1), bob);
        assertEq(mercato.saldiPrelevabili(alice), 1 ether);

        mercato.annullaEvento(idEvento);

        assertEq(bob.balance, saldoBobPrima - 1.015 ether);
        assertEq(mercato.saldiPrelevabili(bob), 1 ether);
        assertEq(alice.balance, saldoAlicePrima - 1.015 ether);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.ricaviEventoBloccati(idEvento), 0);
        assertEq(mercato.commissioniAccumulate(), 0.03 ether);
        vm.expectRevert();
        nft.ownerOf(1);
    }

    function testAcquistoRifiutaImportoErrato() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: importo non corretto");
        mercato.acquistaBiglietto{value: 0.5 ether}(idEvento);
        (,,,,,,,,uint256 venduti,,) = mercato.eventi(idEvento);
        assertEq(venduti, 0);
    }

    function testAcquistoRifiutaEventoInesistente() public {
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: evento inesistente");
        mercato.acquistaBiglietto{value: 1.015 ether}(999);
    }

    function testLimiteWalletSeiBigliettiApplicatoAgliAcquistiIniziali() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 7);
        for (uint256 i = 0; i < 6; i++) {
            vm.prank(alice);
            mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        }
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: limite di 6 biglietti per wallet superato");
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        (,,,,,,,,uint256 venduti,,) = mercato.eventi(idEvento);
        assertEq(venduti, 6);
    }

    function testSoloOrganizzatorePuoAggiornareEAnnullareEvento() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 2);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: non sei organizzatore");
        mercato.aggiornaEvento(idEvento, 2 ether, false);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: non sei organizzatore");
        mercato.annullaEvento(idEvento);
    }

    function testRivenditaRichiedeAutorizzazioneEPrezzoOriginale() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(alice);
        vm.expectRevert();
        mercato.mettiInRivendita(1, 1 ether);
        vm.prank(alice);
        nft.approve(address(mercato), 1);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: rivendita solo al prezzo originale");
        mercato.mettiInRivendita(1, 2 ether);
    }

    function testRivenditaRifiutaAcquistoDaParteDelVenditore() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(alice);
        nft.approve(address(mercato), 1);
        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: non puoi acquistare il tuo biglietto");
        mercato.acquistaRivendita{value: 1.015 ether}(1);
    }

    function testAnnullareAnnuncioRestituisceNFTAlVenditore() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(alice);
        nft.approve(address(mercato), 1);
        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);
        vm.prank(bob);
        vm.expectRevert("MercatoTicket: non sei venditore");
        mercato.annullaRivendita(1);
        vm.prank(alice);
        mercato.annullaRivendita(1);
        assertEq(nft.ownerOf(1), alice);
        (,,bool attivo) = mercato.rivendite(1);
        assertFalse(attivo);
    }

    function testDisabilitareRivenditaBloccaNuoviAnnunci() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        mercato.impostaRivendita(idEvento, false);
        vm.prank(alice);
        nft.approve(address(mercato), 1);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: rivendita sospesa");
        mercato.mettiInRivendita(1, 1 ether);
    }

    function testPrelievoFondiBloccatiSoloDopoInizioEvento() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.expectRevert("MercatoTicket: evento non iniziato");
        mercato.prelevaRicaviEvento(idEvento);
        vm.warp(block.timestamp + 1 days);
        mercato.prelevaRicaviEvento(idEvento);
        assertEq(mercato.saldiPrelevabili(address(this)), 1 ether);
        assertEq(mercato.commissioniAccumulate(), 0.015 ether);
    }

    function testIncassiAnticipatiNonRimborsaAutomaticamente() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 2);
        uint256 saldoAlice = alice.balance;
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        mercato.annullaEvento(idEvento);
        assertEq(alice.balance, saldoAlice - 1.015 ether);
        assertFalse(mercato.bigliettiRimborsati(1));
        vm.expectRevert("MercatoTicket: versare l'intero importo delle vendite");
        mercato.avviaRimborsiCollettivi{value: 0.5 ether}(idEvento);
        assertFalse(mercato.rimborsiCollettiviAvviati(idEvento));
    }

    function testIncassiAnticipatiDopoRivenditaRimborsaPossessoreAttuale() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1);
        uint256 saldoBob = bob.balance;
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(alice);
        nft.approve(address(mercato), 1);
        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);
        vm.prank(bob);
        mercato.acquistaRivendita{value: 1.015 ether}(1);
        mercato.annullaEvento(idEvento);
        assertFalse(mercato.bigliettiRimborsati(1));
        assertEq(nft.ownerOf(1), bob);
        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);
        assertEq(bob.balance, saldoBob - 1.015 ether);
        assertEq(mercato.saldiPrelevabili(bob), 1 ether);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.saldiPrelevabili(alice), 1 ether);
    }

    function testRimborsoNonPuoEssereAvviatoDueVolte() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        mercato.annullaEvento(idEvento);
        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);
        vm.expectRevert("MercatoTicket: rimborsi gia avviati");
        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);
    }

    function testProcessaRimborsiRichiedeAvvioELottoValido() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1);
        vm.expectRevert("MercatoTicket: rimborsi non avviati");
        mercato.processaRimborsiEvento(idEvento, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        mercato.annullaEvento(idEvento);
        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);
        vm.expectRevert("MercatoTicket: dimensione lotto non valida");
        mercato.processaRimborsiEvento(idEvento, 0);
        vm.expectRevert("MercatoTicket: dimensione lotto non valida");
        mercato.processaRimborsiEvento(idEvento, 21);
    }

    function testWalletCheRifiutaETHNonBloccaRimborsiDegliAltri() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 2);
        PortafoglioCheRifiutaETH wallet = new PortafoglioCheRifiutaETH();
        vm.deal(address(wallet), 2 ether);
        wallet.compra{value: 1.015 ether}(mercato, idEvento);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);

        mercato.annullaEvento(idEvento);

        assertTrue(mercato.bigliettiRimborsati(1));
        assertTrue(mercato.bigliettiRimborsati(2));
        assertEq(mercato.saldiPrelevabili(address(wallet)), 1 ether);
        assertEq(alice.balance, 8.985 ether);
        assertEq(mercato.saldiPrelevabili(alice), 1 ether);
    }

    function testIngressoSoloNellaFinestraTemporaleEUnaVolta() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        address validatore = address(0xCAFE);
        mercato.impostaValidatoreIngresso(idEvento, validatore, true);

        vm.prank(validatore);
        vm.expectRevert("MercatoTicket: evento non iniziato");
        mercato.validaIngresso(1);

        vm.warp(block.timestamp + 1 days);
        vm.prank(validatore);
        mercato.validaIngresso(1);
        vm.prank(validatore);
        vm.expectRevert("MercatoTicket: ingresso gia utilizzato");
        mercato.validaIngresso(1);

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(validatore);
        vm.expectRevert("MercatoTicket: evento terminato");
        mercato.validaIngresso(1);
    }

    function testIngressoRifiutatoPerBigliettoInRivendita() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(alice);
        nft.approve(address(mercato), 1);
        vm.prank(alice);
        mercato.mettiInRivendita(1, 1 ether);
        mercato.impostaValidatoreIngresso(idEvento, address(this), true);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("MercatoTicket: biglietto in rivendita");
        mercato.validaIngresso(1);
    }

    function testPausaMercatoBloccaAcquistiMaNonPrelievi() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        mercato.sospendiMercato();
        vm.prank(bob);
        vm.expectRevert();
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        uint256 saldoPrima = address(this).balance;
        mercato.prelevaSaldo();
        assertEq(address(this).balance, saldoPrima + 1 ether);
    }

    function testSoloProprietarioMercatoPuoPrelevareCommissioni() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(bob);
        vm.expectRevert();
        mercato.prelevaCommissioni(bob);
        uint256 saldoPrima = bob.balance;
        mercato.prelevaCommissioni(bob);
        assertEq(bob.balance, saldoPrima + 0.015 ether);
        assertEq(mercato.commissioniAccumulate(), 0);
    }

    function testIncassiAnticipatiPuoEssereAnnullatoDuranteEvento() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1);
        uint256 saldoAlice = alice.balance;
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);

        vm.warp(block.timestamp + 1 days);
        mercato.annullaEvento(idEvento);
        assertFalse(mercato.bigliettiRimborsati(1));
        assertEq(alice.balance, saldoAlice - 1.015 ether);

        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(alice.balance, saldoAlice - 1.015 ether);
        assertEq(mercato.saldiPrelevabili(alice), 1 ether);
    }

    function testFuzzFondiBloccatiRimborsaImportoEsatto(uint96 prezzoRaw) public {
        uint256 prezzo = bound(uint256(prezzoRaw), 1, 1 ether);
        uint256 idEvento = mercato.creaEvento(
            "Evento fuzz",
            "ipfs://fuzz/",
            prezzo,
            1,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );
        vm.deal(alice, prezzo + 1 ether);
        uint256 saldoIniziale = alice.balance;
        vm.prank(alice);
        mercato.acquistaBiglietto{value: prezzo + (prezzo * mercato.commissionePuntiBase()) / 10_000}(idEvento);
        mercato.annullaEvento(idEvento);
        assertEq(alice.balance, saldoIniziale - prezzo - (prezzo * mercato.commissionePuntiBase()) / 10_000);
        assertEq(mercato.saldiPrelevabili(alice), prezzo);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
    }

    function testCambioCommissioneNonModificaContabilitaAcquistoGiaEffettuato() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        mercato.impostaCommissione(1_000);
        mercato.annullaEvento(idEvento);
        assertEq(mercato.commissioneAcquistoOriginale(1), 0.015 ether);
        assertEq(mercato.ricaviEventoBloccati(idEvento), 0);
        assertEq(mercato.commissioniAccumulate(), 0.015 ether);
    }

    function testEventoEsauritoRifiutaAcquistiSuccessivi() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(bob);
        vm.expectRevert("MercatoTicket: biglietti esauriti");
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
    }

    function testOrganizzatoreRevocatoNonPuoCreareEventi() public {
        mercato.impostaOrganizzatore(alice, false);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: organizzatore non autorizzato");
        mercato.creaEvento(
            "Evento",
            "ipfs://evento/",
            1 ether,
            1,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );
    }

    function testCommissioneNonPuoSuperareDieciPercento() public {
        mercato.impostaCommissione(1_000);
        assertEq(mercato.commissionePuntiBase(), 1_000);
        vm.expectRevert("MercatoTicket: commissione oltre il 10%");
        mercato.impostaCommissione(1_001);
    }

    function testFondiBloccatiNonPuoEssereAnnullatoDopoInizio() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("MercatoTicket: evento gia iniziato");
        mercato.annullaEvento(idEvento);
    }

    function testIncassiAnticipatiNonPuoEssereAnnullatoDopoFine() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1);
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert("MercatoTicket: evento gia terminato");
        mercato.annullaEvento(idEvento);
    }

    function testSoloValidatoreAutorizzatoPuoConvalidare() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.warp(block.timestamp + 1 days);
        vm.prank(bob);
        vm.expectRevert("MercatoTicket: non sei un validatore autorizzato");
        mercato.validaIngresso(1);
    }

    function testTrasferimentoNFTDirettoTraUtentiVieneBloccato() public {
        uint256 idEvento = _creaEvento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1.015 ether}(idEvento);
        vm.prank(alice);
        vm.expectRevert("TicketOnChain: trasferimento consentito solo tramite mercato");
        nft.transferFrom(alice, bob, 1);
    }
}
