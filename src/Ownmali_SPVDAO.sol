// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./interfaces/IOwnmaliSPV.sol";

/// @title OwnmaliSPVDAO
/// @notice Governance contract for Ownmali SPV, allowing token holders to create and vote on SPV-specific proposals
/// @dev Uses ERC-3643 compliant tokens for voting weight and interacts with OwnmaliSPV contract
contract OwnmaliSPVDAO is
    Initializable,
    AccessControlUpgradeable,
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
    error SPVInactive(address spv);
    error InvalidProposalType(uint8 proposalType);

    /*//////////////////////////////////////////////////////////////
                         TYPE DECLARATIONS
    //////////////////////////////////////////////////////////////*/
    enum ProposalStatus {
        Pending,
        Approved,
        Rejected,
        Executed
    }

    enum ProposalType {
        UpdateMetadata, // Update SPV metadata CID
        UpdateAssetDescription, // Update SPV asset description
        UpdateSPVPurpose, // Update SPV purpose
        UpdateOwner, // Update SPV owner
        UpdateKycStatus, // Update SPV KYC status
        Custom // Other actions (e.g., fund allocation)
    }

    struct Proposal {
        address proposer;
        string description;
        ProposalType proposalType;
        bytes data; // Encoded data for execution (e.g., new metadata CID)
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
    address public spv; // Reference to OwnmaliSPV contract
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
        ProposalType proposalType,
        bytes data,
        uint48 createdAt,
        uint48 votingEnd
    );
    event Voted(uint256 indexed proposalId, address indexed voter, bool inSupport, uint256 votes);
    event ProposalExecuted(uint256 indexed proposalId, ProposalType proposalType);
    event ProposalStatusUpdated(uint256 indexed proposalId, ProposalStatus status);
    event VotingPeriodSet(uint48 newPeriod);
    event MinimumVotingPowerSet(uint256 newMinimum);
    event ApprovalThresholdSet(uint256 newThreshold);
    event SPVSet(address indexed spv);

    /*//////////////////////////////////////////////////////////////
                         EXTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/
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
    ) external initializer {
        if (_spv == address(0) || _admin == address(0)) revert InvalidAddress(address(0));
        if (_votingPeriod == 0) revert InvalidParameter("votingPeriod");
        if (_approvalThreshold == 0 || _approvalThreshold > 100) revert InvalidParameter("approvalThreshold");

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        spv = _spv;
        votingPeriod = _votingPeriod;
        minimumVotingPower = _minimumVotingPower;
        approvalThreshold = _approvalThreshold;

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(PROPOSER_ROLE, _admin);
        _setRoleAdmin(PROPOSER_ROLE, ADMIN_ROLE);

        emit SPVSet(_spv);
        emit VotingPeriodSet(_votingPeriod);
        emit MinimumVotingPowerSet(_minimumVotingPower);
        emit ApprovalThresholdSet(_approvalThreshold);
    }

    /// @notice Creates a new proposal
    /// @param description Proposal description
    /// @param proposalType Type of proposal (e.g., UpdateMetadata)
    /// @param data Encoded data for execution
    function createProposal(
        string calldata description,
        ProposalType proposalType,
        bytes calldata data
    ) external onlyRole(PROPOSER_ROLE) nonReentrant whenNotPaused {
        if (bytes(description).length == 0) revert InvalidParameter("description");
        if (uint8(proposalType) > uint8(ProposalType.Custom)) revert InvalidProposalType(uint8(proposalType));
        (, bool kycStatus,,,,,) = IOwnmaliSPV(spv).getDetails();
        if (!kycStatus) revert SPVInactive(spv);

        uint256 proposalId = proposalCount++;
        Proposal storage proposal = proposals[proposalId];
        proposal.proposer = msg.sender;
        proposal.description = description;
        proposal.proposalType = proposalType;
        proposal.data = data;
        proposal.createdAt = uint48(block.timestamp);
        proposal.votingEnd = uint48(block.timestamp + votingPeriod);
        proposal.status = ProposalStatus.Pending;

        emit ProposalCreated(
            proposalId,
            msg.sender,
            description,
            proposalType,
            data,
            proposal.createdAt,
            proposal.votingEnd
        );
    }

    /// @notice Votes on a proposal
    /// @param proposalId Proposal ID
    /// @param inSupport True for supporting, false for opposing
    function vote(uint256 proposalId, bool inSupport) external nonReentrant whenNotPaused {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Pending) revert ProposalNotActive(proposalId);
        if (block.timestamp > proposal.votingEnd) revert VotingPeriodEnded(proposalId);
        if (proposal.hasVoted[msg.sender]) revert AlreadyVoted(msg.sender, proposalId);

        uint256 voterBalance = IOwnmaliSPV(spv).balanceOf(msg.sender);
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
    /// @param proposalId Proposal ID
    function executeProposal(uint256 proposalId) external onlyRole(ADMIN_ROLE) nonReentrant whenNotPaused {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Approved) revert ProposalNotApproved(proposalId);
        if (proposal.status == ProposalStatus.Executed) revert ProposalAlreadyExecuted(proposalId);

        proposal.status = ProposalStatus.Executed;

        // Execute based on proposal type
        if (proposal.proposalType == ProposalType.UpdateMetadata) {
            (bytes32 newMetadataCID) = abi.decode(proposal.data, (bytes32));
            IOwnmaliSPV(spv).updateMetadata(newMetadataCID);
        } else if (proposal.proposalType == ProposalType.UpdateAssetDescription) {
            (string memory newAssetDescription) = abi.decode(proposal.data, (string));
            IOwnmaliSPV(spv).updateAssetDescription(newAssetDescription);
        } else if (proposal.proposalType == ProposalType.UpdateSPVPurpose) {
            (string memory newSpvPurpose) = abi.decode(proposal.data, (string));
            IOwnmaliSPV(spv).updateSPVPurpose(newSpvPurpose);
        } else if (proposal.proposalType == ProposalType.UpdateOwner) {
            (address newOwner) = abi.decode(proposal.data, (address));
            IOwnmaliSPV(spv).updateOwner(newOwner);
        } else if (proposal.proposalType == ProposalType.UpdateKycStatus) {
            (bool newKycStatus) = abi.decode(proposal.data, (bool));
            IOwnmaliSPV(spv).updateKycStatus(newKycStatus);
        } else if (proposal.proposalType == ProposalType.Custom) {
            // Custom execution logic (e.g., fund allocation) can be implemented here
        }

        emit ProposalExecuted(proposalId, proposal.proposalType);
    }

    /// @notice Updates proposal status based on votes
    /// @param proposalId Proposal ID
    function updateProposalStatus(uint256 proposalId) external nonReentrant whenNotPaused {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        if (proposal.status != ProposalStatus.Pending) revert ProposalNotActive(proposalId);
        if (block.timestamp <= proposal.votingEnd) revert InvalidParameter("Voting period not ended");

        uint256 totalSupply = IOwnmaliSPV(spv).totalSupply();
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
    /// @param newMinimum New minimum token balance
    function setMinimumVotingPower(uint256 newMinimum) external onlyRole(ADMIN_ROLE) {
        minimumVotingPower = newMinimum;
        emit MinimumVotingPowerSet(newMinimum);
    }

    /// @notice Sets the approval threshold
    /// @param newThreshold New approval threshold percentage
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
        )
    {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.proposer,
            proposal.description,
            proposal.proposalType,
            proposal.data,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.createdAt,
            proposal.votingEnd,
            proposal.status
        );
    }

    /// @notice Checks if an address has voted on a proposal
    /// @param proposalId Proposal ID
    /// @param voter Voter address
    /// @return True if voter has voted
    function hasVoted(uint256 proposalId, address voter) external view returns (bool) {
        if (proposalId >= proposalCount) revert InvalidProposalId(proposalId);
        return proposals[proposalId].hasVoted[voter];
    }
}