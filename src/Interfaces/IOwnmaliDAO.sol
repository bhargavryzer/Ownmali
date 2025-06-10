// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title Interface for OwnmaliDAO
/// @notice Defines the external and public functions, events, errors, and data structures for the OwnmaliDAO contract
interface IOwnmaliDAO {
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

    /// @notice Enum for proposal statuses
    enum ProposalStatus {
        Pending,
        Approved,
        Rejected,
        Executed
    }

    /// @notice Enum for proposal types
    enum ProposalType {
        UpdateMetadata,
        UpdateAssetDescription,
        UpdateSPVPurpose,
        UpdateOwner,
        UpdateKycStatus,
        Custom
    }

    /// @notice Struct for proposal details
    struct Proposal {
        address proposer;
        string description;
        ProposalType proposalType;
        bytes data;
        uint256 forVotes;
        uint256 againstVotes;
        uint48 createdAt;
        uint48 votingEnd;
        ProposalStatus status;
    }

    /// @notice Emitted when a proposal is created
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        ProposalType proposalType,
        bytes data,
        uint48 createdAt,
        uint48 votingEnd
    );
    /// @notice Emitted when a vote is cast
    event Voted(uint256 indexed proposalId, address indexed voter, bool inSupport, uint256 votes);
    /// @notice Emitted when a proposal is executed
    event ProposalExecuted(uint256 indexed proposalId, ProposalType proposalType);
    /// @notice Emitted when a proposal's status is updated
    event ProposalStatusUpdated(uint256 indexed proposalId, ProposalStatus status);
    /// @notice Emitted when the voting period is set
    event VotingPeriodSet(uint48 newPeriod);
    /// @notice Emitted when the minimum voting power is set
    event MinimumVotingPowerSet(uint256 newMinimum);
    /// @notice Emitted when the approval threshold is set
    event ApprovalThresholdSet(uint256 newThreshold);
    /// @notice Emitted when the SPV address is set
    event SPVSet(address indexed spv);

    /// @notice Initializes the contract
    /// @param _spv Address of the OwnmaliSPV contract
    /// @param _admin Admin address
    /// @param _votingPeriod Voting period in seconds
    /// @param _minimumVotingPower Minimum token balance required to vote
    /// @param _approvalThreshold Approval threshold as a percentage of total supply
    function initialize(
        address _spv,
        address _admin,
        uint48 _votingPeriod,
        uint256 _minimumVotingPower,
        uint256 _approvalThreshold
    ) external;

    /// @notice Creates a new proposal
    /// @param description Proposal description
    /// @param proposalType Type of proposal
    /// @param data Encoded data for execution
    function createProposal(
        string calldata description,
        ProposalType proposalType,
        bytes calldata data
    ) external;

    /// @notice Votes on a proposal
    /// @param proposalId Proposal ID
    /// @param inSupport True for supporting, false for opposing
    function vote(uint256 proposalId, bool inSupport) external;

    /// @notice Executes an approved proposal
    /// @param proposalId Proposal ID
    function executeProposal(uint256 proposalId) external;

    /// @notice Updates proposal status based on votes
    /// @param proposalId Proposal ID
    function updateProposalStatus(uint256 proposalId) external;

    /// @notice Sets the voting period
    /// @param newPeriod New voting period in seconds
    function setVotingPeriod(uint48 newPeriod) external;

    /// @notice Sets the minimum voting power
    /// @param newMinimum New minimum token balance
    function setMinimumVotingPower(uint256 newMinimum) external;

    /// @notice Sets the approval threshold
    /// @param newThreshold New approval threshold percentage
    function setApprovalThreshold(uint256 newThreshold) external;

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