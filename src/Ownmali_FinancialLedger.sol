// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Ownmali_Interfaces.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliFinancialLedger
/// @notice Maintains a transparent, immutable record of ETH financial transactions for Ownmali projects
/// @dev Handles ETH deposits, transfers, and withdrawals, with upgradeable role-based access control
contract OwnmaliFinancialLedger is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidAmount(uint256 amount, string parameter);
    error InsufficientBalance(uint256 balance, uint256 requested);
    error UnauthorizedCaller(address caller);
    error MaxWithdrawalsExceeded(uint256 count, uint256 max);
    error TransferFailed(address recipient, uint256 amount);
    error InvalidParameter(string parameter, string reason);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum TransactionType {
        Deposit,
        Transfer,
        TransferToOwner,
        EmergencyWithdrawal
    }

    struct Transaction {
        address sender;
        address recipient;
        uint256 amount;
        TransactionType txType;
        string purpose;
        uint256 timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant LEDGER_MANAGER_ROLE = keccak256("LEDGER_MANAGER_ROLE");

    address public projectOwner;
    address public project;
    address public orderManager;
    bytes32 public companyId;
    bytes32 public assetId;
    uint256 public maxWithdrawalsPerTx;
    uint256 public transactionCount;
    mapping(uint256 => Transaction) public transactions;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event TransactionRecorded(
        uint256 indexed txId,
        address indexed sender,
        address indexed recipient,
        uint256 amount,
        TransactionType txType,
        string purpose,
        uint256 timestamp
    );
    event MaxWithdrawalsPerTxSet(uint256 newMax);
    event OrderManagerSet(address indexed orderManager);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

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
    ) public initializer {
        if (_projectOwner == address(0)) revert InvalidAddress(_projectOwner, "projectOwner");
        if (_project == address(0)) revert InvalidAddress(_project, "project");
        _companyId.validateId("companyId");
        _assetId.validateId("assetId");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        projectOwner = _projectOwner;
        project = _project;
        companyId = _companyId;
        assetId = _assetId;
        maxWithdrawalsPerTx = 100;

        _grantRole(DEFAULT_ADMIN_ROLE, _projectOwner);
        _grantRole(ADMIN_ROLE, _projectOwner);
        _grantRole(LEDGER_MANAGER_ROLE, _projectOwner);
        _setRoleAdmin(LEDGER_MANAGER_ROLE, ADMIN_ROLE);

        emit MaxWithdrawalsPerTxSet(maxWithdrawalsPerTx);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external onlyRole(ADMIN_ROLE) {
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager, "orderManager");
        orderManager = _orderManager;
        emit OrderManagerSet(_orderManager);
    }

    /// @notice Sets the maximum number of withdrawals per transaction
    /// @param _maxWithdrawals New maximum number of withdrawals
    function setMaxWithdrawalsPerTx(uint256 _maxWithdrawals) external onlyRole(ADMIN_ROLE) {
        if (_maxWithdrawals == 0) revert InvalidParameter("maxWithdrawalsPerTx", "must be non-zero");
        maxWithdrawalsPerTx = _maxWithdrawals;
        emit MaxWithdrawalsPerTxSet(_maxWithdrawals);
    }

    /// @notice Transfers ETH to a recipient (e.g., for order cancellation/finalization)
    /// @param recipient Recipient address
    /// @param amount Amount in wei
    /// @param purpose Transaction purpose
    function transferTo(address recipient, uint256 amount, string calldata purpose)
        external
        whenNotPaused
        nonReentrant
    {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (recipient == address(0)) revert InvalidAddress(recipient, "recipient");
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (address(this).balance < amount) revert InsufficientBalance(address(this).balance, amount);
        if (bytes(purpose).length == 0) revert InvalidParameter("purpose", "must be non-empty");

        (bool sent, ) = recipient.call{value: amount}("");
        if (!sent) revert TransferFailed(recipient, amount);

        _recordTransaction(msg.sender, recipient, amount, TransactionType.Transfer, purpose);

        emit TransactionRecorded(
            transactionCount - 1,
            msg.sender,
            recipient,
            amount,
            TransactionType.Transfer,
            purpose,
            block.timestamp
        );
    }

    /// @notice Transfers ETH to the project owner (e.g., for buy order finalization)
    /// @param amount Amount in wei
    /// @param purpose Transaction purpose
    function transferToOwner(uint256 amount, string calldata purpose) external whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (address(this).balance < amount) revert InsufficientBalance(address(this).balance, amount);
        if (bytes(purpose).length == 0) revert InvalidParameter("purpose", "must be non-empty");

        (bool sent, ) = projectOwner.call{value: amount}("");
        if (!sent) revert TransferFailed(projectOwner, amount);

        _recordTransaction(msg.sender, projectOwner, amount, TransactionType.TransferToOwner, purpose);

        emit TransactionRecorded(
            transactionCount - 1,
            msg.sender,
            projectOwner,
            amount,
            TransactionType.TransferToOwner,
            purpose,
            block.timestamp
        );
    }

    /// @notice Performs an emergency withdrawal of ETH to multiple recipients
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts in wei
    /// @param purposes Array of transaction purposes
    function emergencyWithdrawal(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata purposes
    ) external onlyRole(LEDGER_MANAGER_ROLE) whenPaused nonReentrant {
        if (recipients.length != amounts.length || recipients.length != purposes.length) {
            revert InvalidParameter("array length", "mismatch");
        }
        if (recipients.length == 0 || recipients.length > maxWithdrawalsPerTx) {
            revert MaxWithdrawalsExceeded(recipients.length, maxWithdrawalsPerTx);
        }

        uint256 totalAmount;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidAddress(recipients[i], "recipient");
            if (amounts[i] == 0) revert InvalidAmount(amounts[i], "amount");
            if (bytes(purposes[i]).length == 0) revert InvalidParameter("purpose", "must be non-empty");
            totalAmount += amounts[i];
        }

        if (address(this).balance < totalAmount) revert InsufficientBalance(address(this).balance, totalAmount);

        for (uint256 i = 0; i < recipients.length; i++) {
            (bool sent, ) = recipients[i].call{value: amounts[i]}("");
            if (!sent) revert TransferFailed(recipients[i], amounts[i]);

            _recordTransaction(msg.sender, recipients[i], amounts[i], TransactionType.EmergencyWithdrawal, purposes[i]);

            emit TransactionRecorded(
                transactionCount - 1,
                msg.sender,
                recipients[i],
                amounts[i],
                TransactionType.EmergencyWithdrawal,
                purposes[i],
                block.timestamp
            );
        }
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current ETH balance of the ledger
    /// @return Balance in wei
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /// @notice Returns details of a transaction by ID
    /// @param txId Transaction ID
    /// @return Transaction details
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
        )
    {
        if (txId >= transactionCount) revert InvalidParameter("txId", "invalid");
        Transaction storage tx = transactions[txId];
        return (tx.sender, tx.recipient, tx.amount, tx.txType, tx.purpose, tx.timestamp);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Records a transaction in the ledger
    /// @param sender Sender address
    /// @param recipient Recipient address
    /// @param amount Amount in wei
    /// @param txType Transaction type
    /// @param purpose Transaction purpose
    function _recordTransaction(
        address sender,
        address recipient,
        uint256 amount,
        TransactionType txType,
        string calldata purpose
    ) internal {
        Transaction storage tx = transactions[transactionCount++];
        tx.sender = sender;
        tx.recipient = recipient;
        tx.amount = amount;
        tx.txType = txType;
        tx.purpose = purpose;
        tx.timestamp = block.timestamp;
    }

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }

    /*//////////////////////////////////////////////////////////////
                           RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Receives ETH deposits and records them
    receive() external payable {
        _recordTransaction(msg.sender, address(this), msg.value, TransactionType.Deposit, "ETH deposit");

        emit TransactionRecorded(
            transactionCount - 1,
            msg.sender,
            address(this),
            msg.value,
            TransactionType.Deposit,
            "ETH deposit",
            block.timestamp
        );
    }
}