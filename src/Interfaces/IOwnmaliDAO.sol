// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

interface IOwnmaliDAO {
    enum ProposalStatus {
        Pending,
        Approved,
        Rejected,
        Executed
    }

    function initialize(
        address _project,
        address _admin,
        uint48 _votingPeriod,
        uint256 _minimumVotingPower,
        uint256 _approvalThreshold
    ) external;
    
    function createProposal(string calldata description) external returns (uint256);
    function vote(uint256 proposalId, bool inSupport) external;
    function executeProposal(uint256 proposalId) external;
    function updateProposalStatus(uint256 proposalId, ProposalStatus status) external;
    function setVotingPeriod(uint48 newPeriod) external;
    function setMinimumVotingPower(uint256 newMinimum) external;
    function setApprovalThreshold(uint256 newThreshold) external;
    function setProject(address _project) external;
    
    function getProposal(uint256 proposalId) external view returns (
        address proposer,
        string memory description,
        uint256 forVotes,
        uint256 againstVotes,
        uint48 createdAt,
        uint48 votingEnd,
        ProposalStatus status
    );
    
    function hasVoted(uint256 proposalId, address voter) external view returns (bool);
    function getVotingPower(address voter) external view returns (uint256);
}
