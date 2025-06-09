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

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");

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
    function batchMint(address[] calldata to, uint256[] calldata amounts) external onlyRole(MINTER_ROLE) whenNotPaused {
        require(to.length == amounts.length, "Array length mismatch");
        for (uint256 i = 0; i < to.length; i++) {
            require(to[i] != address(0), "Invalid address");
            require(compliance.canTransfer(address(0), to[i], amounts[i]), "Mint not compliant");
            _mint(to[i], amounts[i]);
        }
    }

    /// @notice Batch burns tokens from multiple addresses
    /// @param from Array of source addresses
    /// @param amounts Array of amounts to burn
    function batchBurn(address[] calldata from, uint256[] calldata amounts) external onlyRole(TRANSFER_ROLE) whenNotPaused {
        require(from.length == amounts.length, "Array length mismatch");
        for (uint256 i = 0; i < from.length; i++) {
            require(from[i] != address(0), "Invalid address");
            require(compliance.canTransfer(from[i], address(0), amounts[i]), "Burn not compliant");
            _burn(from[i], amounts[i]);
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