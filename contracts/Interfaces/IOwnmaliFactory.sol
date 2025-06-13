// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Ownmali_Asset.sol";

/// @title IOwnmaliFactory
/// @notice Interface for the OwnmaliFactory contract, deploying tokenized asset projects for SPVs in the Ownmali ecosystem.
interface IOwnmaliFactory is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidParameter(string parameter, string reason);
    error TemplateNotSet(string templateType);
    error InitializationFailed(string contractType);
    error MaxAssetsExceeded(uint256 current, uint256 max);
    error InvalidAssetType(bytes32 assetType);
    error SPVHasAsset(bytes32 spvId, bytes32 existingAssetId);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct AssetContracts {
        address asset;
        address assetManager;
        address financialLedger;
        address orderManager;
        address spvDao;
    }

    /*//////////////////////////////////////////////////////////////
                           EVENTS
    //////////////////////////////////////////////////////////////*/
    event AssetCreated(
        bytes32 indexed spvId,
        bytes32 indexed assetId,
        address indexed asset,
        address assetManager,
        address financialLedger,
        address orderManager,
        address spvDao
    );
    event TemplateSet(string templateType, address indexed template);
    event MaxAssetsSet(uint256 newMax);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(address _admin) external;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setTemplate(string memory templateType, address template) external;
    function setMaxAssets(uint256 _maxAssets) external;
    function createAsset(OwnmaliAsset.AssetInitParams memory params)
        external
        returns (
            address assetAddress,
            address assetManagerAddress,
            address financialLedgerAddress,
            address orderManagerAddress,
            address spvDaoAddress
        );
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getAssetContracts(bytes32 assetId) external view returns (AssetContracts memory);
    function getSPVAsset(bytes32 spvId) external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function ADMIN_ROLE() external view returns (bytes32);
    function FACTORY_MANAGER_ROLE() external view returns (bytes32);
    function maxAssets() external view returns (uint256);
    function assetTemplate() external view returns (address);
    function assetManagerTemplate() external view returns (address);
    function financialLedgerTemplate() external view returns (address);
    function orderManagerTemplate() external view returns (address);
    function spvDaoTemplate() external view returns (address);
    function assets(bytes32 assetId) external view returns (AssetContracts memory);
    function spvToAsset(bytes32 spvId) external view returns (bytes32);
    function assetCount() external view returns (uint256);
}