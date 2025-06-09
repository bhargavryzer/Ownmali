// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOwnmaliFactory {
    struct CompanyParams {
        bytes32 companyId;
        string name;
        bool kycStatus;
        string countryCode;
        bytes32 metadataCID;
        address owner;
    }

    struct ProjectParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        bytes32 companyId;
        bytes32 assetId;
        bytes32 metadataCID;
        bytes32 assetType;
        bytes32 legalMetadataCID;
        uint16 chainId;
        uint256 dividendPct;
        uint256 premintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 eoiPct;
        bool isRealEstate;
    }

    function initialize(
        address _registry,
        address _projectTemplate,
        address _realEstateTemplate,
        address _escrowTemplate,
        address _orderManagerTemplate,
        address _daoTemplate,
        address _identityRegistry,
        address _compliance,
        address _admin
    ) external;
    
    function createCompany(CompanyParams calldata params) external returns (address);
    
    function createProject(ProjectParams calldata params) 
        external 
        returns (
            address project,
            address escrow,
            address orderManager,
            address dao
        );
    
    function setTemplates(
        address _projectTemplate,
        address _realEstateTemplate,
        address _escrowTemplate,
        address _orderManagerTemplate,
        address _daoTemplate
    ) external;
    
    function setCompliance(address _compliance) external;
    function setIdentityRegistry(address _identityRegistry) external;
    function setRegistry(address _registry) external;
    
    function getProject(bytes32 projectId) external view returns (address);
    function getCompany(bytes32 companyId) external view returns (address);
}
