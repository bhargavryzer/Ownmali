// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IOwnmaliAsset is IERC20Upgradeable, IERC20MetadataUpgradeable {
    struct AssetInitParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        address projectOwner;
        address factory;
        bytes32 spvId;
        bytes32 assetId;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        bytes32 assetType;
        uint256 dividendPct;
        uint256 premintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint16 chainId;
        uint256 eoiPct;
        address identityRegistry;
        address compliance;
    }

    function initialize(AssetInitParams memory params) external;
    function setAssetContractsAndPreMint(
        address assetManager,
        address financialLedger,
        address orderManager,
        address spvDao,
        uint256 premintAmount
    ) external;
    function mint(address to, uint256 amount) external;
    function lock(address account, uint256 amount, uint256 unlockTime) external;
    function unlock(address account, uint256 amount) external;
    function updateMetadata(bytes32 newCID, bool isLegal) external;
    function setActive(bool isActive) external;
    function pause() external;
    function unpause() external;
    function lockedUntil(address account) external view returns (uint256);
    function isActive() external view returns (bool);
}


interface IOwnmaliOrderManager {
    function initialize(address financialLedger, address asset, address projectOwner) external;
    function pause() external;
    function unpause() external;
}

interface IOwnmaliSPVDAO {
    function initialize(address projectOwner, address asset, bytes32 spvId, bytes32 assetId) external;
    function pause() external;
    function unpause() external;
}


interface IOwnmaliAssetManager {
    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event TokensMinted(address indexed recipient, uint256 amountOrId);
    event TokensTransferred(address indexed from, address indexed to, uint256 amountOrId);
    event TokensLocked(address indexed account, uint256 amountOrId);
    event TokensReleased(address indexed account, uint256 amountOrId);
    event OrderManagerSet(address indexed orderManager);
    event DaoContractSet(address indexed daoContract);
    event TokenContractSet(address indexed tokenContract);

    /*//////////////////////////////////////////////////////////////
                             FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the asset manager contract
    /// @param _projectOwner Project owner address
    /// @param _project Project contract address
    /// @param _spvId SPV identifier
    /// @param _assetId Asset identifier
    /// @param _daoContract SPV-level DAO contract address
    /// @param _tokenContract Token contract address
    function initialize(
        address _projectOwner,
        address _project,
        bytes32 _spvId,
        bytes32 _assetId,
        address _daoContract,
        address _tokenContract
    ) external;

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external;

    /// @notice Sets the SPV-level DAO contract address
    /// @param _daoContract New DAO contract address
    function setDaoContract(address _daoContract) external;

    /// @notice Sets the token contract address
    /// @param _tokenContract New token contract address
    function setTokenContract(address _tokenContract) external;

    /// @notice Mints tokens to a recipient
    /// @param recipient Recipient address
    /// @param amountOrId Token amount (ERC-20) or token ID (ERC-721)
    function mintTokens(address recipient, uint256 amountOrId) external;

    /// @notice Transfers tokens from sender to recipient
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amountOrId Token amount (ERC-20) or token ID (ERC-721)
    function transferTokens(address from, address to, uint256 amountOrId) external;

    /// @notice Locks tokens for an account
    /// @param account Account address
    /// @param amountOrId Token amount (ERC-20) or token ID (ERC-721)
    function lockTokens(address account, uint256 amountOrId) external;

    /// @notice Releases locked tokens for an account
    /// @param account Account address
    /// @param amountOrId Token amount (ERC-20) or token ID (ERC-721)
    function releaseTokens(address account, uint256 amountOrId) external;

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;
}

/// @title IFinancialLedger
/// @notice Interface for the FinancialLedger contract, managing ETH transactions and logging for an SPV
interface IOwnmaliFinancialLedger {
    /*//////////////////////////////////////////////////////////////
                             STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct Transaction {
        address sender;
        address recipient;
        uint256 amount;
        uint256 timestamp;
        string transactionType; // e.g., "Deposit", "Transfer", "EmergencyWithdrawal"
    }

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event FundsDeposited(address indexed sender, uint256 amount);
    event FundsTransferred(address indexed recipient, uint256 amount);
    event FundsTransferredToOwner(address indexed owner, uint256 amount);
    event EmergencyWithdrawal(address indexed recipient, uint256 amount);
    event MaxWithdrawalsPerTxSet(uint256 newMax);
    event OrderManagerSet(address indexed orderManager);
    event DaoContractSet(address indexed daoContract);

    /*//////////////////////////////////////////////////////////////
                             FUNCTIONS
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
    ) external;

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external;

    /// @notice Sets the SPV-level DAO contract address
    /// @param _daoContract New DAO contract address
    function setDaoContract(address _daoContract) external;

    /// @notice Sets the maximum number of withdrawals per transaction
    /// @param _maxWithdrawals New maximum number of withdrawals
    function setMaxWithdrawalsPerTx(uint256 _maxWithdrawals) external;

    /// @notice Transfers ETH to a recipient
    /// @param recipient Recipient address
    /// @param amount Amount in wei
    function transferTo(address recipient, uint256 amount) external;

    /// @notice Transfers ETH to the project owner
    /// @param amount Amount in wei
    function transferToOwner(uint256 amount) external;

    /// @notice Performs an emergency withdrawal of ETH to multiple recipients
    /// @param recipients Array of recipient addresses
    /// @param amounts Array of amounts in wei
    function emergencyWithdrawal(address[] calldata recipients, uint256[] calldata amounts) external;

    /// @notice Pauses the contract
    function pause() external;

    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Returns the current ETH balance of the ledger
    /// @return Balance in wei
    function getBalance() external view returns (uint256);

    /// @notice Returns the transaction log
    /// @return Array of transactions
    function getTransactionLog() external view returns (Transaction[] memory);
}