// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract RiceventeETHCheRifiuta {
    function creaEvento(
        MercatoTicket mercato,
        uint256 prezzo,
        MercatoTicket.PoliticaRimborso politica
    ) external returns (uint256) {
        return mercato.creaEvento(
            "Evento wallet",
            "ipfs://wallet/",
            prezzo,
            2,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            politica
        );
    }

    function prelevaSaldo(MercatoTicket mercato) external {
        mercato.prelevaSaldo();
    }

    function riceviCommissioni(MercatoTicket mercato) external {
        mercato.prelevaCommissioni(address(this));
    }

    receive() external payable {
        revert("ETH rifiutati");
    }
}

contract MercatoTicketPermessiTest is Test {
    MercatoTicket private mercato;
    TicketOnChain private nft;
    address private alice = address(0xA11CE);
    address private bob = address(0xB0B);

    function setUp() public {
        nft = new TicketOnChain();
        mercato = new MercatoTicket(address(nft));
        nft.impostaMercato(address(mercato));
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function _evento(
        MercatoTicket.PoliticaRimborso politica,
        uint256 prezzo,
        uint256 quantita
    ) internal returns (uint256) {
        return mercato.creaEvento(
            "Evento test",
            "ipfs://test/",
            prezzo,
            quantita,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            politica
        );
    }

    function testCostruttoreRifiutaContrattoNFTNonValido() public {
        vm.expectRevert("MercatoTicket: indirizzo NFT non valido");
        new MercatoTicket(address(0));
        vm.expectRevert("MercatoTicket: indirizzo NFT non valido");
        new MercatoTicket(alice);
    }

    function testSoloProprietarioGestisceOrganizzatori() public {
        vm.prank(alice);
        vm.expectRevert();
        mercato.impostaOrganizzatore(bob, true);

        vm.expectRevert("MercatoTicket: organizzatore non valido");
        mercato.impostaOrganizzatore(address(0), true);

        mercato.impostaOrganizzatore(bob, true);
        assertTrue(mercato.organizzatoriAutorizzati(bob));
        mercato.impostaOrganizzatore(bob, false);
        assertFalse(mercato.organizzatoriAutorizzati(bob));
    }

    function testOrganizzatoreNonAutorizzatoNonPuoCreareEvento() public {
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: organizzatore non autorizzato");
        mercato.creaEvento(
            "Evento",
            "ipfs://test/",
            1 ether,
            1,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );
    }

    function testCreazioneEventoValidaTuttiIParametri() public {
        vm.expectRevert("MercatoTicket: nome vuoto");
        mercato.creaEvento("", "ipfs://test/", 1 ether, 1, block.timestamp + 1 days, block.timestamp + 2 days, MercatoTicket.PoliticaRimborso.FondiBloccati);

        vm.expectRevert("MercatoTicket: URI metadati vuoto");
        mercato.creaEvento("Evento", "", 1 ether, 1, block.timestamp + 1 days, block.timestamp + 2 days, MercatoTicket.PoliticaRimborso.FondiBloccati);

        vm.expectRevert("MercatoTicket: URI base deve terminare con /");
        mercato.creaEvento("Evento", "ipfs://test", 1 ether, 1, block.timestamp + 1 days, block.timestamp + 2 days, MercatoTicket.PoliticaRimborso.FondiBloccati);

        vm.expectRevert("MercatoTicket: prezzo non valido");
        mercato.creaEvento("Evento", "ipfs://test/", 0, 1, block.timestamp + 1 days, block.timestamp + 2 days, MercatoTicket.PoliticaRimborso.FondiBloccati);

        vm.expectRevert("MercatoTicket: quantita non valida");
        mercato.creaEvento("Evento", "ipfs://test/", 1 ether, 0, block.timestamp + 1 days, block.timestamp + 2 days, MercatoTicket.PoliticaRimborso.FondiBloccati);

        vm.expectRevert("MercatoTicket: data evento non futura");
        mercato.creaEvento("Evento", "ipfs://test/", 1 ether, 1, block.timestamp, block.timestamp + 2 days, MercatoTicket.PoliticaRimborso.FondiBloccati);

        vm.expectRevert("MercatoTicket: data fine non valida");
        mercato.creaEvento("Evento", "ipfs://test/", 1 ether, 1, block.timestamp + 1 days, block.timestamp + 1 days, MercatoTicket.PoliticaRimborso.FondiBloccati);
    }

    function testPausaRiservataAlProprietarioEBloccaCreazione() public {
        vm.prank(alice);
        vm.expectRevert();
        mercato.sospendiMercato();

        mercato.sospendiMercato();
        vm.expectRevert();
        _evento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1 ether, 1);
        mercato.riattivaMercato();
        assertEq(_evento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1 ether, 1), 1);
    }

    function testAggiornamentoEventoPermessoSoloPrimaDellInizio() public {
        uint256 idEvento = _evento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1 ether, 2);

        vm.prank(alice);
        vm.expectRevert("MercatoTicket: non sei organizzatore");
        mercato.aggiornaEvento(idEvento, 2 ether, false);

        vm.expectRevert("MercatoTicket: prezzo non valido");
        mercato.aggiornaEvento(idEvento, 0, false);

        mercato.aggiornaEvento(idEvento, 2 ether, false);
        (,,,,,,uint256 prezzo,,,,) = mercato.eventi(idEvento);
        assertEq(prezzo, 2 ether);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("MercatoTicket: evento gia iniziato");
        mercato.aggiornaEvento(idEvento, 1 ether, true);
    }

    function testEventoEsauritoNonPuoEssereRiattivato() public {
        uint256 idEvento = _evento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1 ether, 1);
        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);

        vm.expectRevert("MercatoTicket: tutti i biglietti sono stati venduti");
        mercato.aggiornaEvento(idEvento, 1 ether, true);
        mercato.aggiornaEvento(idEvento, 1 ether, false);
    }

    function testRivenditaRichiedeOrganizzatoreEEventoNonIniziato() public {
        uint256 idEvento = _evento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1 ether, 1);
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: non sei organizzatore");
        mercato.impostaRivendita(idEvento, false);

        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("MercatoTicket: evento gia iniziato");
        mercato.impostaRivendita(idEvento, false);
    }

    function testPrelievoSaldoVuotoVieneRifiutato() public {
        vm.prank(alice);
        vm.expectRevert("MercatoTicket: saldo vuoto");
        mercato.prelevaSaldo();
    }

    function testPrelievoRicaviRifiutaPoliticaSbagliataENessunRicavo() public {
        uint256 idAnticipati = _evento(MercatoTicket.PoliticaRimborso.IncassiAnticipati, 1 ether, 1);
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("MercatoTicket: incassi gia disponibili all'organizzatore");
        mercato.prelevaRicaviEvento(idAnticipati);

        uint256 idBloccati = mercato.creaEvento(
            "Evento vuoto",
            "ipfs://vuoto/",
            1 ether,
            1,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert("MercatoTicket: nessun ricavo da prelevare");
        mercato.prelevaRicaviEvento(idBloccati);
    }

    function testPrelievoSaldoECommissioniCheFallisceNonPerdeIlCredito() public {
        RiceventeETHCheRifiuta wallet = new RiceventeETHCheRifiuta();
        mercato.impostaOrganizzatore(address(wallet), true);
        uint256 idEvento = wallet.creaEvento(
            mercato,
            1 ether,
            MercatoTicket.PoliticaRimborso.IncassiAnticipati
        );

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);

        uint256 credito = mercato.saldiPrelevabili(address(wallet));
        vm.expectRevert("MercatoTicket: trasferimento ETH fallito");
        wallet.prelevaSaldo(mercato);
        assertEq(mercato.saldiPrelevabili(address(wallet)), credito);

        uint256 commissioni = mercato.commissioniAccumulate();
        vm.expectRevert("MercatoTicket: trasferimento ETH fallito");
        wallet.riceviCommissioni(mercato);
        assertEq(mercato.commissioniAccumulate(), commissioni);
    }

    function testPrelievoCommissioniRifiutaDestinatarioNulloESaldoVuoto() public {
        vm.expectRevert("MercatoTicket: destinatario non valido");
        mercato.prelevaCommissioni(address(0));
        vm.expectRevert("MercatoTicket: nessuna commissione");
        mercato.prelevaCommissioni(bob);
    }

    function testSoloProprietarioPuoCambiareCommissione() public {
        vm.prank(alice);
        vm.expectRevert();
        mercato.impostaCommissione(100);

        mercato.impostaCommissione(0);
        assertEq(mercato.commissionePuntiBase(), 0);
    }

    function testConfigurazioneValidatoreRifiutaIndirizzoNulloEOrganizzatoreErrato() public {
        uint256 idEvento = _evento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1 ether, 1);
        vm.expectRevert("MercatoTicket: validatore non valido");
        mercato.impostaValidatoreIngresso(idEvento, address(0), true);

        vm.prank(alice);
        vm.expectRevert("MercatoTicket: non sei organizzatore");
        mercato.impostaValidatoreIngresso(idEvento, bob, true);
    }

    function testIngressoRifiutaBigliettoInesistenteEOrariErrati() public {
        uint256 idEvento = _evento(MercatoTicket.PoliticaRimborso.FondiBloccati, 1 ether, 1);
        vm.expectRevert("MercatoTicket: biglietto non riconosciuto");
        mercato.validaIngresso(999);

        vm.prank(alice);
        mercato.acquistaBiglietto{value: 1 ether}(idEvento);

        vm.expectRevert("MercatoTicket: evento non iniziato");
        mercato.validaIngresso(1);

        vm.warp(block.timestamp + 2 days + 1);
        vm.expectRevert("MercatoTicket: evento terminato");
        mercato.validaIngresso(1);
    }
}
