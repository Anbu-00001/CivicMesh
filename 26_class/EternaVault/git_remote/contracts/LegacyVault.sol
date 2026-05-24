// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

/// @title LegacyVault
/// @notice Digital legacy access controller for MemCap on QIE Mainnet.
contract LegacyVault {
    address public owner;
    bool public deceased;
    uint256 public unlockTimestamp;
    uint256 public validatorQuorum;
    uint256 public validatorApprovals;
    uint256 public heirCount;

    mapping(address => bool) public heirs;
    mapping(address => bool) public validators;
    mapping(address => bool) public validatorApproved;

    uint256 public shareThreshold;
    mapping(address => bytes) public encryptedShares;
    mapping(address => bool) public shareClaimed;

    bytes32 public heartbeatCommitment;
    uint256 public lastHeartbeat;
    uint256 public silenceThreshold;
    uint256 public heartbeatEpoch;

    event OwnerTransferred(address indexed previousOwner, address indexed newOwner);
    event HeirAdded(address indexed heir);
    event HeirRemoved(address indexed heir);
    event ValidatorAdded(address indexed validator);
    event ValidatorRemoved(address indexed validator);
    event DeceasedMarked(address indexed triggeredBy);
    event ValidatorApproved(address indexed validator, uint256 approvals, uint256 quorum);
    event UnlockTimestampSet(uint256 unlockTimestamp);
    event ShareThresholdSet(uint256 threshold);
    event ShareDeposited(address indexed heir, uint256 shareIndex);
    event ShareClaimed(address indexed heir);
    event HeartbeatInitialized(uint256 epoch, uint256 timestamp, uint256 silenceThreshold);
    event HeartbeatRenewed(uint256 epoch, uint256 timestamp);
    event SilenceEscalated(address indexed triggeredBy, uint256 timestamp);

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier onlyValidator() {
        require(validators[msg.sender], "Only validator");
        _;
    }

    constructor(address[] memory initialHeirs, address[] memory initialValidators, uint256 quorum) {
        owner = msg.sender;
        validatorQuorum = quorum;

        for (uint256 i = 0; i < initialHeirs.length; i++) {
            _addHeir(initialHeirs[i]);
        }

        for (uint256 i = 0; i < initialValidators.length; i++) {
            validators[initialValidators[i]] = true;
            emit ValidatorAdded(initialValidators[i]);
        }
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "Invalid owner");
        emit OwnerTransferred(owner, newOwner);
        owner = newOwner;
    }

    function addHeir(address heir) external onlyOwner {
        _addHeir(heir);
    }

    function removeHeir(address heir) external onlyOwner {
        require(heirs[heir], "Address is not a registered heir");
        heirs[heir] = false;
        heirCount--;
        delete encryptedShares[heir];
        delete shareClaimed[heir];
        emit HeirRemoved(heir);
    }

    function addValidator(address validator) external onlyOwner {
        require(validator != address(0), "Invalid validator");
        require(!validators[validator], "Already validator");
        validators[validator] = true;
        emit ValidatorAdded(validator);
    }

    function removeValidator(address validator) external onlyOwner {
        require(validators[validator], "Address is not a validator");
        validators[validator] = false;
        if (validatorApproved[validator]) {
            validatorApproved[validator] = false;
            validatorApprovals--;
        }
        emit ValidatorRemoved(validator);
    }

    function setValidatorQuorum(uint256 quorum) external onlyOwner {
        validatorQuorum = quorum;
    }

    function setUnlockTimestamp(uint256 timestamp) external onlyOwner {
        unlockTimestamp = timestamp;
        emit UnlockTimestampSet(timestamp);
    }

    function markDeceased() external onlyOwner {
        deceased = true;
        emit DeceasedMarked(msg.sender);
    }

    function approveDeath() external onlyValidator {
        require(!validatorApproved[msg.sender], "Already approved");
        validatorApproved[msg.sender] = true;
        validatorApprovals++;
        emit ValidatorApproved(msg.sender, validatorApprovals, validatorQuorum);

        if (validatorQuorum != 0 && validatorApprovals >= validatorQuorum) {
            deceased = true;
            emit DeceasedMarked(msg.sender);
        }
    }

    function canAccess(address user) public view returns (bool) {
        if (!heirs[user]) return false;
        if (deceased) return true;
        if (unlockTimestamp != 0 && block.timestamp >= unlockTimestamp) return true;
        if (
            silenceThreshold != 0 &&
            lastHeartbeat != 0 &&
            block.timestamp - lastHeartbeat >= silenceThreshold
        ) return true;
        return false;
    }

    function setShareThreshold(uint256 threshold) external onlyOwner {
        require(threshold > 0, "Threshold required");
        require(heirCount == 0 || threshold <= heirCount, "Threshold exceeds heirs");
        shareThreshold = threshold;
        emit ShareThresholdSet(threshold);
    }

    function depositEncryptedShare(address heir, bytes calldata encryptedShare) external onlyOwner {
        require(heirs[heir], "Address is not a registered heir");
        require(encryptedShare.length != 0, "Empty share");
        encryptedShares[heir] = encryptedShare;
        shareClaimed[heir] = false;
        emit ShareDeposited(heir, 0);
    }

    function getEncryptedShare(address heir) external view returns (bytes memory) {
        require(heir == msg.sender || msg.sender == owner, "Can only read own share");
        require(msg.sender == owner || canAccess(msg.sender), "Access not yet granted");
        return encryptedShares[heir];
    }

    function claimMyShare() external returns (bytes memory) {
        require(canAccess(msg.sender), "Access not yet granted");
        require(encryptedShares[msg.sender].length != 0, "No share");
        shareClaimed[msg.sender] = true;
        emit ShareClaimed(msg.sender);
        return encryptedShares[msg.sender];
    }

    function initHeartbeat(bytes32 commitment, uint256 thresholdSeconds) external onlyOwner {
        require(commitment != bytes32(0), "Commitment required");
        require(thresholdSeconds > 0, "Threshold required");
        heartbeatCommitment = commitment;
        lastHeartbeat = block.timestamp;
        silenceThreshold = thresholdSeconds;
        heartbeatEpoch = 1;
        emit HeartbeatInitialized(heartbeatEpoch, block.timestamp, thresholdSeconds);
    }

    function renewHeartbeat(
        bytes32 prevSecret,
        uint256 prevEpoch,
        bytes32 newCommitment
    ) external onlyOwner {
        require(newCommitment != bytes32(0), "New commitment required");
        require(prevEpoch == heartbeatEpoch, "Invalid heartbeat epoch");
        require(
            keccak256(abi.encodePacked(prevSecret, prevEpoch)) == heartbeatCommitment,
            "Invalid heartbeat proof"
        );

        heartbeatCommitment = newCommitment;
        lastHeartbeat = block.timestamp;
        heartbeatEpoch++;
        emit HeartbeatRenewed(heartbeatEpoch, block.timestamp);
    }

    function escalateAccess() external {
        require(
            silenceThreshold != 0 &&
                lastHeartbeat != 0 &&
                block.timestamp - lastHeartbeat >= silenceThreshold,
            "Silence threshold not reached"
        );
        deceased = true;
        emit SilenceEscalated(msg.sender, block.timestamp);
    }

    function _addHeir(address heir) internal {
        require(heir != address(0), "Invalid heir");
        require(!heirs[heir], "Already heir");
        heirs[heir] = true;
        heirCount++;
        emit HeirAdded(heir);
    }
}
