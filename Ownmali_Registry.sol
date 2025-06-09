// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./Ownmali_Validation.sol";
import "./Ownmali_Company.sol";

/// @title OwnmaliRegistry
/// @notice Registry contract for managing company and project metadata
/// @dev Deploys Company contracts and manages project data with role-based access
contract OwnmaliRegistry is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using OwnmaliValidation for *;

    // Role identifiers
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant REGISTRY_MANAGER_ROLE = keccak256("REGISTRY_MANAGER_ROLE");

    // Project struct
    struct Project {
        string name;
        bytes32 assetType;
        address token;
        bytes32 metadataCID;
    }

    // Storage
    mapping(bytes32 => address) private companies; // Maps companyId to Company contract address
    mapping(bytes32 => mapping(bytes32 => Project)) private projects;

    // Events
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

    // Errors
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error InvalidCompanyId(bytes32 companyId);
    error InvalidProjectId(bytes32 projectId);
    error CompanyAlreadyExists(bytes32 companyId);
    error ProjectAlreadyExists(bytes32 projectId);
    error CompanyNotFound(bytes32 companyId);
    error ProjectNotFound(bytes32 projectId);


    /// @notice Initializes the registry
    /// @param _admin The address to be granted admin roles
    function initialize(address _admin) external initializer {
        if (_admin == address(0)) revert InvalidAddress(_admin);

        __AccessControl_init();
        __Pausable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(REGISTRY_MANAGER_ROLE, _admin);
        _setRoleAdmin(REGISTRY_MANAGER_ROLE, ADMIN_ROLE);
    }

    /// @notice Registers a new company by deploying a Company contract
    /// @param companyId Unique identifier for the company
    /// @param name Company name (1-100 characters)
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
    ) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused {
        companyId.validateId("companyId");
        name.validateString("name", 1, 100);
        countryCode.validateString("countryCode", 2, 2);
        metadataCID.validateCID("metadataCID");
        if (owner == address(0)) revert InvalidAddress(owner);
        if (companies[companyId] != address(0)) revert CompanyAlreadyExists(companyId);

        // Deploy new Company contract
        Company company = new Company();
        company.initialize(companyId, name, kycStatus, countryCode, metadataCID, owner, address(this));
        companies[companyId] = address(company);

        emit CompanyRegistered(companyId, address(company), name, kycStatus, countryCode, metadataCID, owner);
    }

    /// @notice Registers a new project under a company
    /// @param companyId Company identifier
    /// @param projectId Unique identifier for the project
    /// @param name Project name (1-100 characters)
    /// @param assetType Type of asset
    /// @param token Token contract address
    /// @param metadataCID IPFS CID for project metadata
    function registerProject(
        bytes32 companyId,
        bytes32 projectId,
        string calldata name,
        bytes32 assetType,
        address token,
        bytes32 metadataCID
    ) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused {
        companyId.validateId("companyId");
        projectId.validateId("projectId");
        name.validateString("name", 1, 100);
        metadataCID.validateCID("metadataCID");
        if (token == address(0)) revert InvalidAddress(token);
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        if (projects[companyId][projectId].token != address(0)) revert ProjectAlreadyExists(projectId);

        projects[companyId][projectId] = Project({
            name: name,
            assetType: assetType,
            token: token,
            metadataCID: metadataCID
        });

        emit ProjectRegistered(companyId, projectId, name, assetType, token, metadataCID);
    }

    /// @notice Updates project metadata CID
    /// @param companyId Company identifier
    /// @param projectId Project identifier
    /// @param newMetadataCID New IPFS CID for project metadata
    function updateProjectMetadata(
        bytes32 companyId,
        bytes32 projectId,
        bytes32 newMetadataCID
    ) external onlyRole(REGISTRY_MANAGER_ROLE) whenNotPaused {
        companyId.validateId("companyId");
        projectId.validateId("projectId");
        newMetadataCID.validateCID("metadataCID");
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        if (projects[companyId][projectId].token == address(0)) revert ProjectNotFound(projectId);

        bytes32 oldCID = projects[companyId][projectId].metadataCID;
        projects[companyId][projectId].metadataCID = newMetadataCID;

        emit ProjectMetadataUpdated(companyId, projectId, oldCID, newMetadataCID);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Gets company contract address
    /// @param companyId Company identifier
    /// @return Address of the Company contract
    function getCompanyAddress(bytes32 companyId) external view returns (address) {
        if (companies[companyId] == address(0)) revert CompanyNotFound(companyId);
        return companies[companyId];
    }

    /// @notice Gets project details
    /// @param companyId Company identifier
    /// @param projectId Project identifier
    /// @return Project struct containing project details
    function getProject(bytes32 companyId, bytes32 projectId) external view returns (Project memory) {
        if (projects[companyId][projectId].token == address(0)) revert ProjectNotFound(projectId);
        return projects[companyId][projectId];
    }
}