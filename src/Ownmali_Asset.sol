// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "./Ownmali_Interfaces.sol";
import "./Ownmali_Validation.sol";

/// @title OwnmaliAsset
/// @notice Tokenized asset contract for an SPV in the Ownmali ecosystem
/// @dev Manages ERC20 token issuance and SPV-specific operations, upgradeable with role-based access control
contract OwnmaliAsset is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
    IERC20Upgradeable,
    IERC20MetadataUpgradeable,
{
    using OwnmaliValidation for *;

    /*/////////////////////////////////////////////////////
    /*                             ERRORS
    //////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error AssetInactive();
    error InvalidMetadataCID(bytes32 cid);
    error InvalidAssetType(bytes32 assetType);
    error TokensLocked(address user, uint48 unlockTime);
    error Unauthorized();

    /*/////////////////////////////////////////////////////
    /*                           TYPE DECLARATIONS
    //////////////////////////////////////////////////////*/
    struct AssetInitParams {
        string name;
        string symbol;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint256 cancelDelay;
        address projectOwner;
        address factory;
        bytes32 spvId;
        bytes32 assetId;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        bytes32 assetType;
        uint256 dividendPct;
        uint256 premintAmount;
        uint256 minInvestment;
        uint256 maxInvestment;
        uint16 chainId;
        uint256 eoiPct;
        address identityRegistry;
        address compliance;
    }

    /*/////////////////////////////////////////////////////
    /*                           STATE VARIABLES
    //////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant ASSET_MANAGER_ROLE = keccak256("ASSET_MANAGER_ROLE");

    string private _name;
    string private _symbol;
    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    mapping(address => uint256) public lockedUntil;

    address public projectOwner;
    address public factory;
    bytes32 public spvId;
    bytes32 public assetId;
    bytes32 public metadataCID;
    bytes32 public legalMetadataCID;
    bytes32 public assetType;
    uint256 public maxSupply;
    uint256 public tokenPrice;
    uint256 public cancelDelay;
    uint256 public dividendPct;
    uint256 public minInvestment;
    uint256 public maxInvestment;
    uint16 public chainId;
    uint256 public eoiPct;
    address public identityRegistry;
    address public compliance;
    bool public isActive;
    address public assetManager;
    address public financialLedger;
    address public orderManager;
    address public spvDao;

    /*/////////////////////////////////////////////////////
    /*                             EVENTS
    //////////////////////////////////////////////////////*/
    event AssetActivated();
    event AssetDeactivated();
    event MetadataUpdated(bytes32 newCID, bool isLegal);
    event AssetContractsSet(address assetManager, address financialLedger, address orderManager, address spvDao);
    event TokensMinted(address indexed to, uint256 amount);
    event TokensLocked(address indexed account, uint256 amount, uint256 unlockTime);
    event TokensUnlocked(address indexed account, uint256 amount);

    /*/////////////////////////////////////////////////////
    /*                           INITIALIZATION
    //////////////////////////////////////////////////////*/

    /// @notice Initializes the asset contract
    /// @param params Asset initialization parameters
    function initialize(AssetInitParams memory params) public initializer {
        if (params.projectOwner == address(0)) revert InvalidAddress(params.projectOwner);
        params.spvId.validateId("spvId");
        params.assetId.validateId("assetId");
        params.name.validateString("name", 1, 100);
        params.symbol.validateString("symbol", 1, 10);
        params.metadataCID.validateCID("metadataCID");
        params.legalMetadataCID.validateCID("legalMetadataCID");

        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _name = params.name;
        _symbol = params.symbol;
        maxSupply = params.maxSupply;
        tokenPrice = params.tokenPrice;
        cancelDelay = params.cancelDelay;
        projectOwner = params.projectOwner;
        factory = params.factory;
        spvId = params.spvId;
        assetId = params.assetId;
        metadataCID = params.metadataCID;
        legalMetadataCID = params.legalMetadataCID;
        assetType = params.assetType;
        dividendPct = params.dividendPct;
        minInvestment = params.minInvestment;
        maxInvestment = params.maxInvestment;
        chainId = params.chainId;
        eoiPct = params.eoiPct;
        identityRegistry = params.identityRegistry;
        compliance = params.compliance;
        isActive = true;

        _grantRole(DEFAULT_ADMIN_ROLE, params.projectOwner);
        _grantRole(ADMIN_ROLE, params.projectOwner);
        _grantRole(ASSET_MANAGER_ROLE, params.projectOwner);
        _setRoleAdmin(ASSET_MANAGER_ROLE, ADMIN_ROLE);

        emit AssetActivated();
    }

    /*/////////////////////////////////////////////////////
    /*                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////*/

    /// @notice Sets asset contracts and premints tokens
    /// @param _assetManager Asset manager address
    /// @param _financialLedger Financial ledger address
    /// @param _orderManager Order manager address
    /// @param _spvDao SPV DAO address
    /// @param _premintAmount Amount to premint
    function setAssetContractsAndPreMint(
        address _assetManager,
        address _financialLedger,
        address _orderManager,
        address _spvDao,
        uint256 _premintAmount
    ) external onlyRole(ADMIN_ROLE) {
        if (_assetManager == address(0) || _financialLedger == address(0) || _orderManager == address(0) || _spvDao == address(0)) {
            revert InvalidAddress(address(0), "contract address");
        }
        if (_premintAmount > maxSupply) revert InvalidParameter("premintAmount", "exceeds maxSupply");

        assetManager = _assetManager;
        financialLedger = _financialLedger;
        orderManager = _orderManager;
        spvDao = _spvDao;

        if (_premintAmount > 0) {
            _mint(projectOwner, _premintAmount);
        }

        emit AssetContractsSet(_assetManager, _financialLedger, _orderManager, _spvDao);
    }

    /// @notice Mints tokens to a recipient
    /// @param to Recipient address
    /// @param amount Amount of tokens
    function mint(address to, uint256 amount) external onlyRole(ASSET_MANAGER_ROLE) whenNotPaused {
        if (to == address(0)) revert InvalidAddress(to, "recipient");
        if (amount == 0) revert InvalidParameter("amount", "must be non-zero");
        if (_totalSupply + amount > maxSupply) revert InvalidParameter("amount", "exceeds maxSupply");

        _mint(to, amount);
    }

    /// @notice Locks tokens for an account
    /// @param account Account to lock tokens for
    /// @param amount Amount of tokens
    /// @param unlockTime Unlock timestamp
    function lock(address account, uint256 amount, uint256 unlockTime) external onlyRole(ASSET_MANAGER_ROLE) whenNotPaused {
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (amount == 0) revert InvalidParameter("amount", "must be non-zero");
        if (unlockTime <= block.timestamp) revert InvalidParameter("unlockTime", "must be in future");
        if (_balances[account] < amount) revert InvalidParameter("amount", "insufficient balance");

        lockedUntil[account] = unlockTime;
        emit TokensLocked(account, amount, unlockTime);
    }

    /// @notice Unlocks tokens for an account
    /// @param account Account to unlock tokens for
    /// @param amount Amount of tokens
    function unlock(address account, uint256 amount) external onlyRole(ASSET_MANAGER_ROLE) whenNotPaused {
        if (account == address(0)) revert InvalidAddress(account, "account");
        if (amount == 0) revert InvalidParameter("amount", "must be non-zero");
        if (lockedUntil[account] == 0 || lockedUntil[account] > block.timestamp) {
            revert TokensLocked(account, uint48(lockedUntil[account]));
        }

        lockedUntil[account] = 0;
        emit TokensUnlocked(account, amount);
    }

    /// @notice Updates metadata CID
    /// @param newCID New metadata CID
    /// @param isLegal Whether the CID is for legal metadata
    function updateMetadata(bytes32 newCID, bool isLegal) external onlyRole(ADMIN_ROLE) {
        newCID.validateCID(isLegal ? "legalMetadataCID" : "metadataCID");
        if (isLegal) {
            legalMetadataCID = newCID;
        } else {
            metadataCID = newCID;
        }
        emit MetadataUpdated(newCID, isLegal);
    }

    /// @notice Sets asset active status
    /// @param _isActive New active status
    function setActive(bool _isActive) external onlyRole(ADMIN_ROLE) {
        isActive = _isActive;
        emit _isActive ? AssetActivated() : AssetDeactivated();
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
                           ERC20 FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function name() external view override returns (string memory) {
        return _name;
    }

    function symbol() external view override returns (string memory) {
        return _symbol;
    }

    function decimals() external view override returns (uint8) {
        return 18;
    }

    function totalSupply() external view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external override whenNotPaused returns (bool) {
        if (!isActive) revert AssetInactive();
        if (lockedUntil[msg.sender] > block.timestamp) revert TokensLocked(msg.sender, uint48(lockedUntil[msg.sender]));
        _transfer(msg.sender, to, amount);
        return true;
    }

    function allowance(address owner_, address spender) external view override returns (uint256) {
        return _allowances[owner_][spender];
    }

    function approve(address spender, uint256 amount) external override whenNotPaused returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override whenNotPaused returns (bool) {
        if (!isActive) revert AssetInactive();
        if (lockedUntil[from] > block.timestamp) revert TokensLocked(from, uint48(lockedUntil[from]));
        _spendAllowance(from, msg.sender, amount);
        _transfer(from, to, amount);
        return true;
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    function _mint(address to, uint256 amount) internal {
        _totalSupply += amount;
        _balances[to] += amount;
        emit Transfer(address(0), to, amount);
        emit TokensMinted(to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal {
        if (from == address(0) || to == address(0)) revert InvalidAddress(from == address(0) ? from : to, "account");
        if (_balances[from] < amount) revert InvalidParameter("amount", "insufficient balance");
        _balances[from] -= amount;
        _balances[to] += amount;
        emit Transfer(from, to, amount);
    }

    function _approve(address owner_, address spender, uint256 amount) internal {
        if (owner_ == address(0) || spender == address(0)) revert InvalidAddress(owner_ == address(0) ? owner_ : spender, "account");
        _allowances[owner_][spender] = amount;
        emit Approval(owner_, spender, amount);
    }

    function _spendAllowance(address owner_, address spender, uint256 amount) internal {
        uint256 currentAllowance = _allowances[owner_][spender];
        if (currentAllowance != type(uint256).max) {
            if (currentAllowance < amount) revert InvalidParameter("amount", "insufficient allowance");
            _approve(owner_, spender, currentAllowance - amount);
        }
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation, "newImplementation");
        }
    }
}