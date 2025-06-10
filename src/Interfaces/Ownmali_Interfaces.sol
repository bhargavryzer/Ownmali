// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20MetadataUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";

interface IOwnmaliAsset is IERC20Upgradeable, IERC20MetadataUpgradeable {
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

    function initialize(AssetInitParams memory params) external;
    function setAssetContractsAndPreMint(
        address assetManager,
        address financialLedger,
        address orderManager,
        address spvDao,
        uint256 premintAmount
    ) external;
    function mint(address to, uint256 amount) external;
    function lock(address account, uint256 amount, uint256 unlockTime) external;
    function unlock(address account, uint256 amount) external;
    function updateMetadata(bytes32 newCID, bool isLegal) external;
    function setActive(bool isActive) external;
    function pause() external;
    function unpause() external;
    function lockedUntil(address account) external view returns (uint256);
    function isActive() external view returns (bool);
}

interface IOwnmaliAssetManager {
    function initialize(address projectOwner, address asset, bytes32 spvId, bytes32 assetId) external;
    function setOrderManager(address orderManager) external;
    function mintTokens(address recipient, uint256 amount) external;
    function transferTokens(address from, address to, uint256 amount) external;
    function lockTokens(address account, uint256 amount, uint256 unlockTime) external;
    function releaseTokens(address account, uint256 amount) external;
    function pause() external;
    function unpause() external;
}

interface IOwnmaliFinancialLedger {
    function initialize(address projectOwner, address asset, bytes32 spvId, bytes32 assetId) external;
    function setOrderManager(address orderManager) external;
    function setMaxWithdrawalsPerTx(uint256 maxWithdrawals) external;
    function transferTo(address recipient, uint256 amount, string calldata purpose) external;
    function transferToOwner(uint256 amount, string calldata purpose) external;
    function emergencyWithdrawal(
        address[] calldata recipients,
        uint256[] calldata amounts,
        string[] calldata purposes
    ) external;
    function getBalance() external view returns (uint256);
    function getTransaction(uint256 txId) external view returns (
        address sender,
        address recipient,
        uint256 amount,
        uint8 txType,
        string memory purpose,
        uint256 timestamp
    );
    function pause() external;
    function unpause() external;
}

interface IOwnmaliOrderManager {
    function initialize(address financialLedger, address asset, address projectOwner) external;
    function pause() external;
    function unpause() external;
}

interface IOwnmaliSPVDAO {
    function initialize(address projectOwner, address asset, bytes32 spvId, bytes32 assetId) external;
    function pause() external;
    function unpause() external;
}