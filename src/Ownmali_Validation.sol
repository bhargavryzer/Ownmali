// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title OwnmaliValidation
/// @notice Library for validating input parameters in the Ownmali ecosystem
/// @dev Provides reusable validation functions for IDs, strings, CIDs, addresses, and numbers
library OwnmaliValidation {
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidId(bytes32 id, string parameter);
    error InvalidString(string value, string parameter, uint256 minLength, uint256 maxLength);
    error InvalidCID(bytes32 cid, string parameter);
    error InvalidAddress(address addr, string parameter);
    error InvalidNumber(uint256 value, string parameter);

    /*//////////////////////////////////////////////////////////////
                         VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates a bytes32 ID
    function validateId(bytes32 id, string memory parameter) internal pure {
        if (id == bytes32(0)) revert InvalidId(id, parameter);
    }

    /// @notice Validates a string length (in bytes)
    /// @dev This function checks byte length, not character count. For UTF-8 strings, use with caution.
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
    function validateNonZero(uint256 value, string memory parameter) internal pure {
        if (value == 0) revert InvalidNumber(value, parameter);
    }

    /// @notice Validates a number within a range
    function validateRange(
        uint256 value,
        uint256 min,
        uint256 max,
        string memory parameter
    ) internal pure {
        if (value < min || value > max) revert InvalidNumber(value, parameter);
    }

    /// @notice Validates an Ethereum address
    function validateAddress(address addr, string memory parameter) internal pure {
        if (addr == address(0)) revert InvalidAddress(addr, parameter);
    }

    /// @notice Validates an IPFS CID (presence check only)
    /// @dev This is a basic check for non-zero CIDs. Full CID format validation should be done externally.
    function validateCID(bytes32 cid, string memory parameter) internal pure {
        if (cid == bytes32(0)) revert InvalidCID(cid, parameter);
    }
}