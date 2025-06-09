// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOwnmaliRegistry {
    struct Project {
        string name;
        bytes32 assetType;
        address token;
        bytes32 metadataCID;
    }

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
    
    function getCompany(bytes32 companyId) external view returns (address);
    function getProject(bytes32 companyId, bytes32 projectId) external view returns (
        string memory name,
        bytes32 assetType,
        address token,
        bytes32 metadataCID
    );
}
