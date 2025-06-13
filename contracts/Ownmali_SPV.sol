// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./OwnmaliValidation.sol";

/**
 * @title OwnmaliSPV
 * @notice Manages metadata for a Special Purpose Vehicle (SPV) in the Ownmali ecosystem.
 * @dev Provides pausable, role-based metadata management for SPV name and country code, with timelocked updates.
 */
contract OwnmaliSPV is Initializable, PausableUpgradeable, AccessControlUpgradeable {
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TimelockNotExpired(uint48 unlockTime);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct PendingMetadataUpdate {
        string value;
        bool isSpvName;
        uint48 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    uint48 public constant TIMELOCK_DURATION = 1 days;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    string public spvName;
    string public countryCode;
    PendingMetadataUpdate public pendingMetadataUpdate;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event MetadataUpdated(string field, string value);

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the SPV with metadata and admin.
     * @param spvName SPV name (1-50 bytes).
     * @param countryCode Country code (2-3 bytes, ISO 3166-1 alpha-2/3).
     * @param admin Admin address for role assignment.
     */
    function initialize(
        string memory spvName,
        string memory countryCode,
        address admin
    ) external initializer {
        OwnmaliValidation.validateString(spvName, "spvName", 1, 50);
        OwnmaliValidation.validateString(countryCode, "countryCode", 2, 3);
        OwnmaliValidation.validateAddress(admin, "admin");

        __Pausable_init();
        __AccessControl_init();

        spvName = spvName;
        countryCode = countryCode;

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Proposes or executes an SPV name update with a timelock.
     * @param newSpvName New SPV name (1-50 bytes).
     */
    function updateSpvName(string memory newSpvName)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        OwnmaliValidation.validateString(newSpvName, "newSpvName", 1, 50);

        if (keccak256(abi.encodePacked(pendingMetadataUpdate.value)) != keccak256(abi.encodePacked(newSpvName)) ||
            !pendingMetadataUpdate.isSpvName)
        {
            pendingMetadataUpdate = PendingMetadataUpdate({
                value: newSpvName,
                isSpvName: true,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingMetadataUpdate.unlockTime) {
            revert TimelockNotExpired(pendingMetadataUpdate.unlockTime);
        }

        spvName = newSpvName;
        emit MetadataUpdated("spvName", newSpvName);
        delete pendingMetadataUpdate;
    }

    /**
     * @notice Proposes or executes a country code update with a timelock.
     * @param newCountryCode New country code (2-3 bytes, ISO 3166-1 alpha-2/3).
     */
    function updateCountryCode(string memory newCountryCode)
        external
        onlyRole(ADMIN_ROLE)
        whenNotPaused
    {
        OwnmaliValidation.validateString(newCountryCode, "newCountryCode", 2, 3);

        if (keccak256(abi.encodePacked(pendingMetadataUpdate.value)) != keccak256(abi.encodePacked(newCountryCode)) ||
            pendingMetadataUpdate.isSpvName)
        {
            pendingMetadataUpdate = PendingMetadataUpdate({
                value: newCountryCode,
                isSpvName: false,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < pendingMetadataUpdate.unlockTime) {
            revert TimelockNotExpired(pendingMetadataUpdate.unlockTime);
        }

        countryCode = newCountryCode;
        emit MetadataUpdated("countryCode", newCountryCode);
        delete pendingMetadataUpdate;
    }

    /**
     * @notice Pauses the contract.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}