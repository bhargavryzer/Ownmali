// SPDX-License-Identifier: MIT
pragma solidity 0.8.29;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IOwnmaliProject.sol";

/// @title OwnmaliDAO
/// @notice Governance contract for Ownmali projects, allowing token holders to create and vote on proposals
/// @dev Uses ERC-3643 compliant tokens for voting weight
contract OwnmaliDAO is
    Initializable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    /*//////////////////////////////////////////////////////////////
                         ERRORS
    //////////////////////////////////////////////////////////////*/
    error InvalidAddress(address addr);
    error InvalidProposalId(uint256 proposalId);
    error InvalidParameter(string parameter);
    error ProposalNotActive(uint256 proposalId);
    error ProposalAlreadyExecuted(uint256 proposalId);
    error AlreadyVoted(address voter, uint256 proposalId);
    error InsufficientVotingPower(address voter, uint256 balance);
    error VotingPeriodEnded(uint256 proposalId);
    error ProposalNotApproved(uint256 proposalId);
    error ProjectInactive(address project);

    /*//////////////////////////////////////////////////////////////
                         TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum ProposalStatus {
        Pending,
        Approved,
        Rejected,
        Executed
    }

    struct Proposal {
        address proposer;
        string description;
        uint256 forVotes;
        uint256 againstVotes;
        uint48 createdAt;
        uint48 votingEnd;
        ProposalStatus status;
        mapping(address => bool) hasVoted;
    }

    /*//////////////////////////////////////////////////////////////
                         STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");

    address public project;
    uint256 public proposalCount;
    uint48 public votingPeriod;
    uint256 public minimumVotingPower;
    uint256 public approvalThreshold;
    mapping(uint256 => Proposal) public proposals;

    /*//////////////////////////////////////////////////////////////
                         EVENTS
    //////////////////////////////////////////////////////////////*/
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string description,
        uint48 createdAt,
        uint48 votingEnd
    );
    event Voted(uint256 indexed proposalId, address indexed voter, bool inSupport, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId);
    event ProposalStatusUpdated(uint256 indexed proposalId, ProposalStatus status);
    event VotingPeriodSet(uint48 newPeriod);
    event MinimumVotingPowerSet(uint256 newMinimum);
    event ApprovalThresholdSet(uint256 newThreshold);
    event ProjectSet(address indexed project);

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Initializes the contract
    function initialize(
        address _project,
        address _admin,
        uint48 _votingPeriod,
        uint256 _minimumVotingPower,
        uint256 _approvalThreshold
    ) external initializer {
        if (_project == address(0) || _admin == address(0)) revert InvalidAddress(address(0));
        if (_votingPeriod == 0) revert InvalidParameter("votingPeriod");
        if (_approvalThreshold == 0 || _approvalThreshold > 100) revert InvalidParameter("approvalThreshold");

        __AccessControlEnumerable_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        project = _project;
        votingPeriod = _votingPeriod;
        minimumVotingPower = _minimumVotingPower;
        approvalThreshold = _approvalThreshold;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PROPOSER_ROLE, _admin);
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);

        emit ProjectSet(_project);
        emit VotingPeriodSet(_votingPeriod);
        emit MinimumVotingPowerSet(_minimumVotingPower);
        emit ApprovalThresholdSet(_approvalThreshold);
    }

    /// @notice Creates a new proposal
    /// @param description Description of the proposal
    function createProposal(string calldata description) external onlyRole(PROPOSER_ROLE) nonReentrant whenNotPaused {
        if (bytes(description).length == 0) revert InvalidParameter("description");
        if (!IOwnmaliProject(project).getIsActive()) revert ProjectInactive(project);

        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.createdAt = uint48(block.timestamp);
        proposal.votingEnd = uint48(block.timestamp + votingPeriod);
        proposal.status = ProposalStatus.Pending;

        emit ProposalCreated(proposalId, msg.sender, description, proposal.createdAt, proposal.votingEnd);
    }

    /// @notice Votes on a proposal
    /// @param proposalId The ID of the proposal
    /// @param inSupport Whether the vote is in support
    function vote(uint256 proposalId, bool inSupport) external nonReentrant whenNotPaused {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Pending) revert ProposalNotActive(proposalId);
        if (block.timestamp > proposal.votingEnd) revert VotingPeriodEnded(proposalId);
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted(msg.sender, proposalId);

        uint256 voterBalance = IOwnmaliProject(project).balanceOf(msg.sender);
        if (voterBalance < minimumVotingPower) revert InsufficientVotingPower(msg.sender, voterBalance);

        proposal.hasVoted[msg.sender] = true;
        if (inSupport) {
            proposal.forVotes += voterBalance;
        } else {
            proposal.againstVotes += voterBalance;
        }

        emit Voted(proposalId, msg.sender, inSupport, voterBalance);
    }

    /// @notice Executes an approved proposal
    /// @param proposalId The ID of the proposal
    function executeProposal(uint256 proposalId) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Approved) revert ProposalNotApproved(proposalId);
        if (proposal.status == ProposalStatus.Executed) revert ProposalAlreadyExecuted(proposalId);

        proposal.status = ProposalStatus.Executed;
        emit ProposalExecuted(proposalId);
    }

    /// @notice Updates proposal status based on votes
    /// @param proposalId The ID of the proposal
    function updateProposalStatus(uint256 proposalId) external nonReentrant whenNotPaused {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Pending) revert ProposalNotActive(proposalId);
        if (block.timestamp <= proposal.votingEnd) revert InvalidParameter("Voting period not ended");

        uint256 totalSupply = IOwnmaliProject(project).totalSupply();
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;
        if (totalVotes == 0 || (proposal.forVotes * 100) / totalSupply < approvalThreshold) {
            proposal.status = ProposalStatus.Rejected;
        } else {
            proposal.status = ProposalStatus.Approved;
        }

        emit ProposalStatusUpdated(proposalId, proposal.status);
    }

    /// @notice Sets the voting period
    /// @param newPeriod New voting period in seconds
    function setVotingPeriod(uint48 newPeriod) external onlyRole(ADMIN_ROLE) {
        if (newPeriod == 0) revert InvalidParameter("votingPeriod");
        votingPeriod = newPeriod;
        emit VotingPeriodSet(newPeriod);
    }

    /// @notice Sets the minimum voting power
    /// @param newMinimum New minimum voting power
    function setMinimumVotingPower(uint256 newMinimum) external onlyRole(ADMIN_ROLE) {
        minimumVotingPower = newMinimum;
        emit MinimumVotingPowerSet(newMinimum);
    }

    /// @notice Sets the approval threshold
    /// @param newThreshold New approval threshold (percentage)
    function setApprovalThreshold(uint256 newThreshold) external onlyRole(ADMIN_ROLE) {
        if (newThreshold == 0 || newThreshold > 100) revert InvalidParameter("approvalThreshold");
        approvalThreshold = newThreshold;
        emit ApprovalThresholdSet(newThreshold);
    }

    /// @notice Pauses the contract
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the contract
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Gets proposal details by ID
    /// @param proposalId The ID of the proposal
    /// @return proposer Proposer address
    /// @return description Proposal description
    /// @return forVotes Votes in support
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
            uint256 forVotes,
            uint256 againstVotes,
            uint48 createdAt,
            uint48 votingEnd,
            ProposalStatus status
        )
    {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.proposer,
            proposal.description,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.createdAt,
            proposal.votingEnd,
            proposal.status
        );
    }

    /// @notice Checks if an address has voted on a proposal
    /// @param proposalId The ID of the proposal
    /// @param voter The voter address
    /// @return Whether the voter has voted
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        return proposals[proposalId].hasVoted[voter];
    }
}