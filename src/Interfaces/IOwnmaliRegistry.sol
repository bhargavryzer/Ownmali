// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOwnmaliRegistry {
    struct Project {
        string name;
        bytes32 assetType;
        address token;
        bytes32 metadataCID;
    }

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
    event CompanyTemplateSet(address indexed template);

    // External Functions
    function initialize(address _admin) external;
    
    function registerCompany(
        bytes32 companyId,
        string calldata name,
        bool kycStatus,
        string calldata countryCode,
        bytes32 metadataCID,
        address owner
    ) external;
    
    function registerProject(
        bytes32 companyId,
        bytes32 projectId,
        string calldata name,
        bytes32 assetType,
        address token,
        bytes32 metadataCID
    ) external;
    
    function updateProjectMetadata(
        bytes32 companyId,
        bytes32 projectId,
        bytes32 newMetadataCID
    ) external;
    
    function setCompanyTemplate(address _template) external;
    
    function pause() external;
    
    function unpause() external;
    
    // View Functions
    function getCompany(bytes32 companyId) external view returns (address);
    
    function getProject(
        bytes32 companyId, 
        bytes32 projectId
    ) external view returns (Project memory);
    
    function companyTemplate() external view returns (address);
    
    function companies(bytes32) external view returns (address);
    
    function projects(bytes32, bytes32) external view returns (
        string memory name,
        bytes32 assetType,
        address token,
        bytes32 metadataCID
    );
    
    // Constants
    function ADMIN_ROLE() external view returns (bytes32);
    function REGISTRY_MANAGER_ROLE() external view returns (bytes32);
}
