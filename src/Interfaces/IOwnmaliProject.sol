// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITREXFactory} from "@tokenysolutions/t-rex/factory/ITREXFactory.sol";
import {ITREXGateway} from "@tokenysolutions/t-rex/factory/ITREXGateway.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TrexToken} from "@tokenysolutions/t-rex/token/IToken.sol";

interface IOwnmaliProject is IERC20, IERC20Metadata {
    // Custom Errors
    error InvalidAddress(address addr);
    error InvalidChainId(uint16 chainId);
    error InvalidParameter(string parameter);
    error ProjectInactive();
    error InvalidMetadataCID(bytes32 cid);
    error InvalidAssetType(bytes32 assetType);
    error TokensLocked(address user, uint48 unlockTime);
    error InvalidMetadataUpdate(uint256 updateId);
    error AlreadySigned(address signer);
    error UpdateAlreadyExecuted(uint256 updateId);
    error Unauthorized();
    error InvalidAmount();

    // Structs
    struct ProjectInitParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        address projectOwner;
        address factory;
        bytes32 companyId;
        bytes32 assetId;
        bytes32 metadataCID;
        bytes32 assetType;
        bytes32 legalMetadataCID;
        uint16 chainId;
        uint256 dividendPct;
        uint256 premintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 eoiPct;
        address identityRegistry;
        address compliance;
    }

    struct MetadataUpdate {
        bytes32 newCID;
        bool isLegal;
        uint256 approvals;
        bool executed;
        mapping(address => bool) signers;
    }

    // Events
    event MetadataUpdateProposed(uint256 indexed updateId, bytes32 newCID, bool isLegal);
    event MetadataUpdateSigned(uint256 indexed updateId, address indexed signer);
    event MetadataUpdateExecuted(uint256 indexed updateId, bytes32 newCID, bool isLegal);
    event ProjectActivated();
    event ProjectDeactivated();
    event LockPeriodUpdated(uint256 lockPeriod);
    event FundsWithdrawn(address indexed token, address indexed to, uint256 amount);
    event EscrowUpdated(address indexed escrow);
    event OrderManagerUpdated(address indexed orderManager);
    event DAOUpdated(address indexed dao);

    // External Functions
    function initialize(ProjectInitParams calldata params) external;
    
    function proposeMetadataUpdate(bytes32 newCID, bool isLegal) external;
    
    function signMetadataUpdate(uint256 updateId) external;
    
    function executeMetadataUpdate(uint256 updateId) external;
    
    function setEscrow(address _escrow) external;
    
    function setOrderManager(address _orderManager) external;
    
    function setDAO(address _dao) external;
    
    function setActive(bool _isActive) external;
    
    function setLockPeriod(uint256 _lockPeriod) external;
    
    function withdrawFunds(address token, address to, uint256 amount) external;

    // View Functions
    function getProjectDetails() external view returns (
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint256 tokenPrice,
        uint256 cancelDelay,
        uint256 dividendPct,
        uint256 minInvestment,
        uint256 maxInvestment,
        bytes32 assetType,
        bytes32 metadataCID,
        bytes32 legalMetadataCID,
        bytes32 companyId,
        bytes32 assetId,
        address projectOwner,
        address factoryOwner,
        address escrow,
        address orderManager,
        address dao,
        address owner,
        uint16 chainId,
        bool isActive
    );

    function getMetadataUpdate(uint256 updateId) external view returns (
        bytes32 newCID,
        bool isLegal,
        uint256 approvals,
        bool executed
    );

    function hasSignedMetadataUpdate(uint256 updateId, address signer) external view returns (bool);
    
    function lockUntil(address account) external view returns (uint256);
    
    function isActive() external view returns (bool);
    
    function lockPeriod() external view returns (uint256);
    
    function metadataUpdateCount() external view returns (uint256);
    
    // Required overrides from parent contracts
    function name() external view override returns (string memory);
    
    function symbol() external view override returns (string memory);
    
    function decimals() external view override returns (uint8);
    
    function totalSupply() external view override returns (uint256);
    
    function balanceOf(address account) external view override returns (uint256);
    
    function transfer(address to, uint256 amount) external override returns (bool);
    
    function allowance(address owner, address spender) external view override returns (uint256);
    
    function approve(address spender, uint256 amount) external override returns (bool);
    
    function transferFrom(address from, address to, uint256 amount) external override returns (bool);
    
    function pause() external;
    
    function unpause() external;
}
