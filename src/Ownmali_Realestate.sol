// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./Ownmali_Project.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/// @title OwnmaliRealEstateToken
/// @notice ERC-3643 compliant token for real estate assets, extending OwnmaliProject
/// @dev Adds real estate-specific features like batch minting/burning and forced transfers with upgradeability
contract OwnmaliRealEstateToken is OwnmaliProject {
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAssetType(bytes32 assetType);
    error BatchTooLarge(uint256 size, uint256 maxSize);
    error ArrayLengthMismatch(uint256 toLength, uint256 amountsLength);
    error ZeroAmountDetected(address recipient);
    error InvalidRecipient(address recipient);
    error TotalSupplyExceeded(uint256 requested, uint256 maxSupply);
    error InsufficientBalance(address account, uint256 balance, uint256 requested);

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    uint256 public maxBatchSize;

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event BatchMinted(address indexed minter, address[] recipients, uint256[] amounts);
    event BatchBurned(address indexed burner, address[] accounts, uint256[] amounts);
    event MaxBatchSizeSet(uint256 newMaxSize);
    event TransferRoleUpdated(address indexed account, bool granted);

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with real estate-specific validation
    /// @param initData Encoded ProjectInitParams for initialization
    function initialize(bytes memory initData) public override initializer {
        super.initialize(initData);
        maxBatchSize = 100; // Initial max batch size
        _setRoleAdmin(TRANSFER_ROLE, ADMIN_ROLE);
        _grantRole(TRANSFER_ROLE, projectOwner);
        emit MaxBatchSizeSet(maxBatchSize);
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the maximum batch size for minting/burning
    /// @param _maxBatchSize New maximum batch size
    function setMaxBatchSize(uint256 _maxBatchSize) external onlyRole(ADMIN_ROLE) {
        if (_maxBatchSize == 0) revert InvalidParameter("maxBatchSize", "must be non-zero");
        maxBatchSize = _maxBatchSize;
        emit MaxBatchSizeSet(_maxBatchSize);
    }

    /// @notice Batch mints tokens to multiple addresses
    /// @param to Array of recipient addresses
    /// @param amounts Array of amounts to mint
    function batchMint(address[] calldata to, uint256[] calldata amounts)
        external
        onlyRole(MINTER_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (to.length != amounts.length) revert ArrayLengthMismatch(to.length, amounts.length);
        if (to.length == 0 || to.length > maxBatchSize) revert BatchTooLarge(to.length, maxBatchSize);

        uint256 totalAmount;
        for (uint256 i = 0; i < to.length; i++) {
            if (to[i] == address(0)) revert InvalidRecipient(to[i]);
            if (amounts[i] == 0) revert ZeroAmountDetected(to[i]);
            totalAmount += amounts[i];
        }

        if (totalSupply() + totalAmount > maxSupply()) {
            revert TotalSupplyExceeded(totalSupply() + totalAmount, maxSupply());
        }

        for (uint256 i = 0; i < to.length; i++) {
            if (!compliance.canTransfer(address(0), to[i], amounts[i])) {
                revert TransferNotCompliant(address(0), to[i], amounts[i]);
            }
            _mint(to[i], amounts[i]);
        }

        emit BatchMinted(msg.sender, to, amounts);
    }

    /// @notice Batch burns tokens from multiple addresses
    /// @param from Array of source addresses
    /// @param amounts Array of amounts to burn
    function batchBurn(address[] calldata from, uint256[] calldata amounts)
        external
        onlyRole(TRANSFER_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (from.length != amounts.length) revert ArrayLengthMismatch(from.length, amounts.length);
        if (from.length == 0 || from.length > maxBatchSize) revert BatchTooLarge(from.length, maxBatchSize);

        for (uint256 i = 0; i < from.length; i++) {
            if (from[i] == address(0)) revert InvalidRecipient(from[i]);
            if (amounts[i] == 0) revert ZeroAmountDetected(from[i]);
            if (balanceOf(from[i]) < amounts[i]) {
                revert InsufficientBalance(from[i], balanceOf(from[i]), amounts[i]);
            }
            if (!compliance.canTransfer(from[i], address(0), amounts[i])) {
                revert TransferNotCompliant(from[i], address(0), amounts[i]);
            }
            _burn(from[i], amounts[i]);
        }

        emit BatchBurned(msg.sender, from, amounts);
    }

    /// @notice Grants or revokes the TRANSFER_ROLE
    /// @param account Address to update
    /// @param grant True to grant, false to revoke
    function setTransferRole(address account, bool grant) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (grant) {
            _grantRole(TRANSFER_ROLE, account);
        } else {
            _revokeRole(TRANSFER_ROLE, account);
        }
        emit TransferRoleUpdated(account, grant);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates initialization parameters with real estate-specific asset types
    /// @param params Project initialization parameters
    function _validateInitParams(ProjectInitParams memory params) internal view override {
        super._validateInitParams(params);
        if (
            params.assetType != bytes32("Commercial") &&
            params.assetType != bytes32("Residential") &&
            params.assetType != bytes32("Holiday") &&
            params.assetType != bytes32("Land")
        ) revert InvalidAssetType(params.assetType);
    }

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the maximum supply of tokens
    /// @return Maximum supply
    function maxSupply() public view returns (uint256) {
        return getProjectDetails().maxSupply;
    }
}