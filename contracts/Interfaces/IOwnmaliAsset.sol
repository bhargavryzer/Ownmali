// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC20} from "../../lib/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "../../lib/@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IIdentityRegistry} from "../../lib/@tokenysolutions/t-rex/contracts/registry/interface/IIdentityRegistry.sol";
import {IModularCompliance} from "../../lib/@tokenysolutions/t-rex/contracts/compliance/modular/IModularCompliance.sol";

/// @title Interface for OwnmaliAsset
/// @notice Defines the external and public functions, events, errors, and data structures for the OwnmaliAsset contract
interface IOwnmaliAsset is IERC20, IERC20Metadata {
    /// @notice Asset configuration parameters
    struct AssetConfig {
        string name;
        string symbol;
        bytes32 assetId;
        bytes32 assetType;
        uint256 maxSupply;
        uint256 tokenPrice;
        uint8 dividendPct;
        bytes32 metadataCID;
        bytes32 legalMetadataCID;
        address assetOwner;
        address factory;
        address identityRegistry;
        address compliance;
        uint16 chainId;
    }

    /// @notice Metadata update information
    struct MetadataUpdateInfo {
        bytes32 newCID;
        bool isLegal;
        uint8 signatureCount;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/
    event LockPeriodSet(address indexed user, uint48 unlockTime);
    event ProjectStatusChanged(bool isActive);
    event MetadataUpdateProposed(uint256 indexed updateId, bytes32 newCID, bool isLegal);
    event MetadataUpdateSigned(uint256 indexed updateId, address indexed signer);
    event MetadataUpdated(uint256 indexed updateId, bytes32 oldCID, bytes32 newCID, bool isLegal);

    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidParameter(string parameter);
    error ProjectInactive();
    error TokensLocked(address user, uint48 unlockTime);
    error InvalidMetadataUpdate(uint256 updateId);
    error AlreadySigned(address signer);
    error UpdateAlreadyExecuted(uint256 updateId);
    error UnauthorizedCaller(address caller);
    error TransferNotCompliant(address from, address to, uint256 amount);
    error ExceedsMaxSupply(uint256 amount, uint256 maxSupply);
    error MintingDisabled();
    error BurningNotAllowed();
    error InsufficientBalance(address account, uint256 balance, uint256 required);

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the asset contract
    /// @param configData Encoded AssetConfig struct
    function initialize(bytes calldata configData) external;

    /*//////////////////////////////////////////////////////////////
                         GETTERS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Returns the asset ID
    /// @return The asset ID
    function assetId() external view returns (bytes32);

    /// @notice Returns the asset type
    /// @return The asset type
    function assetType() external view returns (bytes32);
    
    /// @notice Returns the metadata CID
    /// @return The metadata CID
    function metadataCID() external view returns (bytes32);
    
    /// @notice Returns the legal metadata CID
    /// @return The legal metadata CID
    function legalMetadataCID() external view returns (bytes32);
    
    /// @notice Returns the token price
    /// @return The token price
    function tokenPrice() external view returns (uint256);
    
    /// @notice Returns the dividend percentage
    /// @return The dividend percentage
    function dividendPct() external view returns (uint8);
    
    /// @notice Returns the maximum supply
    /// @return The maximum supply
    function maxSupply() external view returns (uint256);
    
    /// @notice Returns the chain ID
    /// @return The chain ID
    function chainId() external view returns (uint16);
    
    /// @notice Returns the asset owner
    /// @return The asset owner address
    function assetOwner() external view returns (address);
    
    /// @notice Returns the factory address
    /// @return The factory address
    function factory() external view returns (address);
    
    /// @notice Returns the identity registry
    /// @return The identity registry address
    function identityRegistry() external view returns (IIdentityRegistry);
    
    /// @notice Returns the compliance module
    /// @return The compliance module address
    function compliance() external view returns (IModularCompliance);
    
    /// @notice Returns the unlock time for a user
    /// @param user The user address
    /// @return The unlock timestamp
    function unlockTime(address user) external view returns (uint48);
    
    /// @notice Returns whether the project is active
    /// @return True if active, false otherwise
    function isActive() external view returns (bool);
    
    /// @notice Returns metadata update information
    /// @param updateId The update ID
    /// @return newCID The new CID
    /// @return isLegal Whether the update is for legal metadata
    /// @return signatureCount The number of signatures
    /// @return executed Whether the update has been executed
    function getMetadataUpdate(uint256 updateId) 
        external 
        view 
        returns (bytes32 newCID, bool isLegal, uint8 signatureCount, bool executed);
        
    /// @notice Returns the total number of metadata updates
    /// @return The total number of updates
    function metadataUpdateCount() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                         STATE CHANGING
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Proposes a metadata update
    /// @param newCID The new metadata CID
    /// @param isLegal Whether the update is for legal metadata
    function proposeMetadataUpdate(bytes32 newCID, bool isLegal) external;
    
    /// @notice Approves a metadata update
    /// @param updateId The update ID to approve
    function approveMetadataUpdate(uint256 updateId) external;
    
    /// @notice Executes a metadata update
    /// @param updateId The update ID to execute
    function executeMetadataUpdate(uint256 updateId) external;
    
    /// @notice Sets the unlock time for a user
    /// @param user The user address
    /// @param unlockTimestamp The unlock timestamp
    function setUnlockTime(address user, uint48 unlockTimestamp) external;
    
    /// @notice Sets the project active status
    /// @param active The new active status
    function setProjectActive(bool active) external;
    
    /// @notice Pauses the contract
    function pause() external;
    
    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Returns the asset type
    /// @return The asset type
    function assetType() external view returns (bytes32);

    /// @notice Returns the metadata CID
    /// @return The metadata CID
    function metadataCID() external view returns (bytes32);

    /// @notice Returns the legal metadata CID
    /// @return The legal metadata CID
    function legalMetadataCID() external view returns (bytes32);

    /// @notice Returns the token price in wei
    /// @return The token price in wei
    function tokenPrice() external view returns (uint256);

    /// @notice Returns the cancel delay in seconds
    /// @return The cancel delay in seconds
    function cancelDelay() external view returns (uint256);

    /// @notice Returns the project owner address
    /// @return The project owner address
    function projectOwner() external view returns (address);

    /// @notice Returns the factory address
    /// @return The factory address
    function factory() external view returns (address);

    /// @notice Returns the maximum supply of tokens
    /// @return The maximum supply of tokens
    function maxSupply() external view returns (uint256);

    /// @notice Returns whether the asset is active
    /// @return True if the asset is active, false otherwise
    function isActive() external view returns (bool);

    /// @notice Returns the number of metadata updates
    /// @return The number of metadata updates
    function metadataUpdateCount() external view returns (uint256);

    /// @notice Returns metadata update information by ID
    /// @param updateId The update ID
    /// @return newCID The new metadata CID
    /// @return isLegal Whether the update is for legal metadata
    /// @return signatureCount The number of signatures required for the update
    /// @return executed Whether the update has been executed
    function getMetadataUpdate(uint256 updateId)
        external
        view
        returns (bytes32 newCID, bool isLegal, uint256 signatureCount, bool executed);
}
