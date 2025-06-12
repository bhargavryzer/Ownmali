// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/// @title OwnmaliAssetManager
/// @notice Manages token operations for an SPV’s real estate token in the Ownmali ecosystem.
/// @dev Interacts with an OwnmaliRealEstate token contract via IOwnmaliRealEstate interface. Uses UUPS proxy for upgrades.
///      Supports role-based access (ADMIN, TOKEN_MANAGER, FORCED_TRANSFER) with timelocked updates.
///      Storage layout must be preserved across upgrades. All amounts are in wei.
contract OwnmaliAssetManager is
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
        address target; // New address (token contract or role account)
        bytes32 role; // Role for role updates (0 for token contract)
        bool grant; // True for grant, false for revoke (for roles)
        uint48 unlockTime; // Timestamp for execution
    }

    /// @notice Interface for OwnmaliRealEstate token contract.
    interface IOwnmaliRealEstate {
        function transfer(address to, uint256 amount) external returns (bool);
        function transferFrom(address from, address to, uint256 amount) external returns (bool);
        function approve(address spender, uint256 amount) external returns (bool);
        function allowance(address owner, address spender) external view returns (uint256);
        function balanceOf(address account) external view returns (uint256);
        function forcedTransfer(address from, address to, uint256 amount, string calldata reason) external;
        function getRealEstateConfig() external view returns (bytes32[] memory supportedAssetTypes, uint256 remainingSupply);
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Duration for timelock on critical updates (1 day).
    uint48 public constant TIMELOCK_DURATION = 1 days;

    /// @notice Token manager role for transfer and approval operations.
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    /// @notice Forced transfer role for regulatory transfers.
    bytes32 public constant FORCED_TRANSFER_ROLE = keccak256("FORCED_TRANSFER_ROLE");

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    /// @notice Address of the OwnmaliRealEstate token contract.
    address public tokenContract;

    /// @notice Mapping of action IDs to pending updates (token contract or roles).
    mapping(bytes32 => PendingUpdate) public pendingUpdates;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    /// @notice Emitted when the token contract is updated.
    event TokenContractSet(address indexed tokenContract);

    /// @notice Emitted when tokens are transferred.
    event TokensTransferred(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when tokens are approved for a spender.
    event ApprovalSet(address indexed owner, address indexed spender, uint256 amount);

    /// @notice Emitted when tokens are forcibly transferred.
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the asset manager contract.
    /// @dev Sets up roles and token contract. Only callable once.
    /// @param admin Address for DEFAULT_ADMIN_ROLE.
    /// @param tokenManager Address for TOKEN_MANAGER_ROLE.
    /// @param forcedTransferManager Address for FORCED_TRANSFER_ROLE.
    /// @param tokenContract_ OwnmaliRealEstate token contract address.
    function initialize(
        address admin,
        address tokenManager,
        address forcedTransferManager,
        address tokenContract_
    ) external initializer {
        _validateAddress(admin, "admin");
        _validateAddress(tokenManager, "tokenManager");
        _validateAddress(forcedTransferManager, "forcedTransferManager");
        _validateAddress(tokenContract_, "tokenContract");
        if (tokenContract_.code.length == 0) revert InvalidTokenContract(tokenContract_);

        __UUPSUpgradeable_init();
        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        tokenContract = tokenContract_;
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(TOKEN_MANAGER_ROLE, tokenManager);
        _grantRole(FORCED_TRANSFER_ROLE, forcedTransferManager);
        _setRoleAdmin(TOKEN_MANAGER_ROLE, DEFAULT_ADMIN_ROLE);
        _setRoleAdmin(FORCED_TRANSFER_ROLE, DEFAULT_ADMIN_ROLE);

        emit TokenContractSet(tokenContract_);
    }

    /*//////////////////////////////////////////////////////////////
                           TOKEN MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Transfers tokens to a specified address.
    /// @dev Calls transfer on the token contract. Only callable by TOKEN_MANAGER_ROLE.
    /// @param to Recipient address.
    /// @param amount Amount of tokens (in wei).
    function transferTokens(address to, uint256 amount)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateTokenOperation(address(0), to, amount, "transfer");

        try IOwnmaliRealEstate(tokenContract).transfer(to, amount) returns (bool success) {
            if (!success) revert TokenOperationFailed("transfer");
            emit TokensTransferred(address(this), to, amount);
        } catch {
            revert TokenOperationFailed("transfer");
        }
    }

    /// @notice Transfers tokens from one address to another.
    /// @dev Calls transferFrom on the token contract. Only callable by TOKEN_MANAGER_ROLE.
    /// @param from Source address.
    /// @param to Recipient address.
    /// @param amount Amount of tokens (in wei).
    function transferTokensFrom(address from, address to, uint256 amount)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateTokenOperation(from, to, amount, "transferFrom");

        try IOwnmaliRealEstate(tokenContract).transferFrom(from, to, amount) returns (bool success) {
            if (!success) revert TokenOperationFailed("transferFrom");
            emit TokensTransferred(from, to, amount);
        } catch {
            revert TokenOperationFailed("transferFrom");
        }
    }

    /// @notice Transfers tokens to multiple recipients in a single transaction.
    /// @dev Optimizes gas for bulk transfers. Only callable by TOKEN_MANAGER_ROLE.
    /// @param recipients Array of recipient addresses.
    /// @param amounts Array of token amounts (in wei).
    function batchTransferTokens(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (recipients.length != amounts.length) revert ArrayLengthMismatch(recipients.length, amounts.length);
        if (recipients.length == 0) revert InvalidAmount(0, "recipients");

        for (uint256 i = 0; i < recipients.length; i++) {
            _validateTokenOperation(address(0), recipients[i], amounts[i], "batchTransfer");

            try IOwnmaliRealEstate(tokenContract).transfer(recipients[i], amounts[i]) returns (bool success) {
                if (!success) revert TokenOperationFailed("batchTransfer");
                emit TokensTransferred(address(this), recipients[i], amounts[i]);
            } catch {
                revert TokenOperationFailed("batchTransfer");
            }
        }
    }

    /// @notice Approves a spender to spend tokens.
    /// @dev Calls approve on the token contract. Only callable by TOKEN_MANAGER_ROLE.
    /// @param spender Spender address.
    /// @param amount Amount of tokens (in wei).
    function approveTokens(address spender, uint256 amount)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateAddress(spender, "spender");
        // Amount can be 0 for resetting approval

        try IOwnmaliRealEstate(tokenContract).approve(spender, amount) returns (bool success) {
            if (!success) revert TokenOperationFailed("approve");
            emit ApprovalSet(address(this), spender, amount);
        } catch {
            revert TokenOperationFailed("approve");
        }
    }

    /// @notice Performs a forced transfer for legal/regulatory reasons.
    /// @dev Calls forcedTransfer on the token contract. Only callable by FORCED_TRANSFER_ROLE.
    /// @param from Source address.
    /// @param to Destination address.
    /// @param amount Amount of tokens (in wei).
    /// @param reason Reason for forced transfer (min 10 bytes).
    function forcedTransferTokens(address from, address to, uint256 amount, string calldata reason)
        external
        onlyRole(FORCED_TRANSFER_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateTokenOperation(from, to, amount, "forcedTransfer");
        if (bytes(reason).length < 10) revert InvalidReasonLength(reason);

        try IOwnmaliRealEstate(tokenContract).forcedTransfer(from, to, amount, reason) {
            emit ForcedTransfer(from, to, amount, reason);
        } catch {
            revert TokenOperationFailed("forcedTransfer");
        }
    }

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Proposes or executes a token contract update with a timelock.
    /// @dev Requires two calls: propose, then execute after timelock. Only callable by DEFAULT_ADMIN_ROLE.
    /// @param newTokenContract New token contract address.
    function setTokenContract(address newTokenContract)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        _validateAddress(newTokenContract, "newTokenContract");
        if (newTokenContract.code.length == 0) revert InvalidTokenContract(newTokenContract);

        bytes32 actionId = keccak256(abi.encode("tokenContract", newTokenContract));
        if (pendingUpdates[actionId].target != newTokenContract) {
            pendingUpdates[actionId] = PendingUpdate({
                target: newTokenContract,
                role: bytes32(0),
                grant: false,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        tokenContract = newTokenContract;
        delete pendingUpdates[actionId];
        emit TokenContractSet(newTokenContract);
    }

    /// @notice Proposes or executes granting/revoking a role with a timelock.
    /// @dev Requires two calls: propose, then execute after timelock. Only callable by DEFAULT_ADMIN_ROLE.
    /// @param role Role to update (DEFAULT_ADMIN_ROLE, TOKEN_MANAGER_ROLE, FORCED_TRANSFER_ROLE).
    /// @param account Address to update.
    /// @param grant True to grant, false to revoke.
    function setRole(bytes32 role, address account, bool grant)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (role != DEFAULT_ADMIN_ROLE && role != TOKEN_MANAGER_ROLE && role != FORCED_TRANSFER_ROLE) {
            revert InvalidParameter("role", "invalid role");
        }

        bytes32 actionId = keccak256(abi.encode("role", role, account, grant));
        if (pendingUpdates[actionId].target != account) {
            pendingUpdates[actionId] = PendingUpdate({
                target: account,
                role: role,
                grant: grant,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingUpdates[actionId].unlockTime) {
            revert TimelockNotExpired(pendingUpdates[actionId].unlockTime);
        }

        if (grant) {
            _grantRole(role, account);
        } else {
            _revokeRole(role, account);
        }
        delete pendingUpdates[actionId];
    }

    /// @notice Revokes the admin role from an account.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Enhances security by allowing admin privilege removal.
    /// @param account Address to revoke admin role from.
    function revokeAdminRole(address account)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (account == address(0)) revert InvalidAddress(account, "account");
        _revokeRole(DEFAULT_ADMIN_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Retrieves the allowance of a spender for an owner.
    /// @dev Queries the token contract’s allowance.
    /// @param owner Owner address.
    /// @param spender Spender address.
    /// @return Allowance amount (in wei).
    function getAllowance(address owner, address spender)
        external
        view
        whenNotPaused
        returns (uint256)
    {
        _validateAddress(owner, "owner");
        _validateAddress(spender, "spender");
        return IOwnmaliRealEstate(tokenContract).allowance(owner, spender);
    }

    /// @notice Retrieves the balance of an account.
    /// @dev Queries the token contract’s balanceOf.
    /// @param account Account address.
    /// @return Balance amount (in wei).
    function getBalance(address account)
        external
        view
        whenNotPaused
        returns (uint256)
    {
        _validateAddress(account, "account");
        return IOwnmaliRealEstate(tokenContract).balanceOf(account);
    }

    /// @notice Retrieves the real estate token configuration.
    /// @dev Queries the token contract’s getRealEstateConfig.
    /// @return supportedAssetTypes Array of supported asset types.
    /// @return remainingSupply Remaining premintable supply (in wei).
    function getRealEstateConfig()
        external
        view
        whenNotPaused
        returns (bytes32[] memory supportedAssetTypes, uint256 remainingSupply)
    {
        return IOwnmaliRealEstate(tokenContract).getRealEstateConfig();
    }

    /// @notice Retrieves the status of a pending update.
    /// @dev Returns details for a given action ID.
    /// @param actionId Action identifier (keccak256 hash).
    /// @return target Target address (token contract or role account).
    /// @return role Role for role updates (0 for token contract).
    /// @return grant True for grant, false for revoke (for roles).
    /// @return unlockTime Timestamp when update can be executed.
    function getPendingUpdate(bytes32 actionId)
        external
        view
        returns (address target, bytes32 role, bool grant, uint48 unlockTime)
    {
        PendingUpdate memory update = pendingUpdates[actionId];
        return (update.target, update.role, update.grant, update.unlockTime);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Validates token operation parameters.
    /// @dev Ensures valid addresses and amount for transfer operations.
    /// @param from Source address (0 for direct transfers).
    /// @param to Recipient address.
    /// @param amount Amount of tokens (in wei).
    /// @param operation Operation name for error reporting.
    function _validateTokenOperation(address from, address to, uint256 amount, string memory operation) private pure {
        if (from != address(0)) _validateAddress(from, "from");
        _validateAddress(to, "to");
        if (amount == 0) revert InvalidAmount(amount, operation);
    }

    /// @notice Validates an address.
    /// @dev Ensures address is non-zero.
    /// @param addr Address to validate.
    /// @param parameter Parameter name for error reporting.
    function _validateAddress(address addr, string memory parameter) private pure {
        if (addr == address(0)) revert InvalidAddress(addr, parameter);
    }

    /// @notice Authorizes contract upgrades.
    /// @dev Only callable by DEFAULT_ADMIN_ROLE. Ensures non-zero implementation.
    /// @param newImplementation Address of the new implementation contract.
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (newImplementation == address(0)) revert InvalidAddress(newImplementation, "newImplementation");
    }
}