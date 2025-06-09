// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IOwnmaliProject.sol";
import "./interfaces/IOwnmaliRegistry.sol";
import "./interfaces/IOwnmaliEscrow.sol";
import "./interfaces/IOwnmaliOrderManager.sol";
import "./interfaces/IOwnmaliDAO.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliFactory
/// @notice Factory contract for creating and managing Ownmali projects
/// @dev Deploys clones of project-related contracts with ERC-3643 compliance
contract OwnmaliFactory is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using OwnmaliValidation for *;

    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error InvalidCompanyId(bytes32 companyId);
    error InvalidProjectId(bytes32 projectId);
    error TemplateNotSet(string template);
    error ProjectAlreadyExists(bytes32 projectId);

    /*//////////////////////////////////////////////////////////////
                         TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct CompanyParams {
        bytes32 companyId;
        string name;
        bool kycStatus;
        string countryCode;
        bytes32 metadataCID;
        address owner;
    }

    struct ProjectParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        bytes32 companyId;
        bytes32 assetId;
        bytes32 metadataCID;
        bytes32 assetType;
        bytes32 legalMetadataCID;
        uint16 chainId;
        uint256 dividendPct;
        uint256 premintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint256 eoiPct;
        bool isRealEstate;
    }

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant COMPANY_CREATOR_ROLE = keccak256("COMPANY_CREATOR_ROLE");

    address public registry;
    address public projectTemplate;
    address public realEstateTemplate;
    address public escrowTemplate;
    address public orderManagerTemplate;
    address public daoTemplate;
    address public identityRegistry;
    address public compliance;
    mapping(bytes32 => address) public projects;

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event CompanyCreated(
        bytes32 indexed companyId,
        address indexed companyContract,
        string name,
        bool kycStatus,
        string countryCode,
        bytes32 metadataCID,
        address owner
    );
    event ProjectCreated(
        bytes32 indexed companyId,
        bytes32 indexed projectId,
        address project,
        address escrow,
        address orderManager,
        address dao
    );
    event TemplateSet(string indexed templateType, address template);
    event RegistrySet(address indexed registry);
    event IdentityRegistrySet(address indexed identityRegistry);
    event ComplianceSet(address indexed compliance);

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the factory
    /// @param _registry Address of the OwnmaliRegistry contract
    /// @param _admin Admin address for role assignment
    /// @param _identityRegistry Identity registry address for ERC-3643 compliance
    /// @param _compliance Compliance contract address
    function initialize(
        address _registry,
        address _admin,
        address _identityRegistry,
        address _compliance
    ) external initializer {
        if (_registry == address(0) || _admin == address(0) || _identityRegistry == address(0) || _compliance == address(0)) {
            revert InvalidAddress(address(0));
        }

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        registry = _registry;
        identityRegistry = _identityRegistry;
        compliance = _compliance;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(COMPANY_CREATOR_ROLE, _admin);
        _setRoleAdmin(COMPANY_CREATOR_ROLE, ADMIN_ROLE);

        emit RegistrySet(_registry);
        emit IdentityRegistrySet(_identityRegistry);
        emit ComplianceSet(_compliance);
    }

    /// @notice Sets template addresses for project-related contracts
    /// @param _projectTemplate Standard project template
    /// @param _realEstateTemplate Real estate project template
    /// @param _escrowTemplate Escrow contract template
    /// @param _orderManagerTemplate Order manager template
    /// @param _daoTemplate DAO template
    function setTemplates(
        address _projectTemplate,
        address _realEstateTemplate,
        address _escrowTemplate,
        address _orderManagerTemplate,
        address _daoTemplate
    ) external onlyRole(ADMIN_ROLE) {
        if (
            _projectTemplate == address(0) ||
            _realEstateTemplate == address(0) ||
            _escrowTemplate == address(0) ||
            _orderManagerTemplate == address(0) ||
            _daoTemplate == address(0)
        ) revert InvalidAddress(address(0));

        projectTemplate = _projectTemplate;
        realEstateTemplate = _realEstateTemplate;
        escrowTemplate = _escrowTemplate;
        orderManagerTemplate = _orderManagerTemplate;
        daoTemplate = _daoTemplate;

        emit TemplateSet("Project", _projectTemplate);
        emit TemplateSet("RealEstate", _realEstateTemplate);
        emit TemplateSet("Escrow", _escrowTemplate);
        emit TemplateSet("OrderManager", _orderManagerTemplate);
        emit TemplateSet("DAO", _daoTemplate);
    }

    /// @notice Creates a new company by registering it in the registry
    /// @param params Company parameters (ID, name, KYC status, country code, metadata CID, owner)
    function createCompany(CompanyParams calldata params) external onlyRole(COMPANY_CREATOR_ROLE) nonReentrant whenNotPaused {
        params.companyId.validateId("companyId");
        params.name.validateString("name", 1, 100);
        params.countryCode.validateString("countryCode", 2, 2);
        params.metadataCID.validateCID("metadataCID");
        if (params.owner == address(0)) revert InvalidAddress(params.owner);

        // Register company in the registry (deploys Company contract)
        IOwnmaliRegistry(registry).registerCompany(
            params.companyId,
            params.name,
            params.kycStatus,
            params.countryCode,
            params.metadataCID,
            params.owner
        );

        // Get the deployed Company contract address
        address companyContract = IOwnmaliRegistry(registry).getCompanyAddress(params.companyId);

        emit CompanyCreated(
            params.companyId,
            companyContract,
            params.name,
            params.kycStatus,
            params.countryCode,
            params.metadataCID,
            params.owner
        );
    }

    /// @notice Creates a new project with associated contracts
    /// @param params Project parameters (name, symbol, supply, price, etc.)
    function createProject(ProjectParams calldata params) external nonReentrant whenNotPaused {
        params.companyId.validateId("companyId");
        params.assetId.validateId("assetId");
        params.name.validateString("name", 1, 100);
        params.symbol.validateString("symbol", 1, 10);
        params.metadataCID.validateCID("metadataCID");
        params.legalMetadataCID.validateCID("legalMetadataCID");
        if (params.maxSupply == 0) revert InvalidParameter("maxSupply");
        if (params.tokenPrice == 0) revert InvalidParameter("tokenPrice");
        if (params.cancelDelay == 0) revert InvalidParameter("cancelDelay");
        if (params.chainId == 0) revert InvalidParameter("chainId");
        if (params.dividendPct > 50) revert InvalidParameter("dividendPct");
        if (params.eoiPct > 50) revert InvalidParameter("eoiPct");
        if (params.minInvestment == 0) revert InvalidParameter("minInvestment");
        if (params.maxInvestment < params.minInvestment) revert InvalidParameter("maxInvestment");
        if (params.premintAmount > params.maxSupply) revert InvalidParameter("premintAmount");
        if (projects[params.assetId] != address(0)) revert ProjectAlreadyExists(params.assetId);

        // Verify company exists
        if (IOwnmaliRegistry(registry).getCompanyAddress(params.companyId) == address(0)) {
            revert InvalidCompanyId(params.companyId);
        }

        // Deploy project contract
        address projectTemplateToUse = params.isRealEstate ? realEstateTemplate : projectTemplate;
        if (projectTemplateToUse == address(0)) revert TemplateNotSet(params.isRealEstate ? "RealEstate" : "Project");
        address project = Clones.clone(projectTemplateToUse);

        // Deploy related contracts
        if (escrowTemplate == address(0)) revert TemplateNotSet("Escrow");
        if (orderManagerTemplate == address(0)) revert TemplateNotSet("OrderManager");
        if (daoTemplate == address(0)) revert TemplateNotSet("DAO");
        address escrow = Clones.clone(escrowTemplate);
        address orderManager = Clones.clone(orderManagerTemplate);
        address dao = Clones.clone(daoTemplate);

        // Initialize project
        IOwnmaliProject.ProjectInitParams memory initParams = IOwnmaliProject.ProjectInitParams({
            name: params.name,
            symbol: params.symbol,
            maxSupply: params.maxSupply,
            tokenPrice: params.tokenPrice,
            cancelDelay: params.cancelDelay,
            projectOwner: msg.sender,
            factory: address(this),
            companyId: params.companyId,
            assetId: params.assetId,
            metadataCID: params.metadataCID,
            assetType: params.assetType,
            legalMetadataCID: params.legalMetadataCID,
            chainId: params.chainId,
            dividendPct: params.dividendPct,
            premintAmount: params.premintAmount,
            minInvestment: params.minInvestment,
            maxInvestment: params.maxInvestment,
            eoiCid: params.eoiPct,
            identityRegistry: identityRegistry,
            compliance: compliance
        });
        IOwnmaliProject(project).initialize(initParams);

        // Initialize related contracts
        IOwnmaliEscrow(escrow).initialize(project, msg.sender);
        IOwnmaliOrderManager(orderManager).initialize(project, msg.sender);
        IOwnmaliDAO(dao).initialize(project, msg.sender, 7 days, 1e18, 51);

        // Set project contracts and premint
        IOwnmaliProject(project).setProjectContractsAndPreMint(escrow, orderManager, dao, params.premintAmount);

        // Register project in registry
        IOwnmaliRegistry(registry).registerProject(
            params.companyId,
            params.assetId,
            params.name,
            params.assetType,
            project,
            params.metadataCID
        );

        projects[params.assetId] = project;

        emit ProjectCreated(params.companyId, params.assetId, project, escrow, orderManager, dao);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets the project address for an asset ID
    /// @param assetId The asset ID of the project
    /// @return Address of the project contract
    function getProject(bytes32 assetId) external view returns (address) {
        return projects[assetId];
    }
}