// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "../lib/@tokenysolutions/t-rex/contracts/token/IToken.sol";

/// @title IOwnmaliAsset
/// @notice Interface for the OwnmaliAsset contract, an ERC-3643 compliant token for asset tokenization.
interface IOwnmaliAsset is
    Initializable,
    UUPSUpgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    IToken
{
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr, string parameter);
    error InvalidString(string value, string parameter);
    error InvalidId(bytes32 id, string parameter);
    error InvalidAmount(uint256 value, string parameter);
    error AssetInactive();
    error TokensLocked(address account, uint48 unlockTime);
    error TimelockNotExpired(uint48 unlockTime);
    error TransferNotCompliant(address from, address to, uint256 amount);
    error ExceedsMaxSupply(uint256 totalSupply, uint256 maxSupply);
    error PremintCompleted();
    error ArrayLengthMismatch(uint256 recipients, uint256 amounts);
    error InvalidRecipientCount(uint256 count);

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Asset configuration structure.
    struct AssetConfig {
        bytes32 assetId;
        bytes32 assetType;
        uint256 maxSupply;
        uint128 tokenPrice;
        uint8 dividendPct;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
    }

    /// @notice Structure for pending updates with timelock.
    struct PendingUpdate {
        bytes32 value;
        bytes32 role;
        bool isLegal;
        bool grant;
        address account;
        uint48 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event PremintCompleted(uint256 totalSupply, uint256 timestamp);
    event Preminted(address indexed operator, uint256 totalAmount, uint256 recipientCount);
    event LockPeriodSet(address indexed account, uint48 unlockTime);
    event AssetStatusChanged(bool isActive);
    event TokenPriceUpdated(uint128 oldPrice, uint128 newPrice);
    event DividendPctUpdated(uint8 oldPct, uint8 newPct);
    event MetadataUpdated(bytes32 oldCID, bytes32 newCID, bool isLegal);

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        string memory name,
        string memory symbol,
        address identityRegistry,
        address compliance,
        address owner,
        address admin,
        address operator,
        bytes calldata configData
    ) external;

    /*//////////////////////////////////////////////////////////////
                           TOKEN MANAGEMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function premint(address[] calldata recipients, uint256[] calldata amounts) external;
    function completePremint() external;

    /*//////////////////////////////////////////////////////////////
                           CONFIGURATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function updateMetadata(bytes32 newCID, bool isLegal) external;
    function batchSetLockPeriod(address[] calldata accounts, uint48[] calldata unlockTimes) external;
    function setAssetStatus(bool isActive_) external;
    function setTokenPrice(uint128 tokenPrice_) external;
    function setDividendPct(uint8 dividendPct_) external;
    function setRole(bytes32 role, address account, bool grant) external;
    function revokeRole(bytes32 role, address account) external;
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                           VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getAssetConfig() external view returns (AssetConfig memory config);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function MAX_DIVIDEND_PCT() external view returns (uint8);
    function TIMELOCK_DURATION() external view returns (uint48);
    function ASSET_ADMIN_ROLE() external view returns (bytes32);
    function ASSET_OPERATOR_ROLE() external view returns (bytes32);
    function assetId() external view returns (bytes32);
    function assetType() external view returns (bytes32);
    function metadataCID() external view returns (bytes32);
    function legalMetadataCID() external view returns (bytes32);
    function tokenPrice() external view returns (uint128);
    function dividendPct() external view returns (uint8);
    function maxSupply() external view returns (uint256);
    function isActive() external view returns (bool);
    function isPremintCompleted() external view returns (bool);
    function unlockTime(address account) external view returns (uint48);
    function pendingUpdates(bytes32 actionId) external view returns (PendingUpdate memory);
}