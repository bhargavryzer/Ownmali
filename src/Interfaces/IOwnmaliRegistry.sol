SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IOwnmaliRegistry
/// @notice Interface for the OwnmaliRegistry contract, managing company and project metadata
interface IOwnmaliRegistry {
    /// @notice Structure for project details
    struct Project {
        string name;
        bytes32 assetType;
        address token;
        bytes32 metadataCID;
    }

    /// @notice Emitted when a new company is registered
    event CompanyRegistered(
        bytes32 indexed companyId,
        address indexed companyContract,
        string name,
        bool kycStatus,
        string countryCode,
        bytes32 metadataCID,
        address owner
    );

    /// @notice Emitted when a new project is registered
    event ProjectRegistered(
        bytes32 indexed companyId,
        bytes32 indexed projectId,
        string name,
        bytes32 assetType,
        address token,
        bytes32 metadataCID
    );

    /// @notice Emitted when project metadata is updated
    event ProjectMetadataUpdated(
        bytes32 indexed companyId,
        bytes32 indexed projectId,
        bytes32 oldCID,
        bytes32 newCID
    );

    /// @notice Emitted when the company template is set
    event CompanyTemplateSet(address indexed template);

    /// @notice Emitted when the maximum number of companies is set
    event MaxCompaniesSet(uint256 newMax);

    /// @notice Emitted when the maximum number of projects per company is set
    event MaxProjectsPerCompanySet(uint256 newMax);

    /// @notice Initializes the registry contract
    /// @param _admin Admin address for role assignment
    function initialize(address _admin) external;

    /// @notice Sets the company template for cloning
    /// @param _companyTemplate Address of the company template contract
    function setCompanyTemplate(address _companyTemplate) external;

    /// @notice Sets the maximum number of companies
    /// @param _maxCompanies New maximum number of companies
    function setMaxCompanies(uint256 _maxCompanies) external;

    /// @notice Sets the maximum number of projects per company
    /// @param _maxProjects New maximum number of projects per company
    function setMaxProjectsPerCompany(uint256 _maxProjects) external;

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
    ) external;

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
    ) external;

    /// @notice Updates project metadata CID
    /// @param companyId Unique identifier for the company
    /// @param projectId Unique identifier for the project
    /// @param newMetadataCID New IPFS CID for project metadata
    function updateProjectMetadata(
        bytes32 companyId,
        bytes32 projectId,
        bytes32 newMetadataCID
    ) external;

    /// @notice Gets company contract address by ID
    /// @param companyId Unique identifier for the company
    /// @return Company contract address
    function getCompanyAddress(bytes32 companyId) external view returns (address);

    /// @notice Gets project details by company and project ID
    /// @param companyId Unique identifier for the company
    /// @param projectId Unique identifier for the project
    /// @return Project details
    function getProject(bytes32 companyId, bytes32 projectId) external view returns (Project memory);

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;
}