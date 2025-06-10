// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Interface for OwnmaliRealEstateToken
/// @notice Defines the external and public functions, events, and errors for the OwnmaliRealEstateToken contract
interface IOwnmaliRealEstateToken {
    /// @notice Error thrown when the asset type is invalid
    error InvalidAssetType(bytes32 assetType);
    /// @notice Error thrown when batch size exceeds maximum
    error BatchTooLarge(uint256 size, uint256 maxSize);
    /// @notice Error thrown when array lengths do not match
    error ArrayLengthMismatch(uint256 toLength, uint256 amountsLength);
    /// @notice Error thrown when a zero amount is detected
    error ZeroAmountDetected(address recipient);
    /// @notice Error thrown when recipient address is invalid
    error InvalidRecipient(address recipient);
    /// @notice Error thrown when total supply exceeds maximum
    error TotalSupplyExceeded(uint256 requested, uint256 maxSupply);
    /// @notice Error thrown when account has insufficient balance
    error InsufficientBalance(address account, uint256 balance, uint256 requested);
    /// @notice Error thrown when a parameter is invalid
    error InvalidParameter(string param, string reason);
    /// @notice Error thrown when an address is invalid
    error InvalidAddress(address addr, string reason);
    /// @notice Error thrown when transfer is not compliant
    error TransferNotCompliant(address from, address to, uint256 amount);

    /// @notice Emitted when tokens are batch minted
    event BatchMinted(address indexed minter, address[] recipients, uint256[] amounts);
    /// @notice Emitted when tokens are batch burned
    event BatchBurned(address indexed burner, address[] accounts, uint256[] amounts);
    /// @notice Emitted when max batch size is updated
    event MaxBatchSizeSet(uint256 newMaxSize);
    /// @notice Emitted when TRANSFER_ROLE is granted or revoked
    event TransferRoleUpdated(address indexed account, bool granted);

    /// @notice Initializes the contract with real estate-specific parameters
    /// @param initData Encoded initialization parameters
    function initialize(bytes memory initData) external;

    /// @notice Sets the maximum batch size for minting/burning
    /// @param _maxBatchSize New maximum batch size
    function setMaxBatchSize(uint256 _maxBatchSize) external;

    /// @notice Batch mints tokens to multiple addresses
    /// @param to Array of recipient addresses
    /// @param amounts Array of amounts to mint
    function batchMint(address[] calldata to, uint256[] calldata amounts) external;

    /// @notice Batch burns tokens from multiple addresses
    /// @param from Array of source addresses
    /// @param amounts Array of amounts to burn
    function batchBurn(address[] calldata from, uint256[] calldata amounts) external;

    /// @notice Grants or revokes the TRANSFER_ROLE
    /// @param account Address to update
    /// @param grant True to grant, false to revoke
    function setTransferRole(address account, bool grant) external;

    /// @notice Returns the maximum supply of tokens
    /// @return Maximum supply
    function maxSupply() external view returns (uint256);

    /// @notice Returns the total supply of tokens
    /// @return Total supply
    function totalSupply() external view returns (uint256);

    /// @notice Returns the balance of an account
    /// @param account Address to query
    /// @return Balance of the account
    function balanceOf(address account) external view returns (uint256);

    /// @notice Returns the project details
    /// @return Project details struct
    function getProjectDetails() external view returns (ProjectDetails memory);

    /// @notice Struct for project details (assumed from OwnmaliProject)
    struct ProjectDetails {
        bytes32 assetType;
        uint256 maxSupply;
        // Add other fields as needed from OwnmaliProject
    }
}