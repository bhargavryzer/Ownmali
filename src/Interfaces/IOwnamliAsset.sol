// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IIdentityRegistry} from "@tokenysolutions/t-rex/registry/interface/IIdentityRegistry.sol";
import {IModularCompliance} from "@tokenysolutions/t-rex/compliance/modular/IModularCompliance.sol";

interface IOwnmaliAsset is IERC20, IERC20Metadata {
    // Struct for project details
    struct AssetDetails {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        uint8 dividendPct;
        uint256 minInvestment;
        uint256 maxInvestment;
        bytes32 assetType;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        bytes32 spvId;
        bytes32 assetId;
        address owner;
        address factory;
        address assetManager;
        address financialLedger;
        address orderManager;
        address spvDao;
        address owner_;
        uint16 chainId;
        bool isActive;
    }

    // Errors
    error InvalidAddress(address addr, string parameter);
    error InvalidChainId(uint16 chainId);
    error InvalidParameter(string parameter, string reason);
    error ProjectInactive();
    error InvalidMetadataCID(bytes32 owner);
    error TokensLocked(address indexed user, uint48 unlockTime);
    error InvalidMetadataUpdate(uint256 updateId);
    error AlreadySigned(address indexed signer);
    error UpdateAlreadyExecuted(uint256 updateId);
    error UnauthorizedCaller(address caller);

    // Events
    event LockPeriodSet(address indexed user, uint48 unlockTime, uint16 chainId);
    event BatchLockPeriodSet(uint256 userCount, uint48 unlockTime, uint16 chainId);
    event ProjectDeactivated(address indexed project, bytes32 reason, uint16 chainId);
    event MetadataUpdateProposed(uint256 indexed updateId, bytes32 newCID, bool isLegal, uint16 chainId);
    event MetadataUpdateSigned(uint256 indexed updateId, address indexed signer, uint16 chainId);
    event MetadataUpdated(uint256 indexed updateId, bytes32 oldCID, bytes32 newCID, bool isLegal, uint16 chainId);
    event ProjectContractsSet(address indexed escrow, address indexed orderManager, address indexed dao, uint16 chainId);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount, uint16 chainId);
    event MaxDividendPctSet(uint256 newMaxDividendPct);
    event DefaultLockPeriodSet(uint48 newLockPeriod);
    event RequiredSignaturesSet(uint256 newRequiredSignatures);

    // Initialization
    function initialize(bytes memory initData) external;

    // Metadata Management
    function proposeMetadataUpdate(bytes32 newCID, bool isLegal) external;
    function approveMetadataUpdate(uint256 updateId) external;

    // Project Configuration
    function setProjectContractsAndPreMint(
        address _escrow,
        address _orderManager,
        address _dao,
        uint256 _preMintAmount
    ) external;
    function setMaxDividendPct(uint256 _maxDividendPct) external;
    function setDefaultLockPeriod(uint48 _lockPeriod) external;
    function setRequiredSignatures(uint256 _requiredSignatures) external;
    function setLockPeriod(address user, uint48 unlockTime) external;

    // Pause Functionality
    function pause() external;
    function unpause() external;

    // View Functions
    function owner() external view returns (address);
    function getIsActive() external view returns (bool);
    function getInvestmentLimits() external view returns (uint256 minInvestment, uint256 maxInvestment);
    function getProjectDetails() external view returns (AssetDetails memory);
    function getProjectOwner() external view returns (address);
    function getMetadataUpdate(uint256 updateId)
        external
        view
        returns (
            bytes32 newCID,
            bool isLegal,
            uint256 signatureCount,
            bool executed
        );
    function hasSignedMetadataUpdate(uint256 updateId, address signer) external view returns (bool);
    function getLockUntil(address account) external view returns (uint256);

    // Additional View Functions for State Variables
    function spvId() external view returns (bytes32);
    function assetId() external view returns (bytes32);
    function metadataCID() external view returns (bytes32);
    function legalMetadataCID() external view returns (bytes32);
    function assetType() external view returns (bytes32);
    function tokenPrice() external view returns (uint256);
    function cancelDelay() external view returns (uint256);
    function dividendPct() external view returns (uint8);
    function minInvestment() external view returns (uint256);
    function maxInvestment() external view returns (uint256);
    function eoiPct() external view returns (uint8);
    function factory() external view returns (address);
    function assetManager() external view returns (address);
    function financialLedger() external view returns (address);
    function orderManager() external view returns (address);
    function spvDao() external view returns (address);
    function chainId() external view returns (uint16);
    function identityRegistry() external view returns (IIdentityRegistry);
    function compliance() external view returns (IModularCompliance);
    function maxDividendPct() external view returns (uint8);
    function defaultLockPeriod() external view returns (uint48);
    function requiredSignatures() external view returns (uint8);
}