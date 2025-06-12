// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./Ownmali_Asset.sol";

/**
 * @title OwnmaliRealEstateToken
 * @notice ERC-3643 compliant token for real estate asset tokenization with premint-only mechanism.
 * @dev Tokens represent real estate assets and are fully tokenized during premint; no further minting or burning is allowed.
 */
contract OwnmaliRealEstateToken is OwnmaliAsset {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error TimelockNotExpired(uint48 unlockTime);
    error InvalidReason();

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
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 public constant PREMINT_ROLE = keccak256("PREMINT_ROLE");
    uint256 public constant MAX_BATCH_SIZE = 100;
    uint48 public constant TIMELOCK_DURATION = 1 days;

    /*//////////////////////////////////////////////////////////////
                             STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    ForcedTransferRequest public forcedTransferRequest;
    mapping(bytes32 => uint48) public roleTimelocks;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);

    /*//////////////////////////////////////////////////////////////
                             INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the real estate asset contract with optional initial premint.
     * @param name Token name.
     * @param symbol Token symbol.
     * @param identityRegistry Identity registry address.
     * @param compliance Compliance contract address.
     * @param assetOwner Asset owner address.
     * @param configData Encoded AssetConfig.
     * @param initialRecipients Initial premint recipients.
     * @param initialAmounts Initial premint amounts.
     */
    function initialize(
        string memory name,
        string memory symbol,
        address identityRegistry,
        address compliance,
        address assetOwner,
        bytes calldata configData,
        address[] calldata initialRecipients,
        uint256[] calldata initialAmounts
    ) public override initializer {
        // Initialize parent contract
        super.initialize(name, symbol, identityRegistry, compliance, assetOwner, configData);

        // Setup roles
        _setRoleAdmin(TRANSFER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(PREMINT_ROLE, ADMIN_ROLE);
        _grantRole(TRANSFER_ROLE, assetOwner);
        _grantRole(PREMINT_ROLE, assetOwner);

        // Handle initial premint
        if (initialRecipients.length > 0) {
            batchPremint(initialRecipients, initialAmounts);
        }
    }

    /*//////////////////////////////////////////////////////////////
                           EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Premints tokens to multiple addresses during tokenization phase.
     * @param to Recipient addresses.
     * @param amounts Amounts to premint.
     */
    function batchPremint(address[] calldata to, uint256[] calldata amounts)
        public
        onlyRole(PREMINT_ROLE)
        whenNotPaused
        onlyActiveAsset
    {
        if (to.length > MAX_BATCH_SIZE) revert OwnmaliValidation.InvalidAmount(to.length);
        super.premint(to, amounts);
    }

    /**
     * @notice Proposes or executes a forced transfer for legal/regulatory reasons.
     * @param from Source address.
     * @param to Destination address.
     * @param amount Amount to transfer.
     * @param reason Reason for forced transfer.
     */
    function forcedTransfer(
        address from,
        address to,
        uint256 amount,
        string calldata reason
    ) external onlyRole(TRANSFER_ROLE) whenNotPaused onlyActiveAsset {
        if (from == address(0) || to == address(0)) revert InvalidAddress(from == address(0) ? from : to);
        if (amount == 0) revert OwnmaliValidation.InvalidAmount(0);
        if (bytes(reason).length == 0) revert InvalidReason();

        bytes32 requestId = keccak256(abi.encode(from, to, amount, reason));
        if (forcedTransferRequest.from != from ||
            forcedTransferRequest.to != to ||
            forcedTransferRequest.amount != amount ||
            keccak256(bytes(forcedTransferRequest.reason)) != keccak256(bytes(reason)))
        {
            forcedTransferRequest = ForcedTransferRequest({
                from: from,
                to: to,
                amount: amount,
                reason: reason,
                unlockTime: uint48(block.timestamp) + TIMELOCK_DURATION
            });
            return;
        }

        if (block.timestamp < forcedTransferRequest.unlockTime) {
            revert TimelockNotExpired(forcedTransferRequest.unlockTime);
        }

        uint256 balance = balanceOf(from);
        if (balance < amount) revert OwnmaliValidation.InsufficientBalance(from, balance, amount);

        _forceTransfer(from, to, amount);
        delete forcedTransferRequest;
        emit ForcedTransfer(from, to, amount, reason);
    }

    /**
     * @notice Grants or revokes the TRANSFER_ROLE with a timelock.
     * @param account Address to update.
     * @param grant True to grant, false to revoke.
     */
    function setTransferRole(address account, bool grant) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account);

        bytes32 actionId = keccak256(abi.encode("setTransferRole", account, grant));
        if (roleTimelocks[actionId] == 0) {
            roleTimelocks[actionId] = uint48(block.timestamp) + TIMELOCK_DURATION;
            return;
        }

        if (block.timestamp < roleTimelocks[actionId]) {
            revert TimelockNotExpired(roleTimelocks[actionId]);
        }

        if (grant) {
            _grantRole(TRANSFER_ROLE, account);
        } else {
            _revokeRole(TRANSFER_ROLE, account);
        }
        delete roleTimelocks[actionId];
    }

    /**
     * @notice Grants or revokes the PREMINT_ROLE with a timelock.
     * @param account Address to update.
     * @param grant True to grant, false to revoke.
     */
    function setPremintRole(address account, bool grant) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account);

        bytes32 actionId = keccak256(abi.encode("setPremintRole", account, grant));
        if (roleTimelocks[actionId] == 0) {
            roleTimelocks[actionId] = uint48(block.timestamp) + TIMELOCK_DURATION;
            return;
        }

        if (block.timestamp < roleTimelocks[actionId]) {
            revert TimelockNotExpired(roleTimelocks[actionId]);
        }

        if (grant) {
            _grantRole(PREMINT_ROLE, account);
        } else {
            _revokeRole(PREMINT_ROLE, account);
        }
        delete roleTimelocks[actionId];
    }

    /*//////////////////////////////////////////////////////////////
                           OVERRIDDEN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Disables minting after initialization.
     */
    function mint(address, uint256) public pure override {
        revert MintingDisabled();
    }

    /**
     * @notice Disables burning for real estate assets.
     */
    function burn(address, uint256) external pure {
        revert BurningNotAllowed();
    }

    /**
     * @notice Disables burning from real estate assets.
     */
    function burnFrom(address, uint256) external pure {
        revert BurningNotAllowed();
    }

    /*//////////////////////////////////////////////////////////////
                             VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns real estate-specific configuration.
     * @return supportedAssetTypes Supported real estate asset types.
     * @return remainingSupply Remaining premintable supply.
     */
    function getRealEstateConfig()
        external
        view
        returns (bytes32[] memory supportedAssetTypes, uint256 remainingSupply)
    {
        supportedAssetTypes = new bytes32[](6);
        supportedAssetTypes[0] = keccak256("Commercial");
        supportedAssetTypes[1] = keccak256("Residential");
        supportedAssetTypes[2] = keccak256("Holiday");
        supportedAssetTypes[3] = keccak256("Land");
        supportedAssetTypes[4] = keccak256("Industrial");
        supportedAssetTypes[5] = keccak256("Mixed-Use");

        remainingSupply = maxSupply - totalSupply();
    }
}