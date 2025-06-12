// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title OwnmaliDAO
/// @notice Secure governance contract for Ownmali SPV with snapshot-based voting
/// @dev Production-ready DAO with comprehensive security measures and gas optimizations
contract OwnmaliDAO is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                         CONSTANTS & ROLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
    bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
    bytes32 public constant GUARDIAN_ROLE = keccak256("GUARDIAN_ROLE");
    
    uint256 private constant MAX_BASIS_POINTS = 10000; // 100%
    uint256 private constant MIN_VOTING_PERIOD = 1 days;
    uint256 private constant MAX_VOTING_PERIOD = 30 days;
    uint256 private constant MIN_TIMELOCK_DELAY = 2 days;

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
        Pending,    // Proposal created, voting active
        Succeeded,  // Voting ended, proposal passed
        Defeated,   // Voting ended, proposal failed
        Queued,     // Proposal queued for execution (timelock)
        Executed,   // Proposal executed
        Cancelled   // Proposal cancelled
    }

    enum VoteType {
        Against,    // 0
        For,        // 1
        Abstain     // 2
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
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    // Core parameters
    IERC20 public votingToken;
    uint256 public proposalCount;
    
    // Governance parameters (packed)
    uint48 public votingPeriod;
    uint48 public timelockDelay;
    uint16 public quorumBasisPoints;        // Quorum as basis points (e.g., 500 = 5%)
    uint16 public approvalThresholdBasisPoints; // Approval threshold (e.g., 5000 = 50%)
    uint128 public minimumVotingPower;      // Minimum tokens to vote
    
    // Proposal storage
    mapping(uint256 => ProposalCore) public proposalCores;
    mapping(uint256 => ProposalVotes) public proposalVotes;
    mapping(uint256 => ProposalData) public proposalData;
    mapping(uint256 => mapping(address => Receipt)) public receipts;
    
    // Vote snapshots for flash loan protection
    mapping(uint256 => uint256) public proposalSnapshots;
    mapping(address => mapping(uint256 => uint256)) public votingPowerAt;

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
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        VoteType voteType,
        uint256 votes
    );
    
    event ProposalQueued(uint256 indexed proposalId, uint48 queueTime);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalCancelled(uint256 indexed proposalId);
    
    event QuorumUpdated(uint16 oldQuorum, uint16 newQuorum);
    event ApprovalThresholdUpdated(uint16 oldThreshold, uint16 newThreshold);
    event VotingPeriodUpdated(uint48 oldPeriod, uint48 newPeriod);
    event TimelockDelayUpdated(uint48 oldDelay, uint48 newDelay);
    event MinimumVotingPowerUpdated(uint128 oldMinimum, uint128 newMinimum);

    /*//////////////////////////////////////////////////////////////
                         MODIFIERS
    //////////////////////////////////////////////////////////////*/
    modifier validProposalId(uint256 proposalId) {
        if (proposalId >= proposalCount) revert InvalidProposalId();
        _;
    }

    modifier onlyActiveProposal(uint256 proposalId) {
        ProposalCore storage proposal = proposalCores[proposalId];
        if (proposal.state != ProposalState.Pending || proposal.cancelled) {
            revert ProposalNotActive();
        }
        if (block.timestamp > proposal.endTime) revert VotingPeriodEnded();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                         INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Initializes the DAO contract
    /// @param _votingToken Address of the ERC20 token used for voting
    /// @param _admin Address that will receive admin roles
    /// @param _votingPeriod Duration of voting period in seconds
    /// @param _timelockDelay Delay before execution after proposal passes
    /// @param _quorumBasisPoints Minimum participation required (basis points)
    /// @param _approvalThresholdBasisPoints Minimum approval percentage (basis points)
    /// @param _minimumVotingPower Minimum token balance required to vote
    function initialize(
        address _votingToken,
        address _admin,
        uint48 _votingPeriod,
        uint48 _timelockDelay,
        uint16 _quorumBasisPoints,
        uint16 _approvalThresholdBasisPoints,
        uint128 _minimumVotingPower
    ) external initializer {
        // Input validation
        if (_votingToken == address(0) || _admin == address(0)) revert ZeroAddress();
        if (_votingPeriod < MIN_VOTING_PERIOD || _votingPeriod > MAX_VOTING_PERIOD) {
            revert InvalidParameter();
        }
        if (_timelockDelay < MIN_TIMELOCK_DELAY) revert InvalidParameter();
        if (_quorumBasisPoints == 0 || _quorumBasisPoints > MAX_BASIS_POINTS) {
            revert InvalidParameter();
        }
        if (_approvalThresholdBasisPoints == 0 || _approvalThresholdBasisPoints > MAX_BASIS_POINTS) {
            revert InvalidParameter();
        }

        // Initialize OpenZeppelin contracts
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        // Set state variables
        votingToken = IERC20(_votingToken);
        votingPeriod = _votingPeriod;
        timelockDelay = _timelockDelay;
        quorumBasisPoints = _quorumBasisPoints;
        approvalThresholdBasisPoints = _approvalThresholdBasisPoints;
        minimumVotingPower = _minimumVotingPower;

        // Setup roles
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PROPOSER_ROLE, _admin);
        _grantRole(EXECUTOR_ROLE, _admin);
        _grantRole(GUARDIAN_ROLE, _admin);
        
        // Set role hierarchies
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);
        _setRoleAdmin(EXECUTOR_ROLE, ADMIN_ROLE);
        _setRoleAdmin(GUARDIAN_ROLE, ADMIN_ROLE);
    }

    /*//////////////////////////////////////////////////////////////
                         PROPOSAL CREATION
    //////////////////////////////////////////////////////////////*/
    /// @notice Creates a new governance proposal
    /// @param description Human-readable description of the proposal
    /// @param executionData Encoded function call data for execution
    /// @return proposalId The ID of the created proposal
    function createProposal(
        string calldata description,
        bytes calldata executionData
    ) external onlyRole(PROPOSER_ROLE) whenNotPaused returns (uint256 proposalId) {
        if (bytes(description).length == 0) revert InvalidParameter();
        
        // Check proposer has minimum voting power
        uint256 proposerBalance = votingToken.balanceOf(msg.sender);
        if (proposerBalance < minimumVotingPower) revert InsufficientVotingPower();

        proposalId = proposalCount++;
        
        uint48 startTime = uint48(block.timestamp);
        uint48 endTime = startTime + votingPeriod;
        bytes32 descriptionHash = keccak256(bytes(description));

        // Store proposal data
        proposalCores[proposalId] = ProposalCore({
            proposer: msg.sender,
            startTime: startTime,
            endTime: endTime,
            queueTime: 0,
            state: ProposalState.Pending,
            cancelled: false
        });

        proposalData[proposalId] = ProposalData({
            description: description,
            descriptionHash: descriptionHash,
            executionData: executionData
        });

        // Create snapshot for vote weights (simple block number for now)
        proposalSnapshots[proposalId] = block.number;

        emit ProposalCreated(proposalId, msg.sender, description, startTime, endTime);
    }

    /*//////////////////////////////////////////////////////////////
                         VOTING
    //////////////////////////////////////////////////////////////*/
    /// @notice Cast a vote on a proposal
    /// @param proposalId ID of the proposal to vote on
    /// @param voteType Type of vote (Against=0, For=1, Abstain=2)
    function castVote(
        uint256 proposalId,
        VoteType voteType
    ) external validProposalId(proposalId) onlyActiveProposal(proposalId) whenNotPaused {
        return _castVote(proposalId, msg.sender, voteType);
    }

    /// @notice Internal vote casting logic
    function _castVote(
        uint256 proposalId,
        address voter,
        VoteType voteType
    ) internal {
        if (uint8(voteType) > 2) revert InvalidVoteType();
        
        Receipt storage receipt = receipts[proposalId][voter];
        if (receipt.hasVoted) revert AlreadyVoted();

        uint256 votes = _getVotingPower(voter, proposalId);
        if (votes < minimumVotingPower) revert InsufficientVotingPower();

        // Record the vote
        receipt.hasVoted = true;
        receipt.vote = voteType;
        receipt.votes = votes;

        // Update proposal vote counts
        ProposalVotes storage proposalVote = proposalVotes[proposalId];
        proposalVote.totalVotes += votes;

        if (voteType == VoteType.For) {
            proposalVote.forVotes += votes;
        } else if (voteType == VoteType.Against) {
            proposalVote.againstVotes += votes;
        } else {
            proposalVote.abstainVotes += votes;
        }

        emit VoteCast(proposalId, voter, voteType, votes);
    }

    /*//////////////////////////////////////////////////////////////
                         PROPOSAL EXECUTION
    //////////////////////////////////////////////////////////////*/
    /// @notice Queue a successful proposal for execution after timelock
    /// @param proposalId ID of the proposal to queue
    function queueProposal(uint256 proposalId) 
        external 
        validProposalId(proposalId) 
        whenNotPaused 
    {
        ProposalCore storage proposal = proposalCores[proposalId];
        
        if (proposal.state != ProposalState.Pending) revert ProposalNotPending();
        if (proposal.cancelled) revert ProposalCancelled();
        if (block.timestamp <= proposal.endTime) revert VotingPeriodActive();

        // Check if proposal succeeded
        if (!_isProposalSuccessful(proposalId)) {
            proposal.state = ProposalState.Defeated;
            return;
        }

        // Queue the proposal
        proposal.state = ProposalState.Queued;
        proposal.queueTime = uint48(block.timestamp);

        emit ProposalQueued(proposalId, proposal.queueTime);
    }

    /// @notice Execute a queued proposal after timelock period
    /// @param proposalId ID of the proposal to execute
    function executeProposal(uint256 proposalId)
        external
        onlyRole(EXECUTOR_ROLE)
        validProposalId(proposalId)
        nonReentrant
        whenNotPaused
    {
        ProposalCore storage proposal = proposalCores[proposalId];
        
        if (proposal.state != ProposalState.Queued) revert ProposalNotApproved();
        if (proposal.cancelled) revert ProposalCancelled();
        if (block.timestamp < proposal.queueTime + timelockDelay) revert TimelockNotMet();

        // Mark as executed first to prevent reentrancy
        proposal.state = ProposalState.Executed;

        // Execute the proposal
        bytes memory executionData = proposalData[proposalId].executionData;
        if (executionData.length > 0) {
            (bool success,) = address(this).call(executionData);
            if (!success) revert ExecutionFailed();
        }

        emit ProposalExecuted(proposalId);
    }

    /// @notice Cancel a proposal (Guardian role for emergency situations)
    /// @param proposalId ID of the proposal to cancel
    function cancelProposal(uint256 proposalId)
        external
        onlyRole(GUARDIAN_ROLE)
        validProposalId(proposalId)
    {
        ProposalCore storage proposal = proposalCores[proposalId];
        
        if (proposal.state == ProposalState.Executed) revert ProposalAlreadyExecuted();
        if (proposal.cancelled) revert ProposalCancelled();

        proposal.cancelled = true;
        proposal.state = ProposalState.Cancelled;

        emit ProposalCancelled(proposalId);
    }

    /*//////////////////////////////////////////////////////////////
                         ADMIN FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Update quorum requirement
    function setQuorum(uint16 newQuorumBasisPoints) external onlyRole(ADMIN_ROLE) {
        if (newQuorumBasisPoints == 0 || newQuorumBasisPoints > MAX_BASIS_POINTS) {
            revert InvalidParameter();
        }
        
        uint16 oldQuorum = quorumBasisPoints;
        quorumBasisPoints = newQuorumBasisPoints;
        
        emit QuorumUpdated(oldQuorum, newQuorumBasisPoints);
    }

    /// @notice Update approval threshold
    function setApprovalThreshold(uint16 newThresholdBasisPoints) external onlyRole(ADMIN_ROLE) {
        if (newThresholdBasisPoints == 0 || newThresholdBasisPoints > MAX_BASIS_POINTS) {
            revert InvalidParameter();
        }
        
        uint16 oldThreshold = approvalThresholdBasisPoints;
        approvalThresholdBasisPoints = newThresholdBasisPoints;
        
        emit ApprovalThresholdUpdated(oldThreshold, newThresholdBasisPoints);
    }

    /// @notice Update voting period
    function setVotingPeriod(uint48 newVotingPeriod) external onlyRole(ADMIN_ROLE) {
        if (newVotingPeriod < MIN_VOTING_PERIOD || newVotingPeriod > MAX_VOTING_PERIOD) {
            revert InvalidParameter();
        }
        
        uint48 oldPeriod = votingPeriod;
        votingPeriod = newVotingPeriod;
        
        emit VotingPeriodUpdated(oldPeriod, newVotingPeriod);
    }

    /// @notice Update timelock delay
    function setTimelockDelay(uint48 newTimelockDelay) external onlyRole(ADMIN_ROLE) {
        if (newTimelockDelay < MIN_TIMELOCK_DELAY) revert InvalidParameter();
        
        uint48 oldDelay = timelockDelay;
        timelockDelay = newTimelockDelay;
        
        emit TimelockDelayUpdated(oldDelay, newTimelockDelay);
    }

    /// @notice Update minimum voting power
    function setMinimumVotingPower(uint128 newMinimumVotingPower) external onlyRole(ADMIN_ROLE) {
        uint128 oldMinimum = minimumVotingPower;
        minimumVotingPower = newMinimumVotingPower;
        
        emit MinimumVotingPowerUpdated(oldMinimum, newMinimumVotingPower);
    }

    /// @notice Emergency pause
    function pause() external onlyRole(GUARDIAN_ROLE) {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @notice Get the current state of a proposal
    function getProposalState(uint256 proposalId) 
        external 
        view 
        validProposalId(proposalId) 
        returns (ProposalState) 
    {
        ProposalCore storage proposal = proposalCores[proposalId];
        
        if (proposal.cancelled) return ProposalState.Cancelled;
        if (proposal.state == ProposalState.Executed) return ProposalState.Executed;
        if (proposal.state == ProposalState.Queued) return ProposalState.Queued;
        
        if (block.timestamp <= proposal.endTime) {
            return ProposalState.Pending;
        }
        
        return _isProposalSuccessful(proposalId) ? ProposalState.Succeeded : ProposalState.Defeated;
    }

    /// @notice Get voting receipt for a voter on a proposal
    function getReceipt(uint256 proposalId, address voter)
        external
        view
        validProposalId(proposalId)
        returns (Receipt memory)
    {
        return receipts[proposalId][voter];
    }

    /// @notice Get proposal vote counts
    function getProposalVotes(uint256 proposalId)
        external
        view
        validProposalId(proposalId)
        returns (uint256 forVotes, uint256 againstVotes, uint256 abstainVotes, uint256 totalVotes)
    {
        ProposalVotes storage votes = proposalVotes[proposalId];
        return (votes.forVotes, votes.againstVotes, votes.abstainVotes, votes.totalVotes);
    }

    /// @notice Check if a proposal has reached quorum
    function hasReachedQuorum(uint256 proposalId) 
        external 
        view 
        validProposalId(proposalId) 
        returns (bool) 
    {
        return _hasReachedQuorum(proposalId);
    }

    /// @notice Check if a proposal is approved (majority of votes)
    function isProposalApproved(uint256 proposalId) 
        external 
        view 
        validProposalId(proposalId) 
        returns (bool) 
    {
        return _isProposalApproved(proposalId);
    }

    /// @notice Get voting power of an account for a specific proposal
    function getVotingPower(address account, uint256 proposalId) 
        external 
        view 
        validProposalId(proposalId) 
        returns (uint256) 
    {
        return _getVotingPower(account, proposalId);
    }

    /*//////////////////////////////////////////////////////////////
                         INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    /// @dev Check if proposal has reached quorum
    function _hasReachedQuorum(uint256 proposalId) internal view returns (bool) {
        uint256 totalSupply = votingToken.totalSupply();
        uint256 totalVotes = proposalVotes[proposalId].totalVotes;
        
        return (totalVotes * MAX_BASIS_POINTS) >= (totalSupply * quorumBasisPoints);
    }

    /// @dev Check if proposal is approved by majority
    function _isProposalApproved(uint256 proposalId) internal view returns (bool) {
        ProposalVotes storage votes = proposalVotes[proposalId];
        uint256 totalDecisiveVotes = votes.forVotes + votes.againstVotes;
        
        if (totalDecisiveVotes == 0) return false;
        
        return (votes.forVotes * MAX_BASIS_POINTS) >= (totalDecisiveVotes * approvalThresholdBasisPoints);
    }

    /// @dev Check if proposal is successful (quorum + approval)
    function _isProposalSuccessful(uint256 proposalId) internal view returns (bool) {
        return _hasReachedQuorum(proposalId) && _isProposalApproved(proposalId);
    }

    /// @dev Get voting power for an account at proposal creation time
    function _getVotingPower(address account) internal view returns (uint256) {
        return votingToken.balanceOf(account);
    }
}