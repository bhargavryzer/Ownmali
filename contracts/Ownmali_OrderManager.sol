// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title OwnmaliOrderManager
/// @notice Manages buy and sell orders for tokenized assets in the Ownmali ecosystem without payments or fees.
/// @dev Processes orders in a single transaction, validating transactions, generating order IDs, and transferring tokens.
///      Integrates with FinancialLedger for token transaction recording and AssetManager for token operations.
///      Uses UUPS proxy pattern for upgrades. Storage layout must be preserved across upgrades.
///      Buy orders mint tokens to the investor; sell orders transfer tokens to a specified buyer.
contract OwnmaliOrderManager is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidAmount(uint256 amount, string parameter);
    error InvalidId(bytes32 id, string parameter);
    error OrderAlreadyExists(bytes32 orderId);
    error InvalidOrderType(uint8 orderType);
    error TimelockNotExpired(uint48 unlockTime);
    error TransactionNotValid(address investor, address buyer, uint256 amount);
    error TokenOperationFailed(string operation);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Enum for order types.
    enum OrderType { Buy, Sell }

    /// @notice Struct for order transaction details.
    struct Order {
        bytes32 orderId; // Unique order identifier
        address investor; // Investor address
        address buyer; // Buyer for sell orders (zero address for buy orders)
        OrderType type; // Buy or Sell
        uint256 amount; // Number of tokens (in wei)
        bytes32 companyId; // Optional reference identifier for company
        bytes32 assetId; // Optional reference identifier for asset
        uint256 timestamp; // Execution timestamp
    }

    /// @notice Struct for pending critical updates with timelock.
    struct PendingUpdate {
        address newAddress; // New address
        bytes32 role; // Role for role updates (0 for contract updates)
        bool grant; // True for grant, false for revoke
        uint48 unlockTime; // Timestamp for execution
    }

    /// @notice Interface for FinancialLedger contract (token transactions only).
    interface IOwnmaliFinancialLedger {
        function recordTokenTransaction(
            address investor,
            bytes32 orderId,
            address tokenContract,
            uint256 amount,
            uint8 transactionType,
            bytes32 referenceId
        ) external;
    }

    /// @notice Interface for AssetManager contract.
    interface IOwnmaliAssetManager {
        function mintTokens(address to, uint256 amount) external;
        function transferTokens(address from, address to, uint256 amount) external;
        function getBalance(address account) external view returns (uint256);
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Duration for timelock on critical updates (1 day).
    uint48 public constant TIMELOCK_DURATION = 1 days;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Role for managing orders.
    bytes32 public constant ORDER_MANAGER_ROLE = keccak256("ORDER_MANAGER_ROLE");

    /// @notice FinancialLedger contract for token transaction recording.
    IOwnmaliFinancialLedger public financialLedger;

    /// @notice AssetManager contract for token operations.
    IOwnmaliAssetManager public assetManager;

    /// @notice Log of executed order transactions.
    Order[] public orderLog;

    /// @notice Mapping of order ID to existence flag to prevent duplicates.
    mapping(bytes32 => bool) public orderExists;

    /// @notice Pending critical updates (contract addresses or roles).
    mapping(bytes32 => PendingUpdate) public pendingUpdates;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    /// @notice Emitted when an order is executed.
    event OrderDetails(
        bytes32 indexed orderId,
        address indexed investor,
        address indexed buyer,
        OrderType type,
        uint256 amount,
        bytes32 companyId,
        bytes32 assetId
    );

    /// @notice Emitted when the financial ledger address is set.
    event FinancialLedgerSet(address indexed financialLedger);

    /// @notice Emitted when the asset manager address is set.
    event AssetManagerSet(address indexed assetManager);

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @notice Restricts function calls to the admin role.
    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the order manager contract.
    /// @dev Sets initial configuration and roles. Only callable once.
    /// @param _financialLedger FinancialLedger contract address.
    /// @param _assetManager AssetManager contract address.
    /// @param _admin Admin address for role assignment.
    /// @param _orderManager Address for order management role.
    function initialize(
        address _financialLedger,
        address _assetManager,
        address _admin,
        address _orderManager
    ) external initializer {
        if (_financialLedger == address(0)) revert InvalidAddress(_financialLedger, "financialLedger");
        if (_assetManager == address(0)) revert InvalidAddress(_assetManager, "assetManager");
        if (_admin == address(0)) revert InvalidAddress(_admin, "admin");
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager, "orderManager");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        financialLedger = IOwnmaliFinancialLedger(_financialLedger);
        assetManager = IOwnmaliAssetManager(_assetManager);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ORDER_MANAGER_ROLE, _orderManager);
        _setRoleAdmin(ORDER_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);

        emit FinancialLedgerSet(_financialLedger);
        emit AssetManagerSet(_assetManager);
    }

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Proposes or executes an update to the financial ledger address with a timelock.
    /// @dev Requires two calls: first to propose, second to execute after timelock. Only callable by admin.
    /// @param _financialLedger New financial ledger address.
    function setFinancialLedger(address _financialLedger) external onlyAdmin {
        if (_financialLedger == address(0)) revert InvalidAddress(_financialLedger, "financialLedger");

        bytes32 actionId = keccak256(abi.encode("financialLedger", _financialLedger));
        if (pendingUpdates[actionId].newAddress != _financialLedger) {
            pendingUpdates[actionId] = PendingUpdate({
                newAddress: _financialLedger,
                role: bytes32(0),
                grant: false,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        financialLedger = IOwnmaliFinancialLedger(_financialLedger);
        delete pendingUpdates[actionId];
        emit FinancialLedgerSet(_financialLedger);
    }

    /// @notice Proposes or executes an update to the asset manager address with a timelock.
    /// @dev Requires two calls: first to propose, second to execute after timelock. Only callable by admin.
    /// @param _assetManager New asset manager address.
    function setAssetManager(address _assetManager) external onlyAdmin {
        if (_assetManager == address(0)) revert InvalidAddress(_assetManager, "assetManager");

        bytes32 actionId = keccak256(abi.encode("assetManager", _assetManager));
        if (pendingUpdates[actionId].newAddress != _assetManager) {
            pendingUpdates[actionId] = PendingUpdate({
                newAddress: _assetManager,
                role: bytes32(0),
                grant: false,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        assetManager = IOwnmaliAssetManager(_assetManager);
        delete pendingUpdates[actionId];
        emit AssetManagerSet(_assetManager);
    }

    /// @notice Proposes or executes granting/revoking the ORDER_MANAGER_ROLE with a timelock.
    /// @dev Requires two calls: first to propose, second to execute after timelock. Only callable by admin.
    /// @param account Address to update.
    /// @param grant True to grant, false to revoke.
    function setOrderManagerRole(address account, bool grant) external onlyAdmin {
        if (account == address(0)) revert InvalidAddress(account, "account");

        bytes32 actionId = keccak256(abi.encode("orderManagerRole", account, grant));
        if (pendingUpdates[actionId].newAddress != account) {
            pendingUpdates[actionId] = PendingUpdate({
                newAddress: account,
                role: ORDER_MANAGER_ROLE,
                grant: grant,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        if (grant) {
            _grantRole(ORDER_MANAGER_ROLE, account);
        } else {
            _revokeRole(ORDER_MANAGER_ROLE, account);
        }
        delete pendingUpdates[actionId];
    }

    /// @notice Revokes the admin role from an account.
    /// @dev Only callable by admin. Allows removing admin privileges for security.
    /// @param account Address to revoke admin role from.
    function revokeAdminRole(address account) external onlyAdmin {
        if (account == address(0)) revert InvalidAddress(account, "account");
        _revokeRole(DEFAULT_ADMIN_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////
                           ORDER MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Places and executes a buy or sell order for tokens.
    /// @dev Validates transaction, generates order ID, records transaction, and transfers tokens.
    ///      Only callable by ORDER_MANAGER_ROLE. Buy orders mint tokens; sell orders transfer tokens.
    /// @param investor Investor address.
    /// @param buyer Buyer address for sell orders (ignored for buy orders).
    /// @param orderType Buy or Sell.
    /// @param amount Number of tokens (in wei).
    /// @param companyId Optional company identifier for logging.
    /// @param assetId Optional asset identifier for logging.
    /// @return orderId Generated order identifier.
    function placeOrder(
        address investor,
        address buyer,
        OrderType orderType,
        uint256 amount,
        bytes32 companyId,
        bytes32 assetId
    ) external onlyRole(ORDER_MANAGER_ROLE) whenNotPaused nonReentrant returns (bytes32 orderId) {
        _validateOrderInputs(investor, buyer, orderType, amount, companyId, assetId);

        // Generate unique order ID
        orderId = keccak256(abi.encode(investor, buyer, orderType, amount, block.timestamp));
        if (orderExists[orderId]) revert OrderAlreadyExists(orderId);

        // Validate transaction (validTx check)
        bool validTx = _isValidTransaction(investor, orderType == OrderType.Buy ? address(0) : buyer, amount);
        if (!validTx) {
            revert TransactionNotValid(investor, orderType == OrderType.Buy ? address(0) : buyer, amount);
        }

        // Record order in log
        orderLog.push(Order({
            orderId: orderId,
            investor: investor,
            buyer: orderType == OrderType.Buy ? address(0) : buyer,
            type: orderType,
            amount: amount,
            companyId: companyId,
            assetId: assetId,
            timestamp: block.timestamp
        }));
        orderExists[orderId] = true;

        // Process order
        if (orderType == OrderType.Buy) {
            assetManager.mintTokens(investor, amount);
            financialLedger.recordTokenTransaction(
                investor,
                orderId,
                address(assetManager),
                amount,
                uint8(2), // Purchase
                orderId
            );
        } else {
            assetManager.transferTokens(investor, buyer, amount);
            financialLedger.recordTokenTransaction(
                investor,
                orderId,
                address(assetManager),
                amount,
                uint8(3), // Redemption
                orderId
            );
        }

        emit OrderDetails(orderId, investor, orderType == OrderType.Buy ? address(0) : buyer, orderType, amount, companyId, assetId);
    }

    /// @notice Places multiple orders in a single transaction.
    /// @dev Optimizes gas for bulk orders. Only callable by ORDER_MANAGER_ROLE.
    /// @param investors Array of investor addresses.
    /// @param buyers Array of buyer addresses (ignored for buy orders).
    /// @param orderTypes Array of order types.
    /// @param amounts Array of token amounts.
    /// @param companyIds Array of company identifiers.
    /// @param assetIds Array of asset identifiers.
    /// @return orderIds Array of generated order identifiers.
    function placeBatchOrders(
        address[] calldata investors,
        address[] calldata buyers,
        OrderType[] calldata orderTypes,
        uint256[] calldata amounts,
        bytes32[] calldata companyIds,
        bytes32[] calldata assetIds
    ) external onlyRole(ORDER_MANAGER_ROLE) whenNotPaused nonReentrant returns (bytes32[] memory orderIds) {
        if (investors.length != buyers.length ||
            investors.length != orderTypes.length ||
            investors.length != amounts.length ||
            investors.length != companyIds.length ||
            investors.length != assetIds.length) {
            revert InvalidParameter("array length", "mismatch");
        }
        if (investors.length == 0) revert InvalidParameter("array length", "empty");

        orderIds = new bytes32[](investors.length);

        // Validate inputs and generate order IDs
        for (uint256 i = 0; i < investors.length; i++) {
            _validateOrderInputs(investors[i], buyers[i], orderTypes[i], amounts[i], companyIds[i], assetIds[i]);
            orderIds[i] = keccak256(abi.encode(investors[i], buyers[i], orderTypes[i], amounts[i], block.timestamp, i));
            if (orderExists[orderIds[i]]) revert OrderAlreadyExists(orderIds[i]);
        }

        // Process orders
        for (uint256 i = 0; i < investors.length; i++) {
            bool validTx = _isValidTransaction(
                investors[i],
                orderTypes[i] == OrderType.Buy ? address(0) : buyers[i],
                amounts[i]
            );
            if (!validTx) {
                revert TransactionNotValid(investors[i], orderTypes[i] == OrderType.Buy ? address(0) : buyers[i], amounts[i]);
            }

            orderLog.push(Order({
                orderId: orderIds[i],
                investor: investors[i],
                buyer: orderTypes[i] == OrderType.Buy ? address(0) : buyers[i],
                type: orderTypes[i],
                amount: amounts[i],
                companyId: companyIds[i],
                assetId: assetIds[i],
                timestamp: block.timestamp
            }));
            orderExists[orderIds[i]] = true;

            try {
                if (orderTypes[i] == OrderType.Buy) {
                    assetManager.mintTokens(investors[i], amounts[i]);
                    financialLedger.recordTokenTransaction(
                        investors[i],
                        orderIds[i],
                        address(assetManager),
                        amounts[i],
                        uint8(2), // Purchase
                        orderIds[i]
                    );
                } else {
                    assetManager.transferTokens(investors[i], buyers[i], amounts[i]);
                    financialLedger.recordTokenTransaction(
                        investors[i],
                        orderIds[i],
                        address(assetManager),
                        amounts[i],
                        uint8(3), // Redemption
                        orderIds[i]
                    );
                }
            } catch {
                revert TokenOperationFailed(orderTypes[i] == OrderType.Buy ? "mint" : "transfer");
            }

            emit OrderDetails(
                orderIds[i],
                investors[i],
                orderTypes[i] == OrderType.Buy ? address(0) : buyers[i],
                orderTypes[i],
                amounts[i],
                companyIds[i],
                assetIds[i]
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Returns the order transaction log.
    /// @dev Returns all executed orders. Consider pagination for large logs.
    /// @return Array of order transactions.
    function getOrderLog() external view returns (Order[] memory) {
        return orderLog;
    }

    /// @notice Checks if an order exists.
    /// @param orderId Order identifier.
    /// @return True if order exists.
    function doesOrderExist(bytes32 orderId) external view returns (bool) {
        return orderExists[orderId];
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Validates order input parameters.
    /// @dev Reverts on invalid inputs to ensure transaction integrity.
    /// @param investor Investor address.
    /// @param buyer Buyer address.
    /// @param orderType Order type.
    /// @param amount Token amount.
    /// @param companyId Company identifier.
    /// @param assetId Asset identifier.
    function _validateOrderInputs(
        address investor,
        address buyer,
        OrderType orderType,
        uint256 amount,
        bytes32 companyId,
        bytes32 assetId
    ) private pure {
        if (investor == address(0)) revert InvalidAddress(investor, "investor");
        if (orderType == OrderType.Sell && buyer == address(0)) {
            revert InvalidAddress(buyer, "buyer");
        }
        if (uint8(orderType) > uint8(OrderType.Sell)) revert InvalidOrderType(uint8(orderType));
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (companyId == bytes32(0)) revert InvalidId(companyId, "companyId");
        if (assetId == bytes32(0)) revert InvalidId(assetId, "assetId");
    }

    /// @notice Checks if a transaction is valid.
    /// @dev Queries AssetManager for investor balance for sell orders.
    /// @param investor Investor address.
    /// @param buyer Buyer address.
    /// @param amount Token amount.
    /// @return True if transaction is valid.
    function _isValidTransaction(address investor, address buyer, uint256 amount) private view returns (bool) {
        if (investor == address(0)) return false;
        if (investor == buyer) return false; // Prevent self-transfers
        if (amount == 0) return false;
        if (buyer != address(0)) { // Sell order
            uint256 balance = assetManager.getBalance(investor);
            if (balance < amount) return false;
        }
        return true;
    }

    /// @notice Authorizes contract upgrades.
    /// @dev Only callable by admin. Ensures non-zero address for new implementation.
    /// @param newImplementation Address of the new implementation contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {
        if (newImplementation == address(0)) revert InvalidAddress(newImplementation, "newImplementation");
    }
}