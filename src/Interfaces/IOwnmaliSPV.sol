// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IOwnmaliSPV
/// @notice Interface for OwnmaliSPV contract
interface IOwnmaliSPV {
    function balanceOf(address account) external view returns (uint256);
    function totalSupply() external view returns (uint256);
    function getDetails() external view returns (
        string memory spvName,
        bool kycStatus,
        string memory countryCode,
        bytes32 metadataCID,
        address owner,
        string memory assetDescription,
        string memory spvPurpose
    );
    function updateMetadata(bytes32 newMetadataCID) external;
    function updateAssetDescription(string calldata newAssetDescription) external;
    function updateSPVPurpose(string calldata newSpvPurpose) external;
    function updateOwner(address newOwner) external;
    function updateKycStatus(bool _kycStatus) external;
}