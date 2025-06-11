// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./Interfaces/IOwnmali_Interfaces.sol";
import "./Ownmali_Validation.sol";

/// @title AssetManager
/// @notice Manages token-related operations (minting, transferring, locking, releasing) for an SPV in the Ownmali ecosystem
/// @dev Interacts with order manager and IOwnmaliAsset token contract for asset operations
contract OwnmaliAssetManager is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    IOwnmaliAssetManager
{
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidAmount(uint256 amount, string parameter);
    error UnauthorizedCaller(address caller);
    error TokenOperationFailed(string operation);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    address public projectOwner;
    address public project;
    address public orderManager;
    address public daoContract;
    address public tokenContract; // Address of the IOwnmaliAsset token contract
    bytes32 public spvId;
    bytes32 public assetId;

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function calls to the SPV-level DAO contract
    modifier onlyDao() {
        if (msg.sender != daoContract) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /// @notice Restricts function calls to the order manager
    modifier onlyOrderManager() {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        _;
    }

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the asset manager contract
    /// @param _projectOwner Project owner address
    /// @param _project Project contract address
    /// @param _spvId SPV identifier
    /// @param _assetId Asset identifier
    /// @param _daoContract SPV-level DAO contract address
    /// @param _tokenContract IOwnmaliAsset token contract address
    function initialize(
        address _projectOwner,
        address _project,
        bytes32 _spvId,
        bytes32 _assetId,
        address _daoContract,
        address _tokenContract
    ) public initializer {
        if (_projectOwner == address(0)) revert InvalidAddress(_projectOwner, "projectOwner");
        if (_project == address(0)) revert InvalidAddress(_project, "project");
        if (_daoContract == address(0)) revert InvalidAddress(_daoContract, "daoContract");
        if (_tokenContract == address(0)) revert InvalidAddress(_tokenContract, "tokenContract");
        _spvId.validateId("spvId");
        _assetId.validateId("assetId");

        __UUPSUpgradeable_init();
        __Pausable_init();

        projectOwner = _projectOwner;
        project = _project;
        spvId = _spvId;
        assetId = _assetId;
        daoContract = _daoContract;
        tokenContract = _tokenContract;

        emit DaoContractSet(_daoContract);
        emit TokenContractSet(_tokenContract);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external onlyDao {
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager, "orderManager");
        orderManager = _orderManager;
        emit OrderManagerSet(_orderManager);
    }

    /// @notice Sets the SPV-level DAO contract address
    /// @param _daoContract New DAO contract address
    function setDaoContract(address _daoContract) external onlyDao {
        if (_daoContract == address(0)) revert InvalidAddress(_daoContract, "daoContract");
        daoContract = _daoContract;
        emit DaoContractSet(_daoContract);
    }

    /// @notice Sets the token contract address
    /// @param _tokenContract New IOwnmaliAsset token contract address
    function setTokenContract(address _tokenContract) external onlyDao {
        if (_tokenContract == address(0)) revert InvalidAddress(_tokenContract, "tokenContract");
        tokenContract = _tokenContract;
        emit TokenContractSet(_tokenContract);
    }

    /// @notice Mints tokens to a recipient (called by order manager)
    /// @param recipient Recipient address
    /// @param amount Token amount
    function mintTokens(address recipient, uint256 amount) external onlyOrderManager whenNotPaused {
        if (recipient == address(0)) revert InvalidAddress(recipient, "recipient");
        if (amount == 0) revert InvalidAmount(amount, "amount");

        try IOwnmaliAsset(tokenContract).mint(recipient, amount) {
            emit TokensMinted(recipient, amount);
        } catch {
            revert TokenOperationFailed("mint");
        }
    }

    /// @notice Transfers tokens from sender to recipient (called by order manager)
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Token amount
    function transferTokens(address from, address to, uint256 amount) external onlyOrderManager whenNotPaused {
        if (from == address(0)) revert InvalidAddress(from, "from");
        if (to == address(0)) revert InvalidAddress(to, "to");
        if (amount == 0) revert InvalidAmount(amount, "amount");

        bool success = IERC20Upgradeable(tokenContract).transferFrom(from, to, amount);
        if (!success) revert TokenOperationFailed("transfer");

        emit TokensTransferred(from, to, amount);
    }

    /// @notice Locks tokens for an account (called by order manager)
    /// @param account Account address
    /// @param amount Token amount
    function lockTokens(address account, uint256 amount) external onlyOrderManager whenNotPaused {
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (amount == 0) revert InvalidAmount(amount, "amount");

        // Assume lock period is managed by IOwnmaliAsset; use current block timestamp + default period
        uint256 unlockTime = block.timestamp + 365 days; // Example: 1-year lock
        try IOwnmaliAsset(tokenContract).lock(account, amount, unlockTime) {
            emit TokensLocked(account, amount);
        } catch {
            revert TokenOperationFailed("lock");
        }
    }

    /// @notice Releases locked tokens for an account (called by order manager)
    /// @param account Account address
    /// @param amount Token amount
    function releaseTokens(address account, uint256 amount) external onlyOrderManager whenNotPaused {
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (amount == 0) revert InvalidAmount(amount, "amount");

        try IOwnmaliAsset(tokenContract).unlock(account, amount) {
            emit TokensReleased(account, amount);
        } catch {
            revert TokenOperationFailed("release");
        }
    }

    /// @notice Pauses the contract
    function pause() external onlyDao {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyDao {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyDao view {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }
}