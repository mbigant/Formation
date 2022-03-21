// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.13;

import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";

contract Voting is Ownable {

    struct Voter {
        bool isRegistered;
        bool hasVoted;
        uint votedProposalId;
    }

    struct Proposal {
        string description;
        uint voteCount;
    }

    struct Result {
        Proposal winner;
        WinningType winningType;
        uint totalVote;
        uint totalRegisteredVoter;
    }

    enum WorkflowStatus {
        RegisteringVoters,
        ProposalsRegistrationStarted,
        ProposalsRegistrationEnded,
        VotingSessionStarted,
        VotingSessionEnded,
        VotesTallied
    }

    enum WinningType {
        Majority,
        Draw
    }

    /**
    * Throws if called by an unregistered voter address.
    */
    modifier onlyRegisteredVoter() {
        require(voters[msg.sender].isRegistered, "Only registered voter are allowed");
        _;
    }

    event VoterRegistered(address voterAddress);
    event WorkflowStatusChange(WorkflowStatus previousStatus, WorkflowStatus newStatus);
    event ProposalRegistered(uint proposalId);
    event Voted (address voter, uint proposalId);
    event ProposalElected (uint proposalId);

    // Mapping from address to voter
    mapping( address => Voter ) voters;

    // Mapping from address to whitelist status
    mapping( address => bool ) whitelist;

    // Mapping from voteCount to array of proposalIds
    mapping( uint => uint[] ) proposalsIdByVotingCount;

    // Array of proposals
    Proposal[] proposals;

    // Id of the winning proposal
    uint private winningProposalId;

    // Number of registered voters
    uint private totalRegisteredVoters;

    // Current status of the vote
    WorkflowStatus private status;

    // Details of the vote results
    Result private result;


    /**
     * Whitelist an address or not.
     *
     * Requirements:
     *
     * - `msg.sender` must be the owner.
     *
     */
    function whitelistVoter( address _voter, bool _isWhitelisted ) external onlyOwner {
        setWhitelisted( _voter, _isWhitelisted );
    }

    /**
     * Return winning proposalId.
     *
     * Requirements:
     *
     * - `status` must be VotesTallied.
     *
     */
    function getWinner() external view returns(uint) {

        require( status == WorkflowStatus.VotesTallied, "Vote still in progress" );

        return winningProposalId;
    }

    /**
     * Return proposalId voted from `_voterAddress`.
     *
     * Requirements:
     *
     * - `_voterAddress` must have voted.
     *
     */
    function getVote( address _voterAddress ) external view returns(uint) {

        // Test if voter has voted to ensure not returning default value "0" that could be confusing
        require( voters[_voterAddress].hasVoted, "Voter did not vote yet" );

        return voters[_voterAddress].votedProposalId;
    }

    /**
     * Return proposal associated with the id `_proposalId`
     */
    function getProposal( uint _proposalId ) external view returns(Proposal memory){
        return proposals[_proposalId];
    }


    /**
     * A whitelisted address can submit a proposal during registration period.
     * Add a new proposal to the list.
     *
     * Requirements:
     *
     * - `status` must be ProposalsRegistrationStarted.
     * - `msg.sender` must be a registered voter.
     *
     * Emits a {ProposalRegistered} event.
     */
    function registerProposal( string memory _description ) external onlyRegisteredVoter {

        require( status == WorkflowStatus.ProposalsRegistrationStarted, "Proposals registration period ended !" );

        proposals.push(Proposal( _description, 0 ));

        emit ProposalRegistered(proposals.length - 1);
    }


    /**
    * Voter can register during the RegisteringVoters period.
    *
    * Requirements:
    *
    * - `msg.sender` must be whitelisted.
    * - `status` must be RegisteringVoters.
    * - `msg.sender` must not be already registered.
    *
    * Emits a {VoterRegistered} event.
    */
    function registerAsVoter() external {

        require( whitelist[msg.sender], "You are not authorized to register" );
        require( status == WorkflowStatus.RegisteringVoters, "Voters registration period ended !" );
        require( !voters[msg.sender].isRegistered, "You are already registered");

        voters[msg.sender].isRegistered = true;
        totalRegisteredVoters++;

        emit VoterRegistered(msg.sender);
    }

    /**
    * Register a vote for proposal.
    *
    * Requirements:
    *
    * - `status` must be VotingSessionStarted.
    * - `_proposalId` must exist.
    * - `msg.sender` must have not vote yet.
    * - `msg.sender` must be a registered voter.
    *
    * Emits a {Voted} event.
    */
    function vote( uint _proposalId ) external onlyRegisteredVoter {

        require( status == WorkflowStatus.VotingSessionStarted, "Voting session not started" );
        require( _proposalId < proposals.length, "Proposal not found" );
        require( !voters[msg.sender].hasVoted, "Only one vote accepted" );

        proposals[_proposalId].voteCount++;
        voters[msg.sender].hasVoted = true;
        voters[msg.sender].votedProposalId = _proposalId;

        emit Voted(msg.sender, _proposalId);
    }


    function startProposalRegistration() external onlyOwner {
        changeWorkflowStatus( WorkflowStatus.ProposalsRegistrationStarted );
    }


    function stopProposalRegistration() external onlyOwner {
        changeWorkflowStatus( WorkflowStatus.ProposalsRegistrationEnded );
    }

    function startVoteRegistration() external onlyOwner {

        require( proposals.length > 0, "No proposals to vote for..." );

        changeWorkflowStatus( WorkflowStatus.VotingSessionStarted );
    }


    function stopVoteRegistration() external onlyOwner {
        changeWorkflowStatus( WorkflowStatus.VotingSessionEnded );
    }


    /**
    * Find the winner of the vote.
    * Winner is the proposal with the highest `voteCount`.
    * If more than one proposal got the same amount of vote, pickup will be random.
    *
    * Requirements:
    *
    * - `status` must be VotingSessionEnded.
    * - `totalVote` must greater than zero.
    * - `msg.sender` must be the owner.
    *
    * Emits a {ProposalElected} event.
    */
    function checkWinner() external onlyOwner {

        if( status == WorkflowStatus.VotesTallied ) {
            revert("Votes already tallied");
        }

        require( status == WorkflowStatus.VotingSessionEnded, "Voting session not ended" );

        uint maxVoteCount;
        uint totalVote;

        for( uint id = 0; id < proposals.length; id++ ) {

            Proposal memory proposal = proposals[id];

            totalVote += proposal.voteCount;

            if( proposal.voteCount > maxVoteCount ) {
                maxVoteCount = proposal.voteCount;
            }

            proposalsIdByVotingCount[proposal.voteCount].push( id );

        }

        require( totalVote > 0, "No vote, no winner" );

        WinningType winningType = WinningType.Majority;

        // If we got only one proposal with the max voting count, this is the winner
        // Else we will pickup a random winner
        if( proposalsIdByVotingCount[maxVoteCount].length == 0 ) {
            winningProposalId = proposalsIdByVotingCount[maxVoteCount][0];
        }
        else {
            uint winningPosition = uint( keccak256(abi.encodePacked(block.timestamp, block.difficulty)) ) % proposalsIdByVotingCount[maxVoteCount].length;
            winningProposalId = proposalsIdByVotingCount[maxVoteCount][winningPosition];
            winningType = WinningType.Draw;
            console.log("Random position is '%d'", winningPosition);
        }

        console.log("Winner is '%d'", winningProposalId);

        result = Result( proposals[winningProposalId], winningType, totalVote, totalRegisteredVoters );

        changeWorkflowStatus( WorkflowStatus.VotesTallied );

        emit ProposalElected(winningProposalId);
    }

    /**
    * Return results of the vote.
    *
    * Requirements:
    *
    * - `status` must be VotesTallied.
    *
    */
    function getResult() external view returns(Result memory) {

        require(status == WorkflowStatus.VotesTallied, "Voting session not ended");

        return result;
    }


    /**
    * Change the WorkflowStatus if requirement match.
    * Note: Assuming status are sequentials we juste have to check if the previous status uint val + 1 == new status.
    * If more than one proposal got the same amount of vote, pickup will be random.
    *
    * Requirements:
    *
    * - `status` must be the previous status of `_newStatus`.
    * - `msg.sender` must be the owner.
    *
    * Emits a {WorkflowStatusChange} event.
    */
    function changeWorkflowStatus(WorkflowStatus _newStatus) private onlyOwner {

        require( WorkflowStatus(uint(status) + 1) == _newStatus, "Not allowed from this status" );

        status = _newStatus;

        emit WorkflowStatusChange( WorkflowStatus(uint(_newStatus) - 1), _newStatus);

    }

    function setWhitelisted( address _voterAddress, bool _isWhitelisted ) private {
        whitelist[_voterAddress] = _isWhitelisted;
    }

    function getStatus() external view returns(WorkflowStatus) {
        return status;
    }

}