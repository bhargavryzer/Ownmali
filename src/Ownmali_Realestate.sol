// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "./Ownmali_Asset.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/// @title OwnmaliRealEstateToken
/// @notice ERC-3643 compliant token for real estate assets with token allocation system
/// @dev Adds real estate-specific features like batch operations, forced transfers, and token allocation management
contract OwnmaliRealEstateToken is OwnmaliAsset, ReentrancyGuardUpgradeable {
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAssetType(bytes32 assetType);
    error BatchTooLarge(uint256 size, uint256 maxSize);
    error ArrayLengthMismatch(uint256 toLength, uint256 amountsLength);
    error ZeroAmountDetected(address recipient);
    error InvalidRecipient(address recipient);
    error TotalSupplyExceeded(uint256 requested, uint256 maxSupply);
    error InsufficientBalance(address account, uint256 balance, uint256 requested);
    error EmptyBatch();
    error AllocationNotExists(bytes32 allocationId);
    error AllocationAlreadyExists(bytes32 allocationId);
    error AllocationNotActive(bytes32 allocationId);
    error AllocationExpired(bytes32 allocationId, uint256 deadline);
    error InsufficientAllocation(bytes32 allocationId, uint256 available, uint256 requested);
    error InvalidAllocationPeriod(uint256 startTime, uint256 endTime);
    error AllocationAlreadyClaimed(bytes32 allocationId, address beneficiary);
    error NotAllocationBeneficiary(bytes32 allocationId, address caller);
    error InvalidVestingSchedule(uint256 cliffPeriod, uint256 vestingPeriod);

    /*//////////////////////////////////////////////////////////////
                         TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Token allocation structure for managing token distribution
    struct TokenAllocation {
        bytes32 id;                    // Unique allocation identifier
        address beneficiary;           // Address that can claim tokens
        uint256 totalAmount;          // Total tokens allocated
        uint256 claimedAmount;        // Amount already claimed
        uint256 startTime;            // When allocation becomes active
        uint256 endTime;              // When allocation expires
        uint256 cliffPeriod;          // Cliff period in seconds
        uint256 vestingPeriod;        // Total vesting period in seconds
        bool isActive;                // Whether allocation is active
        bool allowPartialClaim;       // Whether partial claims are allowed
        bytes32 allocationCategory;   // Category (e.g., "Investor", "Team", "Public")
        string metadata;              // Additional metadata (IPFS hash, etc.)
    }

    /// @notice Vesting schedule for calculating claimable amounts
    struct VestingInfo {
        uint256 claimableAmount;      // Amount that can be claimed now
        uint256 vestedAmount;         // Total amount vested so far
        uint256 nextClaimTime;        // Next time when more tokens vest
        bool isFullyVested;           // Whether allocation is fully vested
    }

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant TRANSFER_ROLE = keccak256("TRANSFER_ROLE");
    bytes32 public constant ALLOCATION_MANAGER_ROLE = keccak256("ALLOCATION_MANAGER_ROLE");
    
    uint256 public constant MAX_BATCH_SIZE_LIMIT = 500; // Hard limit for gas optimization
    uint256 public maxBatchSize;

    // Token Allocation Management
    mapping(bytes32 => TokenAllocation) public allocations;
    mapping(address => bytes32[]) public beneficiaryAllocations;
    mapping(bytes32 => uint256) public categoryTotalAllocated;
    
    bytes32[] public allocationIds;
    uint256 public totalAllocatedTokens;
    uint256 public totalClaimedTokens;
    
    // Allocation categories
    bytes32 public constant INVESTOR_ALLOCATION = keccak256("INVESTOR");
    bytes32 public constant TEAM_ALLOCATION = keccak256("TEAM");
    bytes32 public constant PUBLIC_ALLOCATION = keccak256("PUBLIC");
    bytes32 public constant RESERVE_ALLOCATION = keccak256("RESERVE");
    bytes32 public constant MARKETING_ALLOCATION = keccak256("MARKETING");

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event BatchMinted(address indexed minter, address[] recipients, uint256[] amounts, uint256 totalAmount);
    event BatchBurned(address indexed burner, address[] accounts, uint256[] amounts, uint256 totalAmount);
    event MaxBatchSizeSet(uint256 oldMaxSize, uint256 newMaxSize);
    event TransferRoleUpdated(address indexed account, bool granted);
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount, string reason);
    
    // Allocation Events
    event AllocationCreated(
        bytes32 indexed allocationId,
        address indexed beneficiary,
        uint256 totalAmount,
        bytes32 indexed category
    );
    event AllocationUpdated(bytes32 indexed allocationId, bool isActive);
    event TokensClaimed(
        bytes32 indexed allocationId,
        address indexed beneficiary,
        uint256 amount,
        uint256 totalClaimed
    );
    event AllocationTransferred(
        bytes32 indexed allocationId,
        address indexed oldBeneficiary,
        address indexed newBeneficiary
    );

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract with real estate-specific validation and allocation system
    /// @param configData Encoded AssetConfig for initialization
    function initialize(bytes calldata configData) public override initializer {
        // Decode and validate asset type for real estate
        AssetConfig memory config = abi.decode(configData, (AssetConfig));
        _validateRealEstateAssetType(config.assetType);
        
        // Initialize parent contract
        super.initialize(configData);
        
        // Initialize ReentrancyGuard
        __ReentrancyGuard_init();
        
        // Set real estate specific configurations
        maxBatchSize = 100; // Initial max batch size
        _setRoleAdmin(TRANSFER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(ALLOCATION_MANAGER_ROLE, ADMIN_ROLE);
        _grantRole(TRANSFER_ROLE, assetOwner);
        _grantRole(ALLOCATION_MANAGER_ROLE, assetOwner);
        
        emit MaxBatchSizeSet(0, maxBatchSize);
    }

    /*//////////////////////////////////////////////////////////////
                         TOKEN ALLOCATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Creates a new token allocation
    /// @param allocationId Unique identifier for the allocation
    /// @param beneficiary Address that can claim the tokens
    /// @param totalAmount Total amount of tokens to allocate
    /// @param startTime When the allocation becomes active
    /// @param endTime When the allocation expires
    /// @param cliffPeriod Cliff period in seconds
    /// @param vestingPeriod Total vesting period in seconds
    /// @param category Allocation category
    /// @param allowPartialClaim Whether partial claims are allowed
    /// @param metadata Additional metadata
    function createAllocation(
        bytes32 allocationId,
        address beneficiary,
        uint256 totalAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 cliffPeriod,
        uint256 vestingPeriod,
        bytes32 category,
        bool allowPartialClaim,
        string calldata metadata
    ) external onlyRole(ALLOCATION_MANAGER_ROLE) whenNotPaused {
        if (allocationId == bytes32(0)) revert InvalidParameter("allocationId");
        if (beneficiary == address(0)) revert InvalidAddress(beneficiary);
        if (totalAmount == 0) revert InvalidParameter("totalAmount");
        if (allocations[allocationId].id != bytes32(0)) revert AllocationAlreadyExists(allocationId);
        if (startTime >= endTime) revert InvalidAllocationPeriod(startTime, endTime);
        if (cliffPeriod > vestingPeriod) revert InvalidVestingSchedule(cliffPeriod, vestingPeriod);
        if (totalAllocatedTokens + totalAmount > maxSupply) {
            revert ExceedsMaxSupply(totalAllocatedTokens + totalAmount, maxSupply);
        }

        // Create allocation
        allocations[allocationId] = TokenAllocation({
            id: allocationId,
            beneficiary: beneficiary,
            totalAmount: totalAmount,
            claimedAmount: 0,
            startTime: startTime,
            endTime: endTime,
            cliffPeriod: cliffPeriod,
            vestingPeriod: vestingPeriod,
            isActive: true,
            allowPartialClaim: allowPartialClaim,
            allocationCategory: category,
            metadata: metadata
        });

        // Update tracking
        allocationIds.push(allocationId);
        beneficiaryAllocations[beneficiary].push(allocationId);
        categoryTotalAllocated[category] += totalAmount;
        totalAllocatedTokens += totalAmount;

        emit AllocationCreated(allocationId, beneficiary, totalAmount, category);
    }

    /// @notice Updates allocation status
    /// @param allocationId Allocation identifier
    /// @param isActive New active status
    function updateAllocationStatus(bytes32 allocationId, bool isActive) 
        external 
        onlyRole(ALLOCATION_MANAGER_ROLE) 
    {
        if (allocations[allocationId].id == bytes32(0)) revert AllocationNotExists(allocationId);
        
        allocations[allocationId].isActive = isActive;
        emit AllocationUpdated(allocationId, isActive);
    }

    /// @notice Claims tokens from an allocation
    /// @param allocationId Allocation identifier
    /// @param amount Amount to claim (0 for maximum claimable)
    function claimTokens(bytes32 allocationId, uint256 amount) 
        external 
        nonReentrant 
        whenNotPaused 
        onlyActiveProject 
    {
        TokenAllocation storage allocation = allocations[allocationId];
        
        if (allocation.id == bytes32(0)) revert AllocationNotExists(allocationId);
        if (allocation.beneficiary != msg.sender) revert NotAllocationBeneficiary(allocationId, msg.sender);
        if (!allocation.isActive) revert AllocationNotActive(allocationId);
        if (block.timestamp > allocation.endTime) revert AllocationExpired(allocationId, allocation.endTime);

        VestingInfo memory vestingInfo = calculateVestingInfo(allocationId);
        
        uint256 claimAmount = amount == 0 ? vestingInfo.claimableAmount : amount;
        if (claimAmount == 0) revert InvalidParameter("claimAmount");
        if (claimAmount > vestingInfo.claimableAmount) {
            revert InsufficientAllocation(allocationId, vestingInfo.claimableAmount, claimAmount);
        }

        // Update allocation
        allocation.claimedAmount += claimAmount;
        totalClaimedTokens += claimAmount;

        // Mint tokens to beneficiary
        _mint(allocation.beneficiary, claimAmount);

        emit TokensClaimed(allocationId, allocation.beneficiary, claimAmount, allocation.claimedAmount);
    }

    /// @notice Transfers allocation to a new beneficiary
    /// @param allocationId Allocation identifier
    /// @param newBeneficiary New beneficiary address
    function transferAllocation(bytes32 allocationId, address newBeneficiary) 
        external 
        onlyRole(ALLOCATION_MANAGER_ROLE) 
    {
        if (newBeneficiary == address(0)) revert InvalidAddress(newBeneficiary);
        
        TokenAllocation storage allocation = allocations[allocationId];
        if (allocation.id == bytes32(0)) revert AllocationNotExists(allocationId);
        
        address oldBeneficiary = allocation.beneficiary;
        allocation.beneficiary = newBeneficiary;
        
        // Update beneficiary mappings
        _removeBeneficiaryAllocation(oldBeneficiary, allocationId);
        beneficiaryAllocations[newBeneficiary].push(allocationId);
        
        emit AllocationTransferred(allocationId, oldBeneficiary, newBeneficiary);
    }

    /// @notice Batch creates multiple allocations
    /// @param allocationIds Array of allocation identifiers
    /// @param beneficiaries Array of beneficiary addresses
    /// @param amounts Array of token amounts
    /// @param startTimes Array of start times
    /// @param endTimes Array of end times
    /// @param categories Array of categories
    function batchCreateAllocations(
        bytes32[] calldata allocationIds,
        address[] calldata beneficiaries,
        uint256[] calldata amounts,
        uint256[] calldata startTimes,
        uint256[] calldata endTimes,
        bytes32[] calldata categories
    ) external onlyRole(ALLOCATION_MANAGER_ROLE) whenNotPaused {
        uint256 length = allocationIds.length;
        if (length != beneficiaries.length || length != amounts.length || 
            length != startTimes.length || length != endTimes.length || 
            length != categories.length) {
            revert ArrayLengthMismatch(length, beneficiaries.length);
        }
        if (length == 0 || length > maxBatchSize) revert BatchTooLarge(length, maxBatchSize);

        uint256 totalBatchAmount;
        for (uint256 i = 0; i < length; i++) {
            totalBatchAmount += amounts[i];
        }

        if (totalAllocatedTokens + totalBatchAmount > maxSupply) {
            revert ExceedsMaxSupply(totalAllocatedTokens + totalBatchAmount, maxSupply);
        }

        for (uint256 i = 0; i < length; i++) {
            createAllocation(
                allocationIds[i],
                beneficiaries[i],
                amounts[i],
                startTimes[i],
                endTimes[i],
                0, // No cliff period for batch
                endTimes[i] - startTimes[i], // Full vesting period
                categories[i],
                true, // Allow partial claims
                "" // No metadata for batch
            );
        }
    }

    /*//////////////////////////////////////////////////////////////
                         BATCH OPERATIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the maximum batch size for operations
    /// @param _maxBatchSize New maximum batch size
    function setMaxBatchSize(uint256 _maxBatchSize) external onlyRole(ADMIN_ROLE) {
        if (_maxBatchSize == 0) revert InvalidParameter("maxBatchSize");
        if (_maxBatchSize > MAX_BATCH_SIZE_LIMIT) revert BatchTooLarge(_maxBatchSize, MAX_BATCH_SIZE_LIMIT);
        
        uint256 oldMaxSize = maxBatchSize;
        maxBatchSize = _maxBatchSize;
        emit MaxBatchSizeSet(oldMaxSize, _maxBatchSize);
    }

    /// @notice Batch mints tokens to multiple addresses
    /// @param to Array of recipient addresses
    /// @param amounts Array of amounts to mint
    function batchMint(address[] calldata to, uint256[] calldata amounts)
        external
        onlyRole(OPERATOR_ROLE)
        whenNotPaused
        onlyActiveProject
        nonReentrant
    {
        _validateBatchParams(to, amounts);

        uint256 totalAmount;
        // First pass: validate all recipients and calculate total
        for (uint256 i = 0; i < to.length; i++) {
            if (to[i] == address(0)) revert InvalidRecipient(to[i]);
            if (amounts[i] == 0) revert ZeroAmountDetected(to[i]);
            
            // Check compliance for each recipient
            if (!compliance.canTransfer(address(0), to[i], amounts[i])) {
                revert TransferNotCompliant(address(0), to[i], amounts[i]);
            }
            
            totalAmount += amounts[i];
        }

        // Check total supply constraint
        if (totalSupply() + totalAmount > maxSupply) {
            revert ExceedsMaxSupply(totalSupply() + totalAmount, maxSupply);
        }

        // Second pass: execute minting
        for (uint256 i = 0; i < to.length; i++) {
            _mint(to[i], amounts[i]);
        }

        emit BatchMinted(msg.sender, to, amounts, totalAmount);
    }

    /// @notice Batch burns tokens from multiple addresses
    /// @param from Array of source addresses
    /// @param amounts Array of amounts to burn
    function batchBurn(address[] calldata from, uint256[] calldata amounts)
        external
        onlyRole(TRANSFER_ROLE)
        whenNotPaused
        onlyActiveProject
        nonReentrant
    {
        _validateBatchParams(from, amounts);

        uint256 totalAmount;
        // First pass: validate all accounts and calculate total
        for (uint256 i = 0; i < from.length; i++) {
            if (from[i] == address(0)) revert InvalidRecipient(from[i]);
            if (amounts[i] == 0) revert ZeroAmountDetected(from[i]);
            
            uint256 balance = balanceOf(from[i]);
            if (balance < amounts[i]) {
                revert InsufficientBalance(from[i], balance, amounts[i]);
            }
            
            // Check compliance for burning
            if (!compliance.canTransfer(from[i], address(0), amounts[i])) {
                revert TransferNotCompliant(from[i], address(0), amounts[i]);
            }
            
            totalAmount += amounts[i];
        }

        // Second pass: execute burning
        for (uint256 i = 0; i < from.length; i++) {
            _burn(from[i], amounts[i]);
        }

        emit BatchBurned(msg.sender, from, amounts, totalAmount);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Executes a forced transfer (compliance override for legal/regulatory reasons)
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    /// @param reason Reason for forced transfer
    function forcedTransfer(
        address from,
        address to,
        uint256 amount,
        string calldata reason
    ) external onlyRole(TRANSFER_ROLE) whenNotPaused onlyActiveProject {
        if (from == address(0) || to == address(0)) revert InvalidAddress(from == address(0) ? from : to);
        if (amount == 0) revert InvalidParameter("amount");
        if (bytes(reason).length == 0) revert InvalidParameter("reason");
        
        uint256 balance = balanceOf(from);
        if (balance < amount) {
            revert InsufficientBalance(from, balance, amount);
        }

        // Execute transfer bypassing normal compliance checks
        _transfer(from, to, amount);
        
        emit ForcedTransfer(from, to, amount, reason);
    }

    /// @notice Grants or revokes the TRANSFER_ROLE
    /// @param account Address to update
    /// @param grant True to grant, false to revoke
    function setTransferRole(address account, bool grant) external onlyRole(ADMIN_ROLE) {
        if (account == address(0)) revert InvalidAddress(account);
        
        if (grant) {
            _grantRole(TRANSFER_ROLE, account);
        } else {
            _revokeRole(TRANSFER_ROLE, account);
        }
        emit TransferRoleUpdated(account, grant);
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Checks if an address has specific roles
    /// @param account Address to check
    /// @return hasTransferRole True if account has TRANSFER_ROLE
    /// @return hasAllocationManagerRole True if account has ALLOCATION_MANAGER_ROLE
    /// @return hasAdminRole True if account has ADMIN_ROLE
    function checkRoles(address account) 
        external 
        view 
        returns (
            bool hasTransferRole,
            bool hasAllocationManagerRole,
            bool hasAdminRole
        ) 
    {
        if (account == address(0)) revert InvalidAddress(account);
        
        hasTransferRole = hasRole(TRANSFER_ROLE, account);
        hasAllocationManagerRole = hasRole(ALLOCATION_MANAGER_ROLE, account);
        hasAdminRole = hasRole(ADMIN_ROLE, account);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Validates real estate specific asset types
    /// @param _assetType Asset type to validate
    function _validateRealEstateAssetType(bytes32 _assetType) internal pure {
        if (
            _assetType != keccak256("Commercial") &&
            _assetType != keccak256("Residential") &&
            _assetType != keccak256("Holiday") &&
            _assetType != keccak256("Land") &&
            _assetType != keccak256("Industrial") &&
            _assetType != keccak256("Mixed-Use")
        ) {
            revert InvalidAssetType(_assetType);
        }
    }

    /// @notice Validates batch operation parameters
    /// @param addresses Array of addresses
    /// @param amounts Array of amounts
    function _validateBatchParams(address[] calldata addresses, uint256[] calldata amounts) internal view {
        if (addresses.length != amounts.length) {
            revert ArrayLengthMismatch(addresses.length, amounts.length);
        }
        if (addresses.length == 0) revert EmptyBatch();
        if (addresses.length > maxBatchSize) {
            revert BatchTooLarge(addresses.length, maxBatchSize);
        }
    }

    /// @notice Removes allocation from beneficiary's list
    /// @param beneficiary Beneficiary address
    /// @param allocationId Allocation to remove
    function _removeBeneficiaryAllocation(address beneficiary, bytes32 allocationId) internal {
        bytes32[] storage userAllocations = beneficiaryAllocations[beneficiary];
        for (uint256 i = 0; i < userAllocations.length; i++) {
            if (userAllocations[i] == allocationId) {
                userAllocations[i] = userAllocations[userAllocations.length - 1];
                userAllocations.pop();
                break;
            }
        }
    }

    /// @notice Override transfer function to handle forced transfers
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount to transfer
    function _transfer(address from, address to, uint256 amount) internal override {
        // This is a direct transfer bypassing _beforeTokenTransfer for forced transfers
        // Get current balances
        uint256 fromBalance = balanceOf(from);
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");

        // Update balances directly
        _update(from, to, amount);
    }

    /// @notice Enhanced before token transfer hook
    /// @param from Source address
    /// @param to Destination address
    /// @param amount Amount being transferred
    function _beforeTokenTransfer(address from, address to, uint256 amount)
        internal
        override
        whenNotPaused
    {
        // Call parent validation first
        super._beforeTokenTransfer(from, to, amount);
        
        // Additional real estate specific validations can be added here
        // For example, checking for property-specific transfer restrictions
    }

    /// @notice Authorizes contract upgrades
    /// @param newImplementation Address of the new implementation contract
    function _authorizeUpgrade(address newImplementation) 
        internal 
        view 
        override 
        onlyRole(DEFAULT_ADMIN_ROLE) 
    {
        if (newImplementation == address(0) || newImplementation.code.length == 0) {
            revert InvalidAddress(newImplementation);
        }
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Calculates vesting information for an allocation
    /// @param allocationId Allocation identifier
    /// @return vestingInfo Vesting information
    function calculateVestingInfo(bytes32 allocationId) public view returns (VestingInfo memory vestingInfo) {
        TokenAllocation memory allocation = allocations[allocationId];
        if (allocation.id == bytes32(0)) revert AllocationNotExists(allocationId);

        uint256 currentTime = block.timestamp;
        
        // Check if allocation has started
        if (currentTime < allocation.startTime) {
            return VestingInfo(0, 0, allocation.startTime, false);
        }

        // Check if still in cliff period
        uint256 cliffEndTime = allocation.startTime + allocation.cliffPeriod;
        if (currentTime < cliffEndTime) {
            return VestingInfo(0, 0, cliffEndTime, false);
        }

        // Calculate vested amount
        uint256 vestingEndTime = allocation.startTime + allocation.vestingPeriod;
        uint256 vestedAmount;
        
        if (currentTime >= vestingEndTime) {
            // Fully vested
            vestedAmount = allocation.totalAmount;
            vestingInfo.isFullyVested = true;
            vestingInfo.nextClaimTime = 0;
        } else {
            // Partially vested
            uint256 elapsedTime = currentTime - cliffEndTime;
            uint256 vestingTimeRemaining = vestingEndTime - cliffEndTime;
            vestedAmount = (allocation.totalAmount * elapsedTime) / vestingTimeRemaining;
            vestingInfo.nextClaimTime = currentTime + 1 days; // Next day
        }

        vestingInfo.vestedAmount = vestedAmount;
        vestingInfo.claimableAmount = vestedAmount > allocation.claimedAmount ? 
            vestedAmount - allocation.claimedAmount : 0;
    }

    /// @notice Returns allocation details
    /// @param allocationId Allocation identifier
    /// @return allocation Token allocation details
    function getAllocation(bytes32 allocationId) external view returns (TokenAllocation memory allocation) {
        if (allocations[allocationId].id == bytes32(0)) revert AllocationNotExists(allocationId);
        return allocations[allocationId];
    }

    /// @notice Returns all allocations for a beneficiary
    /// @param beneficiary Beneficiary address
    /// @return allocationIds Array of allocation IDs
    function getBeneficiaryAllocations(address beneficiary) external view returns (bytes32[] memory) {
        return beneficiaryAllocations[beneficiary];
    }

    /// @notice Returns allocation statistics by category
    /// @param category Allocation category
    /// @return totalAllocated Total tokens allocated in category
    /// @return totalClaimed Total tokens claimed in category
    function getCategoryStats(bytes32 category) external view returns (uint256 totalAllocated, uint256 totalClaimed) {
        totalAllocated = categoryTotalAllocated[category];
        
        // Calculate total claimed for category
        for (uint256 i = 0; i < allocationIds.length; i++) {
            TokenAllocation memory allocation = allocations[allocationIds[i]];
            if (allocation.allocationCategory == category) {
                totalClaimed += allocation.claimedAmount;
            }
        }
    }

    /// @notice Returns overall allocation statistics
    /// @return totalAllocated Total tokens allocated
    /// @return totalClaimed Total tokens claimed
    /// @return totalActive Number of active allocations
    /// @return availableForAllocation Tokens available for new allocations
    function getAllocationStats() external view returns (
        uint256 totalAllocated,
        uint256 totalClaimed,
        uint256 totalActive,
        uint256 availableForAllocation
    ) {
        totalAllocated = totalAllocatedTokens;
        totalClaimed = totalClaimedTokens;
        availableForAllocation = maxSupply - totalAllocatedTokens;
        
        // Count active allocations
        for (uint256 i = 0; i < allocationIds.length; i++) {
            if (allocations[allocationIds[i]].isActive) {
                totalActive++;
            }
        }
    }

    /// @notice Returns real estate specific asset configuration with allocation info
    /// @return config Extended asset configuration
    /// @return currentMaxBatchSize Current maximum batch size
    /// @return supportedAssetTypes Supported real estate asset types
    /// @return allocationSummary Allocation summary statistics
    function getRealEstateConfigWithAllocations() external view returns (
        AssetConfig memory config,
        uint256 currentMaxBatchSize,
       

bytes32[] memory supportedAssetTypes,
        uint256[4] memory allocationSummary // [totalAllocated, totalClaimed, activeAllocations, availableForAllocation]
    ) {
        config = getAssetConfig();
        currentMaxBatchSize = maxBatchSize;
        
        // Return supported real estate asset types
        supportedAssetTypes = new bytes32[](6);
        supportedAssetTypes[0] = keccak256("Commercial");
        supportedAssetTypes[1] = keccak256("Residential");
        supportedAssetTypes[2] = keccak256("Holiday");
        supportedAssetTypes[3] = keccak256("Land");
        supportedAssetTypes[4] = keccak256("Industrial");
        supportedAssetTypes[5] = keccak256("Mixed-Use");
        
        // Allocation summary
        allocationSummary[0] = totalAllocatedTokens;
        allocationSummary[1] = totalClaimedTokens;
        allocationSummary[3] = maxSupply - totalAllocatedTokens;
        
        // Count active allocations
        for (uint256 i = 0; i < allocationIds.length; i++) {
            if (allocations[allocationIds[i]].isActive) {
                allocationSummary[2]++;
            }
        }
    }

    /// @notice Validates if a batch operation is possible
    /// @param addresses Array of addresses
    /// @param amounts Array of amounts
    /// @param isMinting True for minting, false for burning
    /// @return isValid True if batch is valid
    /// @return totalAmount Total amount in batch
    function validateBatch(
        address[] calldata addresses,
        uint256[] calldata amounts,
        bool isMinting
    ) external view returns (bool isValid, uint256 totalAmount) {
        if (addresses.length != amounts.length || addresses.length == 0 || addresses.length > maxBatchSize) {
            return (false, 0);
        }

        for (uint256 i = 0; i < addresses.length; i++) {
            if (addresses[i] == address(0) || amounts[i] == 0) {
                return (false, 0);
            }
            
            if (isMinting) {
                if (!compliance.canTransfer(address(0), addresses[i], amounts[i])) {
                    return (false, 0);
                }
            } else {
                if (balanceOf(addresses[i]) < amounts[i]) {
                    return (false, 0);
                }
                if (!compliance.canTransfer(addresses[i], address(0), amounts[i])) {
                    return (false, 0);
                }
            }
            
            totalAmount += amounts[i];
        }

        if (isMinting && totalSupply() + totalAmount > maxSupply) {
            return (false, totalAmount);
        }

        return (true, totalAmount);
    }

    /// @notice Returns the number of allocations
    /// @return Total number of allocations created
    function getAllocationCount() external view returns (uint256) {
        return allocationIds.length;
    }

    /// @notice Returns batch operation limits
    /// @return currentMaxBatchSize Current maximum batch size
    /// @return maxBatchSizeLimit Hard limit for batch size
    function getBatchLimits() external view returns (uint256 currentMaxBatchSize, uint256 maxBatchSizeLimit) {
        return (maxBatchSize, MAX_BATCH_SIZE_LIMIT);
    }
}