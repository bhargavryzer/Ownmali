// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {TrexToken} from "@tokenysolutions/t-rex/contracts/token/IToken.sol";
import {IModularCompliance} from "@tokenysolutions/t-rex/contracts/compliance/modular/IModularCompliance.sol";
import {IIdentityRegistry} from "@tokenysolutions/t-rex/contracts/registry/interface/IIdentityRegistry.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliAsset
/// @notice ERC-3643 compliant token for asset tokenization with compliance management
/// @dev Production-ready contract for tokenizing real-world assets
contract OwnmaliAsset is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    TrexToken
{
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error ProjectInactive();
    error TokensLocked(address user, uint48 unlockTime);
    error InvalidMetadataUpdate(uint256 updateId);
    error AlreadySigned(address signer);
    error UpdateAlreadyExecuted(uint256 updateId);
    error UnauthorizedCaller(address caller);
    error TransferNotCompliant(address from, address to, uint256 amount);
    error ExceedsMaxSupply(uint256 amount, uint256 maxSupply);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct AssetConfig {
        // Basic asset info
        string name;
        string symbol;
        bytes32 assetId;
        bytes32 assetType;
        
        // Financial parameters
        uint256 maxSupply;
        uint256 tokenPrice;
        uint8 dividendPct;
        
        // Metadata
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        
        // Addresses
        address assetOwner;
        address factory;
        address identityRegistry;
        address compliance;
        
        // Configuration
        uint16 chainId;
        uint256 premintAmount;
    }

    struct MetadataUpdate {
        bytes32 newCID;
        bool isLegal;
        uint8 signatureCount;
        mapping(address => bool) signed;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Role definitions - Only two roles as requested
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // Constants
    uint8 public constant MAX_DIVIDEND_PCT = 100;
    uint8 public constant REQUIRED_SIGNATURES = 2;

    // Asset configuration
    bytes32 public assetId;
    bytes32 public assetType;
    bytes32 public metadataCID;
    bytes32 public legalMetadataCID;
    uint256 public tokenPrice;
    uint8 public dividendPct;
    uint256 public maxSupply;
    uint16 public chainId;

    // Ecosystem contracts
    address public assetOwner;
    address public factory;
    IIdentityRegistry public identityRegistry;
    IModularCompliance public compliance;

    // Operational state
    bool public isActive;
    mapping(address => uint48) public unlockTime;
    mapping(uint256 => MetadataUpdate) private metadataUpdates;
    uint256 public metadataUpdateCount;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event LockPeriodSet(address indexed user, uint48 unlockTime);
    event ProjectStatusChanged(bool isActive);
    event MetadataUpdateProposed(uint256 indexed updateId, bytes32 newCID, bool isLegal);
    event MetadataUpdateSigned(uint256 indexed updateId, address indexed signer);
    event MetadataUpdated(uint256 indexed updateId, bytes32 oldCID, bytes32 newCID, bool isLegal);

    /*//////////////////////////////////////////////////////////////
                           MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier onlyActiveProject() {
        if (!isActive) revert ProjectInactive();
        _;
    }

    modifier onlyFactory() {
        if (msg.sender != factory) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the asset contract
    /// @param configData Encoded AssetConfig for initialization
    function initialize(bytes calldata configData) external initializer {
        AssetConfig memory config = abi.decode(configData, (AssetConfig));
        _validateConfig(config);

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();

        // Initialize TrexToken
        TrexToken.initialize(
            config.name,
            config.symbol,
            18,
            config.identityRegistry,
            config.compliance,
            config.assetOwner
        );

        // Set state variables
        assetId = config.assetId;
        assetType = config.assetType;
        metadataCID = config.metadataCID;
        legalMetadataCID = config.legalMetadataCID;
        tokenPrice = config.tokenPrice;
        dividendPct = config.dividendPct;
        maxSupply = config.maxSupply;
        chainId = config.chainId;
        assetOwner = config.assetOwner;
        factory = config.factory;
        identityRegistry = IIdentityRegistry(config.identityRegistry);
        compliance = IModularCompliance(config.compliance);
        isActive = true;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, config.assetOwner);
        _grantRole(ADMIN_ROLE, config.assetOwner);
        _grantRole(OPERATOR_ROLE, config.assetOwner);
        _setRoleAdmin(OPERATOR_ROLE, ADMIN_ROLE);

        // Premint if specified
        if (config.premintAmount > 0) {
            _mint(config.assetOwner, config.premintAmount);
        }

        emit ProjectStatusChanged(true);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes a metadata update
    /// @param newCID New IPFS CID
    /// @param isLegal Whether the update is for legal metadata
    function proposeMetadataUpdate(bytes32 newCID, bool isLegal) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        onlyActiveProject 
    {
        newCID.validateCID("newCID");
        
        uint256 updateId = metadataUpdateCount++;
        MetadataUpdate storage update = metadataUpdates[updateId];
        update.newCID = newCID;
        update.isLegal = isLegal;
        update.signed[msg.sender] = true;
        update.signatureCount = 1;
        
        emit MetadataUpdateProposed(updateId, newCID, isLegal);
        emit MetadataUpdateSigned(updateId, msg.sender);
    }

    /// @notice Approves a metadata update
    /// @param updateId ID of the metadata update
    function approveMetadataUpdate(uint256 updateId) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        onlyActiveProject 
    {
        if (updateId >= metadataUpdateCount) revert InvalidMetadataUpdate(updateId);
        
        MetadataUpdate storage update = metadataUpdates[updateId];
        if (update.newCID == bytes32(0)) revert InvalidMetadataUpdate(updateId);
        if (update.executed) revert UpdateAlreadyExecuted(updateId);
        if (update.signed[msg.sender]) revert AlreadySigned(msg.sender);

        update.signed[msg.sender] = true;
        update.signatureCount++;
        emit MetadataUpdateSigned(updateId, msg.sender);

        if (update.signatureCount >= REQUIRED_SIGNATURES) {
            bytes32 oldCID = update.isLegal ? legalMetadataCID : metadataCID;
            
            if (update.isLegal) {
                legalMetadataCID = update.newCID;
            } else {
                metadataCID = update.newCID;
            }
            
            update.executed = true;
            emit MetadataUpdated(updateId, oldCID, update.newCID, update.isLegal);
        }
    }

    /// @notice Sets the lock period for a user
    /// @param user User address
    /// @param _unlockTime Unlock timestamp
    function setLockPeriod(address user, uint48 _unlockTime) 
        external 
        onlyRole(ADMIN_ROLE) 
    {
        if (user == address(0)) revert InvalidAddress(user);
        if (_unlockTime <= block.timestamp) revert InvalidParameter("unlockTime");
        
        unlockTime[user] = _unlockTime;
        emit LockPeriodSet(user, _unlockTime);
    }

    /// @notice Updates project status
    /// @param _isActive New active status
    function setProjectStatus(bool _isActive) external onlyRole(ADMIN_ROLE) {
        isActive = _isActive;
        emit ProjectStatusChanged(_isActive);
    }

    /// @notice Updates token price
    /// @param _tokenPrice New token price
    function setTokenPrice(uint256 _tokenPrice) external onlyRole(ADMIN_ROLE) {
        if (_tokenPrice == 0) revert InvalidParameter("tokenPrice");
        tokenPrice = _tokenPrice;
    }

    /// @notice Updates dividend percentage
    /// @param _dividendPct New dividend percentage
    function setDividendPct(uint8 _dividendPct) external onlyRole(ADMIN_ROLE) {
        if (_dividendPct > MAX_DIVIDEND_PCT) revert InvalidParameter("dividendPct");
        dividendPct = _dividendPct;
    }

    /// @notice Mints tokens to specified address
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) 
        external 
        onlyRole(OPERATOR_ROLE) 
        whenNotPaused 
        onlyActiveProject 
    {
        if (to == address(0)) revert InvalidAddress(to);
        if (totalSupply() + amount > maxSupply) {
            revert ExceedsMaxSupply(totalSupply() + amount, maxSupply);
        }
        if (!compliance.canTransfer(address(0), to, amount)) {
            revert TransferNotCompliant(address(0), to, amount);
        }
        
        _mint(to, amount);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates token transfers
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount to transfer
    function _beforeTokenTransfer(address from, address to, uint256 amount) 
        internal 
        virtual 
        override 
        whenNotPaused
    {
        if (amount == 0) revert InvalidParameter("amount");
        if (!isActive) revert ProjectInactive();
        
        // Check lock period for sender
        if (from != address(0) && block.timestamp < unlockTime[from]) {
            revert TokensLocked(from, unlockTime[from]);
        }
        
        // Compliance check for transfers
        if (from != address(0) && to != address(0)) {
            if (!compliance.canTransfer(from, to, amount)) {
                revert TransferNotCompliant(from, to, amount);
            }
        }
        
        // Check max supply on minting
        if (from == address(0) && totalSupply() + amount > maxSupply) {
            revert ExceedsMaxSupply(totalSupply() + amount, maxSupply);
        }
    }

    /// @notice Validates asset configuration
    /// @param config Asset configuration struct
    function _validateConfig(AssetConfig memory config) internal pure {
        if (config.assetOwner == address(0)) revert InvalidAddress(config.assetOwner);
        if (config.factory == address(0)) revert InvalidAddress(config.factory);
        if (config.identityRegistry == address(0)) revert InvalidAddress(config.identityRegistry);
        if (config.compliance == address(0)) revert InvalidAddress(config.compliance);
        
        config.name.validateString("name", 1, 100);
        config.symbol.validateString("symbol", 1, 10);
        config.assetId.validateId("assetId");
        config.metadataCID.validateCID("metadataCID");
        config.legalMetadataCID.validateCID("legalMetadataCID");
        
        if (config.maxSupply == 0) revert InvalidParameter("maxSupply");
        if (config.tokenPrice == 0) revert InvalidParameter("tokenPrice");
        if (config.dividendPct > MAX_DIVIDEND_PCT) revert InvalidParameter("dividendPct");
        if (config.premintAmount > config.maxSupply) revert InvalidParameter("premintAmount");
        if (config.chainId == 0) revert InvalidParameter("chainId");
    }

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) 
        internal 
        view 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns asset configuration
    /// @return Asset configuration struct
    function getAssetConfig() external view returns (AssetConfig memory) {
        return AssetConfig({
            name: name(),
            symbol: symbol(),
            assetId: assetId,
            assetType: assetType,
            maxSupply: maxSupply,
            tokenPrice: tokenPrice,
            dividendPct: dividendPct,
            metadataCID: metadataCID,
            legalMetadataCID: legalMetadataCID,
            assetOwner: assetOwner,
            factory: factory,
            identityRegistry: address(identityRegistry),
            compliance: address(compliance),
            chainId: chainId,
            premintAmount: 0 // Not stored after initialization
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
    function getLockUntil(address account) external view returns (uint48) {
        return unlockTime[account];
    }

    /// @notice Returns supply information
    /// @return currentSupply Current token supply
    /// @return maxSupply_ Maximum token supply
    function getSupplyInfo() external view returns (uint256 currentSupply, uint256 maxSupply_) {
        return (totalSupply(), maxSupply);
    }
}