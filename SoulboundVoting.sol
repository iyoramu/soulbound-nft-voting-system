// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Soulbound Voting System
 * @dev A non-transferable NFT voting system with modern features for competitions
 * @notice This contract implements a soulbound NFT that cannot be transferred once minted,
 * with built-in voting functionality and competition management.
 */
contract SoulboundVoting is ERC721, Ownable {
    using Counters for Counters.Counter;
    
    Counters.Counter private _tokenIdCounter;
    Counters.Counter private _competitionIdCounter;

    // Struct to store competition details
    struct Competition {
        string name;
        string description;
        uint256 startTime;
        uint256 endTime;
        uint256[] participantTokenIds;
        mapping(uint256 => uint256) votes; // tokenId => vote count
        bool isActive;
    }

    // Struct to store voter information
    struct Voter {
        bool hasVoted;
        uint256 lastVoteTime;
    }

    // Mapping from competition ID to Competition
    mapping(uint256 => Competition) public competitions;
    
    // Mapping from token ID to voter information
    mapping(uint256 => Voter) public voters;
    
    // Mapping from token ID to metadata URI
    mapping(uint256 => string) private _tokenURIs;

    // Events
    event CompetitionCreated(uint256 indexed competitionId, string name, uint256 startTime, uint256 endTime);
    event ParticipantRegistered(uint256 indexed competitionId, uint256 indexed tokenId);
    event VoteCast(uint256 indexed competitionId, uint256 indexed voterTokenId, uint256 indexed participantTokenId);
    event SoulboundMinted(address indexed to, uint256 indexed tokenId);
    
    // Modifier to check if competition exists
    modifier competitionExists(uint256 competitionId) {
        require(competitions[competitionId].startTime > 0, "Competition does not exist");
        _;
    }

    // Modifier to check if competition is active
    modifier competitionActive(uint256 competitionId) {
        require(competitions[competitionId].isActive, "Competition is not active");
        require(block.timestamp >= competitions[competitionId].startTime, "Competition has not started");
        require(block.timestamp <= competitions[competitionId].endTime, "Competition has ended");
        _;
    }

    /**
     * @dev Constructor
     * @param name_ Name of the NFT token
     * @param symbol_ Symbol of the NFT token
     */
    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) {}

    /**
     * @dev Creates a new competition
     * @param name Name of the competition
     * @param description Description of the competition
     * @param startTime Start time of the competition (unix timestamp)
     * @param endTime End time of the competition (unix timestamp)
     */
    function createCompetition(
        string memory name,
        string memory description,
        uint256 startTime,
        uint256 endTime
    ) external onlyOwner {
        require(startTime < endTime, "End time must be after start time");
        require(startTime > block.timestamp, "Start time must be in the future");
        
        uint256 competitionId = _competitionIdCounter.current();
        _competitionIdCounter.increment();
        
        Competition storage newCompetition = competitions[competitionId];
        newCompetition.name = name;
        newCompetition.description = description;
        newCompetition.startTime = startTime;
        newCompetition.endTime = endTime;
        newCompetition.isActive = true;
        
        emit CompetitionCreated(competitionId, name, startTime, endTime);
    }

    /**
     * @dev Mints a new soulbound NFT (non-transferable)
     * @param to Address to mint the NFT to
     * @param uri Metadata URI for the NFT
     */
    function safeMint(address to, string memory uri) external onlyOwner {
        uint256 tokenId = _tokenIdCounter.current();
        _tokenIdCounter.increment();
        
        _safeMint(to, tokenId);
        _tokenURIs[tokenId] = uri;
        
        emit SoulboundMinted(to, tokenId);
    }

    /**
     * @dev Registers a participant in a competition
     * @param competitionId ID of the competition
     * @param tokenId Token ID of the participant
     */
    function registerParticipant(
        uint256 competitionId,
        uint256 tokenId
    ) external competitionExists(competitionId) onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        
        Competition storage competition = competitions[competitionId];
        competition.participantTokenIds.push(tokenId);
        
        emit ParticipantRegistered(competitionId, tokenId);
    }

    /**
     * @dev Casts a vote for a participant in a competition
     * @param competitionId ID of the competition
     * @param voterTokenId Token ID of the voter
     * @param participantTokenId Token ID of the participant being voted for
     */
    function castVote(
        uint256 competitionId,
        uint256 voterTokenId,
        uint256 participantTokenId
    ) external competitionExists(competitionId) competitionActive(competitionId) {
        require(_exists(voterTokenId), "Voter token does not exist");
        require(_exists(participantTokenId), "Participant token does not exist");
        require(!voters[voterTokenId].hasVoted, "Already voted");
        
        Competition storage competition = competitions[competitionId];
        bool isParticipant = false;
        
        for (uint256 i = 0; i < competition.participantTokenIds.length; i++) {
            if (competition.participantTokenIds[i] == participantTokenId) {
                isParticipant = true;
                break;
            }
        }
        
        require(isParticipant, "Not a valid participant");
        
        competition.votes[participantTokenId] += 1;
        voters[voterTokenId].hasVoted = true;
        voters[voterTokenId].lastVoteTime = block.timestamp;
        
        emit VoteCast(competitionId, voterTokenId, participantTokenId);
    }

    /**
     * @dev Gets the vote count for a participant in a competition
     * @param competitionId ID of the competition
     * @param participantTokenId Token ID of the participant
     * @return uint256 Vote count
     */
    function getVotes(
        uint256 competitionId,
        uint256 participantTokenId
    ) external view competitionExists(competitionId) returns (uint256) {
        return competitions[competitionId].votes[participantTokenId];
    }

    /**
     * @dev Gets all participants in a competition
     * @param competitionId ID of the competition
     * @return uint256[] Array of participant token IDs
     */
    function getParticipants(
        uint256 competitionId
    ) external view competitionExists(competitionId) returns (uint256[] memory) {
        return competitions[competitionId].participantTokenIds;
    }

    /**
     * @dev Gets the winner of a competition
     * @param competitionId ID of the competition
     * @return uint256 Token ID of the winner
     */
    function getWinner(
        uint256 competitionId
    ) external view competitionExists(competitionId) returns (uint256) {
        require(block.timestamp > competitions[competitionId].endTime, "Competition has not ended");
        
        uint256[] memory participants = competitions[competitionId].participantTokenIds;
        require(participants.length > 0, "No participants");
        
        uint256 winningTokenId = participants[0];
        uint256 highestVotes = competitions[competitionId].votes[winningTokenId];
        
        for (uint256 i = 1; i < participants.length; i++) {
            uint256 currentVotes = competitions[competitionId].votes[participants[i]];
            if (currentVotes > highestVotes) {
                highestVotes = currentVotes;
                winningTokenId = participants[i];
            }
        }
        
        return winningTokenId;
    }

    /**
     * @dev Overrides transfer functions to make NFT soulbound (non-transferable)
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal virtual override {
        require(from == address(0), "Token is soulbound and cannot be transferred");
        super._beforeTokenTransfer(from, to, tokenId, batchSize);
    }

    /**
     * @dev Returns the URI for a given token ID
     * @param tokenId Token ID to query
     * @return string Metadata URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "URI query for nonexistent token");
        return _tokenURIs[tokenId];
    }

    /**
     * @dev Updates the metadata URI for a token
     * @param tokenId Token ID to update
     * @param newURI New metadata URI
     */
    function updateTokenURI(uint256 tokenId, string memory newURI) external onlyOwner {
        require(_exists(tokenId), "Token does not exist");
        _tokenURIs[tokenId] = newURI;
    }

    /**
     * @dev Toggles competition active status
     * @param competitionId ID of the competition
     * @param isActive New active status
     */
    function setCompetitionActive(uint256 competitionId, bool isActive) external onlyOwner competitionExists(competitionId) {
        competitions[competitionId].isActive = isActive;
    }
}
