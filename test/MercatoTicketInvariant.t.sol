// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Vm} from "forge-std/Vm.sol";
import {MercatoTicket} from "../contracts/MercatoTicket.sol";
import {TicketOnChain} from "../contracts/TicketOnChain.sol";

contract CompratoreSecondarioInvariant {
    MercatoTicket public immutable mercato;
    TicketOnChain public immutable nft;

    constructor(MercatoTicket mercato_, TicketOnChain nft_) {
        mercato = mercato_;
        nft = nft_;
    }

    receive() external payable {}
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function compraRivendita(uint256 idBiglietto, uint256 prezzo) external payable {
        mercato.acquistaRivendita{value: msg.value}(idBiglietto);
        require(msg.value == prezzo + (prezzo * mercato.commissionePuntiBase()) / 10_000, "prezzo test non coerente");
    }

    function prelevaSaldo() external {
        try mercato.prelevaSaldo() {} catch {}
    }
}

contract GestoreMercatoInvariant {
    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    MercatoTicket public immutable mercato;
    TicketOnChain public immutable nft;
    CompratoreSecondarioInvariant public immutable compratore;

    uint256[] private _eventiCreati;
    uint256[] private _bigliettiCreati;
    mapping(uint256 => bool) public annuncioTentato;

    constructor(MercatoTicket mercato_, TicketOnChain nft_, CompratoreSecondarioInvariant compratore_) {
        mercato = mercato_;
        nft = nft_;
        compratore = compratore_;
    }

    receive() external payable {}
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return 0x150b7a02;
    }

    function creaECompra(uint96 prezzoRaw, bool anticipati) external {
        uint256 prezzo = uint256(prezzoRaw) % 1 gwei + 1;
        uint256 idEvento = mercato.creaEvento(
            "Evento invariant", "ipfs://invariant/", prezzo, 1,
            block.timestamp + 1 days, block.timestamp + 2 days,
            anticipati
                ? MercatoTicket.PoliticaRimborso.IncassiAnticipati
                : MercatoTicket.PoliticaRimborso.FondiBloccati
        );
        _eventiCreati.push(idEvento);
        uint256 idBiglietto = mercato.prossimoIdBiglietto();
        _bigliettiCreati.push(idBiglietto);
        mercato.acquistaBiglietto{value: prezzo + (prezzo * mercato.commissionePuntiBase()) / 10_000}(idEvento);
    }

    function annullaUltimoEvento() external {
        uint256 n = _eventiCreati.length;
        if (n == 0) return;
        try mercato.annullaEvento(_eventiCreati[n - 1]) {} catch {}
    }

    function finanziaUltimoEvento() external {
        uint256 n = _eventiCreati.length;
        if (n == 0) return;
        uint256 idEvento = _eventiCreati[n - 1];
        uint256 importo = mercato.totaleVenditeEvento(idEvento);
        if (importo == 0 || address(this).balance < importo) return;
        try mercato.avviaRimborsiCollettivi{value: importo}(idEvento) {} catch {}
    }

    function processaUltimoLotto(uint8 quantitaRaw) external {
        uint256 n = _eventiCreati.length;
        if (n == 0) return;
        try mercato.processaRimborsiEvento(_eventiCreati[n - 1], uint256(quantitaRaw) % 20 + 1) {} catch {}
    }

    function mettiUltimoBigliettoInRivendita() external {
        uint256 n = _bigliettiCreati.length;
        if (n == 0) return;
        uint256 id = _bigliettiCreati[n - 1];
        if (annuncioTentato[id] || mercato.bigliettiRimborsati(id)) return;
        annuncioTentato[id] = true;
        try nft.ownerOf(id) returns (address proprietario) {
            if (proprietario != address(this)) return;
        } catch { return; }
        uint256 prezzo = mercato.prezzoAcquistoOriginale(id);
        try nft.approve(address(mercato), id) {
            try mercato.mettiInRivendita(id, prezzo) {} catch {}
        } catch {}
    }

    function compraUltimaRivendita() external {
        uint256 n = _bigliettiCreati.length;
        if (n == 0) return;
        uint256 id = _bigliettiCreati[n - 1];
        uint256 prezzo = mercato.prezzoAcquistoOriginale(id);
        uint256 totale = prezzo + (prezzo * mercato.commissionePuntiBase()) / 10_000;
        if (address(compratore).balance < totale) return;
        try compratore.compraRivendita{value: totale}(id, prezzo) {} catch {}
    }

    function annullaUltimoAnnuncio() external {
        uint256 n = _bigliettiCreati.length;
        if (n == 0) return;
        try mercato.annullaRivendita(_bigliettiCreati[n - 1]) {} catch {}
    }

    function avanzaTempo(uint32 secondiRaw) external {
        vm.warp(block.timestamp + uint256(secondiRaw) % 3 days);
    }

    function sbloccaUltimoEvento() external {
        uint256 n = _eventiCreati.length;
        if (n == 0) return;
        try mercato.prelevaRicaviEvento(_eventiCreati[n - 1]) {} catch {}
    }

    function prelevaSaldoOrganizzatore() external { try mercato.prelevaSaldo() {} catch {} }
    function prelevaSaldoCompratore() external { compratore.prelevaSaldo(); }
    function numeroEventi() external view returns (uint256) { return _eventiCreati.length; }
    function eventoCreato(uint256 indice) external view returns (uint256) { return _eventiCreati[indice]; }
}

contract MercatoTicketInvariantTest is StdInvariant, Test {
    MercatoTicket private mercato;
    TicketOnChain private nft;
    GestoreMercatoInvariant private gestore;
    CompratoreSecondarioInvariant private compratore;

    function setUp() public {
        nft = new TicketOnChain();
        mercato = new MercatoTicket(address(nft));
        nft.impostaMercato(address(mercato));
        compratore = new CompratoreSecondarioInvariant(mercato, nft);
        gestore = new GestoreMercatoInvariant(mercato, nft, compratore);
        mercato.impostaOrganizzatore(address(gestore), true);
        vm.deal(address(gestore), 100 ether);
        vm.deal(address(compratore), 100 ether);
        targetContract(address(gestore));
    }

    function invariantBigliettiRimborsatiSonoDistrutti() public view {
        for (uint256 id = 1; id < mercato.prossimoIdBiglietto(); id++) {
            (bool esiste, ) = address(nft).staticcall(abi.encodeWithSelector(nft.ownerOf.selector, id));
            if (mercato.bigliettiRimborsati(id)) assertFalse(esiste, "biglietto rimborsato ancora esistente");
            else assertTrue(esiste, "biglietto non rimborsato inesistente");
        }
    }

    /// @dev La somma include i due wallet controllati dall'handler, le commissioni
    ///      maturate e le riserve lorde per entrambe le politiche di rimborso.
    ///      Il prezzo in FondiBloccati è coperto dalla riserva lorda; le commissioni
    ///      sono contabilizzate separatamente in commissioniAccumulate.
    function invariantContabilitaPassivitaUgualeAlSaldo() public view {
        uint256 passivita = mercato.saldiPrelevabili(address(gestore));
        passivita += mercato.saldiPrelevabili(address(compratore));
        passivita += mercato.commissioniAccumulate();
        for (uint256 i = 0; i < gestore.numeroEventi(); i++) {
            passivita += mercato.fondiRimborsoEvento(gestore.eventoCreato(i));
        }
        assertEq(address(mercato).balance, passivita, "saldo e passivita non coincidono");
    }
}
