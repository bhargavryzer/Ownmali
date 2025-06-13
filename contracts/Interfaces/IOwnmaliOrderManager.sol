// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title IOwnmaliOrderManager
/// @notice Interface for the OwnmaliOrderManager contract, managing buy and sell orders for tokenized assets in the Ownmali ecosystem.
interface IOwnmaliOrderManager is
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
    error UnauthorizedCaller(address caller);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum OrderType { Buy, Sell }

    struct Order {
        bytes32 orderId;
        address investor;
        address buyer;
        OrderType type;
        uint256 amount;
        bytes32 companyId;
        bytes32 assetId;
        uint256 timestamp;
    }

    struct PendingUpdate {
        address newAddress;
        bytes32 role;
        bool grant;
        uint48 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event OrderDetails(
        bytes32 indexed orderId,
        address indexed investor,
        address indexed buyer,
        OrderType type,
        uint256 amount,
        bytes32 companyId,
        bytes32 assetId
    );
    event FinancialLedgerSet(address indexed financialLedger);
    event AssetManagerSet(address indexed assetManager);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _financialLedger,
        address _assetManager,
        address _admin,
        address _orderManager
    ) external;

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setFinancialLedger(address _financialLedger) external;
    function setAssetManager(address _assetManager) external;
    function setOrderManagerRole(address account, bool grant) external;
    function revokeAdminRole(address account) external;

    /*//////////////////////////////////////////////////////////////
                           ORDER MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function placeOrder(
        address investor,
        address buyer,
        OrderType orderType,
        uint256 amount,
        bytes32 companyId,
        bytes32 assetId
    ) external returns (bytes32 orderId);
    function placeBatchOrders(
        address[] calldata investors,
        address[] calldata buyers,
        OrderType[] calldata orderTypes,
        uint256[] calldata amounts,
        bytes32[] calldata companyIds,
        bytes32[] calldata assetIds
    ) external returns (bytes32[] memory orderIds);

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getOrderLog() external view returns (Order[] memory);
    function doesOrderExist(bytes32 orderId) external view returns (bool);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function TIMELOCK_DURATION() external view returns (uint48);
    function ORDER_MANAGER_ROLE() external view returns (bytes32);
    function financialLedger() external view returns (address);
    function assetManager() external view returns (address);
    function orderLog(uint256 index) external view returns (Order memory);
    function orderExists(bytes32 orderId) external view returns (bool);
    function pendingUpdates(bytes32 actionId) external view returns (PendingUpdate memory);
}