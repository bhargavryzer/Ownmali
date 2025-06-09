// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "./Ownmali_Validation.sol";

/// @title Company
/// @notice Manages company metadata and ownership
/// @dev Upgradeable contract with role-based access control
contract Company is Initializable, AccessControlUpgradeable {
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
    event CompanyMetadataUpdated(bytes32 indexed companyId, bytes32 oldCID, bytes32 newCID);
    event CompanyKycStatusUpdated(bytes32 indexed companyId, bool kycStatus);
    event CompanyOwnerUpdated(bytes32 indexed companyId, address oldOwner, address newOwner);

    // Errors
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error InvalidCompanyId(bytes32 companyId);
    error Unauthorized(address caller);


    /// @notice Initializes the company contract
    /// @param companyId Unique identifier for the company
    /// @param _name Company name (1-100 characters)
    /// @param _kycStatus KYC verification status
    /// @param _countryCode ISO 3166-1 alpha-2 country code
    /// @param _metadataCID IPFS CID for company metadata
    /// @param _owner Company owner address
    /// @param _registry Registry contract address
    function initialize(
        bytes32 companyId,
        string calldata _name,
        bool _kycStatus,
        string calldata _countryCode,
        bytes32 _metadataCID,
        address _owner,
        address _registry
    ) external initializer {
        if (_owner == address(0)) revert InvalidAddress(_owner);
        if (_registry == address(0)) revert InvalidAddress(_registry);
        companyId.validateId("companyId");
        _name.validateString("name", 1, 100);
        _countryCode.validateString("countryCode", 2, 2);
        _metadataCID.validateCID("metadataCID");

        __AccessControl_init();

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
    /// @param companyId Company identifier
    /// @param newMetadataCID New IPFS CID for company metadata
    function updateMetadata(bytes32 companyId, bytes32 newMetadataCID)
        external
        onlyRole(COMPANY_ADMIN_ROLE)
    {
        companyId.validateId("companyId");
        newMetadataCID.validateCID("metadataCID");

        bytes32 oldCID = metadataCID;
        metadataCID = newMetadataCID;

        emit CompanyMetadataUpdated(companyId, oldCID, newMetadataCID);
    }

    /// @notice Updates company KYC status
    /// @param companyId Company identifier
    /// @param _kycStatus New KYC status
    function updateKycStatus(bytes32 companyId, bool _kycStatus)
        external
        onlyRole(COMPANY_ADMIN_ROLE)
    {
        companyId.validateId("companyId");
        kycStatus = _kycStatus;
        emit CompanyKycStatusUpdated(companyId, _kycStatus);
    }

    /// @notice Updates company owner
    /// @param companyId Company identifier
    /// @param newOwner New owner address
    function updateOwner(bytes32 companyId, address newOwner)
        external
        onlyRole(COMPANY_ADMIN_ROLE)
    {
        companyId.validateId("companyId");
        if (newOwner == address(0)) revert InvalidAddress(newOwner);

        address oldOwner = owner;
        owner = newOwner;
        _grantRole(COMPANY_ADMIN_ROLE, newOwner);
        _revokeRole(COMPANY_ADMIN_ROLE, oldOwner);

        emit CompanyOwnerUpdated(companyId, oldOwner, newOwner);
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
}