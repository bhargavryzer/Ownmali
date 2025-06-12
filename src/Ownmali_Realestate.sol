// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./Ownmali_Asset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title OwnmaliRealEstateToken
/// @notice ERC-3643 compliant token for real estate assets with premint-only tokenization
/// @dev Real estate assets are fully tokenized during initialization or premint phase, no additional minting or burning allowed
contract OwnmaliRealEstateToken is OwnmaliAsset, ReentrancyGuardUpgradeable {
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAssetType(bytes32 assetType);
    error BatchTooLarge(uint256 size, uint256 maxSize);
    error ArrayLengthMismatch(uint256 toLength, uint256 amountsLength);
    error ZeroAmountDetected(address recipient);
    error InvalidRecipient(address recipient);
    error EmptyBatch();
    error MintingNotAllowed();
    error BurningNotAllowed();
    error PremintAlreadyCompleted();
    error PremintNotCompleted();
    error PremintInProgress();
    error InvalidInitialPremint(address recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 public constant PREMINT_ROLE = keccak256("PREMINT_ROLE");
    
    uint256 public constant MAX_BATCH_SIZE_LIMIT = 500; // Hard limit for gas optimization
    uint256 public maxBatchSize;
    
    bool public isPremintCompleted;
    uint256 public premintedSupply;

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event BatchPreminted(address indexed minter, address[] recipients, uint256[] amounts, uint256 totalAmount);
    event MaxBatchSizeSet(uint256 oldMaxSize, uint256 newMaxSize);
    event TransferRoleUpdated(address indexed account, bool granted);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);
    event PremintCompleted(uint256 totalSupply, uint256 timestamp);
    event PremintRoleUpdated(address indexed account, bool granted);
    event InitialPremint(address[] recipients, uint256[] amounts, uint256 totalAmount);

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with real estate-specific validation and optional initial premint
    /// @param configData Encoded AssetConfig for initialization
    /// @param initialRecipients Array of addresses for initial premint
    /// @param initialAmounts Array of amounts for initial premint
    function initialize(
        bytes calldata configData,
        address[] calldata initialRecipients,
        uint256[] calldata initialAmounts
    ) public override initializer {
        // Decode and validate asset type for real estate
        AssetConfig memory config = abi.decode(configData, (AssetConfig));
        _validateRealEstateAssetType(config.assetType);
        
        // Initialize parent contract
        super.initialize(configData);
        
        // Initialize ReentrancyGuard
        __ReentrancyGuard_init();
        
        // Set real estate specific configurations
        maxBatchSize = 100; // Initial max batch size
        isPremintCompleted = false;
        premintedSupply = 0;
        
        _setRoleAdmin(TRANSFER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PREMINT_ROLE, ADMIN_ROLE);
        _grantRole(TRANSFER_ROLE, assetOwner);
        _grantRole(PREMINT_ROLE, assetOwner);
        
        emit MaxBatchSizeSet(0, maxBatchSize);

        // Handle initial premint if provided
        if (initialRecipients.length > 0) {
            _validateBatchParams(initialRecipients, initialAmounts);
            _executeInitialPremint(initialRecipients, initialAmounts);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates batch parameters for premint operations
    /// @param to Array of recipient addresses
    /// @param amounts Array of amounts
    function _validateBatchParams(address[] calldata to, uint256[] calldata amounts) internal view {
        if (to.length == 0) revert EmptyBatch();
        if (to.length > maxBatchSize) revert BatchTooLarge(to.length, maxBatchSize);
        if (to.length != amounts.length) revert ArrayLengthMismatch(to.length, amounts.length);
    }

    /// @notice Executes initial premint during initialization
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts to premint
    function _executeInitialPremint(address[] calldata recipients, uint256[] calldata amounts) internal {
        uint256 totalAmount;
        
        // First pass: validate all recipients and calculate total
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidRecipient(recipients[i]);
            if (amounts[i] == 0) revert ZeroAmountDetected(recipients[i]);
            
            // Check compliance for each recipient
            if (!compliance.canTransfer(address(0), recipients[i], amounts[i])) {
                revert TransferNotCompliant(address(0), recipients[i], amounts[i]);
            }
            
            totalAmount += amounts[i];
        }

        // Check total supply constraint
        if (premintedSupply + totalAmount > maxSupply) {
            revert ExceedsMaxSupply(premintedSupply + totalAmount, maxSupply);
        }

        // Second pass: execute preminting
        for (uint256 i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }

        premintedSupply += totalAmount;
        emit InitialPremint(recipients, amounts, totalAmount);
        
        // If all supply is preminted, complete premint phase
        if (premintedSupply == maxSupply) {
            isPremintCompleted = true;
            emit PremintCompleted(totalSupply(), block.timestamp);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         PREMINT OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the maximum batch size for operations
    /// @param _maxBatchSize New maximum batch size
    function setMaxBatchSize(uint256 _maxBatchSize) external onlyRole(ADMIN_ROLE) {
        if (_maxBatchSize == 0) revert InvalidParameter("maxBatchSize");
        if (_maxBatchSize > MAX_BATCH_SIZE_LIMIT) revert BatchTooLarge(_maxBatchSize, MAX_BATCH_SIZE_LIMIT);
        
        uint256 oldMaxSize = maxBatchSize;
        maxBatchSize = _maxBatchSize;
        emit MaxBatchSizeSet(oldMaxSize, _maxBatchSize);
    }

    /// @notice Premints tokens to multiple addresses during tokenization phase
    /// @param to Array of recipient addresses
    /// @param amounts Array of amounts to premint
    function batchPremint(address[] calldata to, uint256[] calldata amounts)
        external
        onlyRole(PREMINT_ROLE)
        whenNotPaused
        onlyActiveProject
        nonReentrant
    {
        if (isPremintCompleted) revert PremintAlreadyCompleted();
        _validateBatchParams(to, amounts);

        uint256 totalAmount;
        // First pass: validate all recipients and calculate total
        for (uint256 i = 0; i < to.length; i++) {
            if (to[i] == address(0)) revert InvalidRecipient(to[i]);
            if (amounts[i] == 0) revert ZeroAmountDetected(to[i]);
            
            // Check compliance for each recipient
            if (!compliance.canTransfer(address(0), to[i], amounts[i])) {
                revert TransferNotCompliant(address(0), to[i], amounts[i]);
            }
            
            totalAmount += amounts[i];
        }

        // Check total supply constraint
        if (premintedSupply + totalAmount > maxSupply) {
            revert ExceedsMaxSupply(premintedSupply + totalAmount, maxSupply);
        }

        // Second pass: execute preminting
        for (uint256 i = 0; i < to.length; i++) {
            _mint(to[i], amounts[i]);
        }

        premintedSupply += totalAmount;
        
        // If all supply is preminted, complete premint phase
        if (premintedSupply == maxSupply) {
            isPremintCompleted = true;
            emit PremintCompleted(totalSupply(), block.timestamp);
        }
        
        emit BatchPreminted(msg.sender, to, amounts, totalAmount);
    }

    /// @notice Premints tokens to a single address during tokenization phase
    /// @param to Recipient address
    /// @param amount Amount to premint
    function premint(address to, uint256 amount)
        external
        onlyRole(PREMINT_ROLE)
        whenNotPaused
        onlyActiveProject
        nonReentrant
    {
        if (isPremintCompleted) revert PremintAlreadyCompleted();
        if (to == address(0)) revert InvalidRecipient(to);
        if (amount == 0) revert ZeroAmountDetected(to);
        
        // Check compliance
        if (!compliance.canTransfer(address(0), to, amount)) {
            revert TransferNotCompliant(address(0), to, amount);
        }
        
        // Check total supply constraint
        if (premintedSupply + amount > maxSupply) {
            revert ExceedsMaxSupply(premintedSupply + amount, maxSupply);
        }

        _mint(to, amount);
        premintedSupply += amount;
        
        // If all supply is preminted, complete premint phase
        if (premintedSupply == maxSupply) {
            isPremintCompleted = true;
            emit PremintCompleted(totalSupply(), block.timestamp);
        }
    }

    /// @notice Completes the premint phase, after which no more tokens can be minted
    function completePremint() external onlyRole(ADMIN_ROLE) {
        if (isPremintCompleted) revert PremintAlreadyCompleted();
        
        isPremintCompleted = true;
        emit PremintCompleted(totalSupply(), block.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a forced transfer (compliance override for legal/regulatory reasons)
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    /// @param reason Reason for forced transfer
    function forcedTransfer(
        address from,
        address to,
        uint256 amount,
        string calldata reason
    ) external onlyRole(TRANSFER_ROLE) whenNotPaused onlyActiveProject {
        if (!isPremintCompleted) revert PremintNotCompleted();
        if (from == address(0) || to == address(0)) revert InvalidAddress(from == address(0) ? from : to);
        if (amount == 0) revert InvalidParameter("amount");
        if (bytes(reason).length == 0) revert InvalidParameter("reason");
        
        uint256 balance = balanceOf(from);
        if (balance < amount) {
            revert InsufficientBalance(from, balance, amount);
        }

        // Execute transfer bypassing normal compliance checks
        _forceTransfer(from, to, amount);
        
        emit ForcedTransfer(from, to, amount, reason);
    }

    /// @notice Grants or revokes the TRANSFER_ROLE
    /// @param account Address to update
    /// @param grant True to grant, false to revoke
    function setTransferRole(address account, bool grant) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account);
        
        if (grant) {
            _grantRole(TRANSFER_ROLE, account);
        } else {
            _revokeRole(TRANSFER_ROLE, account);
        }
        emit TransferRoleUpdated(account, grant);
    }

    /// @notice Grants or revokes the PREMINT_ROLE
    /// @param account Address to update
    /// @param grant True to grant, false to revoke
    function setPremintRole(address account, bool grant) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account);
        
        if (grant) {
            _grantRole(PREMINT_ROLE, account);
        } else {
            _revokeRole(PREMINT_ROLE, account);
        }
        emit PremintRoleUpdated(account, grant);
    }

    /*//////////////////////////////////////////////////////////////
                         OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Override mint to prevent minting after initialization
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) public pure override {
        revert MintingNotAllowed();
    }

    /// @notice Burning is not allowed - tokens represent real-world assets
    function burn(address, uint256) external pure {
        revert BurningNotAllowed();
    }

    /// @notice Burning from is not allowed - tokens represent real-world assets
    function burnFrom(address, uint256) external pure {
        revert BurningNotAllowed();
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if an address has specific roles
    /// @param account Address to check
    /// @return hasTransferRole True if account has TRANSFER_ROLE
    /// @return hasPremintRole True if account has PREMINT_ROLE
    /// @return hasAdminRole True if account has ADMIN_ROLE
    function checkRoles(address account) 
        external 
        view 
        returns (
            bool hasTransferRole,
            bool hasPremintRole,
            bool hasAdminRole
        ) 
    {
        if (account == address(0)) revert InvalidAddress(account);
        
        hasTransferRole = hasRole(TRANSFER_ROLE, account);
        hasPremintRole = hasRole(PREMINT_ROLE, account);
        hasAdminRole = hasRole(ADMIN_ROLE, account);
    }

    /// @notice Returns real estate specific asset configuration with premint info
    /// @return config Asset configuration
    /// @return currentMaxBatchSize Current maximum batch size
    /// @return supportedAssetTypes Supported real estate asset types
    /// @return premintInfo [isPremintCompleted, premintedSupply, remainingSupply]
    function getRealEstateConfig() external view returns (
        AssetConfig memory config,
        uint256 currentMaxBatchSize,
        bytes32[] memory supportedAssetTypes,
        uint256[3] memory premintInfo
    ) {
        config = getAssetConfig();
        currentMaxBatchSize = maxBatchSize;
        
        // Return supported real estate asset types
        supportedAssetTypes = new bytes32[](6);
        supportedAssetTypes[0] = keccak256("Commercial");
        supportedAssetTypes[1] = keccak256("Residential");
        supportedAssetTypes[2] = keccak256("Holiday");
        supportedAssetTypes[3] = keccak256("Land");
        supportedAssetTypes[4] = keccak256("Industrial");
        supportedAssetTypes[5] = keccak256("Mixed-Use");
        
        // Premint information
        premintInfo[0] = isPremintCompleted ? 1 : 0;
        premintInfo[1] = premintedSupply;
        premintInfo[2] = maxSupply - premintedSupply;
    }

    /// @notice Validates if a premint batch operation is possible
    /// @param addresses Array of addresses
    /// @param amounts Array of amounts
    /// @return isValid True if batch is valid
    /// @return totalAmount Total amount in batch
    function validatePremintBatch(
        address[] calldata addresses,
        uint256[] calldata amounts
    ) external view returns (bool isValid, uint256 totalAmount) {
        if (isPremintCompleted) {
            return (false, 0);
        }

        if (addresses.length != amounts.length || addresses.length == 0 || addresses.length > maxBatchSize) {
            return (false, 0);
        }

        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == address(0) || amounts[i] == 0) {
                return (false, 0);
            }
            
            if (!compliance.canTransfer(address(0), addresses[i], amounts[i])) {
                return (false, 0);
            }
            
            totalAmount += amounts[i];
        }

        if (premintedSupply + totalAmount > maxSupply) {
            return (false, 0);
        }

        return (true, totalAmount);
    }

    /// @notice Validates real estate asset type
    /// @param assetType Asset type to validate
    function _validateRealEstateAssetType(bytes32 assetType) internal pure {
        bytes32 commercial = keccak256("Commercial");
        bytes32 residential = keccak256("Residential");
        bytes32 holiday = keccak256("Holiday");
        bytes32 land = keccak256("Land");
        bytes32 industrial = keccak256("Industrial");
        bytes32 mixedUse = keccak256("Mixed-Use");

        if (
            assetType != commercial &&
            assetType != residential &&
            assetType != holiday &&
            assetType != land &&
            assetType != industrial &&
            assetType != mixedUse
        ) {
            revert InvalidAssetType(assetType);
        }
    }
}