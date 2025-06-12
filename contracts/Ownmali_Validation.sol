// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title OwnmaliValidation
/// @notice Library for validating inputs in the Ownmali ecosystem.
/// @dev Provides reusable pure functions for validating addresses, strings, bytes32, numbers, and asset types.
/// String validation uses byte length, not character count, due to UTF-8 encoding.
library OwnmaliValidation {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidInput(string kind, string parameter);

    /*//////////////////////////////////////////////////////////////
                             VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates a non-zero bytes32 value (e.g., ID or CID).
    /// @param value The bytes32 to validate.
    /// @param parameter The parameter name for error reporting.
    function validateBytes32(bytes32 value, string memory parameter) internal pure {
        if (value == bytes32(0)) revert InvalidInput("Bytes32", parameter);
    }

    /// @notice Validates a string’s byte length.
    /// @param value The string to validate.
    /// @param parameter The parameter name for error reporting.
    /// @param minLength Minimum byte length.
    /// @param maxLength Maximum byte length.
    function validateString(
        string memory value,
        string memory parameter,
        uint256 minLength,
        uint256 maxLength
    ) internal pure {
        uint256 length = bytes(value).length;
        if (length < minLength || length > maxLength) revert InvalidInput("String", parameter);
    }

    /// @notice Validates a non-zero address.
    /// @param addr The address to validate.
    /// @param parameter The parameter name for error reporting.
    function validateAddress(address addr, string memory parameter) internal pure {
        if (addr == address(0)) revert InvalidInput("Address", parameter);
    }

    /// @notice Validates a number within a range.
    /// @param value The number to validate.
    /// @param min Minimum allowed value.
    /// @param max Maximum allowed value.
    /// @param parameter The parameter name for error reporting.
    function validateRange(
        uint256 value,
        uint256 min,
        uint256 max,
        string memory parameter
    ) internal pure {
        if (value < min || value > max) revert InvalidInput("Number", parameter);
    }

    /// @notice Validates a real estate asset type.
    /// @param assetType The asset type to validate.
    function validateAssetType(bytes32 assetType) internal pure {
        bytes32 commercial = keccak256("Commercial");
        bytes32 residential = keccak256("Residential");
        bytes32 holiday = keccak256("Holiday");
        bytes32 land = keccak256("Land");
        bytes32 industrial = keccak256("Industrial");
        bytes32 mixedUse = keccak256("Mixed-Use");

        if (
            assetType != commercial &&
            assetType != residential &&
            assetType != holiday &&
            assetType != land &&
            assetType != industrial &&
            assetType != mixedUse
        ) {
            revert InvalidInput("AssetType", "assetType");
        }
    }
}