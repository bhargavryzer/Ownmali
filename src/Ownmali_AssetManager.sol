// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./Ownmali_Interfaces.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliAssetManager
/// @notice Manages token-related operations (minting, transferring, locking, releasing) for Ownmali projects
/// @dev Interacts with ERC-3643 compliant project contract, upgradeable with role-based access control
contract OwnmaliAssetManager is
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
    error UnauthorizedCaller(address caller);
    error TokenOperationFailed(string operation);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

    address public projectOwner;
    address public project;
    address public orderManager;
    bytes32 public companyId;
    bytes32 public assetId;

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event TokensMinted(address indexed recipient, uint256 amount);
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);
    event TokensLocked(address indexed account, uint256 amount, uint256 unlockTime);
    event TokensReleased(address indexed account, uint256 amount);
    event OrderManagerSet(address indexed orderManager);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the asset manager contract
    /// @param _projectOwner Project owner address
    /// @param _project Project contract address (ERC-3643 compliant token)
    /// @param _companyId Company identifier
    /// @param _assetId Asset identifier
    function initialize(
        address _projectOwner,
        address _project,
        bytes32 _companyId,
        bytes32 _assetId
    ) public initializer {
        if (_projectOwner == address(0)) revert InvalidAddress(_projectOwner, "projectOwner");
        if (_project == address(0)) revert InvalidAddress(_project, "project");
        _companyId.validateId("companyId");
        _assetId.validateId("assetId");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        projectOwner = _projectOwner;
        project = _project;
        companyId = _companyId;
        assetId = _assetId;

        _grantRole(DEFAULT_ADMIN_ROLE, _projectOwner);
        _grantRole(ADMIN_ROLE, _projectOwner);
        _grantRole(ASSET_MANAGER_ROLE, _projectOwner);
        _setRoleAdmin(ASSET_MANAGER_ROLE, ADMIN_ROLE);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the order manager contract address
    /// @param _orderManager New order manager address
    function setOrderManager(address _orderManager) external onlyRole(ADMIN_ROLE) {
        if (_orderManager == address(0)) revert InvalidAddress(_orderManager, "orderManager");
        orderManager = _orderManager;
        emit OrderManagerSet(_orderManager);
    }

    /// @notice Mints tokens to a recipient (e.g., for buy order finalization)
    /// @param recipient Recipient address
    /// @param amount Amount of tokens
    function mintTokens(address recipient, uint256 amount) external whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (recipient == address(0)) revert InvalidAddress(recipient, "recipient");
        if (amount == 0) revert InvalidAmount(amount, "amount");

        try IOwnmaliProject(project).mint(recipient, amount) {
            emit TokensMinted(recipient, amount);
        } catch {
            revert TokenOperationFailed("mint");
        }
    }

    /// @notice Transfers tokens between accounts (e.g., for order execution)
    /// @param from Sender address
    /// @param to Recipient address
    /// @param amount Amount of tokens
    function transferTokens(address from, address to, uint256 amount) external whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (from == address(0) || to == address(0)) revert InvalidAddress(from == address(0) ? from : to, "account");
        if (amount == 0) revert InvalidAmount(amount, "amount");

        try IOwnmaliProject(project).transferFrom(from, to, amount) {
            emit TokensTransferred(from, to, amount);
        } catch {
            revert TokenOperationFailed("transfer");
        }
    }

    /// @notice Locks tokens for an account until a specified time
    /// @param account Account to lock tokens for
    /// @param amount Amount of tokens
    /// @param unlockTime Unlock timestamp
    function lockTokens(address account, uint256 amount, uint256 unlockTime) external whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (amount == 0) revert InvalidAmount(amount, "amount");
        if (unlockTime <= block.timestamp) revert InvalidParameter("unlockTime", "must be in future");

        try IOwnmaliProject(project).lock(account, amount, unlockTime) {
            emit TokensLocked(account, amount, unlockTime);
        } catch {
            revert TokenOperationFailed("lock");
        }
    }

    /// @notice Releases locked tokens for an account
    /// @param account Account to release tokens for
    /// @param amount Amount of tokens
    function releaseTokens(address account, uint256 amount) external whenNotPaused nonReentrant {
        if (msg.sender != orderManager) revert UnauthorizedCaller(msg.sender);
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (amount == 0) revert InvalidAmount(amount, "amount");

        try IOwnmaliProject(project).unlock(account, amount) {
            emit TokensReleased(account, amount);
        } catch {
            revert TokenOperationFailed("unlock");
        }
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