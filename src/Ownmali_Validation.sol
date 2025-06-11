// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title OwnmaliValidation
/// @notice Library for validating input parameters in the Ownmali ecosystem
/// @dev Provides reusable validation functions for IDs, strings, CIDs, addresses, and numbers.
/// Note that string validation uses byte length, which may not align with character count for UTF-8 strings.
library OwnmaliValidation {
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidId(bytes32 id, string parameter);
    error InvalidString(string value, string parameter, uint256 minLength, uint256 maxLength);
    error InvalidCID(bytes32 cid, string parameter);
    error InvalidAddress(address addr, string parameter);
    error InvalidNumber(uint256 value, string parameter, uint256 min, uint256 max);
    error InvalidPercentage(uint256 value, string parameter);
    error InvalidArrayLength(uint256 length, uint256 expected, string parameter);
    error InvalidCodeSize(address addr, string parameter);

    /*//////////////////////////////////////////////////////////////
                         VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates a bytes32 ID is non-zero
    /// @param id The ID to validate
    /// @param parameter The parameter name for error reporting
    function validateId(bytes32 id, string memory parameter) internal pure {
        if (id == bytes32(0)) revert InvalidId(id, parameter);
    }

    /// @notice Validates a string length (in bytes)
    /// @param value The string to validate
    /// @param parameter The parameter name for error reporting
    /// @param minLength Minimum allowed byte length
    /// @param maxLength Maximum allowed byte length
    function validateString(
        string memory value,
        string memory parameter,
        uint256 minLength,
        uint256 maxLength
    ) internal pure {
        uint256 length = bytes(value).length;
        if (length < minLength || length > maxLength) {
            revert InvalidString(value, parameter, minLength, maxLength);
        }
    }

    /// @notice Validates a non-zero number
    /// @param value The number to validate
    /// @param parameter The parameter name for error reporting
    function validateNonZero(uint256 value, string memory parameter) internal pure {
        if (value == 0) revert InvalidNumber(value, parameter, 1, type(uint256).max);
    }

    /// @notice Validates a number within a range
    /// @param value The number to validate
    /// @param min Minimum allowed value
    /// @param max Maximum allowed value
    /// @param parameter The parameter name for error reporting
    function validateRange(
        uint256 value,
        uint256 min,
        uint256 max,
        string memory parameter
    ) internal pure {
        if (value < min || value > max) revert InvalidNumber(value, parameter, min, max);
    }

    /// @notice Validates a non-zero Ethereum address
    /// @param addr The address to validate
    /// @param parameter The parameter name for error reporting
    function validateAddress(address addr, string memory parameter) internal pure {
        if (addr == address(0)) revert InvalidAddress(addr, parameter);
    }

    /// @notice Validates a non-zero IPFS CID
    /// @param cid The CID to validate
    /// @param parameter The parameter name for error reporting
    function validateCID(bytes32 cid, string memory parameter) internal pure {
        if (cid == bytes32(0)) revert InvalidCID(cid, parameter);
    }

    /// @notice Validates a percentage value (0-100)
    /// @param value The percentage value to validate
    /// @param parameter The parameter name for error reporting
    function validatePercentage(uint256 value, string memory parameter) internal pure {
        if (value > 100) revert InvalidPercentage(value, parameter);
    }

    /// @notice Validates array lengths match
    /// @param length The actual array length
    /// @param expected The expected array length
    /// @param parameter The parameter name for error reporting
    function validateArrayLength(uint256 length, uint256 expected, string memory parameter) internal pure {
        if (length != expected) revert InvalidArrayLength(length, expected, parameter);
    }

    /// @notice Validates contract code exists at address
    /// @param addr The address to validate
    /// @param parameter The parameter name for error reporting
    function validateContractCode(address addr, string memory parameter) internal view {
        validateAddress(addr, parameter);
        if (addr.code.length == 0) revert InvalidCodeSize(addr, parameter);
    }
}