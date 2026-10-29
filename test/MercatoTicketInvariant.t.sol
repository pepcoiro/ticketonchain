// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract GestoreMercatoInvariant {
    MercatoTicket public immutable mercato;
    uint256[] private _eventiCreati;

    constructor(MercatoTicket mercato_) { mercato = mercato_; }
    receive() external payable {}

    function creaECompra(uint96 prezzoRaw) external {
        uint256 prezzo = uint256(prezzoRaw) % 1 gwei + 1;
        uint256 idEvento = mercato.creaEvento(
            "Evento invariant", "ipfs://invariant/", prezzo, 1,
            block.timestamp + 1 days, block.timestamp + 2 days,
            MercatoTicket.PoliticaRimborso.FondiBloccati
        );
        _eventiCreati.push(idEvento);
        mercato.acquistaBiglietto{value: prezzo}(idEvento);
    }

    function annullaUltimoEvento() external {
        uint256 n = _eventiCreati.length;
        if (n == 0) return;
        try mercato.annullaEvento(_eventiCreati[n - 1]) {} catch {}
    }

    function processaUltimoLotto(uint8 quantitaRaw) external {
        uint256 n = _eventiCreati.length;
        if (n == 0) return;
        try mercato.processaRimborsiEvento(_eventiCreati[n - 1], uint256(quantitaRaw) % 20 + 1) {} catch {}
    }

    function prelevaSaldo() external { try mercato.prelevaSaldo() {} catch {} }
    function numeroEventi() external view returns (uint256) { return _eventiCreati.length; }
    function eventoCreato(uint256 indice) external view returns (uint256) { return _eventiCreati[indice]; }
}

contract MercatoTicketInvariantTest is StdInvariant, Test {
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
        for (uint256 id = 1; id < mercato.prossimoIdBiglietto(); id++) {
            (bool esiste, ) = address(nft).staticcall(abi.encodeWithSelector(nft.ownerOf.selector, id));
            if (mercato.bigliettiRimborsati(id)) assertFalse(esiste, "biglietto rimborsato ancora esistente");
            else assertTrue(esiste, "biglietto non rimborsato inesistente");
        }
    }

    /// @dev L'handler genera solo eventi FondiBloccati. IncassiAnticipati richiede
    ///      una decisione separata sulla copertura dei crediti già maturati.
    function invariantContabilitaFondiBloccatiEsatta() public view {
        uint256 passivita = mercato.saldiPrelevabili(address(gestore)) + mercato.commissioniAccumulate();
        for (uint256 i = 0; i < gestore.numeroEventi(); i++) {
            passivita += mercato.fondiRimborsoEvento(gestore.eventoCreato(i));
        }
        assertEq(address(mercato).balance, passivita, "contabilita FondiBloccati non coincide");
    }
}
