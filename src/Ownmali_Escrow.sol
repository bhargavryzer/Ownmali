// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IOwnmaliProject.sol";
import "./interfaces/IOwnmaliOrderManager.sol";

/// @title OwnmaliEscrow
/// @notice Manages OwnmaliProject tokens for a project, handling deposits, withdrawals, dividends, and disputes
/// @dev Uses ERC-3643 compliant tokens, without USDT payments
contract OwnmaliEscrow is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidAmount(uint256 amount);
    error InvalidOrderId(uint256 orderId);
    error ProjectInactive(address project);
    error InsufficientBalance(uint256 requested, uint256 available);
    error DisputeAlreadyResolved(uint256 orderId);
    error TransferNotCompliant(address from, address to, uint256 amount);
    error InvalidParameter(string parameter);
    error MaxRecipientsExceeded(uint256 limit);

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant DISPUTE_RESOLVER_ROLE = keccak256("DISPUTE_RESOLVER_ROLE");

    address public project;
    mapping(uint256 => bool) public resolvedDisputes;
    uint256 public constant MAX_RECIPIENTS = 100; // Prevent gas limit issues

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event TokensDeposited(address indexed from, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);
    event DividendsDistributed(uint256 totalAmount, uint256 holderCount);
    event DisputeResolved(uint256 indexed orderId, bool refundApproved);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    event ProjectSet(address indexed newProject);

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract
    function initialize(address _project, address _admin) external initializer {
        if (_project == address(0) || _admin == address(0)) revert InvalidAddress(address(0));

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        project = _project;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(DISPUTE_RESOLVER_ROLE, _admin);
        _setRoleAdmin(DISPUTE_RESOLVER_ROLE, ADMIN_ROLE);

        emit ProjectSet(_project);
    }

    /// @notice Deposits project tokens into the escrow
    /// @param amount Amount of tokens to deposit
    function depositTokens(uint256 amount) external nonReentrant whenNotPaused {
        if (amount == 0) revert InvalidAmount(amount);
        if (!IOwnmaliProject(project).getIsActive()) revert ProjectInactive(project);
        if (!IOwnmaliProject(project).compliance().canTransfer(msg.sender, address(this), amount)) {
            revert TransferNotCompliant(msg.sender, address(this), amount);
        }

        IOwnmaliProject(project).transferWithData(address(this), amount, "");
        emit TokensDeposited(msg.sender, amount);
    }

    /// @notice Withdraws project tokens from the escrow
    /// @param to Recipient address
    /// @param amount Amount of tokens to withdraw
    function withdrawTokens(address to, uint256 amount) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (to == address(0)) revert InvalidAddress(to);
        if (amount == 0) revert InvalidAmount(amount);
        if (!IOwnmaliProject(project).getIsActive()) revert ProjectInactive(project);
        uint256 balance = IOwnmaliProject(project).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance(amount, balance);
        if (!IOwnmaliProject(project).compliance().canTransfer(address(this), to, amount)) {
            revert TransferNotCompliant(address(this), to, amount);
        }

        IOwnmaliProject(project).transferWithData(to, amount, "");
        emit TokensWithdrawn(to, amount);
    }

    /// @notice Distributes dividends in project tokens to token holders
    /// @param holders Array of token holder addresses
    /// @param amounts Array of token amounts to distribute
    function distributeDividends(
        address[] calldata holders,
        uint256[] calldata amounts
    ) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (holders.length != amounts.length) revert InvalidParameter("Array length mismatch");
        if (holders.length > MAX_RECIPIENTS) revert MaxRecipientsExceeded(MAX_RECIPIENTS);
        if (!IOwnmaliProject(project).getIsActive()) revert ProjectInactive(project);

        uint256 totalAmount = 0;
        uint256 dividendPct = IOwnmaliProject(project).dividendPct();
        uint256 maxDividendAmount = (IOwnmaliProject(project).balanceOf(address(this)) * dividendPct) / 100;

        for (uint256 i = 0; i < holders.length; i++) {
            if (holders[i] == address(0)) revert InvalidAddress(holders[i]);
            if (amounts[i] == 0) revert InvalidAmount(amounts[i]);
            if (!IOwnmaliProject(project).compliance().canTransfer(address(this), holders[i], amounts[i])) {
                revert TransferNotCompliant(address(this), holders[i], amounts[i]);
            }
            totalAmount += amounts[i];
        }

        if (totalAmount > maxDividendAmount) revert InvalidAmount(totalAmount);

        for (uint256 i = 0; i < holders.length; i++) {
            IOwnmaliProject(project).transferWithData(holders[i], amounts[i], "");
        }

        emit DividendsDistributed(totalAmount, holders.length);
    }

    /// @notice Resolves a dispute for an order
    /// @param orderId The ID of the order
    /// @param refundApproved Whether to approve a refund
    function resolveDispute(
        uint256 orderId,
        bool refundApproved
    ) external onlyRole(DISPUTE_RESOLVER_ROLE) nonReentrant whenNotPaused {
        if (resolvedDisputes[orderId]) revert DisputeAlreadyResolved(orderId);
        if (!IOwnmaliProject(project).getIsActive()) revert ProjectInactive(project);

        resolvedDisputes[orderId] = true;
        address orderManager = IOwnmaliProject(project).orderManager();
        if (refundApproved && orderManager != address(0)) {
            IOwnmaliOrderManager(orderManager).refundOrder(orderId);
        }

        emit DisputeResolved(orderId, refundApproved);
    }

    /// @notice Performs an emergency withdrawal of project tokens
    /// @param recipient Recipient address
    /// @param amount Amount of tokens to withdraw
    function emergencyWithdrawal(
        address recipient,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) nonReentrant {
        if (recipient == address(0)) revert InvalidAddress(recipient);
        if (amount == 0) revert InvalidAmount(amount);
        uint256 balance = IOwnmaliProject(project).balanceOf(address(this));
        if (amount > balance) revert InsufficientBalance(amount, balance);
        if (!IOwnmaliProject(project).compliance().canTransfer(address(this), recipient, amount)) {
            revert TransferNotCompliant(address(this), recipient, amount);
        }

        IOwnmaliProject(project).transferWithData(recipient, amount, "");
        emit EmergencyWithdrawal(recipient, amount);
    }

    /// @notice Updates the project address
    function setProject(address _project) external onlyRole(ADMIN_ROLE) {
        if (_project == address(0)) revert InvalidAddress(_project);
        project = _project;
        emit ProjectSet(_project);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
}