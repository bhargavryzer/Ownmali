// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";

/// @title IOwnmaliSPV
/// @notice Interface for the OwnmaliSPV contract, managing metadata for a Special Purpose Vehicle (SPV) in the Ownmali ecosystem.
interface IOwnmaliSPV is Initializable, PausableUpgradeable, AccessControlUpgradeable {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TimelockNotExpired(uint48 unlockTime);
    error InvalidString(string value, string parameter);
    error InvalidAddress(address addr, string parameter);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct PendingMetadataUpdate {
        string value;
        bool isSpvName;
        uint48 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event MetadataUpdated(string field, string value);

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function initialize(string memory spvName, string memory countryCode, address admin) external;
    function updateSpvName(string memory newSpvName) external;
    function updateCountryCode(string memory newCountryCode) external;
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function ADMIN_ROLE() external view returns (bytes32);
    function TIMELOCK_DURATION() external view returns (uint48);
    function spvName() external view returns (string memory);
    function countryCode() external view returns (string memory);
    function pendingMetadataUpdate() external view returns (PendingMetadataUpdate memory);
}