// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import "./Ownmali_Interfaces.sol";
import "./Ownmali_Validation.sol";
import "./Ownmali_Asset.sol";
import "./Ownmali_AssetManager.sol";
import "./Ownmali_FinancialLedger.sol";
import "./Ownmali_OrderManager.sol";
import "./Ownmali_SPVDAO.sol";

/// @title OwnmaliFactory
/// @notice Factory contract for deploying tokenized asset projects for SPVs in the Ownmali ecosystem, with one asset per SPV
/// @dev Uses Clones for gas-efficient deployment of asset, asset manager, financial ledger, order manager, and SPV DAO contracts
contract OwnmaliFactory is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using OwnmaliValidation for *;

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
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FACTORY_MANAGER_ROLE = keccak256("FACTORY_MANAGER_ROLE");

    uint256 public maxAssets;
    address public assetTemplate;
    address public assetManagerTemplate;
    address public financialLedgerTemplate;
    address public orderManagerTemplate;
    address public spvDaoTemplate;
    mapping(bytes32 => AssetContracts) public assets;
    mapping(bytes32 => bytes32) public spvToAsset; // Maps spvId to its single assetId
    uint256 public assetCount;

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

    /// @notice Initializes the factory contract
    /// @param _admin Admin address for role assignment
    function initialize(address _admin) public initializer {
        if (_admin == address(0)) revert InvalidAddress(_admin, "admin");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        maxAssets = 1000;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(FACTORY_MANAGER_ROLE, _admin);
        _setRoleAdmin(FACTORY_MANAGER_ROLE, ADMIN_ROLE);

        emit MaxAssetsSet(maxAssets);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the template for a contract type
    /// @param templateType Type of template ("asset", "assetManager", "financialLedger", "orderManager", "spvDao")
    /// @param template Address of the template contract
    function setTemplate(string memory templateType, address template) external onlyRole(ADMIN_ROLE) {
        if (template == address(0) || template.code.length == 0) revert InvalidAddress(template, templateType);
        bytes32 templateTypeHash = keccak256(abi.encodePacked(templateType));
        if (templateTypeHash == keccak256(abi.encodePacked("asset"))) {
            assetTemplate = template;
        } else if (templateTypeHash == keccak256(abi.encodePacked("assetManager"))) {
            assetManagerTemplate = template;
        } else if (templateTypeHash == keccak256(abi.encodePacked("financialLedger"))) {
            financialLedgerTemplate = template;
        } else if (templateTypeHash == keccak256(abi.encodePacked("orderManager"))) {
            orderManagerTemplate = template;
        } else if (templateTypeHash == keccak256(abi.encodePacked("spvDao"))) {
            spvDaoTemplate = template;
        } else {
            revert InvalidParameter("templateType", "invalid type");
        }
        emit TemplateSet(templateType, template);
    }

    /// @notice Sets the maximum number of assets
    /// @param _maxAssets New maximum number of assets
    function setMaxAssets(uint256 _maxAssets) external onlyRole(ADMIN_ROLE) {
        if (_maxAssets == 0) revert InvalidParameter("maxAssets", "must be non-zero");
        maxAssets = _maxAssets;
        emit MaxAssetsSet(_maxAssets);
    }

    /// @notice Creates a new asset with associated contracts for an SPV, ensuring one asset per SPV
    /// @param params Asset initialization parameters
    /// @return assetAddress Address of the deployed asset contract
    /// @return assetManagerAddress Address of the deployed asset manager contract
    /// @return financialLedgerAddress Address of the deployed financial ledger contract
    /// @return orderManagerAddress Address of the deployed order manager contract
    /// @return spvDaoAddress Address of the deployed SPV DAO contract
    function createAsset(OwnmaliAsset.AssetInitParams memory params)
        external
        onlyRole(FACTORY_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
        returns (
            address assetAddress,
            address assetManagerAddress,
            address financialLedgerAddress,
            address orderManagerAddress,
            address spvDaoAddress
        )
    {
        if (assetCount >= maxAssets) revert MaxAssetsExceeded(assetCount, maxAssets);
        if (assetTemplate == address(0)) revert TemplateNotSet("asset");
        if (assetManagerTemplate == address(0)) revert TemplateNotSet("assetManager");
        if (financialLedgerTemplate == address(0)) revert TemplateNotSet("financialLedger");
        if (orderManagerTemplate == address(0)) revert TemplateNotSet("orderManager");
        if (spvDaoTemplate == address(0)) revert TemplateNotSet("spvDao");
        if (spvToAsset[params.spvId] != bytes32(0)) {
            revert SPVHasAsset(params.spvId, spvToAsset[params.spvId]);
        }
        _validateAssetParams(params);

        // Deploy asset contract
        assetAddress = Clones.clone(assetTemplate);
        try OwnmaliAsset(assetAddress).initialize(params) {
            assetCount++;
        } catch {
            revert InitializationFailed("asset");
        }

        // Deploy asset manager contract
        assetManagerAddress = Clones.clone(assetManagerTemplate);
        try OwnmaliAssetManager(assetManagerAddress).initialize(
            params.projectOwner,
            assetAddress,
            params.spvId,
            params.assetId
        ) {
        } catch {
            revert InitializationFailed("assetManager");
        }

        // Deploy financial ledger contract
        financialLedgerAddress = Clones.clone(financialLedgerTemplate);
        try OwnmaliFinancialLedger(financialLedgerAddress).initialize(
            params.projectOwner,
            assetAddress,
            params.spvId,
            params.assetId
        ) {
        } catch {
            revert InitializationFailed("financialLedger");
        }

        // Deploy order manager contract
        orderManagerAddress = Clones.clone(orderManagerTemplate);
        try IOwnmaliOrderManager(orderManagerAddress).initialize(
            financialLedgerAddress,
            assetAddress,
            params.projectOwner
        ) {
        } catch {
            revert InitializationFailed("orderManager");
        }

        // Deploy SPV DAO contract
        spvDaoAddress = Clones.clone(spvDaoTemplate);
        try IOwnmaliSPVDAO(spvDaoAddress).initialize(
            params.projectOwner,
            assetAddress,
            params.spvId,
            params.assetId
        ) {
        } catch {
            revert InitializationFailed("spvDao");
        }

        // Set asset contracts and premint tokens
        try OwnmaliAsset(assetAddress).setAssetContractsAndPreMint(
            assetManagerAddress,
            financialLedgerAddress,
            orderManagerAddress,
            spvDaoAddress,
            params.premintAmount
        ) {
        } catch {
            revert InitializationFailed("asset contracts");
        }

        assets[params.assetId] = AssetContracts({
            asset: assetAddress,
            assetManager: assetManagerAddress,
            financialLedger: financialLedgerAddress,
            orderManager: orderManagerAddress,
            spvDao: spvDaoAddress
        });
        spvToAsset[params.spvId] = params.assetId;

        emit AssetCreated(
            params.spvId,
            params.assetId,
            assetAddress,
            assetManagerAddress,
            financialLedgerAddress,
            orderManagerAddress,
            spvDaoAddress
        );

        return (
            assetAddress,
            assetManagerAddress,
            financialLedgerAddress,
            orderManagerAddress,
            spvDaoAddress
        );
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
                           EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns asset contracts for an asset ID
    /// @param assetId Asset identifier
    /// @return AssetContracts struct
    function getAssetContracts(bytes32 assetId) external view returns (AssetContracts memory) {
        if (assets[assetId].asset == address(0)) revert InvalidParameter("assetId", "asset not found");
        return assets[assetId];
    }

    /// @notice Returns the asset ID for an SPV
    /// @param spvId SPV identifier
    /// @return Asset ID associated with the SPV
    function getSPVAsset(bytes32 spvId) external view returns (bytes32) {
        if (spvToAsset[spvId] == bytes32(0)) revert InvalidParameter("spvId", "no asset found");
        return spvToAsset[spvId];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates asset initialization parameters
    /// @param params Asset initialization parameters
    function _validateAssetParams(OwnmaliAsset.AssetInitParams memory params) internal view {
        params.spvId.validateId("spvId");
        params.assetId.validateId("assetId");
        params.name.validateString("name", 1, 100);
        params.symbol.validateString("symbol", 1, 10);
        params.metadataCID.validateCID("metadataCID");
        params.legalMetadataCID.validateCID("legalMetadataCID");
        if (params.projectOwner == address(0)) revert InvalidAddress(params.projectOwner, "projectOwner");
        if (params.factory == address(0)) revert InvalidAddress(params.factory, "factory");
        if (params.identityRegistry == address(0)) revert InvalidAddress(params.identityRegistry, "identityRegistry");
        if (params.compliance == address(0)) revert InvalidAddress(params.compliance, "compliance");
        if (params.maxSupply == 0) revert InvalidParameter("maxSupply", "must be non-zero");
        if (params.tokenPrice == 0) revert InvalidParameter("tokenPrice", "must be non-zero");
        if (params.cancelDelay == 0) revert InvalidParameter("cancelDelay", "must be non-zero");
        if (params.dividendPct > 50) revert InvalidParameter("dividendPct", "must not exceed 50");
        if (params.premintAmount > params.maxSupply) revert InvalidParameter("premintAmount", "exceeds maxSupply");
        if (params.minInvestment == 0) revert InvalidParameter("minInvestment", "must be non-zero");
        if (params.maxInvestment < params.minInvestment) {
            revert InvalidParameter("maxInvestment", "must be at least minInvestment");
        }
        if (params.chainId == 0) revert InvalidParameter("chainId", "must be non-zero");
        if (params.eoiPct > 50) revert InvalidParameter("eoiPct", "must not exceed 50");
        if (
            params.assetType != bytes32("Commercial") &&
            params.assetType != bytes32("Residential") &&
            params.assetType != bytes32("Holiday") &&
            params.assetType != bytes32("Land")
        ) {
            revert InvalidAssetType(params.assetType);
        }
    }

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }
}