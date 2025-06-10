// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "./Ownmali_Validation.sol";

/// @title SPV
/// @notice Manages Special Purpose Vehicle (SPV) metadata, assets, and ownership
/// @dev Upgradeable contract with role-based access control and pausing
contract OwnmaliSPV is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using OwnmaliValidation for *;

    // Role identifiers
    bytes32 public constant SPV_ADMIN_ROLE = keccak256("SPV_ADMIN_ROLE");
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");

    // SPV data
    string public spvName;
    bool public kycStatus;
    string public countryCode;
    bytes32 public metadataCID;
    address public owner;
    address public registry;
    string public assetDescription; // Description of assets held by SPV
    string public spvPurpose; // Purpose of the SPV (e.g., real estate, debt securitization)

    // Events
    event SPVMetadataUpdated(bytes32 oldCID, bytes32 newCID);
    event SPVKycStatusUpdated(bool kycStatus);
    event SPVOwnerUpdated(address oldOwner, address newOwner);
    event RegistryUpdated(address oldRegistry, address newRegistry);
    event AssetDescriptionUpdated(string oldDescription, string newDescription);
    event SPVPurposeUpdated(string oldPurpose, string newPurpose);

    // Errors
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error Unauthorized(address caller);

    /// @notice Initializes the SPV contract
    /// @param _spvName SPV name (1-100 characters)
    /// @param _kycStatus KYC verification status
    /// @param _countryCode ISO 3166-1 alpha-2 country code
    /// @param _metadataCID IPFS CID for SPV metadata
    /// @param _owner SPV owner address
    /// @param _registry Registry contract address
    /// @param _assetDescription Description of assets held by the SPV
    /// @param _spvPurpose Purpose of the SPV
    function initialize(
        string calldata _spvName,
        bool _kycStatus,
        string calldata _countryCode,
        bytes32 _metadataCID,
        address _owner,
        address _registry,
        string calldata _assetDescription,
        string calldata _spvPurpose
    ) external initializer {
        if (_owner == address(0)) revert InvalidAddress(_owner);
        if (_registry == address(0)) revert InvalidAddress(_registry);
        _spvName.validateString("spvName", 1, 100);
        _countryCode.validateString("countryCode", 2, 2);
        _metadataCID.validateCID("metadataCID");
        _assetDescription.validateString("assetDescription", 1, 500);
        _spvPurpose.validateString("spvPurpose", 1, 200);

        __AccessControl_init();
        __Pausable_init();

        spvName = _spvName;
        kycStatus = _kycStatus;
        countryCode = _countryCode;
        metadataCID = _metadataCID;
        owner = _owner;
        registry = _registry;
        assetDescription = _assetDescription;
        spvPurpose = _spvPurpose;

        _grantRole(DEFAULT_ADMIN_ROLE, _registry);
        _grantRole(SPV_ADMIN_ROLE, _registry);
        _grantRole(SPV_ADMIN_ROLE, _owner);
    }

    /// @notice Updates SPV metadata CID
    /// @param newMetadataCID New IPFS CID for SPV metadata
    function updateMetadata(bytes32 newMetadataCID)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        newMetadataCID.validateCID("metadataCID");

        bytes32 oldCID = metadataCID;
        metadataCID = newMetadataCID;

        emit SPVMetadataUpdated(oldCID, newMetadataCID);
    }

    /// @notice Updates SPV KYC status
    /// @param _kycStatus New KYC status
    function updateKycStatus(bool _kycStatus)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        kycStatus = _kycStatus;
        emit SPVKycStatusUpdated(_kycStatus);
    }

    /// @notice Updates SPV owner
    /// @param newOwner New owner address
    function updateOwner(address newOwner)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        if (newOwner == address(0)) revert InvalidAddress(newOwner);

        address oldOwner = owner;
        owner = newOwner;
        _grantRole(SPV_ADMIN_ROLE, newOwner);
        _revokeRole(SPV_ADMIN_ROLE, oldOwner);

        emit SPVOwnerUpdated(oldOwner, newOwner);
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
        _grantRole(SPV_ADMIN_ROLE, _registry);
        _revokeRole(DEFAULT_ADMIN_ROLE, oldRegistry);
        _revokeRole(SPV_ADMIN_ROLE, oldRegistry);

        emit RegistryUpdated(oldRegistry, _registry);
    }

    /// @notice Updates asset description
    /// @param newAssetDescription New description of assets
    function updateAssetDescription(string calldata newAssetDescription)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        newAssetDescription.validateString("assetDescription", 1, 500);

        string memory oldDescription = assetDescription;
        assetDescription = newAssetDescription;

        emit AssetDescriptionUpdated(oldDescription, newAssetDescription);
    }

    /// @notice Updates SPV purpose
    /// @param newSpvPurpose New purpose of the SPV
    function updateSPVPurpose(string calldata newSpvPurpose)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        newSpvPurpose.validateString("spvPurpose", 1, 200);

        string memory oldPurpose = spvPurpose;
        spvPurpose = newSpvPurpose;

        emit SPVPurposeUpdated(oldPurpose, newSpvPurpose);
    }

    /// @notice Grants investor role to an address
    /// @param investor Address to grant investor role
    function grantInvestorRole(address investor)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        if (investor == address(0)) revert InvalidAddress(investor);
        _grantRole(INVESTOR_ROLE, investor);
    }

    /// @notice Revokes investor role from an address
    /// @param investor Address to revoke investor role
    function revokeInvestorRole(address investor)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        if (investor == address(0)) revert InvalidAddress(investor);
        _revokeRole(INVESTOR_ROLE, investor);
    }

    /// @notice Gets SPV details
    /// @return SPV details (spvName, kycStatus, countryCode, metadataCID, owner, assetDescription, spvPurpose)
    function getDetails()
        external
        view
        returns (
            string memory,
            bool,
            string memory,
            bytes32,
            address,
            string memory,
            string memory
        )
    {
        return (spvName, kycStatus, countryCode, metadataCID, owner, assetDescription, spvPurpose);
    }

    /// @notice Gets SPV details for investors
    /// @return SPV details (spvName, assetDescription, spvPurpose)
    function getInvestorDetails()
        external
        view
        onlyRole(INVESTOR_ROLE)
        returns (
            string memory,
            string memory,
            string memory
        )
    {
        return (spvName, assetDescription, spvPurpose);
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