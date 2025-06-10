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
import {TrexToken} from "@tokenysolutions/t-rex/token/IToken.sol";
import {IModularCompliance} from "@tokenysolutions/t-rex/compliance/modular/IModularCompliance.sol";
import {IIdentityRegistry} from "@tokenysolutions/t-rex/registry/interface/IIdentityRegistry.sol";
import "./Ownmali_Interfaces.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliProject
/// @notice ERC-3643 compliant token for asset tokenization in the Ownmali SPV ecosystem
/// @dev Manages tokenized assets with compliance, metadata, and SPV-specific operations
contract OwnmaliProject is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    TrexToken
{
    using SafeERC20 for IERC20;
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidChainId(uint16 chainId);
    error InvalidParameter(string parameter, string reason);
    error AssetInactive();
    error InvalidMetadataCID(bytes32 cid);
    error TokensLocked(address user, uint48 unlockTime);
    error InvalidMetadataUpdate(uint256 updateId);
    error AlreadySigned(address signer);
    error UpdateAlreadyExecuted(uint256 updateId);
    error UnauthorizedCaller(address caller);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct AssetInitParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        address owner;
        address factory;
        bytes32 spvId;
        bytes32 assetId;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        bytes32 assetType;
        uint16 chainId;
        uint8 dividendPct;
        uint256 premintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint8 eoiPct;
        address identityRegistry;
        address compliance;
    }

    struct MetadataUpdate {
        bytes32 newCID;
        bool isLegal;
        uint8 signatureCount;
        bool executed;
        mapping(address => bool) signed;
    }

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
        uint16 chainId;
        bool isActive;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Role definitions
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ASSET_ADMIN_ROLE = keccak256("ASSET_ADMIN_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant AGENT_ROLE = keccak256("AGENT_ROLE");

    // Token configuration
    uint256 public constant TOKEN_DECIMALS = 10 ** 18;
    uint8 public maxDividendPct; // Max dividend percentage (1-100)
    uint48 public defaultLockPeriod; // Default lock period in seconds
    uint8 public requiredSignatures; // Number of signatures for metadata updates

    // Asset metadata
    bytes32 public spvId; // SPV identifier
    bytes32 public assetId; // Asset identifier
    bytes32 public metadataCID; // IPFS CID for asset metadata
    bytes32 public legalMetadataCID; // IPFS CID for legal metadata
    bytes32 public assetType; // Asset type (e.g., Commercial, Residential)

    // Financial parameters
    uint256 public tokenPrice; // Price per token in wei
    uint256 public cancelDelay; // Delay before order cancellation
    uint8 public dividendPct; // Dividend percentage (1-100)
    uint256 public minInvestment; // Minimum investment in tokens
    uint256 public maxInvestment; // Maximum investment in tokens
    uint8 public eoiPct; // Expression of Interest percentage

    // Ecosystem contracts
    address public owner; // Asset owner
    address public factory; // Factory contract
    address public assetManager; // Asset manager contract
    address public financialLedger; // Financial ledger contract
    address public orderManager; // Order manager contract
    address public spvDao; // SPV DAO contract
    IIdentityRegistry public identityRegistry; // Identity registry
    IModularCompliance public compliance; // Compliance module

    // Operational state
    uint16 public chainId; // Chain ID for cross-chain compatibility
    bool public isActive; // Asset active status
    mapping(address => uint48) public lockUntil; // Token lock periods
    mapping(uint256 => MetadataUpdate) private metadataUpdates; // Metadata update proposals
    uint256 public metadataUpdateCount; // Counter for metadata updates

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event LockPeriodSet(address indexed user, uint48 unlockTime, uint16 chainId);
    event AssetDeactivated(address indexed asset, bytes32 reason, uint16 chainId);
    event MetadataUpdateProposed(uint256 indexed updateId, bytes32 newCID, bool isLegal, uint16 chainId);
    event MetadataUpdateSigned(uint256 indexed updateId, address indexed signer, uint16 chainId);
    event MetadataUpdated(uint256 indexed updateId, bytes32 oldCID, bytes32 newCID, bool isLegal, uint16 chainId);
    event AssetContractsSet(address indexed assetManager, address indexed financialLedger, address indexed orderManager, address spvDao, uint16 chainId);
    event MaxDividendPctSet(uint8 newMaxDividendPct);
    event DefaultLockPeriodSet(uint48 newLockPeriod);
    event RequiredSignaturesSet(uint8 newRequiredSignatures);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the asset contract
    /// @param initData Encoded AssetInitParams for initialization
    function initialize(bytes memory initData) public virtual initializer {
        AssetInitParams memory params = abi.decode(initData, (AssetInitParams));
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
            params.owner
        );

        _setAssetState(params);

        maxDividendPct = 50;
        defaultLockPeriod = uint48(365 days);
        requiredSignatures = 2;

        _grantRole(DEFAULT_ADMIN_ROLE, params.owner);
        _grantRole(ADMIN_ROLE, params.owner);
        _grantRole(AGENT_ROLE, params.owner);
        _setRoleAdmin(ASSET_ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(MINTER_ROLE, ADMIN_ROLE);
        _grantRole(ASSET_ADMIN_ROLE, params.owner);
        _grantRole(MINTER_ROLE, params.owner);

        emit MaxDividendPctSet(maxDividendPct);
        emit DefaultLockPeriodSet(defaultLockPeriod);
        emit RequiredSignaturesSet(requiredSignatures);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes a metadata update
    /// @param newCID New IPFS CID
    /// @param isLegal Whether the update is for legal metadata
    function proposeMetadataUpdate(bytes32 newCID, bool isLegal) external onlyRole(ASSET_ADMIN_ROLE) whenNotPaused {
        newCID.validateCID("newCID");
        uint256 updateId = metadataUpdateCount++;
        MetadataUpdate storage update = metadataUpdates[updateId];
        update.newCID = newCID;
        update.isLegal = isLegal;
        update.signed[msg.sender] = true;
        update.signatureCount = 1;
        emit MetadataUpdateProposed(updateId, newCID, isLegal, chainId);
        emit MetadataUpdateSigned(updateId, msg.sender, chainId);
    }

    /// @notice Approves a metadata update
    /// @param updateId ID of the metadata update
    function approveMetadataUpdate(uint256 updateId) external onlyRole(ASSET_ADMIN_ROLE) whenNotPaused {
        if (updateId >= metadataUpdateCount) revert InvalidMetadataUpdate(updateId);
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

    /// @notice Sets asset contracts and premints tokens
    /// @param _assetManager Asset manager contract address
    /// @param _financialLedger Financial ledger contract address
    /// @param _orderManager Order manager contract address
    /// @param _spvDao SPV DAO contract address
    /// @param _preMintAmount Amount to premint
    function setAssetContractsAndPreMint(
        address _assetManager,
        address _financialLedger,
        address _orderManager,
        address _spvDao,
        uint256 _preMintAmount
    ) public virtual {
        if (msg.sender != factory) revert UnauthorizedCaller(msg.sender);
        if (_assetManager == address(0)) revert InvalidAddress(_assetManager, "assetManager");
        if (_financialLedger == address(0)) revert InvalidAddress(_financialLedger, "financialLedger");
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager, "orderManager");
        if (_spvDao == address(0)) revert InvalidAddress(_spvDao, "spvDao");
        if (_preMintAmount > maxSupply) revert InvalidParameter("preMintAmount", "exceeds maxSupply");

        assetManager = _assetManager;
        financialLedger = _financialLedger;
        orderManager = _orderManager;
        spvDao = _spvDao;

        if (_preMintAmount > 0) {
            if (!compliance.canTransfer(address(0), _assetManager, _preMintAmount)) {
                revert TransferNotCompliant(address(0), _assetManager, _preMintAmount);
            }
            _mint(_assetManager, _preMintAmount);
        }

        emit AssetContractsSet(_assetManager, _financialLedger, _orderManager, _spvDao, chainId);
    }

    /// @notice Sets the maximum dividend percentage
    /// @param _maxDividendPct New maximum dividend percentage
    function setMaxDividendPct(uint8 _maxDividendPct) external onlyRole(ADMIN_ROLE) {
        if (_maxDividendPct == 0 || _maxDividendPct > 100) revert InvalidParameter("maxDividendPct", "must be between 1 and 100");
        maxDividendPct = _maxDividendPct;
        emit MaxDividendPctSet(_maxDividendPct);
    }

    /// @notice Sets the default lock period
    /// @param _lockPeriod New lock period in seconds
    function setDefaultLockPeriod(uint48 _lockPeriod) external onlyRole(ADMIN_ROLE) {
        if (_lockPeriod == 0) revert InvalidParameter("lockPeriod", "must be non-zero");
        defaultLockPeriod = _lockPeriod;
        emit DefaultLockPeriodSet(_lockPeriod);
    }

    /// @notice Sets the required signatures for metadata updates
    /// @param _requiredSignatures New number of required signatures
    function setRequiredSignatures(uint8 _requiredSignatures) external onlyRole(ADMIN_ROLE) {
        if (_requiredSignatures == 0) revert InvalidParameter("requiredSignatures", "must be non-zero");
        requiredSignatures = _requiredSignatures;
        emit RequiredSignaturesSet(_requiredSignatures);
    }

    /// @notice Sets the lock period for a user
    /// @param user User address
    /// @param unlockTime Unlock timestamp
    function setLockPeriod(address user, uint48 unlockTime) external onlyRole(ADMIN_ROLE) {
        if (user == address(0)) revert InvalidAddress(user, "user");
        if (unlockTime <= block.timestamp) revert InvalidParameter("unlockTime", "must be in future");
        lockUntil[user] = unlockTime;
        emit LockPeriodSet(user, unlockTime, chainId);
    }

    /// @notice Pauses the contract and associated contracts
    function pause() public virtual override onlyRole(ADMIN_ROLE) {
        _pause();
        if (assetManager != address(0)) IOwnmaliAssetManager(assetManager).pause();
        if (financialLedger != address(0)) IOwnmaliFinancialLedger(financialLedger).pause();
        if (orderManager != address(0)) IOwnmaliOrderManager(orderManager).pause();
        if (spvDao != address(0)) IOwnmaliSPVDAO(spvDao).pause();
    }

    /// @notice Unpauses the contract and associated contracts
    function unpause() public virtual override onlyRole(ADMIN_ROLE) {
        _unpause();
        if (assetManager != address(0)) IOwnmaliAssetManager(assetManager).unpause();
        if (financialLedger != address(0)) IOwnmaliFinancialLedger(financialLedger).unpause();
        if (orderManager != address(0)) IOwnmaliOrderManager(orderManager).unpause();
        if (spvDao != address(0)) IOwnmaliSPVDAO(spvDao).unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets asset state variables
    /// @param params Asset initialization parameters
    function _setAssetState(AssetInitParams memory params) internal virtual {
        factory = params.factory;
        owner = params.owner;
        spvId = params.spvId;
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
        eoiPct = params.eoiPct;
        isActive = true;
        identityRegistry = IIdentityRegistry(params.identityRegistry);
        compliance = IModularCompliance(params.compliance);
        maxSupply = params.maxSupply;
    }

    /// @notice Validates token transfers
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount to transfer
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override {
        if (!isActive) revert AssetInactive();
        if (from != address(0) && block.timestamp < lockUntil[from]) {
            revert TokensLocked(from, lockUntil[from]);
        }
        if (from != address(0) && to != address(0)) {
            if (!compliance.canTransfer(from, to, amount)) {
                revert TransferNotCompliant(from, to, amount);
            }
            if (amount < minInvestment && balanceOf(to) + amount < minInvestment) {
                revert InvalidParameter("amount", "below minInvestment");
            }
            if (balanceOf(to) + amount > maxInvestment) {
                revert InvalidParameter("amount", "exceeds maxInvestment");
            }
        }
    }

    /// @notice Validates initialization parameters
    /// @param params Asset initialization parameters
    function _validateInitParams(AssetInitParams memory params) internal virtual view {
        if (params.factory == address(0)) revert InvalidAddress(params.factory, "factory");
        if (params.owner == address(0)) revert InvalidAddress(params.owner, "owner");
        if (params.identityRegistry == address(0)) revert InvalidAddress(params.identityRegistry, "identityRegistry");
        if (params.compliance == address(0)) revert InvalidAddress(params.compliance, "compliance");
        params.name.validateString("name", 1, 100);
        params.symbol.validateString("symbol", 1, 10);
        params.spvId.validateId("spvId");
        params.assetId.validateId("assetId");
        params.metadataCID.validateCID("metadataCID");
        params.legalMetadataCID.validateCID("legalMetadataCID");
        if (params.maxSupply == 0) revert InvalidParameter("maxSupply", "must be non-zero");
        if (params.tokenPrice == 0) revert InvalidParameter("tokenPrice", "must be non-zero");
        if (params.cancelDelay == 0) revert InvalidParameter("cancelDelay", "must be non-zero");
        if (params.dividendPct > maxDividendPct) revert InvalidParameter("dividendPct", "exceeds maxDividendPct");
        if (params.premintAmount > params.maxSupply) revert InvalidParameter("premintAmount", "exceeds maxSupply");
        if (params.minInvestment == 0) revert InvalidParameter("minInvestment", "must be non-zero");
        if (params.maxInvestment < params.minInvestment) {
            revert InvalidParameter("maxInvestment", "must be at least minInvestment");
        }
        if (params.chainId == 0) revert InvalidChainId(params.chainId);
        if (params.eoiPct > 50) revert InvalidParameter("eoiPct", "must not exceed 50");
    }

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the asset owner
    /// @return Asset owner address
    function owner() external view override returns (address) {
        return owner;
    }

    /// @notice Returns whether the asset is active
    /// @return True if active
    function getIsActive() external view returns (bool) {
        return isActive;
    }

    /// @notice Returns investment limits
    /// @return minInvestment_ Minimum investment
    /// @return maxInvestment_ Maximum investment
    function getInvestmentLimits() external view returns (uint256 minInvestment_, uint256 maxInvestment_) {
        return (minInvestment, maxInvestment);
    }

    /// @notice Returns asset details
    /// @return Asset details struct
    function getAssetDetails() public view virtual returns (AssetDetails memory) {
        return AssetDetails({
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
            spvId: spvId,
            assetId: assetId,
            owner: owner,
            factory: factory,
            assetManager: assetManager,
            financialLedger: financialLedger,
            orderManager: orderManager,
            spvDao: spvDao,
            chainId: chainId,
            isActive: isActive
        });
    }

    /// @notice Returns metadata update details
    /// @param updateId Metadata update ID
    /// @return newCID New CID
    /// @return isLegal Whether legal metadata
    /// @return signatureCount Number of signatures
    /// @return executed Whether executed
    function getMetadataUpdate(uint256 updateId)
        external
        view
        returns (bytes32 newCID, bool isLegal, uint8 signatureCount, bool executed)
    {
        if (updateId >= metadataUpdateCount) revert InvalidMetadataUpdate(updateId);
        MetadataUpdate storage update = metadataUpdates[updateId];
        return (update.newCID, update.isLegal, update.signatureCount, update.executed);
    }

    /// @notice Checks if an address signed a metadata update
    /// @param updateId Metadata update ID
    /// @param signer Address to check
    /// @return True if signed
    function hasSignedMetadataUpdate(uint256 updateId, address signer) external view returns (bool) {
        if (updateId >= metadataUpdateCount) revert InvalidMetadataUpdate(updateId);
        return metadataUpdates[updateId].signed[signer];
    }

    /// @notice Returns the lock period for an account
    /// @param account Account address
    /// @return Lock period timestamp
    function getLockUntil(address account) external view returns (uint256) {
        return lockUntil[account];
    }
}