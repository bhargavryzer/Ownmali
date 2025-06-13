// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IOwnmaliDAO
/// @notice Interface for the OwnmaliDAO contract, a secure governance contract with snapshot-based voting.
interface IOwnmaliDAO is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error ZeroAddress();
    error InvalidProposalId();
    error InvalidParameter();
    error ProposalNotActive();
    error ProposalNotPending();
    error ProposalAlreadyExecuted();
    error ProposalCancelled();
    error AlreadyVoted();
    error InsufficientVotingPower();
    error VotingPeriodActive();
    error VotingPeriodEnded();
    error QuorumNotMet();
    error ProposalNotApproved();
    error TimelockNotMet();
    error ExecutionFailed();
    error InvalidVoteType();

    /*//////////////////////////////////////////////////////////////
                         ENUMS
    //////////////////////////////////////////////////////////////*/
    enum ProposalState {
        Pending,
        Succeeded,
        Defeated,
        Queued,
        Executed,
        Cancelled
    }

    enum VoteType {
        Against,
        For,
        Abstain
    }

    /*//////////////////////////////////////////////////////////////
                         STRUCTS
    //////////////////////////////////////////////////////////////*/
    struct ProposalCore {
        address proposer;
        uint48 startTime;
        uint48 endTime;
        uint48 queueTime;
        ProposalState state;
        bool cancelled;
    }

    struct ProposalVotes {
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 totalVotes;
    }

    struct ProposalData {
        string description;
        bytes32 descriptionHash;
        bytes executionData;
    }

    struct Receipt {
        bool hasVoted;
        VoteType vote;
        uint256 votes;
    }

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint48 startTime,
        uint48 endTime
    );
    event VoteCast(uint256 indexed proposalId, address indexed voter, VoteType voteType, uint256 votes);
    event ProposalQueued(uint256 indexed proposalId, uint48 queueTime);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    event QuorumUpdated(uint16 oldQuorum, uint16 newQuorum);
    event ApprovalThresholdUpdated(uint16 oldThreshold, uint16 newThreshold);
    event VotingPeriodUpdated(uint48 oldPeriod, uint48 newPeriod);
    event TimelockDelayUpdated(uint48 oldDelay, uint48 newDelay);
    event MinimumVotingPowerUpdated(uint128 oldMinimum, uint128 newMinimum);

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    function initialize(
        address _votingToken,
        address _admin,
        uint48 _votingPeriod,
        uint48 _timelockDelay,
        uint16 _quorumBasisPoints,
        uint16 _approvalThresholdBasisPoints,
        uint128 _minimumVotingPower
    ) external;

    /*//////////////////////////////////////////////////////////////
                         PROPOSAL CREATION
    //////////////////////////////////////////////////////////////*/
    function createProposal(string calldata description, bytes calldata executionData) external returns (uint256 proposalId);

    /*//////////////////////////////////////////////////////////////
                         VOTING
    //////////////////////////////////////////////////////////////*/
    function castVote(uint256 proposalId, VoteType voteType) external;

    /*//////////////////////////////////////////////////////////////
                         PROPOSAL EXECUTION
    //////////////////////////////////////////////////////////////*/
    function queueProposal(uint256 proposalId) external;
    function executeProposal(uint256 proposalId) external;
    function cancelProposal(uint256 proposalId) external;

    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function setQuorum(uint16 newQuorumBasisPoints) external;
    function setApprovalThreshold(uint16 newThresholdBasisPoints) internal;
    function setVotingPeriod(uint48 newVotingPeriod) external;
    function setTimelockDelay(uint48 newTimelockDelay) external;
    function setMinimumVotingPower(uint128 newMinimumVotingPower) external;
    function pause() external;
    function unpause() external;

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    function getProposalState(uint256 proposalId) external view returns (ProposalState);
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory);
    function getProposalVotes(uint256 proposalId)
        external
        view
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes, uint256 totalVotes);
    function hasReachedQuorum(uint256 proposalId) external view returns (bool);
    function isProposalApproved(uint256 proposalId) external view returns (bool);
    function getVotingPower(address account, uint256 proposalId) external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    function ADMIN_ROLE() external view returns (bytes32);
    function PROPOSER_ROLE() external view returns (bytes32);
    function EXECUTOR_ROLE() external view returns (bytes32);
    function GUARDIAN_ROLE() external view returns (bytes32);
    function votingToken() external view returns (IERC20);
    function proposalCount() external view returns (uint256);
    function votingPeriod() external view returns (uint48);
    function timelockDelay() external view returns (uint48);
    function quorumBasisPoints() external view returns (uint16);
    function approvalThresholdBasisPoints() external view returns (uint16);
    function minimumVotingPower() external view returns (uint128);
    function proposalCores(uint256 proposalId) external view returns (ProposalCore memory);
    function proposalVotes(uint256 proposalId) external view returns (ProposalVotes memory);
    function proposalData(uint256 proposalId) external view returns (ProposalData memory);
    function receipts(uint256 proposalId, address voter) external view returns (Receipt memory);
    function proposalSnapshots(uint256 proposalId) external view returns (uint256);
    function votingPowerAt(address account, uint256 proposalId) external view returns (uint256);
}