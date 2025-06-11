// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Interfaces/IOwnmali_Interfaces.sol";
import "./Ownmali_Validation.sol";

/// @title FinancialLedger
/// @notice Manages ETH transactions and maintains an immutable record for an SPV in the Ownmali ecosystem
/// @dev Handles deposits, transfers, and withdrawals with transparent logging
contract FinancialLedger is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IOwnmaliFinancialLedger
{
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidAmount(uint256 amount, string parameter);
    error InvalidParameter(string parameter, string reason);
    error InsufficientBalance(uint256 balance, uint256 requested);
    error UnauthorizedCaller(address caller);
    error MaxWithdrawalsExceeded(uint256 count, uint256 max);
    error TransferFailed(address recipient, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public projectOwner;
    address public project;
    address public orderManager;
    address public daoContract;
    bytes32 public spvId;
    bytes32 public assetId;
    uint256 public maxWithdrawalsPerTx;

    IOwnmaliFinancialLedger.Transaction[] public transactionLog;

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function calls to the SPV-level DAO contract
    modifier onlyDao() {
        if (msg.sender != daoContract) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the financial ledger contract
    /// @param _projectOwner Project owner address
    /// @param _project Project contract address
    /// @param _spvId SPV identifier
    /// @param _assetId Asset identifier
    /// @param _daoContract SPV-level DAO contract address
    function initialize(
        address _projectOwner,
        address _project,
        bytes32 _spvId,
        bytes32 _assetId,
        address _daoContract
    ) public initializer {
        if (_projectOwner == address(0)) revert InvalidAddress(_projectOwner, "projectOwner");
        if (_project == address(0)) revert InvalidAddress(_project, "project");
        if (_daoContract == address(0)) revert InvalidAddress(_daoContract, "daoContract");
        _spvId.validateId("spvId");
        _assetId.validateId("assetId");

        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        projectOwner = _projectOwner;
        project = _project;
        spvId = _spvId;
        assetId = _assetId;
        daoContract = _daoContract;
        maxWithdrawalsPerTx = 100;

        emit MaxWithdrawalsPerTxSet(maxWithdrawalsPerTx);
        emit DaoContractSet(_daoContract);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external onlyDao {
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager, "orderManager");
        orderManager = _orderManager;
        emit OrderManagerSet(_orderManager);
    }

    /// @notice Sets the SPV-level DAO contract address
    /// @param _daoContract New DAO contract address
    function setDaoContract(address _daoContract) external onlyDao {
        if (_daoContract == address(0)) revert InvalidAddress(_daoContract, "daoContract");
        daoContract = _daoContract;
        emit DaoContractSet(_daoContract);
    }

    /// @notice Sets the maximum number of withdrawals per transaction
    /// @param _maxWithdrawals New maximum number of withdrawals
    function setMaxWithdrawalsPerTx(uint256 _maxWithdrawals) external onlyDao {
        if (_maxWithdrawals == 0) revert InvalidAmount(_maxWithdrawals, "maxWithdrawalsPerTx");
        maxWithdrawalsPerTx = _maxWithdrawals;
        emit MaxWithdrawalsPerTxSet(_maxWithdrawals);
    }

    /// @notice Transfers ETH to a recipient (called by orderManager for order cancellation/finalization)
    /// @param recipient Recipient address
    /// @param amount Amount in wei
    function transferTo(address recipient, uint256 amount) external whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (recipient == address(0)) revert InvalidAddress(recipient, "recipient");
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (address(this).balance < amount) revert InsufficientBalance(address(this).balance, amount);

        (bool sent, ) = recipient.call{value: amount}("");
        if (!sent) revert TransferFailed(recipient, amount);

        transactionLog.push(IOwnmaliFinancialLedger.Transaction({
            sender: msg.sender,
            recipient: recipient,
            amount: amount,
            timestamp: block.timestamp,
            transactionType: "Transfer"
        }));

        emit FundsTransferred(recipient, amount);
    }

    /// @notice Transfers ETH to the project owner (called by orderManager for buy order finalization)
    /// @param amount Amount in wei
    function transferToOwner(uint256 amount) external whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (address(this).balance < amount) revert InsufficientBalance(address(this).balance, amount);

        (bool sent, ) = projectOwner.call{value: amount}("");
        if (!sent) revert TransferFailed(projectOwner, amount);

        transactionLog.push(IOwnmaliFinancialLedger.Transaction({
            sender: msg.sender,
            recipient: projectOwner,
            amount: amount,
            timestamp: block.timestamp,
            transactionType: "TransferToOwner"
        }));

        emit FundsTransferredToOwner(projectOwner, amount);
    }

    /// @notice Performs an emergency withdrawal of ETH to multiple recipients
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts in wei
    function emergencyWithdrawal(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyDao
        whenPaused
        nonReentrant
    {
        if (recipients.length != amounts.length) revert InvalidParameter("array length", "mismatch");
        if (recipients.length == 0 || recipients.length > maxWithdrawalsPerTx) {
            revert MaxWithdrawalsExceeded(recipients.length, maxWithdrawalsPerTx);
        }

        uint256 totalAmount;
        for (uint256 i = 0; i < recipients.length; i++) {
            if (recipients[i] == address(0)) revert InvalidAddress(recipients[i], "recipient");
            if (amounts[i] == 0) revert InvalidAmount(amounts[i], "amount");
            totalAmount += amounts[i];
        }

        if (address(this).balance < totalAmount) revert InsufficientBalance(address(this).balance, totalAmount);

        for (uint256 i = 0; i < recipients.length; i++) {
            (bool sent, ) = recipients[i].call{value: amounts[i]}("");
            if (!sent) revert TransferFailed(recipients[i], amounts[i]);

            transactionLog.push(IOwnmaliFinancialLedger.Transaction({
                sender: msg.sender,
                recipient: recipients[i],
                amount: amounts[i],
                timestamp: block.timestamp,
                transactionType: "EmergencyWithdrawal"
            }));

            emit EmergencyWithdrawal(recipients[i], amounts[i]);
        }
    }

    /// @notice Pauses the contract
    function pause() external onlyDao {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyDao {
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

    /// @notice Returns the transaction log
    /// @return Array of transactions
    function getTransactionLog() external view returns (IOwnmaliFinancialLedger.Transaction[] memory) {
        return transactionLog;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyDao view {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }

    /*//////////////////////////////////////////////////////////////
                           RECEIVE FUNCTION
    //////////////////////////////////////////////////////////////*/

    /// @notice Receives ETH deposits from orderManager or investors
    receive() external payable {
        transactionLog.push(IOwnmaliFinancialLedger.Transaction({
            sender: msg.sender,
            recipient: address(this),
            amount: msg.value,
            timestamp: block.timestamp,
            transactionType: "Deposit"
        }));

        emit FundsDeposited(msg.sender, msg.value);
    }
}