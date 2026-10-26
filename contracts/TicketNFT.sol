// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title TicketNFT
 * @notice NFT representation of a TicketOnchain event ticket.
 * @dev Minting is restricted to the configured marketplace. Transfers between
 *      non-zero addresses are also restricted to that marketplace, so secondary
 *      sales can enforce the project's resale rules.
 *
 *      Educational starting point: write and run tests before deployment.
 */
contract TicketNFT is ERC721, Ownable {
    address public marketplace;

    mapping(uint256 tokenId => string uri) private _tokenURIs;

    event MarketplaceSet(address indexed marketplace);
    event TicketMinted(
        uint256 indexed tokenId,
        address indexed recipient,
        string tokenURI
    );

    constructor()
        ERC721("TicketOnchain", "TICKET")
        Ownable(msg.sender)
    {}

    modifier onlyMarketplace() {
        require(msg.sender == marketplace, "TicketNFT: only marketplace");
        _;
    }

    /**
     * @notice Set the marketplace contract once.
     * @dev The owner is expected to be the deployer/admin during development.
     */
    function setMarketplace(address marketplaceAddress) external onlyOwner {
        require(marketplace == address(0), "TicketNFT: marketplace already set");
        require(
            marketplaceAddress != address(0),
            "TicketNFT: invalid marketplace"
        );

        marketplace = marketplaceAddress;
        emit MarketplaceSet(marketplaceAddress);
    }

    /**
     * @notice Mint a ticket NFT to its initial owner.
     * @dev Only the marketplace can mint tickets.
     */
    function mint(
        address recipient,
        uint256 tokenId,
        string calldata uri
    ) external onlyMarketplace {
        require(recipient != address(0), "TicketNFT: invalid recipient");
        require(bytes(uri).length > 0, "TicketNFT: empty token URI");

        _tokenURIs[tokenId] = uri;
        _safeMint(recipient, tokenId);

        emit TicketMinted(tokenId, recipient, uri);
    }

    /**
     * @notice Return the metadata URI associated with a ticket.
     */
    function tokenURI(
        uint256 tokenId
    ) public view override returns (string memory) {
        _requireOwned(tokenId);
        return _tokenURIs[tokenId];
    }

    /**
     * @dev Prevent direct transfers between addresses. Minting and burning are
     *      unaffected because one endpoint is address(0). Secondary transfers
     *      must be initiated by the marketplace contract.
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        if (from != address(0) && to != address(0)) {
            require(
                msg.sender == marketplace,
                "TicketNFT: transfers only via marketplace"
            );
        }

        return super._update(to, tokenId, auth);
    }
}
