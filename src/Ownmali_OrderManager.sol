// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Ownmali_Interfaces.sol";
import "./Ownmali_Validation.sol";
import "./Ownmali_Project.sol";

/// @title OwnmaliOrderManager
/// @notice Manages buy and sell orders for tokenized assets using native ETH in the Ownmali ecosystem
/// @dev Integrates with OwnmaliProject for token transfers and OwnmaliEscrow for ETH fund management
contract OwnmaliOrderManager is
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
    error InvalidOrderId(bytes32 orderId);
    error OrderAlreadyExists(bytes32 orderId);
    error OrderNotFound(bytes32 orderId);
    error OrderNotActive(bytes32 orderId);
    error InsufficientFunds(address account, uint256 balance, uint256 required);
    error TotalSupplyExceeded(uint256 requested, uint256 maxSupply);
    error TransferNotCompliant(address from, address to, uint256 amount);
    error MaxOrdersExceeded(address account, uint256 current, uint256 max);
    error InsufficientEtherSent(uint256 sent, uint256 required);

    /*//////////////////////////////////////////////////////////////
                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum OrderType { Buy, Sell }
    enum OrderStatus { Active, Cancelled, Finalized }

    struct Order {
        bytes32 orderId;
        address investor;
        OrderType orderType;
        uint256 amount;
        uint256 price;
        OrderStatus status;
        address project;
        bytes32 companyId;
        bytes32 assetId;
        uint256 createdAt;
    }

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ORDER_CREATOR_ROLE = keccak256("ORDER_CREATOR_ROLE");
    bytes32 public constant ORDER_FINALIZER_ROLE = keccak256("ORDER_FINALIZER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public maxOrdersPerAddress;
    address public escrow;
    address public project;
    mapping(bytes32 => Order) public orders;
    mapping(address => bytes32[]) public ordersByAddress;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event OrderCreated(
        bytes32 indexed orderId,
        address indexed investor,
        OrderType orderType,
        uint256 amount,
        uint256 price,
        address indexed project,
        bytes32 companyId,
        bytes32 assetId
    );
    event OrderCancelled(bytes32 indexed orderId, address indexed investor);
    event OrderFinalized(
        bytes32 indexed orderId,
        address indexed investor,
        uint256 amount,
        uint256 price
    );
    event MaxOrdersPerAddressSet(uint256 newMax);
    event EscrowSet(address indexed escrow);
    event ProjectSet(address indexed project);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the order manager contract
    /// @param _escrow Escrow contract address
    /// @param _project Project contract address
    /// @param _admin Admin address for role assignment
    function initialize(
        address _escrow,
        address _project,
        address _admin
    ) public initializer {
        if (_escrow == address(0)) revert InvalidAddress(_escrow, "escrow");
        if (_project == address(0)) revert InvalidAddress(_project, "project");
        if (_admin == address(0)) revert InvalidAddress(_admin, "admin");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        escrow = _escrow;
        project = _project;
        maxOrdersPerAddress = 100;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(ORDER_CREATOR_ROLE, _admin);
        _grantRole(ORDER_FINALIZER_ROLE, _admin);
        _setRoleAdmin(ORDER_CREATOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ORDER_FINALIZER_ROLE, ADMIN_ROLE);

        emit EscrowSet(_escrow);
        emit ProjectSet(_project);
        emit MaxOrdersPerAddressSet(maxOrdersPerAddress);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the maximum number of orders per address
    /// @param _maxOrders New maximum number of orders
    function setMaxOrdersPerAddress(uint256 _maxOrders) external onlyRole(ADMIN_ROLE) {
        if (_maxOrders == 0) revert InvalidParameter("maxOrdersPerAddress", "must be non-zero");
        maxOrdersPerAddress = _maxOrders;
        emit MaxOrdersPerAddressSet(_maxOrders);
    }

    /// @notice Sets the escrow contract address
    /// @param _escrow New escrow contract address
    function setEscrow(address _escrow) external onlyRole(ADMIN_ROLE) {
        if (_escrow == address(0)) revert InvalidAddress(_escrow, "escrow");
        escrow = _escrow;
        emit EscrowSet(_escrow);
    }

    /// @notice Sets the project contract address
    /// @param _project New project contract address
    function setProject(address _project) external onlyRole(ADMIN_ROLE) {
        if (_project == address(0)) revert InvalidAddress(_project, "project");
        project = _project;
        emit ProjectSet(_project);
    }

    /// @notice Creates a new buy or sell order
    /// @param orderId Unique order identifier
    /// @param investor Investor address
    /// @param orderType Type of order (Buy or Sell)
    /// @param amount Number of tokens
    /// @param price Total price in ETH (wei)
    /// @param companyId Company identifier
    /// @param assetId Asset identifier
    function createOrder(
        bytes32 orderId,
        address investor,
        OrderType orderType,
        uint256 amount,
        uint256 price,
        bytes32 companyId,
        bytes32 assetId
    ) external payable onlyRole(ORDER_CREATOR_ROLE) whenNotPaused nonReentrant {
        orderId.validateId("orderId");
        if (investor == address(0)) revert InvalidAddress(investor, "investor");
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (price == 0) revert InvalidAmount(price, "price");
        companyId.validateId("companyId");
        assetId.validateId("assetId");
        if (orders[orderId].orderId != bytes32(0)) revert OrderAlreadyExists(orderId);
        if (ordersByAddress[investor].length >= maxOrdersPerAddress) {
            revert MaxOrdersExceeded(investor, ordersByAddress[investor].length, maxOrdersPerAddress);
        }

        orders[orderId] = Order({
            orderId: orderId,
            investor: investor,
            orderType: orderType,
            amount: amount,
            price: price,
            status: OrderStatus.Active,
            project: project,
            companyId: companyId,
            assetId: assetId,
            createdAt: block.timestamp
        });

        ordersByAddress[investor].push(orderId);

        if (orderType == OrderType.Buy) {
            if (msg.value < price) revert InsufficientEtherSent(msg.value, price);
            (bool sent, ) = escrow.call{value: price}("");
            if (!sent) revert InvalidParameter("ETH transfer", "failed to send to escrow");
        } else {
            if (!OwnmaliProject(project).compliance().canTransfer(investor, escrow, amount)) {
                revert TransferNotCompliant(investor, escrow, amount);
            }
            OwnmaliProject(project).transferFrom(investor, escrow, amount);
        }

        emit OrderCreated(orderId, investor, orderType, amount, price, project, companyId, assetId);
    }

    /// @notice Cancels an existing order
    /// @param orderId Order identifier
    function cancelOrder(bytes32 orderId) external onlyRole(ORDER_CREATOR_ROLE) whenNotPaused nonReentrant {
        orderId.validateId("orderId");
        Order storage order = orders[orderId];
        if (order.orderId == bytes32(0)) revert OrderNotFound(orderId);
        if (order.status != OrderStatus.Active) revert OrderNotActive(orderId);

        order.status = OrderStatus.Cancelled;

        if (order.orderType == OrderType.Buy) {
            IOwnmaliEscrow(escrow).transferTo(order.investor, order.price);
        } else {
            if (!OwnmaliProject(project).compliance().canTransfer(escrow, order.investor, order.amount)) {
                revert TransferNotCompliant(escrow, order.investor, order.amount);
            }
            OwnmaliProject(project).transferFrom(escrow, order.investor, order.amount);
        }

        emit OrderCancelled(orderId, order.investor);
    }

    /// @notice Finalizes an order by minting or transferring tokens
    /// @param orderId Order identifier
    function finalizeOrder(bytes32 orderId) external onlyRole(ORDER_FINALIZER_ROLE) whenNotPaused nonReentrant {
        orderId.validateId("orderId");
        Order storage order = orders[orderId];
        if (order.orderId == bytes32(0)) revert OrderNotFound(orderId);
        if (order.status != OrderStatus.Active) revert OrderNotActive(orderId);

        order.status = OrderStatus.Finalized;

        if (order.orderType == OrderType.Buy) {
            uint256 totalSupply = OwnmaliProject(project).totalSupply();
            uint256 maxSupply = OwnmaliProject(project).maxSupply();
            if (totalSupply + order.amount > maxSupply) {
                revert TotalSupplyExceeded(totalSupply + order.amount, maxSupply);
            }
            if (!OwnmaliProject(project).compliance().canTransfer(address(0), order.investor, order.amount)) {
                revert TransferNotCompliant(address(0), order.investor, order.amount);
            }
            OwnmaliProject(project).mint(order.investor, order.amount);
            IOwnmaliEscrow(escrow).transferToOwner(order.price);
        } else {
            IOwnmaliEscrow(escrow).transferTo(order.investor, order.price);
        }

        emit OrderFinalized(orderId, order.investor, order.amount, order.price);
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

    /// @notice Returns order details
    /// @param orderId Order identifier
    /// @return Order details
    function getOrder(bytes32 orderId) external view returns (Order memory) {
        if (orders[orderId].orderId == bytes32(0)) revert OrderNotFound(orderId);
        return orders[orderId];
    }

    /// @notice Returns orders for an address
    /// @param investor Investor address
    /// @return Array of order IDs
    function getOrdersByAddress(address investor) external view returns (bytes32[] memory) {
        if (investor == address(0)) revert InvalidAddress(investor, "investor");
        return ordersByAddress[investor];
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
}