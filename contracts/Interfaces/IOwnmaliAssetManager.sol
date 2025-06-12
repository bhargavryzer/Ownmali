// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Interface for OwnmaliAssetManager
/// @notice Defines the external and public functions, events, and errors for the OwnmaliAssetManager contract
interface IOwnmaliAssetManager {
    /// @notice Error thrown when an address is invalid
    error InvalidAddress(address addr);
    /// @notice Error thrown when an amount is invalid
    error InvalidAmount(uint256 amount);
    /// @notice Error thrown when the caller is unauthorized
    error UnauthorizedCaller(address caller);
    /// @notice Error thrown when a token operation fails
    error TokenOperationFailed(string operation);
    /// @notice Error thrown when the implementation is invalid
    error InvalidImplementation();

    /// @notice Emitted when the order manager is set
    event OrderManagerSet(address indexed orderManager);
    /// @notice Emitted when the token contract is set
    event TokenContractSet(address indexed tokenContract);
    /// @notice Emitted when tokens are minted
    event TokensMinted(address indexed recipient, uint256 amount);
    /// @notice Emitted when tokens are transferred
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when tokens are locked
    event TokensLocked(address indexed account, uint256 amount);
    /// @notice Emitted when tokens are released
    event TokensReleased(address indexed account, uint256 amount);

    /// @notice Initializes the asset manager contract
    /// @param _owner Owner address with admin privileges
    /// @param _tokenContract Address of the token contract to manage
    function initialize(
        address _owner,
        address _tokenContract
    ) external;

    /// @notice Returns the token contract address
    /// @return The token contract address
    function tokenContract() external view returns (address);
    
    /// @notice Returns the order manager address
    /// @return The order manager address
    function orderManager() external view returns (address);
    
    /// @notice Returns the owner address
    /// @return The owner address
    function owner() external view returns (address);
    
    /// @notice Returns the implementation address
    /// @return The implementation address
    function getImplementation() external view returns (address);

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external;
    
    /// @notice Sets the token contract address
    /// @param _tokenContract New token contract address
    function setTokenContract(address _tokenContract) external;
    
    /// @notice Mints tokens to a recipient
    /// @param recipient Recipient address
    /// @param amount Amount of tokens to mint
    function mintTokens(address recipient, uint256 amount) external;
    
    /// @notice Transfers tokens between accounts
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount of tokens
    function transferTokens(address from, address to, uint256 amount) external;
    
    /// @notice Locks tokens for an account until a specified time
    /// @param account Account to lock tokens for
    /// @param amount Amount of tokens
    /// @param unlockTime Unlock timestamp
    function lockTokens(address account, uint256 amount, uint256 unlockTime) external;

    /// @notice Releases locked tokens for an account
    /// @param account Account to release tokens for
    /// @param amount Amount of tokens
    function releaseTokens(address account, uint256 amount) external;

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;
}