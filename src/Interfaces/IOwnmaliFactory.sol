// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./Ownmali_Interfaces.sol";

/// @title Interface for OwnmaliFactory
/// @notice Defines the external and public functions, events, errors, and data structures for the OwnmaliFactory contract
interface IOwnmaliFactory {
    /// @notice Error thrown when an address is invalid
    error InvalidAddress(address addr, string parameter);
    /// @notice Error thrown when a parameter is invalid
    error InvalidParameter(string parameter, string reason);
    /// @notice Error thrown when a template is not set
    error TemplateNotSet(string templateType);
    /// @notice Error thrown when contract initialization fails
    error InitializationFailed(string contractType);
    /// @notice Error thrown when maximum assets are exceeded
    error MaxAssetsExceeded(uint256 current, uint256 max);
    /// @notice Error thrown when an invalid asset type is provided
    error InvalidAssetType(bytes32 assetType);
    /// @notice Error thrown when an SPV already has an asset
    error SPVHasAsset(bytes32 spvId, bytes32 existingAssetId);

    /// @notice Struct for asset-related contract addresses
    struct AssetContracts {
        address asset;
        address assetManager;
        address financialLedger;
        address orderManager;
        address spvDao;
    }

    /// @notice Emitted when a new asset and its contracts are created
    event AssetCreated(
        bytes32 indexed spvId,
        bytes32 indexed assetId,
        address indexed asset,
        address assetManager,
        address financialLedger,
        address orderManager,
        address spvDao
    );
    /// @notice Emitted when a template is set
    event TemplateSet(string templateType, address indexed template);
    /// @notice Emitted when max assets is set
    event MaxAssetsSet(uint256 newMax);

    /// @notice Initializes the factory contract
    /// @param _admin Admin address for role assignment
    function initialize(address _admin) external;

    /// @notice Sets the template for a contract type
    /// @param templateType Type of template ("asset", "assetManager", "financialLedger", "orderManager", "spvDao")
    /// @param template Address of the template contract
    function setTemplate(string memory templateType, address template) external;

    /// @notice Sets the maximum number of assets
    /// @param _maxAssets New maximum number of assets
    function setMaxAssets(uint256 _maxAssets) external;

    /// @notice Creates a new asset with associated contracts for an SPV
    /// @param params Asset initialization parameters
    /// @return assetAddress Address of the deployed asset contract
    /// @return assetManagerAddress Address of the deployed asset manager contract
    /// @return financialLedgerAddress Address of the deployed financial ledger contract
    /// @return orderManagerAddress Address of the deployed order manager contract
    /// @return spvDaoAddress Address of the deployed SPV DAO contract
    function createAsset(OwnmaliAsset.AssetInitParams memory params)
        external
        returns (
            address assetAddress,
            address assetManagerAddress,
            address financialLedgerAddress,
            address orderManagerAddress,
            address spvDaoAddress
        );

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Returns asset contracts for an asset ID
    /// @param assetId Asset identifier
    /// @return AssetContracts struct
    function getAssetContracts(bytes32 assetId) external view returns (AssetContracts memory);

    /// @notice Returns the asset ID for an SPV
    /// @param spvId SPV identifier
    /// @return Asset ID associated with the SPV
    function getSPVAsset(bytes32 spvId) external view returns (bytes32);
}