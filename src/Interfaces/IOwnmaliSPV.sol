// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title IOwnmaliSPV
/// @notice Interface for OwnmaliSPV contract
interface IOwnmaliSPV {
    function updateMetadata(bytes32 newMetadataCID) external;
    function updateKycStatus(bool _kycStatus) external;
    function updateOwner(address newOwner) external;
    function setRegistry(address _registry) external;
    function updateAssetDescription(string calldata newAssetDescription) external;
    function updateSPVPurpose(string calldata newSpvPurpose) external;
    function grantInvestorRole(address investor) external;
    function revokeInvestorRole(address investor) external;
    function getDetails() external view returns (
        string memory spvName,
        bool kycStatus,
        string memory countryCode,
        bytes32 metadataCID,
        address owner,
        string memory assetDescription,
        string memory spvPurpose
    );
    function getInvestorDetails() external view returns (
        string memory spvName,
        string memory assetDescription,
        string memory spvPurpose
    );
    function pause() external;
    function unpause() external;
}
