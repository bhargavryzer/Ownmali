// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Ownmali_Interfaces.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliEscrow
/// @notice Escrow contract for managing ETH funds for tokenized asset orders in the Ownmali ecosystem
/// @dev Holds ETH for buy/sell orders, with transfers controlled by the order manager or admin
contract OwnmaliEscrow is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IOwnmaliEscrow
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

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ESCROW_MANAGER_ROLE = keccak256("ESCROW_MANAGER_ROLE");

    address public projectOwner;
    address public project;
    address public orderManager;
    bytes32 public companyId;
    bytes32 public assetId;
    uint256 public maxWithdrawalsPerTx;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event FundsDeposited(address indexed sender, uint256 amount);
    event FundsTransferred(address indexed recipient, uint256 amount);
    event FundsTransferredToOwner(address indexed owner, uint256 amount);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    event MaxWithdrawalsPerTxSet(uint256 newMax);
    event OrderManagerSet(address indexed orderManager);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the escrow contract
    /// @param _projectOwner Project owner address
    /// @param _project Project contract address
    /// @param _companyId Company identifier
    /// @param _assetId Asset identifier
    function initialize(
        address _projectOwner,
        address _project,
        bytes32 _companyId,
        bytes32 _assetId
    ) public override initializer {
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
        _grantRole(ESCROW_MANAGER_ROLE, _projectOwner);
        _setRoleAdmin(ESCROW_MANAGER_ROLE, ADMIN_ROLE);

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

    /// @notice Transfers ETH to a recipient (called by orderManager for order cancellation/finalization)
    /// @param recipient Recipient address
    /// @param amount Amount in wei
    function transferTo(address recipient, uint256 amount) external override whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (recipient == address(0)) revert InvalidAddress(recipient, "recipient");
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (address(this).balance < amount) revert InsufficientBalance(address(this).balance, amount);

        (bool sent, ) = recipient.call{value: amount}("");
        if (!sent) revert TransferFailed(recipient, amount);

        emit FundsTransferred(recipient, amount);
    }

    /// @notice Transfers ETH to the project owner (called by orderManager for buy order finalization)
    /// @param amount Amount in wei
    function transferToOwner(uint256 amount) external override whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (address(this).balance < amount) revert InsufficientBalance(address(this).balance, amount);

        (bool sent, ) = projectOwner.call{value: amount}("");
        if (!sent) revert TransferFailed(projectOwner, amount);

        emit FundsTransferredToOwner(projectOwner, amount);
    }

    /// @notice Performs an emergency withdrawal of ETH to multiple recipients
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts in wei
    function emergencyWithdrawal(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyRole(ESCROW_MANAGER_ROLE)
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
            emit EmergencyWithdrawal(recipients[i], amounts[i]);
        }
    }

    /// @notice Pauses the contract
    function pause() external override onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external override onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the current ETH balance of the escrow
    /// @return Balance in wei
    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

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

    /// @notice Receives ETH deposits from orderManager or investors
    receive() external payable {
        emit FundsDeposited(msg.sender, msg.value);
    }
}