// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./IOwnmaliAsset.sol";

/// @title IOwnmaliRealEstateToken
/// @notice Interface for the OwnmaliRealEstateToken contract, an ERC-3643 compliant token for real estate asset tokenization with premint-only mechanism.
interface IOwnmaliRealEstateToken is IOwnmaliAsset {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TimelockNotExpired(uint48 unlockTime);
    error InvalidReason();
    error InvalidAddress(address addr);
    error InvalidAmount(uint256 amount);
    error InsufficientBalance(address account, uint256 balance, uint256 amount);
    error MintingDisabled();
    error BurningNotAllowed();

    /*//////////////////////////////////////////////////////////////
                             TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    struct ForcedTransferRequest {
        address from;
        address to;
        uint256 amount;
        string reason;
        uint48 unlockTime;
    }

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function initialize(
        string memory name,
        string memory symbol,
        address identityRegistry,
        address compliance,
        address assetOwner,
        bytes calldata configData,
        address[] calldata initialRecipients,
        uint256[] calldata initialAmounts
    ) external;
    function batchPremint(address[] calldata to, uint256[] calldata amounts) external;
    function forcedTransfer(address from, address to, uint256 amount, string calldata reason) external;
    function setTransferRole(address account, bool grant) external;
    function setPremintRole(address account, bool grant) external;
    function mint(address to, uint256 amount) external pure;
    function burn(address account, uint256 amount) external pure;
    function burnFrom(address account, uint256 amount) external pure;
    function getRealEstateConfig() external view returns (bytes32[] memory supportedAssetTypes, uint256 remainingSupply);

    /*//////////////////////////////////////////////////////////////
                           STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function TRANSFER_ROLE() external view returns (bytes32);
    function PREMINT_ROLE() external view returns (bytes32);
    function MAX_BATCH_SIZE() external view returns (uint256);
    function TIMELOCK_DURATION() external view returns (uint48);
    function forcedTransferRequest() external view returns (ForcedTransferRequest memory);
    function roleTimelocks(bytes32 actionId) external view returns (uint48);
}