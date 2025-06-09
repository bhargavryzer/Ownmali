// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./Ownmali_Validation.sol";

/// @title Company
/// @notice Manages company metadata and ownership
/// @dev Upgradeable contract with role-based access control and pausing
contract OwnmaliCompany is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using OwnmaliValidation for *;

    // Role identifiers
    bytes32 public constant COMPANY_ADMIN_ROLE = keccak256("COMPANY_ADMIN_ROLE");

    // Company data
    string public name;
    bool public kycStatus;
    string public countryCode;
    bytes32 public metadataCID;
    address public owner;
    address public registry;

    // Events
    event CompanyMetadataUpdated(bytes32 oldCID, bytes32 newCID);
    event CompanyKycStatusUpdated(bool kycStatus);
    event CompanyOwnerUpdated(address oldOwner, address newOwner);
    event RegistryUpdated(address oldRegistry, address newRegistry);

    // Errors
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error Unauthorized(address caller);

    /// @notice Initializes the company contract
    /// @param _name Company name (1-100 characters)
    /// @param _kycStatus KYC verification status
    /// @param _countryCode ISO 3166-1 alpha-2 country code
    /// @param _metadataCID IPFS CID for company metadata
    /// @param _owner Company owner address
    /// @param _registry Registry contract address
    function initialize(
        string calldata _name,
        bool _kycStatus,
        string calldata _countryCode,
        bytes32 _metadataCID,
        address _owner,
        address _registry
    ) external initializer {
        if (_owner == address(0)) revert InvalidAddress(_owner);
        if (_registry == address(0)) revert InvalidAddress(_registry);
        _name.validateString("name", 1, 100);
        _countryCode.validateString("countryCode", 2, 2);
        _metadataCID.validateCID("metadataCID");

        __AccessControl_init();
        __Pausable_init();

        name = _name;
        kycStatus = _kycStatus;
        countryCode = _countryCode;
        metadataCID = _metadataCID;
        owner = _owner;
        registry = _registry;

        _grantRole(DEFAULT_ADMIN_ROLE, _registry);
        _grantRole(COMPANY_ADMIN_ROLE, _registry);
        _grantRole(COMPANY_ADMIN_ROLE, _owner);
    }

    /// @notice Updates company metadata CID
    /// @param newMetadataCID New IPFS CID for company metadata
    function updateMetadata(bytes32 newMetadataCID)
        external
        onlyRole(COMPANY_ADMIN_ROLE)
        whenNotPaused
    {
        newMetadataCID.validateCID("metadataCID");

        bytes32 oldCID = metadataCID;
        metadataCID = newMetadataCID;

        emit CompanyMetadataUpdated(oldCID, newMetadataCID);
    }

    /// @notice Updates company KYC status
    /// @param _kycStatus New KYC status
    function updateKycStatus(bool _kycStatus)
        external
        onlyRole(COMPANY_ADMIN_ROLE)
        whenNotPaused
    {
        kycStatus = _kycStatus;
        emit CompanyKycStatusUpdated(_kycStatus);
    }

    /// @notice Updates company owner
    /// @param newOwner New owner address
    function updateOwner(address newOwner)
        external
        onlyRole(COMPANY_ADMIN_ROLE)
        whenNotPaused
    {
        if (newOwner == address(0)) revert InvalidAddress(newOwner);

        address oldOwner = owner;
        owner = newOwner;
        _grantRole(COMPANY_ADMIN_ROLE, newOwner);
        _revokeRole(COMPANY_ADMIN_ROLE, oldOwner);

        emit CompanyOwnerUpdated(oldOwner, newOwner);
    }

    /// @notice Updates the registry address
    /// @param _registry New registry address
    function setRegistry(address _registry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenNotPaused
    {
        if (_registry == address(0)) revert InvalidAddress(_registry);

        address oldRegistry = registry;
        registry = _registry;
        _grantRole(DEFAULT_ADMIN_ROLE, _registry);
        _grantRole(COMPANY_ADMIN_ROLE, _registry);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldRegistry);
        _revokeRole(COMPANY_ADMIN_ROLE, oldRegistry);

        emit RegistryUpdated(oldRegistry, _registry);
    }

    /// @notice Gets company details
    /// @return Company details (name, kycStatus, countryCode, metadataCID, owner)
    function getDetails()
        external
        view
        returns (
            string memory,
            bool,
            string memory,
            bytes32,
            address
        )
    {
        return (name, kycStatus, countryCode, metadataCID, owner);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }
}