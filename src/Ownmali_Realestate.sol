// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./Ownmali_Project.sol";

/// @title OwnmaliRealEstateToken
/// @notice ERC-3643 compliant token for real estate assets, extending OwnmaliProject
/// @dev Adds real estate-specific features like batch minting/burning and forced transfers
contract OwnmaliRealEstateToken is OwnmaliProject {
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAssetType(bytes32 assetType);
    error BatchTooLarge(uint256 size);
    error ZeroAmountDetected();

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    uint256 public constant MAX_BATCH_SIZE = 100; // Prevent gas limit issues

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event BatchMinted(address indexed minter, address[] recipients, uint256[] amounts);
    event BatchBurned(address indexed burner, address[] accounts, uint256[] amounts);

    /*//////////////////////////////////////////////////////////////
                         CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with real estate-specific validation
    function initialize(bytes memory initData) public override initializer {
        super.initialize(initData);
        _setRoleAdmin(TRANSFER_ROLE, ADMIN_ROLE);
        _grantRole(TRANSFER_ROLE, projectOwner);
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Batch mints tokens to multiple addresses
    /// @param to Array of recipient addresses
    /// @param amounts Array of amounts to mint
    function batchMint(address[] calldata to, uint256[] calldata amounts) 
        external 
        onlyRole(MINTER_ROLE) 
        whenNotPaused 
        nonReentrant 
    {
        require(to.length == amounts.length, "Array length mismatch");
        require(to.length > 0 && to.length <= MAX_BATCH_SIZE, "Batch size invalid");
        
        for (uint256 i = 0; i < to.length; i++) {
            require(to[i] != address(0), "Invalid address");
            require(amounts[i] > 0, "Zero amount detected");
            require(compliance.canTransfer(address(0), to[i], amounts[i]), "Mint not compliant");
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
        require(from.length == amounts.length, "Array length mismatch");
        require(from.length > 0 && from.length <= MAX_BATCH_SIZE, "Batch size invalid");
        
        for (uint256 i = 0; i < from.length; i++) {
            require(from[i] != address(0), "Invalid address");
            require(amounts[i] > 0, "Zero amount detected");
            require(balanceOf(from[i]) >= amounts[i], "Insufficient balance");
            require(compliance.canTransfer(from[i], address(0), amounts[i]), "Burn not compliant");
            _burn(from[i], amounts[i]);
        }
        emit BatchBurned(msg.sender, from, amounts);
    }

    /// @notice Grants or revokes the TRANSFER_ROLE
    function setTransferRole(address account, bool grant) external onlyRole(ADMIN_ROLE) {
        if (grant) {
            _grantRole(TRANSFER_ROLE, account);
        } else {
            _revokeRole(TRANSFER_ROLE, account);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates initialization parameters with real estate-specific asset types
    function _validateInitParams(ProjectInitParams memory params) internal view override {
        super._validateInitParams(params);
        if (
            params.assetType != bytes32("Commercial") &&
            params.assetType != bytes32("Residential") &&
            params.assetType != bytes32("Holiday") &&
            params.assetType != bytes32("Land")
        ) revert InvalidAssetType(params.assetType);
    }
}