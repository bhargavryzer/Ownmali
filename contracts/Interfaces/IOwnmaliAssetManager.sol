// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title IOwnmaliAssetManager
/// @notice Interface for the OwnmaliAssetManager contract, managing token operations for an SPV’s real estate token.
interface IOwnmaliAssetManager is
    Initializable,
    UUPSUpgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidAmount(uint256 amount, string parameter);
    error InvalidTokenContract(address tokenContract);
    error TimelockNotExpired(uint48 unlockTime);
    error InvalidReasonLength(string reason);
    error TokenOperationFailed(string operation);
    error ArrayLengthMismatch(uint256 expected, uint256 actual);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Structure for pending critical updates with timelock.
    struct PendingUpdate {
        address target;
        bytes32 role;
        bool grant;
        uint48 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event TokenContractSet(address indexed tokenContract);
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);
    event ApprovalSet(address indexed owner, address indexed spender, uint256 amount);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address admin,
        address tokenManager,
        address forcedTransferManager,
        address tokenContract_
    ) external;

    /*//////////////////////////////////////////////////////////////
                           TOKEN MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function transferTokens(address to, uint256 amount) external;
    function transferTokensFrom(address from, address to, uint256 amount) external;
    function batchTransferTokens(address[] calldata recipients, uint256[] calldata amounts) external;
    function approveTokens(address spender, uint256 amount) external;
    function forcedTransferTokens(address from, address to, uint256 amount, string calldata reason) external;

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setTokenContract(address newTokenContract) external;
    function setRole(bytes32 role, address account, bool grant) external;
    function revokeAdminRole(address account) external;

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getAllowance(address owner, address spender) external view returns (uint256);
    function getBalance(address account) external view returns (uint256);
    function getRealEstateConfig() external view returns (bytes32[] memory supportedAssetTypes, uint256 remainingSupply);
    function getPendingUpdate(bytes32 actionId)
        external
        view
        returns (address target, bytes32 role, bool grant, uint48 unlockTime);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function TIMELOCK_DURATION() external view returns (uint48);
    function TOKEN_MANAGER_ROLE() external view returns (bytes32);
    function FORCED_TRANSFER_ROLE() external view returns (bytes32);
    function tokenContract() external view returns (address);
    function pendingUpdates(bytes32 actionId) external view returns (PendingUpdate memory);
}