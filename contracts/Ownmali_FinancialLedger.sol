// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title FinancialLedger
/// @notice Records fiat-based offline transactions and ERC-3643 token transactions for an SPV in the Ownmali ecosystem.
/// @dev Stores immutable transaction logs for investor orders, with pausable and upgradeable functionality. Uses UUPS proxy pattern for upgrades.
///      Storage layout must be preserved across upgrades to prevent data corruption.
contract FinancialLedger is
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
    /// @notice Enum for supported fiat currencies to optimize storage.
    enum Currency { USD, EUR, GBP, JPY }

    /// @notice Enum for transaction types to optimize storage.
    enum TransactionType { Investment, Refund, Purchase, Redemption }

    /// @notice Struct for fiat-based offline transactions.
    struct FiatTransaction {
        address investor; // Investor address
        bytes32 orderId; // Unique order identifier
        uint256 amount; // Amount in smallest fiat unit (e.g., cents for USD)
        Currency currency; // Fiat currency
        TransactionType transactionType; // Transaction type
        bytes32 referenceId; // External reference (e.g., bank transaction ID)
        uint256 timestamp; // Transaction timestamp
    }

    /// @notice Struct for ERC-3643 token transactions.
    struct TokenTransaction {
        address investor; // Investor address
        bytes32 orderId; // Unique order identifier
        address tokenContract; // ERC-3643 token contract address
        uint256 amount; // Token amount in smallest unit
        TransactionType transactionType; // Transaction type
        bytes32 referenceId; // External reference (e.g., compliance ID)
        uint256 timestamp; // Transaction timestamp
    }

    /// @notice Struct for pending critical updates with timelock.
    struct PendingUpdate {
        address newAddress; // New address for update
        uint48 unlockTime; // Timestamp when update can be executed
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Duration for timelock on critical updates (1 day).
    uint48 public constant TIMELOCK_DURATION = 1 days;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Address of the project owner.
    address public projectOwner;

    /// @notice Address of the order manager contract.
    address public orderManager;

    /// @notice Address of the SPV-level DAO contract.
    address public daoContract;

    /// @notice Unique identifier for the SPV.
    bytes32 public spvId;

    /// @notice Unique identifier for the associated asset.
    bytes32 public assetId;

    /// @notice Log of fiat transactions.
    FiatTransaction[] public fiatTransactionLog;

    /// @notice Log of token transactions.
    TokenTransaction[] public tokenTransactionLog;

    /// @notice Pending update for order manager address.
    PendingUpdate public pendingOrderManagerUpdate;

    /// @notice Pending update for DAO contract address.
    PendingUpdate public pendingDaoContractUpdate;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when the order manager address is updated.
    event OrderManagerSet(address indexed orderManager);

    /// @notice Emitted when the DAO contract address is updated.
    event DaoContractSet(address indexed daoContract);

    /// @notice Emitted when a fiat transaction is recorded.
    event FiatTransactionRecorded(
        address indexed investor,
        bytes32 indexed orderId,
        uint256 amount,
        Currency currency,
        TransactionType transactionType,
        bytes32 referenceId
    );

    /// @notice Emitted when a token transaction is recorded.
    event TokenTransactionRecorded(
        address indexed investor,
        bytes32 indexed orderId,
        address indexed tokenContract,
        uint256 amount,
        TransactionType transactionType,
        bytes32 referenceId
    );

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/
    /// @notice Restricts function calls to the SPV-level DAO contract.
    modifier onlyDao() {
        if (msg.sender != daoContract) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /// @notice Restricts function calls to the order manager contract.
    modifier onlyOrderManager() {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the financial ledger contract.
    /// @dev Sets initial state variables and initializes inherited contracts. Only callable once.
    /// @param _projectOwner Address of the project owner.
    /// @param _spvId Unique SPV identifier.
    /// @param _assetId Unique asset identifier.
    /// @param _daoContract Address of the SPV-level DAO contract.
    function initialize(
        address _projectOwner,
        bytes32 _spvId,
        bytes32 _assetId,
        address _daoContract
    ) external initializer {
        if (_projectOwner == address(0)) revert InvalidAddress(_projectOwner, "projectOwner");
        if (_daoContract == address(0)) revert InvalidAddress(_daoContract, "daoContract");
        if (_spvId == bytes32(0)) revert InvalidParameter("spvId", "zero");
        if (_assetId == bytes32(0)) revert InvalidParameter("assetId", "zero");

        __UUPSUpgradeable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        projectOwner = _projectOwner;
        spvId = _spvId;
        assetId = _assetId;
        daoContract = _daoContract;

        emit DaoContractSet(_daoContract);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Proposes or executes an update to the order manager address with a timelock.
    /// @dev Requires two calls: first to propose, second to execute after timelock expires.
    /// @param _orderManager New order manager address.
    function setOrderManager(address _orderManager) external onlyDao {
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager, "orderManager");

        bytes32 actionId = keccak256(abi.encode(_orderManager));
        if (pendingOrderManagerUpdate.newAddress != _orderManager) {
            pendingOrderManagerUpdate = PendingUpdate({
                newAddress: _orderManager,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingOrderManagerUpdate.unlockTime) {
            revert TimelockNotExpired(pendingOrderManagerUpdate.unlockTime);
        }

        orderManager = _orderManager;
        delete pendingOrderManagerUpdate;
        emit OrderManagerSet(_orderManager);
    }

    /// @notice Proposes or executes an update to the DAO contract address with a timelock.
    /// @dev Requires two calls: first to propose, second to execute after timelock expires.
    /// @param _daoContract New DAO contract address.
    function setDaoContract(address _daoContract) external onlyDao {
        if (_daoContract == address(0)) revert InvalidAddress(_daoContract, "daoContract");

        bytes32 actionId = keccak256(abi.encode(_daoContract));
        if (pendingDaoContractUpdate.newAddress != _daoContract) {
            pendingDaoContractUpdate = PendingUpdate({
                newAddress: _daoContract,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingDaoContractUpdate.unlockTime) {
            revert TimelockNotExpired(pendingDaoContractUpdate.unlockTime);
        }

        daoContract = _daoContract;
        delete pendingDaoContractUpdate;
        emit DaoContractSet(_daoContract);
    }

    /// @notice Records a single fiat-based offline transaction for an investor order.
    /// @dev Only callable by the order manager. Stores transaction in fiatTransactionLog.
    /// @param investor Investor address.
    /// @param orderId Unique order identifier.
    /// @param amount Amount in smallest fiat unit (e.g., cents for USD).
    /// @param currency Fiat currency (USD, EUR, GBP, JPY).
    /// @param transactionType Type of transaction (Investment, Refund).
    /// @param referenceId External reference (e.g., bank transaction ID).
    function recordFiatTransaction(
        address investor,
        bytes32 orderId,
        uint256 amount,
        Currency currency,
        TransactionType transactionType,
        bytes32 referenceId
    ) external onlyOrderManager whenNotPaused nonReentrant {
        _validateFiatTransaction(investor, orderId, amount, transactionType);

        fiatTransactionLog.push(FiatTransaction({
            investor: investor,
            orderId: orderId,
            amount: amount,
            currency: currency,
            transactionType: transactionType,
            referenceId: referenceId,
            timestamp: block.timestamp
        }));

        emit FiatTransactionRecorded(investor, orderId, amount, currency, transactionType, referenceId);
    }

    /// @notice Records multiple fiat-based offline transactions in a single call.
    /// @dev Only callable by the order manager. Optimizes gas for bulk recording.
    /// @param investors Array of investor addresses.
    /// @param orderIds Array of unique order identifiers.
    /// @param amounts Array of amounts in smallest fiat unit.
    /// @param currencies Array of fiat currencies.
    /// @param transactionTypes Array of transaction types.
    /// @param referenceIds Array of external references.
    function recordBatchFiatTransactions(
        address[] calldata investors,
        bytes32[] calldata orderIds,
        uint256[] calldata amounts,
        Currency[] calldata currencies,
        TransactionType[] calldata transactionTypes,
        bytes32[] calldata referenceIds
    ) external onlyOrderManager whenNotPaused nonReentrant {
        if (investors.length != orderIds.length ||
            investors.length != amounts.length ||
            investors.length != currencies.length ||
            investors.length != transactionTypes.length ||
            investors.length != referenceIds.length) {
            revert InvalidParameter("array length", "mismatch");
        }
        if (investors.length == 0) revert InvalidParameter("array length", "empty");

        for (uint256 i = 0; i < investors.length; i++) {
            _validateFiatTransaction(investors[i], orderIds[i], amounts[i], transactionTypes[i]);

            fiatTransactionLog.push(FiatTransaction({
                investor: investors[i],
                orderId: orderIds[i],
                amount: amounts[i],
                currency: currencies[i],
                transactionType: transactionTypes[i],
                referenceId: referenceIds[i],
                timestamp: block.timestamp
            }));

            emit FiatTransactionRecorded(
                investors[i],
                orderIds[i],
                amounts[i],
                currencies[i],
                transactionTypes[i],
                referenceIds[i]
            );
        }
    }

    /// @notice Records a single ERC-3643 token transaction for an investor order.
    /// @dev Only callable by the order manager. Stores transaction in tokenTransactionLog.
    /// @param investor Investor address.
    /// @param orderId Unique order identifier.
    /// @param tokenContract ERC-3643 token contract address.
    /// @param amount Token amount in smallest unit.
    /// @param transactionType Type of transaction (Purchase, Redemption).
    /// @param referenceId External reference (e.g., compliance ID).
    function recordTokenTransaction(
        address investor,
        bytes32 orderId,
        address tokenContract,
        uint256 amount,
        TransactionType transactionType,
        bytes32 referenceId
    ) external onlyOrderManager whenNotPaused nonReentrant {
        _validateTokenTransaction(investor, orderId, tokenContract, amount, transactionType);

        tokenTransactionLog.push(TokenTransaction({
            investor: investor,
            orderId: orderId,
            tokenContract: tokenContract,
            amount: amount,
            transactionType: transactionType,
            referenceId: referenceId,
            timestamp: block.timestamp
        }));

        emit TokenTransactionRecorded(investor, orderId, tokenContract, amount, transactionType, referenceId);
    }

    /// @notice Records multiple ERC-3643 token transactions in a single call.
    /// @dev Only callable by the order manager. Optimizes gas for bulk recording.
    /// @param investors Array of investor addresses.
    /// @param orderIds Array of unique order identifiers.
    /// @param tokenContracts Array of ERC-3643 token contract addresses.
    /// @param amounts Array of token amounts.
    /// @param transactionTypes Array of transaction types.
    /// @param referenceIds Array of reference IDs.
    function recordBatchTokenTransactions(
        address[] calldata investors,
        bytes32[] calldata orderIds,
        address[] calldata tokenContracts,
        uint256[] calldata amounts,
        TransactionType[] calldata transactionTypes,
        bytes32[] calldata referenceIds
    ) external onlyOrderManager whenNotPaused nonReentrant {
        if (investors.length != orderIds.length ||
            investors.length != tokenContracts.length ||
            investors.length != amounts.length ||
            investors.length != transactionTypes.length ||
            investors.length != referenceIds.length) {
            revert InvalidParameter("array length", "invalid");
        }
        if (investors.length == 0) revert InvalidParameter("amounts", "zero amounts");

        for (uint256 i = 0; i < investors.length; i++) {
            validateTokenTransaction(
                investors[i],
                orderIds[i],
                tokenContracts[i],
                amounts[i],
                transactionTypes[i]
            );

            tokenTransactionLog.push(TokenTransaction({
                investor: investors[i],
                orderId: orderIds[i],
                tokenContract: tokenContracts[i],
                amount: amounts[i],
                transactionType: transactionTypes[i],
                referenceId: referenceIds[i],
                timestamp: block.timestamp
            }));

            emit TokenTransactionRecorded(
                investors[i],
                orderIds[i],
                tokenContracts[i],
                amounts[i],
                transactionTypes[i],
                referenceIds[i]
            );
        }
    }

    /// @notice Pauses the contract, preventing new transaction recordings.
    /// @dev Only callable by the DAO contract.
    function pause() external onlyDao {
        _pause();
    }

    /// @notice Unpauses the contract, allowing new transaction recordings.
    /// @dev Only callable by the DAO contract.
    function unpause() external onlyDao {
        _unpause();
    }

    /*///////////////////////////////////////////////////////
    //                   EXTERNAL VIEW FUNCTIONS
    /**
     * @notice Retrieves the fiat transaction log.
     * @dev Returns the entire fiat transaction log. Consider pagination for large logs in production.
     * @return Array of fiat transactions
     */
    function getFiatTransactionLog() external view returns (FiatTransaction[] memory) {
        return fiatTransactionLog;
    }

    /**
     * @notice Retrieves the token transaction log.
     * @dev Returns the entire token transaction log. Consider pagination for large logs in production.
     * @return Array of token transactions
     */
    function getTokenTransactionLog() external view returns (TokenTransaction[] memory) {
        return tokenTransactionLog;
    }

    /*///////////////////////////////////////////////////////
    //                   INTERNAL FUNCTIONS
    ///////////////////////////////////////////////////////
    /**
     * @notice Validates parameters for a fiat transaction.
     * @dev Internal function to reduce code duplication.
     * @param investor Investor address.
     * @param orderId Unique order identifier.
     * @param amount Amount in fiat (smallest unit).
     * @param transactionType Transaction type.
     */
    function _validateFiatTransaction(
        address investor,
        bytes32 orderId,
        uint256 amount,
        TransactionType transactionType
    ) private pure {
        if (investor == address(0)) revert InvalidAddress(investor, "investor");
        if (orderId == bytes32(0)) revert InvalidParameter("orderId");
, "zero");
        if (amount == ==0) revert InvalidAmount(amount);
, "amount amount");
        if (uint8(transactionType) > uint8(TransactionType.RefractionType.Refraction)) {
            revert InvalidParameter("transactionType", "invalid");
        }
    }

    /**
     * @notice Validates parameters for a token transaction.
     * @dev Internal function to reduce code duplication.
     * @param investor Investor address.
     * @param orderId Address.
     * @param tokenContract Token contract address.
     * @param amount Token amount.
     * @param transactionType Transaction type
     */
    function _validateTokenTransaction(
        address investor,
        bytes32 orderId,
        address tokenContract,
        uint256 amount,
        TransactionType transactionType,
    ) private pure {
        if (investor == address(0)) revert InvalidAddress(investor, "investor");
        investor);
    if (orderId == bytes32(0)) revert InvalidParameter("orderId", "zero");
        order_id);
    if (tokenContract == address(0)) revert InvalidAddress(tokenContract, "tokenContract");
        tokenContract);
    if (amount == 0) revert InvalidAmount(amount, "amount");
        amount);
    if (uint8(transactionType) > uint8(TransactionType.Redemption)) revert InvalidParameter("transactionType", "invalid");
    }

    /// @notice Authorizes contract upgrades.
    /// @dev Only callable by the DAO contract. Ensures non-zero address for new implementation.
    /// @param newImplementation Address of the new implementation contract.
    function _authorizeUpgrade(address newImplementation) internal override onlyDao view {
        if (newImplementation == address(0)) revert InvalidAddress(newImplementation, "newImplementation");
    }
}