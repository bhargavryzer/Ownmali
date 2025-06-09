// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {TrexToken} from "@tokenysolutions/t-rex/token/IToken.sol";  // or similar file name
import {IModularCompliance} from "@tokenysolutions/t-rex/compliance/modular/IModularCompliance.sol";
import {IIdentityRegistry} from "@tokenysolutions/t-rex/registry/interface/IIdentityRegistry.sol";
import "./interfaces/IOwnmaliEscrow.sol";
import "./interfaces/IOwnmaliOrderManager.sol";

/// @title OwnmaliProject
/// @notice ERC-3643 compliant token for general asset tokenization with compliance and metadata management
/// @dev Base contract for asset tokenization, extended by specific asset types like real estate
contract OwnmaliProject is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    TrexToken
{
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
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

    /*//////////////////////////////////////////////////////////////
                         TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
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
        address identityRegistry;
        address compliance;
    }

    struct MetadataUpdate {
        bytes32 newCID;
        bool isLegal;
        uint256 signatureCount;
        mapping(address => bool) signed;
        bool executed;
    }

    struct ProjectDetails {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        uint256 dividendPct;
        uint256 minInvestment;
        uint256 maxInvestment;
        bytes32 assetType;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        bytes32 companyId;
        bytes32 assetId;
        address projectOwner;
        address factoryOwner;
        address escrow;
        address orderManager;
        address dao;
        address owner;
        uint16 chainId;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROJECT_ADMIN_ROLE = keccak256("PROJECT_ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    uint256 public constant TOKEN_DECIMALS = 10 ** 18;
    uint256 public constant MAX_DIVIDEND_PCT = 50;
    uint256 public constant DEFAULT_LOCK_PERIOD = 365 days;

    address public factoryOwner;
    address public projectOwner;
    bytes32 public companyId;
    bytes32 public assetId;
    uint256 public tokenPrice;
    uint256 public cancelDelay;
    uint256 public dividendPct;
    uint256 public minInvestment;
    uint256 public maxInvestment;
    bytes32 public assetType;
    bytes32 public legalMetadataCID;
    address public escrow;
    address public orderManager;
    address public dao;
    uint16 public chainId;
    bytes32 public metadataCID;
    bool public isActive;
    uint48 public defaultLockPeriod;
    uint256 public requiredSignatures;
    IIdentityRegistry public identityRegistry;
    IModularCompliance public compliance;
    mapping(address => uint48) public lockUntil;
    mapping(uint256 => MetadataUpdate) private metadataUpdates;
    uint256 public metadataUpdateCount;

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event LockPeriodSet(address indexed user, uint48 unlockTime, uint16 chainId);
    event BatchLockPeriodSet(uint256 userCount, uint48 unlockTime, uint16 chainId);
    event ProjectDeactivated(address indexed project, bytes32 reason, uint16 chainId);
    event MetadataUpdateProposed(uint256 indexed updateId, bytes32 newCID, bool isLegal, uint16 chainId);
    event MetadataUpdateSigned(uint256 indexed updateId, address indexed signer, uint16 chainId);
    event MetadataUpdated(uint256 indexed updateId, bytes32 oldCID, bytes32 newCID, bool isLegal, uint16 chainId);
    event ProjectContractsSet(address indexed escrow, address indexed orderManager, address indexed dao, uint16 chainId);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount, uint16 chainId);

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function proposeMetadataUpdate(bytes32 newCID, bool isLegal) external onlyRole(PROJECT_ADMIN_ROLE) whenNotPaused {
        if (newCID == bytes32(0)) revert InvalidMetadataCID(newCID);
        uint256 updateId = metadataUpdateCount++;
        MetadataUpdate storage update = metadataUpdates[updateId];
        update.newCID = newCID;
        update.isLegal = isLegal;
        update.signed[msg.sender] = true;
        update.signatureCount = 1;
        emit MetadataUpdateProposed(updateId, newCID, isLegal, chainId);
        emit MetadataUpdateSigned(updateId, msg.sender, chainId);
    }

    function approveMetadataUpdate(uint256 updateId) external onlyRole(PROJECT_ADMIN_ROLE) whenNotPaused {
        MetadataUpdate storage update = metadataUpdates[updateId];
        if (update.newCID == bytes32(0)) revert InvalidMetadataUpdate(updateId);
        if (update.executed) revert UpdateAlreadyExecuted(updateId);
        if (update.signed[msg.sender]) revert AlreadySigned(msg.sender);
        update.signed[msg.sender] = true;
        update.signatureCount++;
        emit MetadataUpdateSigned(updateId, msg.sender, chainId);
        if (update.signatureCount >= requiredSignatures) {
            bytes32 oldCID = update.isLegal ? legalMetadataCID : metadataCID;
            if (update.isLegal) {
                legalMetadataCID = update.newCID;
            } else {
                metadataCID = update.newCID;
            }
            update.executed = true;
            emit MetadataUpdated(updateId, oldCID, update.newCID, update.isLegal, chainId);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PUBLIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function initialize(bytes memory initData) public virtual initializer {
        ProjectInitParams memory params = abi.decode(initData, (ProjectInitParams));
        _validateInitParams(params);
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __Pausable_init();
        TrexToken.initialize(
            params.name,
            params.symbol,
            18,
            params.identityRegistry,
            params.compliance,
            params.projectOwner
        );
        _setProjectState(params);
        _grantRole(DEFAULT_ADMIN_ROLE, params.projectOwner);
        _grantRole(ADMIN_ROLE, params.projectOwner);
        _grantRole(AGENT_ROLE, params.projectOwner);
        _setRoleAdmin(PROJECT_ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _grantRole(PROJECT_ADMIN_ROLE, params.projectOwner);
        _grantRole(MINTER_ROLE, params.projectOwner);
    }

    function setProjectContractsAndPreMint(
        address _escrow,
        address _orderManager,
        address _dao,
        uint256 _preMintAmount
    ) public virtual {
        if (_escrow == address(0) || _orderManager == address(0) || _dao == address(0)) {
            revert InvalidAddress(address(0));
        }
        escrow = _escrow;
        orderManager = _orderManager;
        dao = _dao;
        if (_preMintAmount > 0) {
            _mint(_escrow, _preMintAmount);
        }
        emit ProjectContractsSet(_escrow, _orderManager, _dao, chainId);
    }

    function pause() public virtual onlyRole(ADMIN_ROLE) {
        _pause();
        if (escrow != address(0)) IOwnmaliEscrow(escrow).pause();
        if (orderManager != address(0)) IOwnmaliOrderManager(orderManager).pause();
    }

    function unpause() public virtual onlyRole(ADMIN_ROLE) {
        _unpause();
        if (escrow != address(0)) IOwnmaliEscrow(escrow).unpause();
        if (orderManager != address(0)) IOwnmaliOrderManager(orderManager).unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function _setProjectState(ProjectInitParams memory params) internal virtual {
        factoryOwner = params.factory;
        projectOwner = params.projectOwner;
        companyId = params.companyId;
        assetId = params.assetId;
        tokenPrice = params.tokenPrice;
        cancelDelay = params.cancelDelay;
        dividendPct = params.dividendPct;
        minInvestment = params.minInvestment;
        maxInvestment = params.maxInvestment;
        assetType = params.assetType;
        legalMetadataCID = params.legalMetadataCID;
        metadataCID = params.metadataCID;
        chainId = params.chainId;
        isActive = true;
        defaultLockPeriod = uint48(DEFAULT_LOCK_PERIOD);
        requiredSignatures = 2;
        identityRegistry = IIdentityRegistry(params.identityRegistry);
        compliance = IModularCompliance(params.compliance);
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (!isActive) revert ProjectInactive();
        if (from != address(0) && block.timestamp < lockUntil[from]) {
            revert TokensLocked(from, lockUntil[from]);
        }
        if (from != address(0) && to != address(0)) {
            require(compliance.canTransfer(from, to, amount), "Transfer not compliant");
            require(amount >= minInvestment || balanceOf(to) + amount >= minInvestment, "Amount below minInvestment");
            require(balanceOf(to) + amount <= maxInvestment, "Exceeds maxInvestment");
        }
    }

    function _validateInitParams(ProjectInitParams memory params) internal virtual view {
        if (params.factory == address(0)) revert InvalidAddress(params.factory);
        if (params.projectOwner == address(0)) revert InvalidAddress(params.projectOwner);
        if (params.identityRegistry == address(0)) revert InvalidAddress(params.identityRegistry);
        if (params.compliance == address(0)) revert InvalidAddress(params.compliance);
        if (params.maxSupply == 0) revert InvalidParameter("maxSupply");
        if (params.tokenPrice == 0) revert InvalidParameter("tokenPrice");
        if (params.cancelDelay == 0) revert InvalidParameter("cancelDelay");
        if (params.dividendPct > MAX_DIVIDEND_PCT) revert InvalidParameter("dividendPct");
        if (params.premintAmount > params.maxSupply) revert InvalidParameter("premintAmount");
        if (params.metadataCID == bytes32(0)) revert InvalidMetadataCID(params.metadataCID);
        if (params.legalMetadataCID == bytes32(0)) revert InvalidMetadataCID(params.legalMetadataCID);
        if (params.minInvestment == 0) revert InvalidParameter("minInvestment");
        if (params.maxInvestment < params.minInvestment) revert InvalidParameter("maxInvestment");
        if (params.chainId == 0) revert InvalidChainId(params.chainId);
    }

    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function owner() external view returns (address) {
        return projectOwner;
    }

    function getIsActive() external view returns (bool) {
        return isActive;
    }

    function getInvestmentLimits() external view returns (uint256 minInvestment_, uint256 maxInvestment_) {
        return (minInvestment, maxInvestment);
    }

    function getProjectDetails() public view virtual returns (ProjectDetails memory) {
        return ProjectDetails({
            name: name(),
            symbol: symbol(),
            maxSupply: totalSupply(),
            tokenPrice: tokenPrice,
            cancelDelay: cancelDelay,
            dividendPct: dividendPct,
            minInvestment: minInvestment,
            maxInvestment: maxInvestment,
            assetType: assetType,
            metadataCID: metadataCID,
            legalMetadataCID: legalMetadataCID,
            companyId: companyId,
            assetId: assetId,
            projectOwner: projectOwner,
            factoryOwner: factoryOwner,
            escrow: escrow,
            orderManager: orderManager,
            dao: dao,
            owner: projectOwner,
            chainId: chainId,
            isActive: isActive
        });
    }

    function getProjectOwner() external view returns (address) {
        return projectOwner;
    }
    
    // IOwnmaliProject interface implementation
    function getMetadataUpdate(uint256 updateId) external view returns (
        bytes32 newCID,
        bool isLegal,
        uint256 approvals,
        bool executed
    ) {
        MetadataUpdate storage update = metadataUpdates[updateId];
        return (update.newCID, update.isLegal, update.approvals, update.executed);
    }
    
    function hasSignedMetadataUpdate(uint256 updateId, address signer) external view returns (bool) {
        return metadataUpdates[updateId].signers[signer];
    }
    
    function lockUntil(address account) external view returns (uint256) {
        return lockUntil[account];
    }
    
    function isActive() external view returns (bool) {
        return isActive;
    }
    
    function lockPeriod() external view returns (uint256) {
        return lockPeriod;
    }
    
    function metadataUpdateCount() external view returns (uint256) {
        return metadataUpdateCount;
    }
}