// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliSPV
/// @notice Manages a Special Purpose Vehicle for holding and distributing assets
/// @dev Upgradeable contract with role-based access control, pausing, and asset management
contract OwnmaliSPV is Initializable, AccessControlUpgradeable, PausableUpgradeable {
    using OwnmaliValidation for *;

    // Role identifiers
    bytes32 public constant SPV_ADMIN_ROLE = keccak256("SPV_ADMIN_ROLE");
    bytes32 public constant INVESTOR_ROLE = keccak256("INVESTOR_ROLE");

    // SPV data
    string public spvName; // Name of the SPV
    bool public kycStatus; // KYC status for compliance
    string public countryCode; // ISO 3166-1 alpha-2 code for country
    bytes32 public metadataCID; // IPFS CID for SPV metadata (e.g., purpose, legal docs)
    address public manager; // SPV manager
    address public registry; // Registry contract for compliance
    address public assetToken; // ERC-20 token or asset managed by SPV
    uint256 public totalAssets; // Total assets held (in assetToken units or ETH)

    // Struct for initialization parameters
    struct InitParams {
        string spvName;
        bool kycStatus;
        string countryCode;
        bytes32 metadataCID;
        address manager;
        address registry;
        address assetToken;
    }

    // Events
    event SPVMetadataUpdated(bytes32 oldCID, bytes32 newCID);
    event SPVKycStatusUpdated(bool kycStatus);
    event SPVManagerUpdated(address oldManager, address newManager);
    event RegistryUpdated(address oldRegistry, address newRegistry);
    event AssetsDeposited(address indexed depositor, uint256 amount);
    event AssetsWithdrawn(address indexed recipient, uint256 amount);
    event InvestorAdded(address indexed investor);
    event InvestorRemoved(address indexed investor);
    event ProfitsDistributed(address indexed investor, uint256 amount);

    // Errors
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error Unauthorized(address caller);
    error InsufficientAssets(uint256 requested, uint256 available);
    error AssetTransferFailed(address token, address to, uint256 amount);

    /// @notice Initializes the SPV contract
    /// @param params Initialization parameters
    function initialize(InitParams calldata params) external initializer {
        // Validate addresses
        if (params.manager == address(0)) revert InvalidAddress(params.manager);
        if (params.registry == address(0)) revert InvalidAddress(params.registry);

        // Validate inputs
        params.spvName.validateString("spvName", 1, 100);
        params.countryCode.validateString("countryCode", 2, 2);
        params.metadataCID.validateCID("metadataCID");

        // Initialize inherited contracts
        __AccessControl_init();
        __Pausable_init();

        // Set state variables
        spvName = params.spvName;
        kycStatus = params.kycStatus;
        countryCode = params.countryCode;
        metadataCID = params.metadataCID;
        manager = params.manager;
        registry = params.registry;
        assetToken = params.assetToken;
        totalAssets = 0;

        // Set roles
        _setupRoles(params.registry, params.manager);
    }

    /// @notice Internal function to set up roles during initialization
    /// @param _registry Registry address
    /// @param _manager Manager address
    function _setupRoles(address _registry, address _manager) internal {
        _grantRole(DEFAULT_ADMIN_ROLE, _registry);
        _grantRole(SPV_ADMIN_ROLE, _registry);
        _grantRole(SPV_ADMIN_ROLE, _manager);
    }

    /// @notice Deposits assets (ETH or ERC-20 tokens) into the SPV
    /// @param amount Amount of assets to deposit
    function depositAssets(uint256 amount) external payable whenNotPaused {
        if (!hasRole(INVESTOR_ROLE, msg.sender) && !hasRole(SPV_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(msg.sender);
        }
        if (amount == 0) revert InvalidParameter("amount");

        if (assetToken == address(0)) {
            // Handle ETH deposits
            if (msg.value != amount) revert InvalidParameter("msg.value");
            totalAssets += amount;
        } else {
            // Handle ERC-20 token deposits
            if (msg.value != 0) revert InvalidParameter("msg.value");
            bool success = IERC20Upgradeable(assetToken).transferFrom(msg.sender, address(this), amount);
            if (!success) revert AssetTransferFailed(assetToken, address(this), amount);
            totalAssets += amount;
        }

        emit AssetsDeposited(msg.sender, amount);
    }

    /// @notice Withdraws assets to a specified address
    /// @param recipient Address to receive the assets
    /// @param amount Amount of assets to withdraw
    function withdrawAssets(address recipient, uint256 amount)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        if (recipient == address(0)) revert InvalidAddress(recipient);
        if (amount == 0 || amount > totalAssets) revert InsufficientAssets(amount, totalAssets);

        totalAssets -= amount;

        if (assetToken == address(0)) {
            // Handle ETH withdrawal
            (bool success, ) = recipient.call{value: amount}("");
            if (!success) revert AssetTransferFailed(address(0), recipient, amount);
        } else {
            // Handle ERC-20 token withdrawal
            bool success = IERC20Upgradeable(assetToken).transfer(recipient, amount);
            if (!success) revert AssetTransferFailed(assetToken, recipient, amount);
        }

        emit AssetsWithdrawn(recipient, amount);
    }

    /// @notice Distributes profits to investors
    /// @param investors List of investor addresses
    /// @param amounts Corresponding amounts to distribute
    function distributeProfits(address[] calldata investors, uint256[] calldata amounts)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        if (investors.length != amounts.length) revert InvalidParameter("array length mismatch");
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }
        if (totalAmount > totalAssets) revert InsufficientAssets(totalAmount, totalAssets);

        totalAssets -= totalAmount;

        for (uint256 i = 0; i < investors.length; i++) {
            if (!hasRole(INVESTOR_ROLE, investors[i])) revert Unauthorized(investors[i]);
            if (amounts[i] == 0) continue;

            if (assetToken == address(0)) {
                (bool success, ) = investors[i].call{value: amounts[i]}("");
                if (!success) revert AssetTransferFailed(address(0), investors[i], amounts[i]);
            } else {
                bool success = IERC20Upgradeable(assetToken).transfer(investors[i], amounts[i]);
                if (!success) revert AssetTransferFailed(assetToken, investors[i], amounts[i]);
            }

            emit ProfitsDistributed(investors[i], amounts[i]);
        }
    }

    /// @notice Adds an investor to the SPV
    /// @param investor Address of the investor
    function addInvestor(address investor) external onlyRole(SPV_ADMIN_ROLE) whenNotPaused {
        if (investor == address(0)) revert InvalidAddress(investor);
        _grantRole(INVESTOR_ROLE, investor);
        emit InvestorAdded(investor);
    }

    /// @notice Removes an investor from the SPV
    /// @param investor Address of the investor
    function removeInvestor(address investor) external onlyRole(SPV_ADMIN_ROLE) whenNotPaused {
        if (investor == address(0)) revert InvalidAddress(investor);
        _revokeRole(INVESTOR_ROLE, investor);
        emit InvestorRemoved(investor);
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

    /// @notice Updates SPV manager
    /// @param newManager New manager address
    function updateManager(address newManager)
        external
        onlyRole(SPV_ADMIN_ROLE)
        whenNotPaused
    {
        if (newManager == address(0)) revert InvalidAddress(newManager);

        address oldManager = manager;
        manager = newManager;
        _grantRole(SPV_ADMIN_ROLE, newManager);
        _revokeRole(SPV_ADMIN_ROLE, oldManager);

        emit SPVManagerUpdated(oldManager, newManager);
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

    /// @notice Gets SPV details
    /// @return SPV details (spvName, kycStatus, countryCode, metadataCID, manager, assetToken, totalAssets)
    function getDetails()
        external
        view
        returns (
            string memory,
            bool,
            string memory,
            bytes32,
            address,
            address,
            uint256
        )
    {
        return (spvName, kycStatus, countryCode, metadataCID, manager, assetToken, totalAssets);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /// @notice Fallback to prevent accidental ETH transfers
    receive() external payable {
        revert InvalidParameter("direct ETH transfer not allowed");
    }
}