// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Interface for OwnmaliAssetManager
/// @notice Defines the external and public functions, events, and errors for the OwnmaliAssetManager contract
interface IOwnmaliAssetManager {
    /// @notice Error thrown when an address is invalid
    error InvalidAddress(address addr, string parameter);
    /// @notice Error thrown when an amount is invalid
    error InvalidAmount(uint256 amount, string parameter);
    /// @notice Error thrown when the caller is unauthorized
    error UnauthorizedCaller(address caller);
    /// @notice Error thrown when a token operation fails
    error TokenOperationFailed(string operation);
    /// @notice Error thrown when a parameter is invalid
    error InvalidParameter(string parameter, string reason);

    /// @notice Emitted when tokens are minted
    event TokensMinted(address indexed recipient, uint256 amount);
    /// @notice Emitted when tokens are transferred
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);
    /// @notice Emitted when tokens are locked
    event TokensLocked(address indexed account, uint256 amount, uint256 unlockTime);
    /// @notice Emitted when tokens are released
    event TokensReleased(address indexed account, uint256 amount);
    /// @notice Emitted when the order manager address is set
    event OrderManagerSet(address indexed orderManager);

    /// @notice Initializes the asset manager contract
    /// @param _projectOwner Project owner address
    /// @param _project Project contract address (ERC-3643 compliant token)
    /// @param _companyId Company identifier
    /// @param _assetId Asset identifier
    function initialize(
        address _projectOwner,
        address _project,
        bytes32 _companyId,
        bytes32 _assetId
    ) external;

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external;

    /// @notice Mints tokens to a recipient (e.g., for buy order finalization)
    /// @param recipient Recipient address
    /// @param amount Amount of tokens
    function mintTokens(address recipient, uint256 amount) external;

    /// @notice Transfers tokens between accounts (e.g., for order execution)
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