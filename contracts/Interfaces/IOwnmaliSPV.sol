// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IOwnmaliSPV
/// @notice Interface for the OwnmaliSPV contract managing a Special Purpose Vehicle
interface IOwnmaliSPV {
    // Struct for initialization parameters
    struct InitParams {
        string spvName;
        bool kycStatus;
        string countryCode;
        bytes32 metadataCID;
        address manager;
        address registry;
        address assetToken;
    }

    // Role identifiers
    function SPV_ADMIN_ROLE() external view returns (bytes32);
    function INVESTOR_ROLE() external view returns (bytes32);

    // State variables
    function spvName() external view returns (string memory);
    function kycStatus() external view returns (bool);
    function countryCode() external view returns (string memory);
    function metadataCID() external view returns (bytes32);
    function manager() external view returns (address);
    function registry() external view returns (address);
    function assetToken() external view returns (address);
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);


    // Events
    event SPVMetadataUpdated(bytes32 oldCID, bytes32 newCID);
    event SPVKycStatusUpdated(bool kycStatus);
    event SPVManagerUpdated(address indexed oldManager, address indexed newManager);
    event RegistryUpdated(address indexed oldRegistry, address indexed newRegistry);
    event AssetsDeposited(address indexed depositor, uint256 amount);
    event AssetsWithdrawn(address indexed recipient, uint256 amount);
    event InvestorAdded(address indexed investor);
    event InvestorRemoved(address indexed investor);
    event ProfitsDistributed(address indexed investor, uint256 amount);

    event SPVPurposeUpdated(string oldPurpose, string newPurpose);
    event OwnerUpdated(address indexed oldOwner, address indexed newOwner);

    // Errors
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error Unauthorized(address caller);
    error InsufficientAssets(uint256 requested, uint256 available);
    error AssetTransferFailed(address token, address to, uint256 amount);

    /// @notice Initializes the SPV contract
    /// @param params Initialization parameters
    function initialize(InitParams calldata params) external;

    /// @notice Deposits assets (ETH or ERC-20 tokens) into the SPV
    /// @param amount Amount of assets to deposit
    function depositAssets(uint256 amount) external payable;

    /// @notice Withdraws assets to a specified address
    /// @param recipient Address to receive the assets
    /// @param amount Amount of assets to withdraw
    function withdrawAssets(address recipient, uint256 amount) external;

     

    /// @notice Distributes profits to investors
    /// @param investors List of investor addresses
    /// @param amounts Corresponding amounts to distribute
    function distributeProfits(address[] calldata investors, uint256[] calldata amounts) external;

    /// @notice Adds an investor to the SPV
    /// @param investor Address of the investor
    function addInvestor(address investor) external;

    /// @notice Removes an investor from the SPV
    /// @param investor Address of the investor
    function removeInvestor(address investor) external;

    /// @notice Updates SPV metadata CID
    /// @param newMetadataCID New IPFS CID for SPV metadata
    function updateMetadata(bytes32 newMetadataCID) external;

    /// @notice Updates SPV KYC status
    /// @param _kycStatus New KYC status
    function updateKycStatus(bool _kycStatus) external;

    /// @notice Updates SPV manager
    /// @param newManager New manager address
    function updateManager(address newManager) external;

    /// @notice Updates the registry address
    /// @param _registry New registry address
    function setRegistry(address _registry) external;
    
    /// @notice Updates SPV asset description
    /// @param newAssetDescription New asset description
    function updateAssetDescription(string calldata newAssetDescription) external; // New function

    function updateSPVPurpose(string calldata newSpvPurpose) external;
    function updateOwner(address newOwner) external;  

    /// @notice Gets SPV details
    /// @return SPV details (spvName, kycStatus, countryCode, metadataCID, manager, assetToken, totalAssets)
    function getDetails()
        external
        view
        returns (
            string memory,
            bool,
            string memory,
            bytes32,
            address,
            address,
            uint256
        );

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;
}