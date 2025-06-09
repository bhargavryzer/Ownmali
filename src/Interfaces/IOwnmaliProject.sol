// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ITREXFactory} from "@tokenysolutions/t-rex/factory/ITREXFactory.sol";
import {ITREXGateway} from "@tokenysolutions/t-rex/factory/ITREXGateway.sol";

interface IOwnmaliProject {
    function initialize(
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint256 tokenPrice,
        uint256 cancelDelay,
        address projectOwner,
        address factory,
        bytes32 companyId,
        bytes32 assetId,
        bytes32 metadataCID,
        bytes32 assetType,
        bytes32 legalMetadataCID,
        uint16 chainId,
        uint256 dividendPct,
        uint256 premintAmount,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 eoiPct,
        address identityRegistry,
        address compliance
    ) external;

    function getProjectDetails() external view returns (
        string memory name,
        string memory symbol,
        uint256 maxSupply,
        uint256 tokenPrice,
        uint256 cancelDelay,
        uint256 dividendPct,
        uint256 minInvestment,
        uint256 maxInvestment,
        bytes32 assetType,
        bytes32 metadataCID,
        bytes32 legalMetadataCID,
        bytes32 companyId,
        bytes32 assetId,
        address projectOwner,
        address factoryOwner,
        address escrow,
        address orderManager,
        address dao,
        address owner,
        uint16 chainId,
        bool isActive
    );

    function compliance() external view returns (address);
    function getIsActive() external view returns (bool);
    function transferWithData(address to, uint256 amount, bytes calldata data) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function pause() external;
    function unpause() external;
}
