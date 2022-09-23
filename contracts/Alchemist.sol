// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./interfaces/ItokenURIEngine.sol";
import "./TokenURISetting.sol";
import "./Royalty.sol";

contract Alchemist is Royalty, AccessControl, ERC721Enumerable, Pausable, TokenURISetting, Ownable {
    Counters.Counter private next_id = Counters.Counter(1000);

    struct AlchemistOf {
        uint8 allow;
        uint8 minted;
    }

    uint256 private constant _cap = 3000;
    bytes32 public constant ALCHEMIST_ADMIN = keccak256("ALCHEMIST_ADMIN");
    bytes32 public constant TOKENURI_ENGINE_ROLE = keccak256("TOKENURI_ENGINE_ROLE");
    bytes32 public constant ROYALTY_ORACLE_ROLE = keccak256("ROYALTY_ORACLE_ROLE");
    bytes32 public constant ALCHEMIST_ROLE = keccak256("ALCHEMIST_ROLE");
    bytes32 public constant ALCHEMIST_CONTRACT_ROLE = keccak256("ALCHEMIST_CONTRACT_ROLE");
    mapping(address => AlchemistOf) private _alchemists;

    using Address for address;
    using Counters for Counters.Counter;

    event Minted(address indexed owner, uint256 indexed tokenId);
    event CallSetAlchemist(address alchemist, uint8 allow);
    constructor(address timelockController, address erc20TransferHelper_, ITreasury micTreasury_, ITreasury midLandTreasury_, ITreasury alchemistTreasury_) ERC721("Alchemist", "ALC") Royalty(erc20TransferHelper_, micTreasury_, midLandTreasury_, alchemistTreasury_) {
        _setRoleAdmin(ALCHEMIST_ADMIN, ALCHEMIST_ADMIN);
        require(timelockController != address(0), "Timelock controller address is invalid");
        _setRoleAdmin(TOKENURI_ENGINE_ROLE, ALCHEMIST_ADMIN);
        _setRoleAdmin(ALCHEMIST_ROLE, ALCHEMIST_ADMIN);
        _setRoleAdmin(ALCHEMIST_CONTRACT_ROLE, ALCHEMIST_ADMIN);
        _setRoleAdmin(ROYALTY_ORACLE_ROLE, ALCHEMIST_ADMIN);
        _setupRole(ALCHEMIST_ADMIN, timelockController);
        _setupRole(TOKENURI_ENGINE_ROLE, timelockController);
        _setupRole(ROYALTY_ORACLE_ROLE, timelockController);
    }

    function cap() public pure returns (uint256) {
        return _cap;
    }
    function pause() external whenNotPaused onlyOwner {
        _pause();
    }
    function unpause() external whenPaused onlyOwner {
        _unpause();
    }
    function tokenURI(uint256 tokenId) override public view returns (string memory) {
        require(tokenId >= 1000 && tokenId < next_id.current(), "ID is invalid");
        ItokenURIEngine tokenURIEngine_ = tokenURIEngine();
        string memory render =  tokenURIEngine_.render(tokenId);
        string memory json = Base64.encode(bytes(string(abi.encodePacked('{"name": "', Strings.toString(tokenId),'.alchemist", "description": "Alchemsit is the NFTGenesis for MIDHub Protocol.", ', render, '}'))));
        string memory output = string(abi.encodePacked('data:application/json;base64,', json));
        return output;
    }
    function mint() external nonReentrant {
        AlchemistOf memory alchemist = _alchemists[msg.sender];
        require(alchemist.allow > alchemist.minted, "You are not allowed to mint");
        uint256 id = next_id.current();
        require(id >= 1000 && id <= cap() + 1000, "ID invalid");
        _alchemists[msg.sender].minted++;
        _safeMint(_msgSender(), id);
        emit Minted(_msgSender(), id);
        next_id.increment();
    }

    function mintByContract(address owner_) external nonReentrant {
        require(hasRole(ALCHEMIST_CONTRACT_ROLE, msg.sender) && msg.sender.isContract(), "No permission");
        uint256 id = next_id.current();
        require(totalSupply() < cap(), "ID invalid");
        _safeMint(owner_, id);
        emit Minted(owner_, id);
        next_id.increment();
    }

    /* settings */
    function setTokenURIEngine(address tokenURIEngine__) external nonReentrant {
        require(hasRole(TOKENURI_ENGINE_ROLE, msg.sender), "No permission");
        _setTokenURIEngine(tokenURIEngine__);
    }
    function setRoyaltyOracle(address royaltyOracle_) external nonReentrant {
        require(hasRole(ROYALTY_ORACLE_ROLE, msg.sender), "No permission");
        _setRoyaltyOracle(royaltyOracle_);
    }
    function setAlchemist(address owner_, uint8 allow_) external {
        require(hasRole(ALCHEMIST_ROLE, msg.sender), "No permission");
        require(owner_ != address(0), "Alchemist address is invalid");
        require(allow_ > 0 && allow_ <= 50, "Allow is invalid");
        require(_alchemists[owner_].allow == 0, "Alchemist is already set");
        _alchemists[owner_] = AlchemistOf(allow_, 0);
        emit CallSetAlchemist(owner_, allow_);
    }
    function ownerOfMinted(address owner_) external view returns(uint8) {
        return _alchemists[owner_].minted;
    }
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl, ERC721Enumerable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
        require(!paused(), "ERC721Pausable: token transfer while paused");
        super._beforeTokenTransfer(from, to, tokenId);
        compute(from, to, tokenId);
    }
}
