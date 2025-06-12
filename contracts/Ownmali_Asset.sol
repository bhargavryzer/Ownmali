// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../lib/@tokenysolutions/t-rex/contracts/token/IToken.sol";
import "../lib/@tokenysolutions/t-rex/contracts/compliance/modular/IModularCompliance.sol";
import "../lib/@tokenysolutions/t-rex/contracts/registry/interface/IIdentityRegistry.sol";

/// @title OwnmaliAsset
/// @notice ERC-3643 compliant token for asset tokenization with premint-only mechanism in the Ownmali ecosystem.
/// @dev Tokens represent real-world assets, fully tokenized during premint; no further minting or burning allowed.
///      Inherits TrexToken for ERC-3643 functionality (identity and compliance checks). Uses UUPS proxy for upgrades.
///      Storage layout must be preserved across upgrades. All IDs are bytes32; amounts in wei.
contract OwnmaliAsset is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    TrexToken
{
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidString(string value, string parameter);
    error InvalidId(bytes32 id, string parameter);
    error InvalidAmount(uint256 value, string parameter);
    error AssetInactive();
    error TokensLocked(address account, uint48 unlockTime);
    error TimelockNotExpired(uint48 unlockTime);
    error TransferNotCompliant(address from, address to, uint256 amount);
    error ExceedsMaxSupply(uint256 totalSupply, uint256 maxSupply);
    error PremintCompleted();
    error ArrayLengthMismatch(uint256 recipients, uint256 amounts);
    error InvalidRecipientCount(uint256 count);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Asset configuration structure.
    struct AssetConfig {
        bytes32 assetId; // Unique asset identifier
        bytes32 assetType; // Asset category (e.g., real estate)
        uint256 maxSupply; // Maximum token supply (in wei)
        uint128 tokenPrice; // Reference price per token (in wei)
        uint8 dividendPct; // Dividend yield percentage (0-100)
        bytes32 metadataCID; // IPFS CID for asset metadata
        bytes32 legalMetadataCID; // IPFS CID for legal documents
    }

    /// @notice Structure for pending updates with timelock.
    struct PendingUpdate {
        bytes32 value; // New value (CID or role)
        bytes32 role; // Role for role updates (0 for metadata)
        bool isLegal; // True for legal metadata update
        bool grant; // True for grant, false for revoke (for roles)
        address account; // Account for role updates (0 for metadata)
        uint48 unlockTime; // Timestamp for execution
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Maximum dividend percentage (100%).
    uint8 public constant MAX_DIVIDEND_PCT = 100;

    /// @notice Duration for timelock on updates (1 day).
    uint48 public constant TIMELOCK_DURATION = 1 days;

    /// @notice Role for asset administration (e.g., metadata, status).
    bytes32 public constant ASSET_ADMIN_ROLE = keccak256("ASSET_ADMIN_ROLE");

    /// @notice Role for preminting operations.
    bytes32 public constant ASSET_OPERATOR_ROLE = keccak256("ASSET_OPERATOR_ROLE");

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Unique asset identifier.
    bytes32 public assetId;

    /// @notice Asset category (e.g., real estate).
    bytes32 public assetType;

    /// @notice IPFS CID for asset metadata.
    bytes32 public metadataCID;

    /// @notice IPFS CID for legal documents.
    bytes32 public legalMetadataCID;

    /// @notice Reference price per token (in wei).
    uint128 public tokenPrice;

    /// @notice Dividend yield percentage (0-100).
    uint8 public dividendPct;

    /// @notice Maximum token supply (in wei).
    uint256 public maxSupply;

    /// @notice Whether the asset is active for transfers.
    bool public isActive;

    /// @notice Whether preminting is completed.
    bool public isPremintCompleted;

    /// @notice Mapping of account to token unlock timestamp.
    mapping(address => uint48) public unlockTime;

    /// @notice Mapping of action IDs to pending updates (metadata or roles).
    mapping(bytes32 => PendingUpdate) public pendingUpdates;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when preminting is completed.
    event PremintCompleted(uint256 totalSupply, uint256 timestamp);

    /// @notice Emitted when tokens are preminted.
    event Preminted(address indexed operator, uint256 totalAmount, uint256 recipientCount);

    /// @notice Emitted when a lock period is set for an account.
    event LockPeriodSet(address indexed account, uint48 unlockTime);

    /// @notice Emitted when the asset’s active status changes.
    event AssetStatusChanged(bool isActive);

    /// @notice Emitted when the token price is updated.
    event TokenPriceUpdated(uint128 oldPrice, uint128 newPrice);

    /// @notice Emitted when the dividend percentage is updated.
    event DividendPctUpdated(uint8 oldPct, uint8 newPct);

    /// @notice Emitted when metadata is updated.
    event MetadataUpdated(bytes32 oldCID, bytes32 newCID, bool isLegal);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the asset token contract.
    /// @dev Sets up token configuration, roles, and T-REX contracts. Only callable once.
    /// @param name Token name (max 64 bytes).
    /// @param symbol Token symbol (max 4 bytes).
    /// @param identityRegistry Address of the identity registry (T-REX).
    /// @param compliance Address of the modular compliance contract (T-REX).
    /// @param owner Address of the asset owner (T-REX owner).
    /// @param admin Address for ASSET_ADMIN_ROLE.
    /// @param operator Address for ASSET_OPERATOR_ROLE.
    /// @param configData ABI-encoded AssetConfig.
    function initialize(
        string memory name,
        string memory symbol,
        address identityRegistry,
        address compliance,
        address owner,
        address admin,
        address operator,
        bytes calldata configData
    ) external initializer {
        AssetConfig memory config = abi.decode(configData, (AssetConfig));
        _validateString(name, "name", 1, 64);
        _validateString(symbol, "symbol", 1, 8);
        _validateAddress(owner, "owner");
        _validateAddress(admin, "admin");
        _validateAddress(operator, "operator");
        _validateAddress(identityRegistry, "identityRegistry");
        _validateAddress(compliance, "compliance");
        _validateId(config.assetId, "assetId");
        _validateId(config.assetType, "assetType");
        _validateId(config.metadataCID, "metadataCID");
        _validateId(config.legalMetadataCID, "legalMetadataCID");
        if (config.maxSupply == 0) revert InvalidAmount(0, "maxSupply");
        if (config.tokenPrice == 0) revert InvalidAmount(0, "tokenPrice");
        if (config.dividendPct > MAX_DIVIDEND_PCT) revert InvalidAmount(config.dividendPct, "dividendPct");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        // Initialize TrexToken
        TrexToken.initialize(name, symbol, 18, identityRegistry, compliance, owner);

        // Set state variables
        assetId = config.assetId;
        assetType = config.assetType;
        metadataCID = config.metadataCID;
        legalMetadataCID = config.legalMetadataCID;
        tokenPrice = config.tokenPrice;
        dividendPct = config.dividendPct;
        maxSupply = config.maxSupply;
        isActive = true;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ASSET_ADMIN_ROLE, admin);
        _grantRole(ASSET_OPERATOR_ROLE, operator);
        _setRoleAdmin(ASSET_ADMIN_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(ASSET_OPERATOR_ROLE, ASSET_ADMIN_ROLE);

        emit AssetStatusChanged(true);
    }

    /*//////////////////////////////////////////////////////////////
                           TOKEN MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Premints tokens to multiple recipients.
    /// @dev Mints tokens in a single batch, subject to compliance checks. Only callable by ASSET_OPERATOR_ROLE.
    /// @param recipients Array of recipient addresses.
    /// @param amounts Array of token amounts (in wei).
    function premint(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyRole(ASSET_OPERATOR_ROLE)
        whenNotPaused
        onlyActiveAsset
        nonReentrant
    {
        if (isPremintCompleted) revert PremintCompleted();
        if (recipients.length == 0 || recipients.length != amounts.length) {
            revert ArrayLengthMismatch(recipients.length, amounts.length);
        }

        uint256 totalAmount;
        for (uint256 i = 0; i < recipients.length; i++) {
            _validateAddress(recipients[i], "recipient");
            if (amounts[i] == 0) revert InvalidAmount(0, "amount");
            if (!compliance.canTransfer(address(0), recipients[i], amounts[i])) {
                revert TransferNotCompliant(address(0), recipients[i], amounts[i]);
            }
            totalAmount += amounts[i];
            _mint(recipients[i], amounts[i]);
        }

        uint256 currentSupply = totalSupply();
        if (currentSupply > maxSupply) revert ExceedsMaxSupply(currentSupply, maxSupply);
        if (currentSupply == maxSupply) {
            isPremintCompleted = true;
            emit PremintCompleted(currentSupply, block.timestamp);
        }
        emit Preminted(msg.sender, totalAmount, recipients.length);
    }

    /// @notice Finalizes preminting, preventing further minting.
    /// @dev Callable even if maxSupply is not reached. Only callable by ASSET_ADMIN_ROLE.
    function completePremint()
        external
        onlyRole(ASSET_ADMIN_ROLE)
        whenNotPaused
        onlyActiveAsset
        nonReentrant
    {
        if (isPremintCompleted) revert PremintCompleted();
        isPremintCompleted = true;
        emit PremintCompleted(totalSupply(), block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Updates metadata (asset or legal) after timelock.
    /// @dev Requires two calls: propose, then execute after timelock. Only callable by ASSET_ADMIN_ROLE.
    /// @param newCID New IPFS CID.
    /// @param isLegal True for legal metadata, false for asset metadata.
    function updateMetadata(bytes32 newCID, bool isLegal)
        external
        onlyRole(ASSET_ADMIN_ROLE)
        whenNotPaused
        onlyActiveAsset
        nonReentrant
    {
        _validateId(newCID, "newCID");

        bytes32 actionId = keccak256(abi.encode("metadata", newCID, isLegal));
        if (pendingUpdates[actionId].value != newCID || pendingUpdates[actionId].isLegal != isLegal) {
            pendingUpdates[actionId] = PendingUpdate({
                value: newCID,
                role: bytes32(0),
                isLegal: isLegal,
                grant: false,
                account: address(0),
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        bytes32 oldCID = isLegal ? legalMetadataCID : metadataCID;
        if (isLegal) {
            legalMetadataCID = newCID;
        } else {
            metadataCID = newCID;
        }
        delete pendingUpdates[actionId];
        emit MetadataUpdated(oldCID, newCID, isLegal);
    }

    /// @notice Sets lock periods for multiple accounts.
    /// @dev Updates unlock timestamps for token transfers. Only callable by ASSET_ADMIN_ROLE.
    /// @param accounts Array of account addresses.
    /// @param unlockTimes Array of unlock timestamps.
    function batchSetLockPeriod(address[] calldata accounts, uint48[] calldata unlockTimes)
        external
        onlyRole(ASSET_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (accounts.length == 0 || accounts.length != unlockTimes.length) {
            revert ArrayLengthMismatch(accounts.length, unlockTimes.length);
        }

        for (uint256 i = 0; i < accounts.length; i++) {
            _validateAddress(accounts[i], "account");
            if (unlockTimes[i] <= block.timestamp) revert InvalidAmount(unlockTimes[i], "unlockTime");
            unlockTime[accounts[i]] = unlockTimes[i];
            emit LockPeriodSet(accounts[i], unlockTimes[i]);
        }
    }

    /// @notice Updates the asset’s active status.
    /// @dev Enables or disables transfers. Only callable by ASSET_ADMIN_ROLE.
    /// @param isActive_ New active status.
    function setAssetStatus(bool isActive_)
        external
        onlyRole(ASSET_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        isActive = isActive_;
        emit AssetStatusChanged(isActive_);
    }

    /// @notice Updates the token reference price.
    /// @dev Sets new price per token. Only callable by ASSET_ADMIN_ROLE.
    /// @param tokenPrice_ New price (in wei).
    function setTokenPrice(uint128 tokenPrice_)
        external
        onlyRole(ASSET_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (tokenPrice_ == 0) revert InvalidAmount(0, "tokenPrice");
        uint128 oldPrice = tokenPrice;
        tokenPrice = tokenPrice_;
        emit TokenPriceUpdated(oldPrice, tokenPrice_);
    }

    /// @notice Updates the dividend yield percentage.
    /// @dev Sets new percentage (0-100). Only callable by ASSET_ADMIN_ROLE.
    /// @param dividendPct_ New percentage.
    function setDividendPct(uint8 dividendPct_)
        external
        onlyRole(ASSET_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (dividendPct_ > MAX_DIVIDEND_PCT) revert InvalidAmount(dividendPct_, "dividendPct");
        uint8 oldPct = dividendPct;
        dividendPct = dividendPct_;
        emit DividendPctUpdated(oldPct, dividendPct_);
    }

    /// @notice Proposes or executes granting/revoking a role with a timelock.
    /// @dev Requires two calls: propose, then execute after timelock. Only callable by DEFAULT_ADMIN_ROLE.
    /// @param role Role to update (DEFAULT_ADMIN_ROLE, ASSET_ADMIN_ROLE, ASSET_OPERATOR_ROLE).
    /// @param account Address to update.
    /// @param grant True to grant, false to revoke.
    function setRole(bytes32 role, address account, bool grant)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateAddress(account, "account");
        if (role != DEFAULT_ADMIN_ROLE && role != ASSET_ADMIN_ROLE && role != ASSET_OPERATOR_ROLE) {
            revert InvalidParameter("role", "invalid role");
        }

        bytes32 actionId = keccak256(abi.encode("role", role, account, grant));
        if (pendingUpdates[actionId].account != account || pendingUpdates[actionId].role != role) {
            pendingUpdates[actionId] = PendingUpdate({
                value: bytes32(0),
                role: role,
                isLegal: false,
                grant: grant,
                account: account,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        if (grant) {
            _grantRole(role, account);
        } else {
            _revokeRole(role, account);
        }
        delete pendingUpdates[actionId];
    }

    /// @notice Revokes a role from an account.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Enhances security by allowing role removal.
    /// @param role Role to revoke.
    /// @param account Address to revoke role from.
    function revokeRole(bytes32 role, address account)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateAddress(account, "account");
        if (role != DEFAULT_ADMIN_ROLE && role != ASSET_ADMIN_ROLE && role != ASSET_OPERATOR_ROLE) {
            revert InvalidParameter("role", "invalid role");
        }
        _revokeRole(role, account);
    }

    /// @notice Pauses the contract.
    /// @dev Only callable by ASSET_ADMIN_ROLE.
    function pause() external onlyRole(ASSET_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract.
    /// @dev Only callable by ASSET_ADMIN_ROLE.
    function unpause() external onlyRole(ASSET_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Retrieves the asset configuration.
    /// @dev Returns all asset parameters.
    /// @return config AssetConfig structure.
    function getAssetConfig() external view returns (AssetConfig memory config) {
        return AssetConfig({
            assetId: assetId,
            assetType: assetType,
            maxSupply: maxSupply,
            tokenPrice: tokenPrice,
            dividendPct: dividendPct,
            metadataCID: metadataCID,
            legalMetadataCID: legalMetadataCID
        });
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Validates token transfers.
    /// @dev Checks asset status, lock periods, and compliance. Overrides TrexToken.
    /// @param from Sender address.
    /// @param to Recipient address.
    /// @param amount Amount to transfer (in wei).
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
        whenNotPaused
    {
        if (amount == 0) revert InvalidAmount(0, "amount");
        if (!isActive) revert AssetInactive();
        if (from != address(0) && block.timestamp < unlockTime[from]) {
            revert TokensLocked(from, unlockTime[from]);
        }
        if (!compliance.canTransfer(from, to, amount)) {
            revert TransferNotCompliant(from, to, amount);
        }
    }

    /// @notice Authorizes contract upgrades.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Ensures valid implementation.
    /// @param newImplementation Address of the new implementation contract.
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }

    /// @notice Validates an address.
    /// @dev Ensures address is non-zero.
    /// @param addr Address to validate.
    /// @param parameter Parameter name for error reporting.
    function _validateAddress(address addr, string memory parameter) private pure {
        if (addr == address(0)) revert InvalidAddress(addr, parameter);
    }

    /// @notice Validates a string.
    /// @dev Ensures string length is within bounds.
    /// @param value String to validate.
    /// @param param Parameter name for error reporting.
    /// @param minLength Minimum length.
    /// @param maxLength Maximum length.
    function _validateString(string memory value, string memory param, uint256 minLength, uint256 maxLength) private pure {
        uint256 length = bytes(value).length;
        if (length < minLength || length > maxLength) revert InvalidString(value, param);
    }

    /// @notice Validates a bytes32 ID.
    /// @dev Ensures ID is non-zero.
    /// @param id ID to validate.
    /// @param parameter Parameter name for error reporting.
    function _validateId(bytes32 id, string memory parameter) private pure {
        if (id == bytes32(0)) revert InvalidId(id, parameter);
    }
}