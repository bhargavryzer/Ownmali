// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./Ownmali_Validation.sol";

// Interface for IOwnmaliAsset - should be defined separately
interface IOwnmaliAsset {
    function mint(address to, uint256 amount) external;
    function lock(address account, uint256 amount, uint256 unlockTime) external;
    function unlock(address account, uint256 amount) external;
}

/// @title AssetManager
/// @notice Manages token-related operations (minting, transferring, locking, releasing) for an SPV in the Ownmali ecosystem
/// @dev Interacts with order manager and IOwnmaliAsset token contract for asset operations
contract OwnmaliAssetManager is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable
{
    using OwnmaliValidation for bytes32;

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidAmount(uint256 amount);
    error UnauthorizedCaller(address caller);
    error TokenOperationFailed(string operation);
    error InvalidImplementation();

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event OrderManagerSet(address indexed orderManager);
    event TokenContractSet(address indexed tokenContract);
    event TokensMinted(address indexed recipient, uint256 amount);
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);
    event TokensLocked(address indexed account, uint256 amount);
    event TokensReleased(address indexed account, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ORDER_MANAGER_ROLE = keccak256("ORDER_MANAGER_ROLE");
    
    address public projectOwner;
    address public project;
    address public orderManager;
    address public tokenContract;
    bytes32 public spvId;
    bytes32 public assetId;

    /*//////////////////////////////////////////////////////////////
                             MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts function calls to accounts with ORDER_MANAGER_ROLE
    modifier onlyOrderManager() {
        _checkRole(ORDER_MANAGER_ROLE);
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
    /// @param _admin Admin address that will have DEFAULT_ADMIN_ROLE
    /// @param _tokenContract IOwnmaliAsset token contract address
    function initialize(
        address _projectOwner,
        address _project,
        bytes32 _spvId,
        bytes32 _assetId,
        address _admin,
        address _tokenContract
    ) external initializer {
        if (_projectOwner == address(0)) revert InvalidAddress(_projectOwner);
        if (_project == address(0)) revert InvalidAddress(_project);
        if (_admin == address(0)) revert InvalidAddress(_admin);
        if (_tokenContract == address(0)) revert InvalidAddress(_tokenContract);
        
        _spvId.validateId("spvId");
        _assetId.validateId("assetId");

        __UUPSUpgradeable_init();
        __Pausable_init();
        __AccessControl_init();

        projectOwner = _projectOwner;
        project = _project;
        spvId = _spvId;
        assetId = _assetId;
        tokenContract = _tokenContract;

        // Grant DEFAULT_ADMIN_ROLE to the admin address
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        emit TokenContractSet(_tokenContract);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the order manager contract address and grants ORDER_MANAGER_ROLE
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager);
        
        // Revoke role from previous order manager if exists
        if (orderManager != address(0)) {
            _revokeRole(ORDER_MANAGER_ROLE, orderManager);
        }
        
        orderManager = _orderManager;
        _grantRole(ORDER_MANAGER_ROLE, _orderManager);
        emit OrderManagerSet(_orderManager);
    }

    /// @notice Sets the token contract address
    /// @param _tokenContract New IOwnmaliAsset token contract address
    function setTokenContract(address _tokenContract) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_tokenContract == address(0)) revert InvalidAddress(_tokenContract);
        tokenContract = _tokenContract;
        emit TokenContractSet(_tokenContract);
    }

    /// @notice Mints tokens to a recipient (called by order manager)
    /// @param recipient Recipient address
    /// @param amount Token amount
    function mintTokens(address recipient, uint256 amount) external onlyOrderManager whenNotPaused {
        if (recipient == address(0)) revert InvalidAddress(recipient);
        if (amount == 0) revert InvalidAmount(amount);

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
        if (from == address(0)) revert InvalidAddress(from);
        if (to == address(0)) revert InvalidAddress(to);
        if (amount == 0) revert InvalidAmount(amount);

        if (!IERC20Upgradeable(tokenContract).transferFrom(from, to, amount)) {
            revert TokenOperationFailed("transfer");
        }

        emit TokensTransferred(from, to, amount);
    }

    /// @notice Locks tokens for an account with specified unlock time
    /// @param account Account address
    /// @param amount Token amount
    /// @param unlockTime Timestamp when tokens can be unlocked
    function lockTokens(address account, uint256 amount, uint256 unlockTime) external onlyOrderManager whenNotPaused {
        if (account == address(0)) revert InvalidAddress(account);
        if (amount == 0) revert InvalidAmount(amount);
        if (unlockTime <= block.timestamp) revert InvalidAmount(unlockTime);

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
        if (account == address(0)) revert InvalidAddress(account);
        if (amount == 0) revert InvalidAmount(amount);

        try IOwnmaliAsset(tokenContract).unlock(account, amount) {
            emit TokensReleased(account, amount);
        } catch {
            revert TokenOperationFailed("release");
        }
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal view override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidImplementation();
        }
    }
}