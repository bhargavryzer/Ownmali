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
import "./Ownmali_Project.sol";
import "./Ownmali_Escrow.sol";
import "./Ownmali_OrderManager.sol";
import "./Ownmali_DAO.sol";

/// @title OwnmaliFactory
/// @notice Factory contract for deploying tokenized asset projects in the Ownmali ecosystem, with one project per company
/// @dev Uses Clones for gas-efficient deployment of project, escrow, order manager, and DAO contracts
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
    error MaxProjectsExceeded(uint256 current, uint256 max);
    error InvalidAssetType(bytes32 assetType);
    error CompanyHasProject(bytes32 companyId, bytes32 existingAssetId);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct ProjectContracts {
        address project;
        address escrow;
        address orderManager;
        address dao;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FACTORY_MANAGER_ROLE = keccak256("FACTORY_MANAGER_ROLE");

    uint256 public maxProjects;
    address public projectTemplate;
    address public escrowTemplate;
    address public orderManagerTemplate;
    address public daoTemplate;
    mapping(bytes32 => ProjectContracts) public projects;
    mapping(bytes32 => bytes32) public companyToProject; // Maps companyId to its single assetId
    uint256 public projectCount;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event ProjectCreated(
        bytes32 indexed companyId,
        bytes32 indexed assetId,
        address indexed project,
        address escrow,
        address orderManager,
        address dao
    );
    event TemplateSet(string templateType, address indexed template);
    event MaxProjectsSet(uint256 newMax);

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

        maxProjects = 1000;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(FACTORY_MANAGER_ROLE, _admin);
        _setRoleAdmin(FACTORY_MANAGER_ROLE, ADMIN_ROLE);

        emit MaxProjectsSet(maxProjects);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the template for a contract type
    /// @param templateType Type of template ("project", "escrow", "orderManager", "dao")
    /// @param template Address of the template contract
    function setTemplate(string memory templateType, address template) external onlyRole(ADMIN_ROLE) {
        if (template == address(0) || template.code.length == 0) revert InvalidAddress(template, templateType);
        if (keccak256(abi.encodePacked(templateType)) == keccak256(abi.encodePacked("project"))) {
            projectTemplate = template;
        } else if (keccak256(abi.encodePacked(templateType)) == keccak256(abi.encodePacked("escrow"))) {
            escrowTemplate = template;
        } else if (keccak256(abi.encodePacked(templateType)) == keccak256(abi.encodePacked("orderManager"))) {
            orderManagerTemplate = template;
        } else if (keccak256(abi.encodePacked(templateType)) == keccak256(abi.encodePacked("dao"))) {
            daoTemplate = template;
        } else {
            revert InvalidParameter("templateType", "invalid type");
        }
        emit TemplateSet(templateType, template);
    }

    /// @notice Sets the maximum number of projects
    /// @param _maxProjects New maximum number of projects
    function setMaxProjects(uint256 _maxProjects) external onlyRole(ADMIN_ROLE) {
        if (_maxProjects == 0) revert InvalidParameter("maxProjects", "must be non-zero");
        maxProjects = _maxProjects;
        emit MaxProjectsSet(_maxProjects);
    }

    /// @notice Creates a new project with associated contracts, ensuring one project per company
    /// @param params Project initialization parameters
    /// @return projectAddress Address of the deployed project contract
    /// @return escrowAddress Address of the deployed escrow contract
    /// @return orderManagerAddress Address of the deployed order manager contract
    /// @return daoAddress Address of the deployed DAO contract
    function createProject(OwnmaliProject.ProjectInitParams memory _params)
        external
        onlyRole(FACTORY_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
        returns (address projectAddress, address escrowAddress, address orderManagerAddress, address daoAddress)
    {
        if (projectCount >= maxProjects) revert MaxProjectsExceeded(projectCount, maxProjects);
        if (projectTemplate == address(0)) revert TemplateNotSet("project");
        if (escrowTemplate == address(0)) revert TemplateNotSet("escrow");
        if (orderManagerTemplate == address(0)) revert TemplateNotSet("orderManager");
        if (daoTemplate == address(0)) revert TemplateNotSet("dao");
        if (companyToProject[_params.companyId] != bytes32(0)) {
            revert CompanyHasProject(_params.companyId, companyToProject[_params.companyId]);
        }
        _validateProjectParams(_params);

        // Deploy project contract
        projectAddress = Clones.clone(projectTemplate);
        try OwnmaliProject(projectAddress).initialize(abi.encode(_params)) {
            projectCount++;
        } catch {
            revert InitializationFailed("project");
        }

        // Deploy escrow contract
        escrowAddress = Clones.clone(escrowTemplate);
        try IOwnmaliEscrow(escrowAddress).initialize(_params.projectOwner, projectAddress, _params.companyId, _params.assetId) {
        } catch {
            revert InitializationFailed("escrow");
        }

        // Deploy order manager contract
        orderManagerAddress = Clones.clone(orderManagerTemplate);
        try IOwnmaliOrderManager(orderManagerAddress).initialize(escrowAddress, projectAddress, _params.projectOwner) {
        } catch {
            revert InitializationFailed("orderManager");
        }

        // Deploy DAO contract
        daoAddress = Clones.clone(daoTemplate);
        try IOwnmaliDAO(daoAddress).initialize(_params.projectOwner, projectAddress, _params.companyId, _params.assetId) {
        } catch {
            revert InitializationFailed("dao");
        }

        // Set project contracts and premint tokens
        try OwnmaliProject(projectAddress).setProjectContractsAndPreMint(
            escrowAddress,
            orderManagerAddress,
            daoAddress,
            _params.premintAmount
        ) {
        } catch {
            revert InitializationFailed("project contracts");
        }

        projects[_params.assetId] = ProjectContracts({
            project: projectAddress,
            escrow: escrowAddress,
            orderManager: orderManagerAddress,
            dao: daoAddress
        });
        companyToProject[_params.companyId] = _params.assetId;

        emit ProjectCreated(_params.companyId, _params.assetId, projectAddress, escrowAddress, orderManagerAddress, daoAddress);

        return (projectAddress, escrowAddress, orderManagerAddress, daoAddress);
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

    /// @notice Returns project contracts for an asset ID
    /// @param assetId Asset identifier
    /// @return ProjectContracts struct
    function getProjectContracts(bytes32 assetId) external view returns (ProjectContracts memory) {
        if (projects[assetId].project == address(0)) revert InvalidParameter("assetId", "project not found");
        return projects[assetId];
    }

    /// @notice Returns the asset ID for a company
    /// @param companyId Company identifier
    /// @return Asset ID associated with the company
    function getCompanyProject(bytes32 companyId) external view returns (bytes32) {
        if (companyToProject[companyId] == bytes32(0)) revert InvalidParameter("companyId", "no project found");
        return companyToProject[companyId];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates project initialization parameters
    /// @param params Project initialization parameters
    function _validateProjectParams(OwnmaliProject.ProjectInitParams memory params) internal view {
        params.companyId.validateId("companyId");
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
        ) revert InvalidAssetType(params.assetType);
    }

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }
}