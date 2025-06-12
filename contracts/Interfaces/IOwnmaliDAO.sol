// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import "@openzeppelin/contracts-upgradeable/access/IAccessControlUpgradeable.sol";
import "./IOwnmaliSPV.sol";

/// @title Interface for OwnmaliDAO
/// @notice Defines the external and public functions, events, errors, and data structures for the OwnmaliDAO contract
interface IOwnmaliDAO is IAccessControlUpgradeable, IOwnmaliSPV {
    /*//////////////////////////////////////////////////////////////
                             CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Role identifier for the admin role
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Role identifier for the proposer role
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    
    /// @notice Role identifier for the executor role
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    
    /*//////////////////////////////////////////////////////////////
                             ERRORS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Error thrown when the caller is not authorized
    error Unauthorized(address caller, bytes32 role);
    
    /// @notice Error thrown when the contract is not initialized
    error NotInitialized();
    
    /// @notice Error thrown when the contract is already initialized
    error AlreadyInitialized();
    
    /// @notice Error thrown when the voting period is invalid
    error InvalidVotingPeriod();
    
    /// @notice Error thrown when the quorum percentage is invalid
    error InvalidQuorumPercentage();
    
    /// @notice Error thrown when the minimum proposal power is invalid
    error InvalidMinProposalPower();
    
    /// @notice Error thrown when the voting token is invalid
    error InvalidVotingToken();
    
    /// @notice Error thrown when the proposal is not in the correct state for the action
    error InvalidProposalState(uint256 proposalId, uint8 currentState, uint8 requiredState);
    
    /// @notice Error thrown when the vote type is invalid
    error InvalidVoteType();
    
    /// @notice Error thrown when the proposal execution fails
    error ProposalExecutionFailed(uint256 proposalId);
    
    /// @notice Error thrown when the voting has not ended
    error VotingNotEnded(uint256 proposalId, uint256 currentBlock, uint256 endBlock);
    
    /// @notice Error thrown when the proposal execution is too early
    error ExecutionTooEarly(uint256 proposalId, uint256 currentBlock, uint256 earliestExecutionBlock);
    
    /// @notice Error thrown when the proposal execution is too late
    error ExecutionTooLate(uint256 proposalId, uint256 currentBlock, uint256 latestExecutionBlock);
    
    /// @notice Error thrown when the proposal execution is not allowed
    error ExecutionNotAllowed(uint256 proposalId);
    
    /// @notice Error thrown when the proposal execution is already queued
    error ProposalAlreadyQueued(uint256 proposalId);
    
    /// @notice Error thrown when the proposal execution is not queued
    error ProposalNotQueued(uint256 proposalId);
    
    /*//////////////////////////////////////////////////////////////
                             ENUMS
    //////////////////////////////////////////////////////////////*/
    /// @notice Error thrown when an address is invalid
    error InvalidAddress(address addr);
    /// @notice Error thrown when a proposal ID is invalid
    error InvalidProposalId(uint256 proposalId);
    /// @notice Error thrown when a parameter is invalid
    error InvalidParameter(string parameter);
    /// @notice Error thrown when a proposal is not active
    error ProposalNotActive(uint256 proposalId);
    /// @notice Error thrown when a proposal is already executed
    error ProposalAlreadyExecuted(uint256 proposalId);
    /// @notice Error thrown when a voter has already voted
    error AlreadyVoted(address voter, uint256 proposalId);
    /// @notice Error thrown when voting power is insufficient
    error InsufficientVotingPower(address voter, uint256 balance);
    /// @notice Error thrown when the voting period has ended
    error VotingPeriodEnded(uint256 proposalId);
    /// @notice Error thrown when a proposal is not approved
    error ProposalNotApproved(uint256 proposalId);
    /// @notice Error thrown when the SPV is inactive
    error SPVInactive(address spv);
    /// @notice Error thrown when an invalid proposal type is provided
    error InvalidProposalType(uint8 proposalType);

    /// @notice Enum for vote types
    enum VoteType {
        Against,    // 0
        For,        // 1
        Abstain     // 2
    }

    /// @notice Enum for proposal statuses
    enum ProposalStatus {
        Pending,    // 0 - Initial state, accepting votes
        Active,     // 1 - Voting period has started
        Succeeded,  // 2 - Vote succeeded but not yet queued/executed
        Queued,     // 3 - Proposal queued for execution
        Executed,   // 4 - Proposal executed
        Canceled,   // 5 - Proposal canceled
        Defeated,   // 6 - Proposal defeated (voting period ended without enough votes)
        Expired     // 7 - Proposal expired (not executed before deadline)
    }


    /// @notice Enum for proposal types
    enum ProposalType {
        UpdateMetadata,        // 0 - Update SPV metadata
        UpdateAssetDescription, // 1 - Update asset description
        UpdateSPVPurpose,      // 2 - Update SPV purpose
        UpdateOwner,           // 3 - Update SPV owner
        UpdateKycStatus,       // 4 - Update KYC status
        TransferFunds,         // 5 - Transfer funds from treasury
        UpdateTreasury,        // 6 - Update treasury address
        UpdateVotingSettings,  // 7 - Update voting settings
        Custom                 // 8 - Custom proposal type
    }


    /// @notice Struct for vote information
    struct VoteInfo {
        bool hasVoted;        // Whether the address has voted
        bool inSupport;        // Whether the vote was in support
        uint256 votes;         // Number of votes cast
    }


    /// @notice Struct for proposal details
    struct Proposal {
        address proposer;              // Address of the proposer
        uint256 startBlock;            // Block number when voting starts
        uint256 endBlock;              // Block number when voting ends
        uint256 forVotes;              // Total votes in favor
        uint256 againstVotes;          // Total votes against
        uint256 abstainVotes;          // Total abstaining votes
        bool canceled;                 // Whether the proposal is canceled
        bool executed;                 // Whether the proposal is executed
        string description;             // Description of the proposal
        ProposalType proposalType;      // Type of the proposal
        bytes data;                    // Encoded function call data
        mapping(address => VoteInfo) votes; // Mapping of voter addresses to their vote info
    }

    /*//////////////////////////////////////////////////////////////
                             EVENTS
    //////////////////////////////////////////////////////////////*/

    
    /// @notice Emitted when a new proposal is created
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        address[] targets,
        uint256[] values,
        string[] signatures,
        bytes[] calldatas,
        uint256 startBlock,
        uint256 endBlock,
        string description,
        ProposalType proposalType
    );
    
    /// @notice Emitted when a vote is cast
    event VoteCast(
        address indexed voter,
        uint256 indexed proposalId,
        uint8 support,
        uint256 weight,
        string reason
    );
    
    /// @notice Emitted when a proposal is canceled
    event ProposalCanceled(uint256 indexed proposalId);
    
    /// @notice Emitted when a proposal is queued
    event ProposalQueued(uint256 indexed proposalId, uint256 eta);
    
    /// @notice Emitted when a proposal is executed
    event ProposalExecuted(uint256 indexed proposalId);
    
    /// @notice Emitted when the voting delay is set
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);
    
    /// @notice Emitted when the voting period is set
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);
    
    /// @notice Emitted when the proposal threshold is set
    event ProposalThresholdSet(uint256 oldProposalThreshold, uint256 newProposalThreshold);
    
    /// @notice Emitted when the quorum numerator is set
    event QuorumNumeratorUpdated(uint256 oldQuorumNumerator, uint256 newQuorumNumerator);
    
    /// @notice Emitted when the timelock is set
    event TimelockChange(address oldTimelock, address newTimelock);
    
    /// @notice Emitted when the governance token is set
    event GovernanceTokenSet(address oldToken, address newToken);
    
    /// @notice Emitted when the SPV contract is set
    event SPVSet(address indexed spv);
    
    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Initializes the DAO contract
    /// @param _spv The SPV contract address
    /// @param _votingToken The voting token address
    /// @param _votingPeriod The voting period in blocks
    /// @param _quorumPercentage The quorum percentage (1-100)
    /// @param _minProposalPower The minimum voting power required to create a proposal
    function initialize(
        address _spv,
        address _votingToken,
        uint256 _votingPeriod,
        uint8 _quorumPercentage,
        uint256 _minProposalPower
    ) external;
    
    /*//////////////////////////////////////////////////////////////
                         GETTERS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Returns the voting token address
    /// @return The voting token address
    function votingToken() external view returns (address);
    
    /// @notice Returns the SPV contract
    /// @return The SPV contract
    function spv() external view returns (IOwnmaliSPV);
    
    /// @notice Returns the voting period
    /// @return The voting period in blocks
    function votingPeriod() external view returns (uint256);
    
    /// @notice Returns the quorum percentage required for a proposal to pass
    /// @return The quorum percentage (1-100)
    function quorumPercentage() external view returns (uint8);
    
    /// @notice Returns the minimum voting power required to create a proposal
    /// @return The minimum voting power
    function minProposalPower() external view returns (uint256);
    
    /// @notice Returns the total number of proposals
    /// @return The total number of proposals
    function proposalCount() external view returns (uint256);
    
    /// @notice Returns the current proposal threshold
    /// @return The current proposal threshold
    function proposalThreshold() external view returns (uint256);
    
    /// @notice Returns the current quorum numerator
    /// @return The current quorum numerator
    function quorumNumerator() external view returns (uint256);
    
    /// @notice Returns the timelock address
    /// @return The timelock address
    function timelock() external view returns (address);
    
    /// @notice Returns the governance token address
    /// @return The governance token address
    function governanceToken() external view returns (address);
    
    /*//////////////////////////////////////////////////////////////
                         PROPOSAL MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Creates a new proposal
    /// @param targets The target addresses for the calls to be made
    /// @param values The amounts of native token to send with the calls
    /// @param signatures The function signatures for the calls
    /// @param calldatas The calldata for the calls
    /// @param description The description of the proposal
    /// @param proposalType The type of the proposal
    /// @return The ID of the new proposal
    function propose(
        address[] memory targets,
        uint256[] memory values,
        string[] memory signatures,
        bytes[] memory calldatas,
        string memory description,
        ProposalType proposalType
    ) external returns (uint256);
    
    /// @notice Queues a proposal for execution
    /// @param proposalId The ID of the proposal to queue
    function queue(uint256 proposalId) external;
    
    /// @notice Executes a queued proposal
    /// @param proposalId The ID of the proposal to execute
    function execute(uint256 proposalId) external;
    
    /// @notice Cancels a proposal
    /// @param proposalId The ID of the proposal to cancel
    function cancel(uint256 proposalId) external;
    
    /*//////////////////////////////////////////////////////////////
                         VOTING
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Casts a vote on a proposal
    /// @param proposalId The ID of the proposal to vote on
    /// @param support The support value (0=against, 1=for, 2=abstain)
    function castVote(uint256 proposalId, uint8 support) external;
    
    /// @notice Casts a vote with a reason
    /// @param proposalId The ID of the proposal to vote on
    /// @param support The support value (0=against, 1=for, 2=abstain)
    /// @param reason The reason for the vote
    function castVoteWithReason(
        uint256 proposalId,
        uint8 support,
        string calldata reason
    ) external;
    
    /// @notice Casts a vote with a reason and signature
    /// @param proposalId The ID of the proposal to vote on
    /// @param support The support value (0=against, 1=for, 2=abstain)
    /// @param v The recovery byte of the signature
    /// @param r Half of the ECDSA signature pair
    /// @param s Half of the ECDSA signature pair
    function castVoteBySig(
        uint256 proposalId,
        uint8 support,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;
    
    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Gets the current state of a proposal
    /// @param proposalId The ID of the proposal
    /// @return The current state of the proposal
    function state(uint256 proposalId) external view returns (ProposalStatus);
    
    /// @notice Gets the votes required for a proposal to pass
    /// @param blockNumber The block number to get the votes at
    /// @return The number of votes required
    function quorum(uint256 blockNumber) external view returns (uint256);
    
    /// @notice Gets the voting power of an account
    /// @param account The account to get the voting power of
    /// @return The voting power of the account
    function getVotes(address account) external view returns (uint256);
    
    /// @notice Gets the voting power of an account at a specific block number
    /// @param account The account to get the voting power of
    /// @param blockNumber The block number to get the voting power at
    /// @return The voting power of the account at the specified block
    function getPastVotes(address account, uint256 blockNumber) external view returns (uint256);
    
    /// @notice Gets the total supply of voting tokens at a specific block number
    /// @param blockNumber The block number to get the total supply at
    /// @return The total supply of voting tokens at the specified block
    function getPastTotalSupply(uint256 blockNumber) external view returns (uint256);
    
    /// @notice Gets the vote information for a specific voter on a proposal
    /// @param proposalId The ID of the proposal
    /// @param voter The address of the voter
    /// @return hasVoted Whether the voter has voted
    /// @return inSupport Whether the vote was in support (if voted)
    /// @return votes Number of votes cast (if voted)
    function getVote(
        uint256 proposalId,
        address voter
    ) external view returns (bool hasVoted, bool inSupport, uint256 votes);
    
    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Updates the voting period
    /// @param newVotingPeriod The new voting period in blocks
    function setVotingPeriod(uint256 newVotingPeriod) external;
    
    /// @notice Updates the quorum percentage
    /// @param newQuorumPercentage The new quorum percentage (1-100)
    function setQuorumPercentage(uint8 newQuorumPercentage) external;
    
    /// @notice Updates the minimum proposal power
    /// @param newMinProposalPower The new minimum voting power required to create a proposal
    function setMinProposalPower(uint256 newMinProposalPower) external;
    
    /// @notice Updates the timelock address
    /// @param newTimelock The address of the new timelock
    function setTimelock(address newTimelock) external;
    
    /// @notice Updates the governance token address
    /// @param newGovernanceToken The address of the new governance token
    function setGovernanceToken(address newGovernanceToken) external;
    
    /// @notice Updates the SPV contract address
    /// @param newSPV The address of the new SPV contract
    function setSPV(address newSPV) external;
    
    /// @notice Pauses the contract
    function pause() external;
    
    /// @notice Unpauses the contract
    function unpause() external;

    /// @notice Gets proposal details by ID
    /// @param proposalId Proposal ID
    /// @return proposer Proposer address
    /// @return description Proposal description
    /// @return proposalType Type of proposal
    /// @return data Encoded data
    /// @return forVotes Votes in favor
    /// @return againstVotes Votes against
    /// @return createdAt Creation timestamp
    /// @return votingEnd Voting end timestamp
    /// @return status Proposal status
    function getProposal(
        uint256 proposalId
    )
        external
        view
        returns (
            address proposer,
            string memory description,
            ProposalType proposalType,
            bytes memory data,
            uint256 forVotes,
            uint256 againstVotes,
            uint48 createdAt,
            uint48 votingEnd,
            ProposalStatus status
        );

    /// @notice Checks if an address has voted on a proposal
    /// @param proposalId Proposal ID
    /// @param voter Voter address
    /// @return True if voter has voted
    function hasVoted(uint256 proposalId, address voter) external view returns (bool);
}