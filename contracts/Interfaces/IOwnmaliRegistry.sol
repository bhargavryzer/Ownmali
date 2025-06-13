// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title IOwnmaliRegistry
/// @notice Interface for the OwnmaliRegistry contract, managing SPV and asset metadata with SPV contract cloning in the Ownmali ecosystem.
interface IOwnmaliRegistry is
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
    struct SPV {
        string name;
        string countryCode;
        address spvAddress;
    }

    struct Asset {
        bytes32 spvId;
        string addressLocation;
        bytes32 assetType;
        uint256 totalSupply;
        bytes32 metadataHash;
    }

    struct InitParams {
        uint256 maxSPVs;
        uint256 maxAssetsPerSPV;
        address spvImplementation;
    }

    struct PendingUpdate {
        address newAddress;
        bytes32 role;
        bool grant;
        uint48 unlockTime;
    }

    interface OwnmaliSPV {
        function initialize(bytes32 spvId, address registry) external;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event SPVRegistered(bytes32 indexed spvId, address indexed spvAddress, string name);
    event AssetRegistered(bytes32 indexed assetId, bytes32 indexed spvId, string addressLocation);
    event SPVRemoved(bytes32 indexed spvId);
    event AssetRemoved(bytes32 indexed assetId, bytes32 indexed spvId);
    event SPVImplementationSet(address indexed implementation);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(InitParams memory params) external;

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setSPVImplementation(address _spvImplementation) external;
    function setRegistryManagerRole(address account, bool grant) external;
    function revokeAdminRole(address account) external;

    /*//////////////////////////////////////////////////////////////
                           SPV AND ASSET MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    function registerSPV(bytes32 spvId, string memory name, string memory countryCode) external;
    function removeSPV(bytes32 spvId) external;
    function registerAsset(
        bytes32 assetId,
        bytes32 spvId,
        string memory addressLocation,
        bytes32 assetType,
        uint256 totalSupply,
        bytes32 metadataHash
    ) external;
    function removeAsset(bytes32 assetId) external;

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getSPV(bytes32 spvId) external view returns (SPV memory);
    function getAsset(bytes32 assetId) external view returns (Asset memory);
    function getAllSPVs(uint256 offset, uint256 limit) external view returns (bytes32[] memory spvIds);
    function getAllAssetIds(bytes32 spvId, uint256 offset, uint256 limit) external view returns (bytes32[] memory assetIds);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function TIMELOCK_DURATION() external view returns (uint48);
    function REGISTRY_MANAGER_ROLE() external view returns (bytes32);
    function maxSPVs() external view returns (uint256);
    function maxAssetsPerSPV() external view returns (uint256);
    function spvCount() external view returns (uint256);
    function assetCount(bytes32 spvId) external view returns (uint256);
    function spvs(bytes32 spvId) external view returns (SPV memory);
    function assets(bytes32 assetId) external view returns (Asset memory);
    function spvImplementation() external view returns (address);
    function pendingUpdates(bytes32 actionId) external view returns (PendingUpdate memory);
}
