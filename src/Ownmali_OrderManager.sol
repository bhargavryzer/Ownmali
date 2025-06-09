// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IOwnmaliProject.sol";

/// @title OwnmaliOrderManager
/// @notice Manages token purchase orders for Ownmali projects
/// @dev Handles order creation, cancellation, finalization, and refunds 
contract OwnmaliOrderManager is
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
    error OrderNotActive(uint256 orderId);
    error OrderAlreadyFinalized(uint256 orderId);
    error OrderAlreadyCancelled(uint256 orderId);
    error OrderNotCancellable(uint256 orderId);
    error OrderNotRefundable(uint256 orderId);
    error InvestmentLimitExceeded(uint256 requested, uint256 limit);
    error InvestmentBelowMinimum(uint256 requested, uint256 minimum);
    error ProjectInactive(address project);
    error Unauthorized(); // Added for clarity

    /*//////////////////////////////////////////////////////////////
                         TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum OrderStatus {
        Pending,
        Finalized,
        Cancelled,
        Refunded
    }

    struct Order {
        address buyer;
        uint256 amount; // Amount of project tokens
        uint256 price; // Token price at order creation
        uint48 createdAt;
        uint48 cancelRequestedAt;
        OrderStatus status;
    }

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant FINALIZER_ROLE = keccak256("FINALIZER_ROLE"); // Added
    address public project;
    uint256 public orderCount;
    mapping(uint256 => Order) public orders;

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event OrderCreated(
        uint256 indexed orderId,
        address indexed buyer,
        address indexed project,
        uint256 amount,
        uint256 price,
        uint48 createdAt
    );
    event OrderCancelled(uint256 indexed orderId, address indexed buyer, uint48 cancelRequestedAt);
    event OrderFinalized(uint256 indexed orderId, address indexed buyer, uint256 amount);
    event OrderRefunded(uint256 indexed orderId, address indexed buyer);
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
        orderCount = 0;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(FINALIZER_ROLE, _admin); // Grant finalizer role to admin
        _setRoleAdmin(FINALIZER_ROLE, ADMIN_ROLE);

        emit ProjectSet(_project);
    }

    /// @notice Creates a new order
    function createOrder(address buyer, uint256 amount) external nonReentrant whenNotPaused {
        if (buyer == address(0)) revert InvalidAddress(buyer);
        if (amount == 0) revert InvalidAmount(amount);
        if (!IOwnmaliProject(project).getIsActive()) revert ProjectInactive(project);

        (uint256 minInvestment, uint256 maxInvestment) = IOwnmaliProject(project).getInvestmentLimits();
        uint256 requestedInvestment = amount;

        if (requestedInvestment < minInvestment) {
            revert InvestmentBelowMinimum(requestedInvestment, minInvestment);
        }
        if (requestedInvestment > maxInvestment) {
            revert InvestmentLimitExceeded(requestedInvestment, maxInvestment);
        }

        require(
            IOwnmaliProject(project).compliance().canTransfer(address(0), buyer, amount),
            "Order not compliant"
        );

        uint256 orderId = orderCount++;
        Order storage order = orders[orderId];
        order.buyer = buyer;
        order.amount = amount;
        order.price = IOwnmaliProject(project).tokenPrice();
        order.createdAt = uint48(block.timestamp);
        order.status = OrderStatus.Pending;

        emit OrderCreated(orderId, buyer, project, amount, order.price, order.createdAt);
    }

    /// @notice Requests cancellation of an order
    function cancelOrder(uint256 orderId) external nonReentrant whenNotPaused {
        Order storage order = orders[orderId];
        if (order.buyer != msg.sender) revert Unauthorized();
        if (order.status != OrderStatus.Pending) revert OrderNotActive(orderId);
        if (order.cancelRequestedAt != 0) revert OrderNotCancellable(orderId);

        order.cancelRequestedAt = uint48(block.timestamp);
        order.status = OrderStatus.Cancelled; // Fixed: Update status [[audit issue #1]]

        emit OrderCancelled(orderId, order.buyer, order.cancelRequestedAt);
    }

    /// @notice Finalizes an order by minting tokens
    function finalizeOrder(uint256 orderId) external nonReentrant whenNotPaused {
        Order storage order = orders[orderId];
        if (orderId >= orderCount) revert InvalidOrderId(orderId);
        if (order.status != OrderStatus.Pending) revert OrderNotActive(orderId);
        if (!hasRole(FINALIZER_ROLE, msg.sender)) revert Unauthorized(); // Fixed: Add access control [[audit issue #2]]

        require(
            IOwnmaliProject(project).compliance().canTransfer(address(0), order.buyer, order.amount),
            "Finalization not compliant"
        );

        order.status = OrderStatus.Finalized;
        IOwnmaliProject(project).mint(order.buyer, order.amount);

        emit OrderFinalized(orderId, order.buyer, order.amount);
    }

    /// @notice Refunds an order
    function refundOrder(uint256 orderId) external nonReentrant whenNotPaused {
        Order storage order = orders[orderId];
        if (orderId >= orderCount) revert InvalidOrderId(orderId);
        if (order.status != OrderStatus.Cancelled) revert OrderNotRefundable(orderId);
        if (order.buyer != msg.sender && !hasRole(ADMIN_ROLE, msg.sender)) revert Unauthorized(); // Fixed: Add access control [[audit issue #3]]

        order.status = OrderStatus.Refunded;
        emit OrderRefunded(orderId, order.buyer);
    }

    /// @notice Updates the project address
    function setProject(address _project) external onlyRole(ADMIN_ROLE) {
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

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets order details by ID
    function getOrder(uint256 orderId) external view returns (Order memory) {
        if (orderId >= orderCount) revert InvalidOrderId(orderId);
        return orders[orderId];
    }
}