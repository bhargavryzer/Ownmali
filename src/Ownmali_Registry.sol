// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import "./Ownmali_Validation.sol";
import "./Ownmali_Company.sol";

/// @title OwnmaliRegistry
/// @notice Registry contract for managing company and project metadata in the Ownmali ecosystem
/// @dev Uses clones for efficient contract deployment, with role-based access control and upgradeability
contract OwnmaliRegistry is
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
    error InvalidCompanyId(bytes32 companyId);
    error InvalidProjectId(bytes32 projectId);
    error CompanyAlreadyExists(bytes32 companyId);
    error ProjectAlreadyExists(bytes32 projectId);
    error CompanyNotFound(bytes32 companyId);
    error ProjectNotFound(bytes32 projectId);
    error TemplateNotSet(string templateType);
    error InvalidAssetType(bytes32 assetType);

    /*//////////////////////////////////////////////////////////////
                         TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct Project {
        string name;
        bytes32 assetType;
        address token;
        bytes32 metadataCID;
    }

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");

    address public companyTemplate;
    uint256 public maxCompanies;
    uint256 public maxProjectsPerCompany;
    mapping(bytes32 => address) public companies;
    mapping(bytes32 => mapping(bytes32 => Project)) public projects;

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event CompanyRegistered(
        bytes32 indexed companyId,
        address indexed companyContract,
        string name,
        bool kycStatus,
        string countryCode,
        bytes32 metadataCID,
        address owner
    );
    event ProjectRegistered(
        bytes32 indexed companyId,
        bytes32 indexed projectId,
        string name,
        bytes32 assetType,
        address token,
        bytes32 metadataCID
    );
    event ProjectMetadataUpdated(
        bytes32 indexed companyId,
        bytes32 indexed projectId,
        bytes32 oldCID,
        bytes32 newCID
    );
    event CompanyTemplateSet(address indexed template);
    event MaxCompaniesSet(uint256 newMax);
    event MaxProjectsPerCompanySet(uint256 newMax);

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the registry contract
    /// @param _admin Admin address for role assignment
    function initialize(address _admin) external initializer {
        if (_admin == address(0)) revert InvalidAddress(_admin, "admin");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        maxCompanies = 1000; // Configurable max companies
        maxProjectsPerCompany = 100; // Configurable max projects per company

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(REGISTRY_MANAGER_ROLE, _admin);
        _setRoleAdmin(REGISTRY_MANAGER_ROLE, ADMIN_ROLE);

        emit MaxCompaniesSet(maxCompanies);
        emit MaxProjectsPerCompanySet(maxProjectsPerCompany);
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the company template for cloning
    /// @param _companyTemplate Address of the company template contract
    function setCompanyTemplate(address _companyTemplate) external onlyRole(ADMIN_ROLE) {
        if (_companyTemplate == address(0)) revert InvalidAddress(_companyTemplate, "companyTemplate");
        if (_companyTemplate.code.length == 0) revert InvalidAddress(_companyTemplate, "invalid contract");
        companyTemplate = _companyTemplate;
        emit CompanyTemplateSet(_companyTemplate);
    }

    /// @notice Sets the maximum number of companies
    /// @param _maxCompanies New maximum number of companies
    function setMaxCompanies(uint256 _maxCompanies) external onlyRole(ADMIN_ROLE) {
        if (_maxCompanies == 0) revert InvalidParameter("maxCompanies", "must be non-zero");
        maxCompanies = _maxCompanies;
        emit MaxCompaniesSet(_maxCompanies);
    }

    /// @notice Sets the maximum number of projects per company
    /// @param _maxProjects New maximum number of projects per company
    function setMaxProjectsPerCompany(uint256 _maxProjects) external onlyRole(ADMIN_ROLE) {
        if (_maxProjects == 0) revert InvalidParameter("maxProjectsPerCompany", "must be non-zero");
        maxProjectsPerCompany = _maxProjects;
        emit MaxProjectsPerCompanySet(_maxProjects);
    }

    /// @notice Registers a new company by cloning the template
    /// @param companyId Unique identifier for the company
    /// @param name Company name (1-100 bytes)
    /// @param kycStatus KYC verification status
    /// @param countryCode ISO 3166-1 alpha-2 country code
    /// @param metadataCID IPFS CID for company metadata
    /// @param owner Company owner address
    function registerCompany(
        bytes32 companyId,
        string calldata name,
        bool kycStatus,
        string calldata countryCode,
        bytes32 metadataCID,
        address owner
    ) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused nonReentrant {
        companyId.validateId("companyId");
        name.validateString("name", 1, 100);
        countryCode.validateString("countryCode", 2, 2);
        metadataCID.validateCID("metadataCID");
        if (owner == address(0)) revert InvalidAddress(owner, "owner");
        if (companies[companyId] != address(0)) revert CompanyAlreadyExists(companyId);
        if (companyTemplate == address(0)) revert TemplateNotSet("companyTemplate");

        // Deploy cloned company contract
        address companyAddress = Clones.clone(companyTemplate);
        try OwnmaliCompany(companyAddress).initialize(
            name,
            kycStatus,
            countryCode,
            metadataCID,
            owner,
            address(this)
        ) {
            companies[companyId] = companyAddress;
            emit CompanyRegistered(
                companyId,
                companyAddress,
                name,
                kycStatus,
                countryCode,
                metadataCID,
                owner
            );
        } catch {
            revert InvalidParameter("company initialization", "failed to initialize");
        }
    }

    /// @notice Registers a new project under a company
    /// @param companyId Unique identifier for the company
    /// @param projectId Unique identifier for the project
    /// @param name Project name (1-100 bytes)
    /// @param assetType Type of asset (Commercial, Residential, Land, Holiday)
    /// @param token Project token contract address
    /// @param metadataCID IPFS CID for project metadata
    function registerProject(
        bytes32 companyId,
        bytes32 projectId,
        string calldata name,
        bytes32 assetType,
        address token,
        bytes32 metadataCID
    ) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused nonReentrant {
        companyId.validateId("companyId");
        projectId.validateId("projectId");
        name.validateString("name", 1, 100);
        metadataCID.validateCID("metadataCID");
        if (token == address(0)) revert InvalidAddress(token, "token");
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        if (projects[companyId][projectId].token != address(0)) revert ProjectAlreadyExists(projectId);

        // Validate asset type
        if (
            assetType != bytes32("Commercial") &&
            assetType != bytes32("Residential") &&
            assetType != bytes32("Land") &&
            assetType != bytes32("Holiday")
        ) revert InvalidAssetType(assetType);

        projects[companyId][projectId] = Project({
            name: name,
            assetType: assetType,
            token: token,
            metadataCID: metadataCID
        });

        emit ProjectRegistered(companyId, projectId, name, assetType, token, metadataCID);
    }

    /// @notice Updates project metadata CID
    /// @param companyId Unique identifier for the company
    /// @param projectId Unique identifier for the project
    /// @param newMetadataCID New IPFS CID for project metadata
    function updateProjectMetadata(
        bytes32 companyId,
        bytes32 projectId,
        bytes32 newMetadataCID
    ) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused nonReentrant {
        companyId.validateId("companyId");
        projectId.validateId("projectId");
        newMetadataCID.validateCID("metadataCID");
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        if (projects[companyId][projectId].token == address(0)) revert ProjectNotFound(projectId);

        bytes32 oldCID = projects[companyId][projectId].metadataCID;
        projects[companyId][projectId].metadataCID = newMetadataCID;

        emit ProjectMetadataUpdated(companyId, projectId, oldCID, newMetadataCID);
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets company contract address by ID
    /// @param companyId Unique identifier for the company
    /// @return Company contract address
    function getCompanyAddress(bytes32 companyId) external view returns (address) {
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        return companies[companyId];
    }

    /// @notice Gets project details by company and project ID
    /// @param companyId Unique identifier for the company
    /// @param projectId Unique identifier for the project
    /// @return Project details
    function getProject(bytes32 companyId, bytes32 projectId) external view returns (Project memory) {
        if (projects[companyId][projectId].token == address(0)) revert ProjectNotFound(projectId);
        return projects[companyId][projectId];
    }

    /*//////////////////////////////////////////////////////////////
                         OWNER-GATED FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }
}