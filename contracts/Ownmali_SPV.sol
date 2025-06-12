// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./OwnmaliValidation.sol";
import "./Roles.sol";

/**
 * @title OwnmaliSPV
 * @dev Manages SPV metadata and access control.
 */
contract OwnmaliSPV is InitializableUpgradeable, PausableUpgradeable, AccessControlUpgradeable {
    using OwnmaliValidation for bytes32;

    /// @notice Emitted when the SPV is initialized.
    event SPVInitialized(bytes32 indexed spvId, address indexed manager, address indexed registry);
    /// @notice Emitted when metadata is updated.
    event MetadataUpdated(string field, string value);
    /// @notice Emitted when unexpected ETH is received.
    event UnexpectedETHReceived(address indexed sender, uint256 amount);
    /// @notice Emitted when a contract is paused.
    event ContractPaused(address indexed pauser);
    /// @notice Emitted when a contract is unpaused.
    event ContractUnpaused(address indexed unpauser);

    /// @notice Initialization parameters.
    struct InitParams {
        bytes32 spvId;
        string spvName;
        string countryCode;
        address registry;
        address manager;
    }

    /// @notice SPV ID.
    bytes32 public spvId;
    /// @notice SPV name.
    string public spvName;
    /// @notice Country code.
    string public countryCode;
    /// @notice Registry address.
    address public registry;
    /// @notice Manager address.
    address public manager;

    /**
     * @dev Initializes the SPV.
     * @param params Initialization parameters.
     */
    function initialize(InitParams memory params) external initializer {
        __Pausable_init();
        __AccessControl_init();

        params.spvId.validateId("spvId");
        OwnmaliValidation.validateString(params.spvName, "spvName", 1, 100);
        OwnmaliValidation.validateString(params.countryCode, "countryCode", 2, 10);
        OwnmaliValidation.validateAddress(params.registry);
        OwnmaliValidation.validateAddress(params.manager);

        spvId = params.spvId;
        spvName = params.spvName;
        countryCode = params.countryCode;
        registry = params.registry;
        manager = params.manager;

        _grantRole(DEFAULT_ADMIN_ROLE, params.registry);
        _grantRole(Roles.ADMIN_ROLE, params.registry);
        _grantRole(Roles.ADMIN_ROLE, params.manager);

        emit SPVInitialized(params.spvId, params.manager, params.registry);
    }

    /**
     * @dev Updates SPV metadata.
     * @param field Metadata field to update.
     * @param value New value.
     */
    function updateMetadata(string memory field, string memory value)
        external
        onlyRole(Roles.ADMIN_ROLE)
        whenNotPaused
    {
        OwnmaliValidation.validateString(field, "field", 1, 50);
        OwnmaliValidation.validateString(value, "value", 1, 200);
        if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("spvName"))) {
            spvName = value;
        } else if (keccak256(abi.encodePacked(field)) == keccak256(abi.encodePacked("countryCode"))) {
            countryCode = value;
        } else {
            revert("invalid field");
        }
        emit MetadataUpdated(field, value);
    }

    /**
     * @dev Handles unexpected ETH transfers.
     */
    receive() external payable {
        emit UnexpectedETHReceived(msg.sender, msg.value);
        revert("direct ETH transfer not allowed");
    }

    /**
     * @dev Pauses the contract.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
        emit ContractPaused(msg.sender);
    }

    /**
     * @dev Unpauses the contract.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
        emit ContractUnpaused(msg.sender);
    }
}