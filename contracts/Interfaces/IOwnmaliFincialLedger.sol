// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Interface for OwnmaliFinancialLedger
/// @notice Defines the external and public functions, events, errors, and data structures for the OwnmaliFinancialLedger contract
interface IOwnmaliFinancialLedger {
    /// @notice Error thrown when an address is invalid
    error InvalidAddress(address addr, string parameter);
    /// @notice Error thrown when an amount is invalid
    error InvalidAmount(uint256 amount, string parameter);
    /// @notice Error thrown when balance is insufficient
    error InsufficientBalance(uint256 balance, uint256 requested);
    /// @notice Error thrown when caller is unauthorized
    error UnauthorizedCaller(address caller);
    /// @notice Error thrown when maximum withdrawals are exceeded
    error MaxWithdrawalsExceeded(uint256 count, uint256 max);
    /// @notice Error thrown when a transfer fails
    error TransferFailed(address recipient, uint256 amount);
    /// @notice Error thrown when a parameter is invalid
    error InvalidParameter(string parameter, string reason);

    /// @notice Enum for transaction types
    enum TransactionType {
        Deposit,
        Transfer,
        TransferToOwner,
        EmergencyWithdrawal
    }

    /// @notice Struct for transaction details
    struct Transaction {
        address sender;
        address recipient;
        uint256 amount;
        TransactionType txType;
        string purpose;
        uint256 timestamp;
    }

    /// @notice Emitted when a transaction is recorded
    event TransactionRecorded(
        uint256 indexed txId,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        TransactionType txType,
        string purpose,
        uint256 timestamp
    );
    /// @notice Emitted when max withdrawals per transaction is set
    event MaxWithdrawalsPerTxSet(uint256 newMax);
    /// @notice Emitted when order manager address is set
    event OrderManagerSet(address indexed orderManager);

    /// @notice Initializes the financial ledger contract
    /// @param _projectOwner Project owner address
    /// @param _project Project contract address
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

    /// @notice Sets the maximum number of withdrawals per transaction
    /// @param _maxWithdrawals New maximum number of withdrawals
    function setMaxWithdrawalsPerTx(uint256 _maxWithdrawals) external;

    /// @notice Transfers ETH to a recipient (e.g., for order cancellation/finalization)
    /// @param recipient Recipient address
    /// @param amount Amount in wei
    /// @param purpose Transaction purpose
    function transferTo(address recipient, uint256 amount, string calldata purpose) external;

    /// @notice Transfers ETH to the project owner (e.g., for buy order finalization)
    /// @param amount Amount in wei
    /// @param purpose Transaction purpose
    function transferToOwner(uint256 amount, string calldata purpose) external;

    /// @notice Performs an emergency withdrawal of ETH to multiple recipients
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts in wei
    /// @param purposes Array of transaction purposes
    function emergencyWithdrawal(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata purposes
    ) external;

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Returns the current ETH balance of the ledger
    /// @return Balance in wei
    function getBalance() external view returns (uint256);

    /// @notice Returns details of a transaction by ID
    /// @param txId Transaction ID
    /// @return sender Transaction sender
    /// @return recipient Transaction recipient
    /// @return amount Transaction amount in wei
    /// @return txType Transaction type
    /// @return purpose Transaction purpose
    /// @return timestamp Transaction timestamp
    function getTransaction(uint256 txId)
        external
        view
        returns (
            address sender,
            address recipient,
            uint256 amount,
            TransactionType txType,
            string memory purpose,
            uint256 timestamp
        );

    /// @notice Receives ETH deposits and records them
    receive() external payable;
}