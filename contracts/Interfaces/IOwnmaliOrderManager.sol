// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Interface for OwnmaliOrderManager
/// @notice Defines the external and public functions, events, errors, and data structures for the OwnmaliOrderManager contract
interface IOwnmaliOrderManager {
    /// @notice Error thrown when an address is invalid
    error InvalidAddress(address addr, string parameter);
    /// @notice Error thrown when an amount is invalid
    error InvalidAmount(uint256 amount, string parameter);
    /// @notice Error thrown when an order ID is invalid
    error InvalidOrderId(bytes32 orderId);
    /// @notice Error thrown when an order already exists
    error OrderAlreadyExists(bytes32 orderId);
    /// @notice Error thrown when an order is not found
    error OrderNotFound(bytes32 orderId);
    /// @notice Error thrown when an order is not active
    error OrderNotActive(bytes32 orderId);
    /// @notice Error thrown when funds are insufficient
    error InsufficientFunds(address account, uint256 balance, uint256 required);
    /// @notice Error thrown when total supply exceeds maximum
    error TotalSupplyExceeded(uint256 requested, uint256 maxSupply);
    /// @notice Error thrown when transfer is not compliant
    error TransferNotCompliant(address from, address to, uint256 amount);
    /// @notice Error thrown when maximum orders per address is exceeded
    error MaxOrdersExceeded(address account, uint256 current, uint256 max);
    /// @notice Error thrown when insufficient ETH is sent
    error InsufficientEtherSent(uint256 sent, uint256 required);
    /// @notice Error thrown when a parameter is invalid
    error InvalidParameter(string param, string reason);

    /// @notice Enum for order types
    enum OrderType { Buy, Sell }
    /// @notice Enum for order statuses
    enum OrderStatus { Active, Cancelled, Finalized }

    /// @notice Struct for order details
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

    /// @notice Emitted when an order is created
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
    /// @notice Emitted when an order is cancelled
    event OrderCancelled(bytes32 indexed orderId, address indexed investor);
    /// @notice Emitted when an order is finalized
    event OrderFinalized(
        bytes32 indexed orderId,
        address indexed investor,
        uint256 amount,
        uint256 price
    );
    /// @notice Emitted when max orders per address is set
    event MaxOrdersPerAddressSet(uint256 newMax);
    /// @notice Emitted when escrow address is set
    event EscrowSet(address indexed escrow);
    /// @notice Emitted when project address is set
    event ProjectSet(address indexed project);

    /// @notice Initializes the order manager contract
    /// @param _escrow Escrow contract address
    /// @param _project Project contract address
    /// @param _admin Admin address for role assignment
    function initialize(address _escrow, address _project, address _admin) external;

    /// @notice Sets the maximum number of orders per address
    /// @param _maxOrders New maximum number of orders
    function setMaxOrdersPerAddress(uint256 _maxOrders) external;

    /// @notice Sets the escrow contract address
    /// @param _escrow New escrow contract address
    function setEscrow(address _escrow) external;

    /// @notice Sets the project contract address
    /// @param _project New project contract address
    function setProject(address _project) external;

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
    ) external payable;

    /// @notice Cancels an existing order
    /// @param orderId Order identifier
    function cancelOrder(bytes32 orderId) external;

    /// @notice Finalizes an order by minting or transferring tokens
    /// @param orderId Order identifier
    function finalizeOrder(bytes32 orderId) external;

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Returns order details
    /// @param orderId Order identifier
    /// @return Order details
    function getOrder(bytes32 orderId) external view returns (Order memory);

    /// @notice Returns orders for an address
    /// @param investor Investor address
    /// @return Array of order IDs
    function getOrdersByAddress(address investor) external view returns (bytes32[] memory);
}