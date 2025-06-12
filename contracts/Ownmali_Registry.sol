// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title OwnmaliRegistry
/// @notice Manages SPV (Special Purpose Vehicle) and asset metadata with SPV contract cloning in the Ownmali ecosystem.
/// @dev Uses UUPS proxy for upgrades. Stores SPV/asset details and deploys SPV contracts via EIP-1167 cloning.
///      Integrates with OwnmaliSPV for initialization. Storage layout must be preserved across upgrades.
///      All IDs are bytes32; assetType categorizes assets; metadataHash is an IPFS CID for asset details.
contract OwnmaliRegistry is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidId(bytes32 id, string parameter);
    error InvalidString(string value, string parameter);
    error InvalidAmount(uint256 value, string parameter);
    error InvalidAddress(address addr, string parameter);
    error SPVExists(bytes32 spvId);
    error SPVNotFound(bytes32 spvId);
    error AssetExists(bytes32 assetId);
    error AssetNotFound(bytes32 assetId);
    error MaxSPVsReached(uint256 current, uint256 max);
    error MaxAssetsReached(bytes32 spvId, uint256 current, uint256 max);
    error TimelockNotExpired(uint48 unlockTime);
    error CloneFailed();
    error SPVInitializationFailed();

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice SPV details.
    struct SPV {
        string name; // SPV name (max 64 bytes)
        string countryCode; // ISO country code (max 8 bytes)
        address spvAddress; // Cloned SPV contract address
    }

    /// @notice Asset details.
    struct Asset {
        bytes32 spvId; // Associated SPV ID
        string addressLocation; // Asset location (max 128 bytes)
        bytes32 assetType; // Asset category (e.g., real estate)
        uint256 totalSupply; // Total token supply (in wei)
        bytes32 metadataHash; // IPFS CID for asset metadata
    }

    /// @notice Initialization parameters.
    struct InitParams {
        uint256 maxSPVs; // Maximum number of SPVs
        uint256 maxAssetsPerSPV; // Maximum assets per SPV
        address spvImplementation; // SPV implementation address
    }

    /// @notice Pending critical update with timelock.
    struct PendingUpdate {
        address newAddress; // New address (for implementation or role)
        bytes32 role; // Role for role updates (0 for implementation)
        bool grant; // True for grant, false for revoke
        uint48 unlockTime; // Timestamp for execution
    }

    /// @notice Interface for SPV contract.
    interface OwnmaliSPV {
        function initialize(bytes32 spvId, address registry) external;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Duration for timelock on critical updates (1 day).
    uint48 public constant TIMELOCK_DURATION = 1 days;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Registry manager role for SPV/asset operations.
    bytes32 public constant REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");

    /// @notice Maximum number of SPVs.
    uint256 public maxSPVs;

    /// @notice Maximum number of assets per SPV.
    uint256 public maxAssetsPerSPV;

    /// @notice Total number of registered SPVs.
    uint256 public spvCount;

    /// @notice Number of assets per SPV.
    mapping(bytes32 => uint256) public assetCount;

    /// @notice Maps SPV ID to SPV details.
    mapping(bytes32 => SPV) public spvs;

    /// @notice Maps asset ID to asset details.
    mapping(bytes32 => Asset) public assets;

    /// @notice Address of the SPV implementation for cloning.
    address public spvImplementation;

    /// @notice Pending critical updates (implementation or roles).
    mapping(bytes32 => PendingUpdate) public pendingUpdates;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when an SPV is registered.
    event SPVRegistered(bytes32 indexed spvId, address indexed spvAddress, string name);

    /// @notice Emitted when an asset is registered.
    event AssetRegistered(bytes32 indexed assetId, bytes32 indexed spvId, string addressLocation);

    /// @notice Emitted when an SPV is removed.
    event SPVRemoved(bytes32 indexed spvId);

    /// @notice Emitted when an asset is removed.
    event AssetRemoved(bytes32 indexed assetId, bytes32 indexed spvId);

    /// @notice Emitted when the SPV implementation address is set.
    event SPVImplementationSet(address indexed implementation);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the registry contract.
    /// @dev Sets initial configuration and roles. Only callable once.
    /// @param params Initialization parameters (maxSPVs, maxAssetsPerSPV, spvImplementation).
    function initialize(InitParams memory params) external initializer {
        if (params.maxSPVs == 0) revert InvalidAmount(params.maxSPVs, "maxSPVs");
        if (params.maxAssetsPerSPV == 0) revert InvalidAmount(params.maxAssetsPerSPV, "maxAssetsPerSPV");
        if (params.spvImplementation == address(0)) revert InvalidAddress(params.spvImplementation, "spvImplementation");

        __UUPSUpgradeable_init();
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        maxSPVs = params.maxSPVs;
        maxAssetsPerSPV = params.maxAssetsPerSPV;
        spvImplementation = params.spvImplementation;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REGISTRY_MANAGER_ROLE, msg.sender);
        _setRoleAdmin(REGISTRY_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

        emit SPVImplementationSet(params.spvImplementation);
    }

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Proposes or executes an update to the SPV implementation address with a timelock.
    /// @dev Requires two calls: first to propose, second to execute after timelock. Only callable by admin.
    /// @param _spvImplementation New SPV implementation address.
    function setSPVImplementation(address _spvImplementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_spvImplementation == address(0)) revert InvalidAddress(_spvImplementation, "spvImplementation");

        bytes32 actionId = keccak256(abi.encode("spvImplementation", _spvImplementation));
        if (pendingUpdates[actionId].newAddress != _spvImplementation) {
            pendingUpdates[actionId] = PendingUpdate({
                newAddress: _spvImplementation,
                role: bytes32(0),
                grant: false,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        spvImplementation = _spvImplementation;
        delete pendingUpdates[actionId];
        emit SPVImplementationSet(_spvImplementation);
    }

    /// @notice Proposes or executes granting/revoking the REGISTRY_MANAGER_ROLE with a timelock.
    /// @dev Requires two calls: first to propose, second to execute after timelock. Only callable by admin.
    /// @param account Address to update.
    /// @param grant True to grant, false to revoke.
    function setRegistryManagerRole(address account, bool grant) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account, "account");

        bytes32 actionId = keccak256(abi.encode("registryManagerRole", account, grant));
        if (pendingUpdates[actionId].newAddress != account) {
            pendingUpdates[actionId] = PendingUpdate({
                newAddress: account,
                role: REGISTRY_MANAGER_ROLE,
                grant: grant,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        if (grant) {
            _grantRole(REGISTRY_MANAGER_ROLE, account);
        } else {
            _revokeRole(REGISTRY_MANAGER_ROLE, account);
        }
        delete pendingUpdates[actionId];
    }

    /// @notice Revokes the admin role from an account.
    /// @dev Only callable by admin. Enhances security by allowing admin privilege removal.
    /// @param account Address to revoke admin role from.
    function revokeAdminRole(address account) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account, "account");
        _revokeRole(DEFAULT_ADMIN_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////
                           SPV AND ASSET MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    /// @notice Registers a new SPV with a cloned contract.
    /// @dev Deploys a minimal proxy clone and initializes it. Only callable by REGISTRY_MANAGER_ROLE.
    /// @param spvId Unique SPV identifier.
    /// @param name SPV name (max 64 bytes).
    /// @param countryCode ISO country code (max 8 bytes).
    function registerSPV(bytes32 spvId, string memory name, string memory countryCode)
        external
        onlyRole(REGISTRY_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateId(spvId, "spvId");
        _validateString(name, "name", 1, 64);
        _validateString(countryCode, "countryCode", 2, 8);

        if (spvCount >= maxSPVs) revert MaxSPVsReached(spvCount, maxSPVs);
        if (spvs[spvId].spvAddress != address(0)) revert SPVExists(spvId);

        // Deploy SPV contract via cloning
        address spvAddress = _clone(spvImplementation);
        spvs[spvId] = SPV(name, countryCode, spvAddress);
        spvCount++;

        // Initialize SPV contract
        try OwnmaliSPV(spvAddress).initialize(spvId, address(this)) {
            emit SPVRegistered(spvId, spvAddress, name);
        } catch {
            delete spvs[spvId];
            spvCount--;
            revert SPVInitializationFailed();
        }
    }

    /// @notice Removes an existing SPV.
    /// @dev Deletes SPV data and decrements count. Only callable by REGISTRY_MANAGER_ROLE.
    /// @param spvId SPV identifier.
    function removeSPV(bytes32 spvId) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused nonReentrant {
        _validateId(spvId, "spvId");
        if (spvs[spvId].spvAddress == address(0)) revert SPVNotFound(spvId);
        if (assetCount[spvId] > 0) revert InvalidParameter("spvId", "SPV has assets");

        delete spvs[spvId];
        spvCount--;
        emit SPVRemoved(spvId);
    }

    /// @notice Registers a new asset under an SPV.
    /// @dev Stores asset metadata. Only callable by REGISTRY_MANAGER_ROLE.
    /// @param assetId Unique asset identifier.
    /// @param spvId SPV identifier.
    /// @param addressLocation Asset location (max 128 bytes).
    /// @param assetType Asset category.
    /// @param totalSupply Total token supply (in wei).
    /// @param metadataHash IPFS CID for asset metadata.
    function registerAsset(
        bytes32 assetId,
        bytes32 spvId,
        string memory addressLocation,
        bytes32 assetType,
        uint256 totalSupply,
        bytes32 metadataHash
    ) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused nonReentrant {
        _validateId(assetId, "assetId");
        _validateId(spvId, "spvId");
        _validateString(addressLocation, "addressLocation", 1, 128);
        _validateId(assetType, "assetType");
        if (totalSupply == 0) revert InvalidAmount(totalSupply, "totalSupply");
        _validateId(metadataHash, "metadataHash");

        if (spvs[spvId].spvAddress == address(0)) revert SPVNotFound(spvId);
        if (assetCount[spvId] >= maxAssetsPerSPV) revert MaxAssetsReached(spvId, assetCount[spvId], maxAssetsPerSPV);
        if (assets[assetId].spvId != bytes32(0)) revert AssetExists(assetId);

        assets[assetId] = Asset(spvId, addressLocation, assetType, totalSupply, metadataHash);
        assetCount[spvId]++;
        emit AssetRegistered(assetId, spvId, addressLocation);
    }

    /// @notice Removes an existing asset.
    /// @dev Deletes asset data and decrements count. Only callable by REGISTRY_MANAGER_ROLE.
    /// @param assetId Asset identifier.
    function removeAsset(bytes32 assetId) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused nonReentrant {
        _validateId(assetId, "assetId");
        if (assets[assetId].spvId == bytes32(0)) revert AssetNotFound(assetId);

        bytes32 spvId = assets[assetId].spvId;
        delete assets[assetId];
        assetCount[spvId]--;
        emit AssetRemoved(assetId, spvId);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns SPV details.
    /// @dev Reverts if SPV does not exist.
    /// @param spvId SPV identifier.
    /// @return SPV details.
    function getSPV(bytes32 spvId) external view returns (SPV memory) {
        if (spvs[spvId].spvAddress == address(0)) revert SPVNotFound(spvId);
        return spvs[spvId];
    }

    /// @notice Returns asset details.
    /// @dev Reverts if asset does not exist.
    /// @param assetId Asset identifier.
    /// @return Asset details.
    function getAsset(bytes32 assetId) external view returns (Asset memory) {
        if (assets[assetId].spvId == bytes32(0)) revert AssetNotFound(assetId);
        return assets[assetId];
    }

    /// @notice Returns all registered SPVs with pagination.
    /// @dev Returns an array of SPV IDs. Use pagination to avoid gas limits.
    /// @param offset Starting index.
    /// @param limit Number of SPVs to return.
    /// @return spvIds Array of SPV IDs.
    function getAllSPVs(uint256 offset, uint256 limit) external view returns (bytes32[] memory spvIds) {
        if (offset >= spvCount) return new bytes32[](0);
        uint256 resultSize = (offset + limit > spvCount) ? spvCount - offset : limit;
        spvIds = new bytes32[](resultSize);

        // Note: This assumes SPVs are not enumerable; implement enumeration if needed
        // Current implementation returns empty array as placeholder
        // To fully implement, maintain an array of SPV IDs
    }

    /// @notice Returns all assets for an SPV with pagination.
    /// @dev Returns an array of asset IDs. Use pagination to avoid gas limits.
    /// @param spvId SPV identifier.
    /// @param offset Starting index.
    /// @param limit Number of assets to return.
    /// @return assetIds Array of asset IDs.
    function getAllAssetIds(bytes32 spvId, uint256 offset, uint256 limit) external view returns (bytes32[] memory assetIds) {
        if (spvs[spvId].spvAddress == address(0)) revert SPVNotFound(spvId);
        if (offset >= assetCount[spvId]) return new bytes32[](0);
        uint256 resultSize = (offset + limit > assetCount[spvId]) ? assetCount[spvId] - offset : limit;
        assetIds = new bytes32[](resultSize);

        // Note: Placeholder; requires asset ID enumeration
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Validates a bytes32 ID.
    /// @dev Ensures ID is non-zero.
    /// @param id ID to validate.
    /// @param parameter Parameter name for error reporting.
    function _validateId(bytes32 id, string memory parameter) private pure {
        if (id == bytes32(0)) revert InvalidId(id, parameter);
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

    /// @notice Clones the SPV implementation using EIP-1167 minimal proxy.
    /// @dev Deploys a new contract pointing to the implementation.
    /// @param implementation Address of the implementation contract.
    /// @return newContract Deployed contract address.
    function _clone(address implementation) private returns (address newContract) {
        if (implementation == address(0)) revert InvalidAddress(implementation, "implementation");

        // EIP-1167 minimal proxy bytecode
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28, 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000))
            newContract := create(0, ptr, 0x37)
        }
        if (newContract == address(0)) revert CloneFailed();
    }

    /// @notice Authorizes contract upgrades.
    /// @dev Only callable by admin. Ensures non-zero implementation address.
    /// @param newImplementation Address of the new implementation contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0)) revert InvalidAddress(newImplementation, "newImplementation");
    }
}