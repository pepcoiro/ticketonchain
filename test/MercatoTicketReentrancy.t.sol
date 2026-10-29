// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract WalletRientrante {
    MercatoTicket public immutable mercato;
    uint256 public idEvento;
    bool public tentativoRientranzaBloccato;

    constructor(MercatoTicket mercato_) {
        mercato = mercato_;
    }

    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function compra(uint256 idEvento_, uint256 prezzo) external payable {
        idEvento = idEvento_;
        mercato.acquistaBiglietto{value: prezzo}(idEvento_);
    }

    receive() external payable {
        // Simula un destinatario che consuma gas nel callback: il rimborso non deve chiamarlo.
        uint256 i;
        while (i < 1000) {
            unchecked { i++; }
        }
        try mercato.processaRimborsiEvento(idEvento, 20) {
            // Un rientro riuscito sarebbe un problema di sicurezza.
            tentativoRientranzaBloccato = false;
        } catch {
            tentativoRientranzaBloccato = true;
        }
    }
}

contract MercatoTicketReentrancyTest is Test {
    MercatoTicket private mercato;
    TicketOnChain private nft;
    WalletRientrante private wallet;

    function setUp() public {
        nft = new TicketOnChain();
        mercato = new MercatoTicket(address(nft));
        nft.impostaMercato(address(mercato));
        wallet = new WalletRientrante(mercato);
        vm.deal(address(wallet), 0);
    }

    function testIncassiAnticipatiAccreditaSenzaCallback() public {
        vm.deal(address(this), 3 ether);
        uint256 idEvento = mercato.creaEvento(
            "Evento anticipato",
            "ipfs://anticipato/",
            1 ether,
            1,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.IncassiAnticipati
        );

        wallet.compra{value: 1.015 ether}(idEvento, 1.015 ether);
        mercato.annullaEvento(idEvento);
        mercato.avviaRimborsiCollettivi{value: 1 ether}(idEvento);

        assertFalse(wallet.tentativoRientranzaBloccato(), "il wallet non deve ricevere callback");
        assertEq(address(wallet).balance, 0);
        assertEq(mercato.saldiPrelevabili(address(wallet)), 1 ether);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
        assertEq(mercato.bigliettiDaRimborsare(idEvento), 0);
    }

    function testFondiBloccatiAccreditaSenzaCallback() public {
        uint256 idEvento = mercato.creaEvento(
            "Evento rientranza",
            "ipfs://rientranza/",
            1 ether,
            1,
            block.timestamp + 1 days,
            block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );

        wallet.compra{value: 1.015 ether}(idEvento, 1.015 ether);
        assertEq(address(wallet).balance, 0);

        mercato.annullaEvento(idEvento);

        assertFalse(wallet.tentativoRientranzaBloccato(), "il wallet non deve ricevere callback");
        assertEq(address(wallet).balance, 0);
        assertEq(mercato.saldiPrelevabili(address(wallet)), 1 ether);
        assertTrue(mercato.bigliettiRimborsati(1));
        assertEq(mercato.fondiRimborsoEvento(idEvento), 0);
        assertEq(mercato.bigliettiDaRimborsare(idEvento), 0);
    }
}
