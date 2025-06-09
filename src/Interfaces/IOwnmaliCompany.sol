// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOwnmaliCompany {
    // Events
    event CompanyMetadataUpdated(bytes32 oldCID, bytes32 newCID);
    event CompanyKycStatusUpdated(bool kycStatus);
    event CompanyOwnerUpdated(address oldOwner, address newOwner);
    event RegistryUpdated(address oldRegistry, address newRegistry);

    // External Functions
    function initialize(
        string calldata _name,
        bool _kycStatus,
        string calldata _countryCode,
        bytes32 _metadataCID,
        address _owner,
        address _registry
    ) external;

    function updateMetadata(bytes32 newMetadataCID) external;
    
    function updateKycStatus(bool newKycStatus) external;
    
    function transferOwnership(address newOwner) external;
    
    function setRegistry(address newRegistry) external;
    
    function pause() external;
    
    function unpause() external;

    // View Functions
    function name() external view returns (string memory);
    
    function kycStatus() external view returns (bool);
    
    function countryCode() external view returns (string memory);
    
    function metadataCID() external view returns (bytes32);
    
    function owner() external view returns (address);
    
    function registry() external view returns (address);
    
    function paused() external view returns (bool);
    
    // Constants
    function COMPANY_ADMIN_ROLE() external pure returns (bytes32);
    
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);
}
