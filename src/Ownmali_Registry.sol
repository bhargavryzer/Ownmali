// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./Ownmali_Validation.sol";
import {OwnmaliCompany} from "./Ownmali_Company.sol";

/// @title OwnmaliRegistry
/// @notice Registry contract for managing company and project metadata
/// @dev Uses clones for efficient contract deployment and role-based access control
contract OwnmaliRegistry is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error InvalidCompanyId(bytes32 companyId);
    error InvalidProjectId(bytes32 projectId);
    error CompanyAlreadyExists(bytes32 companyId);
    error ProjectAlreadyExists(bytes32 projectId);
    error CompanyNotFound(bytes32 companyId);
    error ProjectNotFound(bytes32 projectId);
    error TemplateNotSet();

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

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the registry
    /// @param _admin Admin address for role assignment
    function initialize(address _admin) external initializer {
        if (_admin == address(0)) revert InvalidAddress(_admin);

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(REGISTRY_MANAGER_ROLE, _admin);
        _setRoleAdmin(REGISTRY_MANAGER_ROLE, ADMIN_ROLE);
    }

    /// @notice Sets the company template for cloning
    function setCompanyTemplate(address _companyTemplate) external onlyRole(ADMIN_ROLE) {
        if (_companyTemplate == address(0)) revert InvalidAddress(_companyTemplate);
        companyTemplate = _companyTemplate;
        emit CompanyTemplateSet(_companyTemplate);
    }

    /// @notice Registers a new company by cloning the template
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
        if (owner == address(0)) revert InvalidAddress(owner);
        if (companies[companyId] != address(0)) revert CompanyAlreadyExists(companyId);
        if (companyTemplate == address(0)) revert TemplateNotSet();

        // Deploy cloned company contract
        address companyAddress = Clones.clone(companyTemplate);
        OwnmaliCompany(companyAddress).initialize(
            name,
            kycStatus,
            countryCode,
            metadataCID,
            owner,
            address(this)
        );
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
    }

    /// @notice Registers a new project under a company
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
        if (token == address(0)) revert InvalidAddress(token);
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        if (projects[companyId][projectId].token != address(0)) revert ProjectAlreadyExists(projectId);

        // Validate asset type (if restricted)
        if (
            assetType != bytes32("Commercial") &&
            assetType != bytes32("Residential") &&
            assetType != bytes32("Land") &&
            assetType != bytes32("Holiday")
        ) revert InvalidParameter("assetType");

        projects[companyId][projectId] = Project({
            name: name,
            assetType: assetType,
            token: token,
            metadataCID: metadataCID
        });

        emit ProjectRegistered(companyId, projectId, name, assetType, token, metadataCID);
    }

    /// @notice Updates project metadata CID
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

    /// @notice Gets company contract address
    function getCompanyAddress(bytes32 companyId) external view returns (address) {
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        return companies[companyId];
    }

    /// @notice Gets project details
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
}