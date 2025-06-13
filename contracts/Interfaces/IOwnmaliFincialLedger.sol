// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title IFinancialLedger
/// @notice Interface for the FinancialLedger contract, recording fiat-based and ERC-3643 token transactions for an SPV in the Ownmali ecosystem.
interface IFinancialLedger is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidAmount(uint256 amount, string parameter);
    error InvalidParameter(string parameter, string reason);
    error UnauthorizedCaller(address caller);
    error TimelockNotExpired(uint48 unlockTime);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum Currency { USD, EUR, GBP, JPY }
    enum TransactionType { Investment, Refund, Purchase, Redemption }

    struct FiatTransaction {
        address investor;
        bytes32 orderId;
        uint256 amount;
        Currency currency;
        TransactionType transactionType;
        bytes32 referenceId;
        uint256 timestamp;
    }

    struct TokenTransaction {
        address investor;
        bytes32 orderId;
        address tokenContract;
        uint256 amount;
        TransactionType transactionType;
        bytes32 referenceId;
        uint256 timestamp;
    }

    struct PendingUpdate {
        address newAddress;
        uint48 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                               EVENTS
    //////////////////////////////////////////////////////////////*/
    event OrderManagerSet(address indexed orderManager);
    event DaoContractSet(address indexed daoContract);
    event FiatTransactionRecorded(
        address indexed investor,
        bytes32 indexed orderId,
        uint256 amount,
        Currency currency,
        TransactionType transactionType,
        bytes32 referenceId
    );
    event TokenTransactionRecorded(
        address indexed investor,
        bytes32 indexed orderId,
        address indexed tokenContract,
        uint256 amount,
        TransactionType transactionType,
        bytes32 referenceId
    );

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _projectOwner,
        bytes32 _spvId,
        bytes32 _assetId,
        address _daoContract
    ) external;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setOrderManager(address _orderManager) external;
    function setDaoContract(address _daoContract) external;
    function recordFiatTransaction(
        address investor,
        bytes32 orderId,
        uint256 amount,
        Currency currency,
        TransactionType transactionType,
        bytes32 referenceId
    ) external;
    function recordBatchFiatTransactions(
        address[] calldata investors,
        bytes32[] calldata orderIds,
        uint256[] calldata amounts,
        Currency[] calldata currencies,
        TransactionType[] calldata transactionTypes,
        bytes32[] calldata referenceIds
    ) external;
    function recordTokenTransaction(
        address investor,
        bytes32 orderId,
        address tokenContract,
        uint256 amount,
        TransactionType transactionType,
        bytes32 referenceId
    ) external;
    function recordBatchTokenTransactions(
        address[] calldata investors,
        bytes32[] calldata orderIds,
        address[] calldata tokenContracts,
        uint256[] calldata amounts,
        TransactionType[] calldata transactionTypes,
        bytes32[] calldata referenceIds
    ) external;
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getFiatTransactionLog() external view returns (FiatTransaction[] memory);
    function getTokenTransactionLog() external view returns (TokenTransaction[] memory);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function TIMELOCK_DURATION() external view returns (uint48);
    function projectOwner() external view returns (address);
    function orderManager() external view returns (address);
    function daoContract() external view returns (address);
    function spvId() external view returns (bytes32);
    function assetId() external view returns (bytes32);
    function fiatTransactionLog(uint256 index) external view returns (FiatTransaction memory);
    function tokenTransactionLog(uint256 index) external view returns (TokenTransaction memory);
    function pendingOrderManagerUpdate() external view returns (PendingUpdate memory);
    function pendingDaoContractUpdate() external view returns (PendingUpdate memory);
}