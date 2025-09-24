// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

/*
 Emergency Wallet Freeze
 - Owner: primary controller of the wallet (EOA or contract)
 - Guardians: pre-approved addresses able to vote to "freeze" the wallet
 - When frozen: transfers & withdrawals blocked
 - Freeze triggered when guardian votes >= requiredConfirmations
 - Freeze lasts for freezeDuration seconds (auto-unfreeze after that)
 - Owner can unfreeze early.
 - Owner can add/remove guardians and configure params.
 - Supports receiving ETH and sending ETH/ERC20.
*/

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);
}

error NotOwner();
error NotGuardian();
error AlreadyGuardian();
error NotAGuardian();
error FreezeActive();
error NotFrozen();
error VoteAlreadyCast();
error VoteNotFound();
error ZeroAddress();
error TransferFailed();
error InvalidRequiredConfirmations();

contract EmergencyWalletFreeze {
    /* ========== STATE ========== */

    address public owner;

    // Guardians tracking
    mapping(address => bool) public isGuardian;
    address[] public guardiansList;

    // Votes by guardians toward freeze
    mapping(address => bool) private guardianVoted;
    uint256 public votesCount;

    // Freeze state
    uint256 public freezeUntil; // timestamp until which contract is frozen (exclusive)
    uint256 public freezeDuration; // default duration in seconds for any freeze

    // Minimum number of guardian votes required to freeze
    uint256 public requiredConfirmations;

    // Events
    event OwnerChanged(address indexed oldOwner, address indexed newOwner);
    event GuardianAdded(address indexed guardian);
    event GuardianRemoved(address indexed guardian);
    event GuardianVoted(address indexed guardian);
    event GuardianVoteRevoked(address indexed guardian);
    event Frozen(uint256 untilTimestamp, uint256 votesReached);
    event Unfrozen(address indexed by);
    event ReceivedETH(address indexed from, uint256 amount);
    event ETHWithdrawn(address indexed to, uint256 amount);
    event ERC20Withdrawn(address indexed token, address indexed to, uint256 amount);
    event FreezeDurationUpdated(uint256 oldDuration, uint256 newDuration);
    event RequiredConfirmationsUpdated(uint256 oldReq, uint256 newReq);

    /* ========== MODIFIERS ========== */

    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    modifier onlyGuardian() {
        if (!isGuardian[msg.sender]) revert NotGuardian();
        _;
    }

    // If freeze active, block; but also auto-unfreeze if time passed
    modifier notFrozen() {
        _autoUnfreezeIfExpired();
        if (block.timestamp < freezeUntil) revert FreezeActive();
        _;
    }

    /* ========== CONSTRUCTOR ========== */

    constructor(address[] memory initialGuardians, uint256 _requiredConfirmations, uint256 _freezeDuration) {
        owner = msg.sender;

        if (_requiredConfirmations == 0) revert InvalidRequiredConfirmations();
        requiredConfirmations = _requiredConfirmations;
        freezeDuration = _freezeDuration;

        for (uint256 i = 0; i < initialGuardians.length; i++) {
            _addGuardianInternal(initialGuardians[i]);
        }
    }

    /* ========== FALLBACK / RECEIVE ========== */

    receive() external payable {
        emit ReceivedETH(msg.sender, msg.value);
    }

    fallback() external payable {
        if (msg.value > 0) emit ReceivedETH(msg.sender, msg.value);
    }

    /* ========== OWNER FUNCTIONS ========== */

    function changeOwner(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert ZeroAddress();
        address old = owner;
        owner = newOwner;
        emit OwnerChanged(old, newOwner);
    }

    function addGuardian(address guardian) external onlyOwner {
        _addGuardianInternal(guardian);
    }

    function removeGuardian(address guardian) external onlyOwner {
        if (!isGuardian[guardian]) revert NotAGuardian();
        isGuardian[guardian] = false;
        // remove from guardiansList (cheap remove by swap)
        for (uint256 i = 0; i < guardiansList.length; i++) {
            if (guardiansList[i] == guardian) {
                guardiansList[i] = guardiansList[guardiansList.length - 1];
                guardiansList.pop();
                break;
            }
        }

        // if guardian had already voted, revoke their vote
        if (guardianVoted[guardian]) {
            guardianVoted[guardian] = false;
            if (votesCount > 0) votesCount--;
            emit GuardianVoteRevoked(guardian);
        }

        emit GuardianRemoved(guardian);
    }

    function setFreezeDuration(uint256 newDuration) external onlyOwner {
        uint256 old = freezeDuration;
        freezeDuration = newDuration;
        emit FreezeDurationUpdated(old, newDuration);
    }

    function setRequiredConfirmations(uint256 newReq) external onlyOwner {
        if (newReq == 0 || newReq > guardiansList.length) revert InvalidRequiredConfirmations();
        uint256 old = requiredConfirmations;
        requiredConfirmations = newReq;
        emit RequiredConfirmationsUpdated(old, newReq);
    }

    /* ========== GUARDIAN VOTING ========== */

    /// @notice Guardian casts a vote to freeze the wallet. When votes reach requiredConfirmations, freeze activates.
    function guardianVoteToFreeze() external onlyGuardian {
        if (guardianVoted[msg.sender]) revert VoteAlreadyCast();
        guardianVoted[msg.sender] = true;
        votesCount++;
        emit GuardianVoted(msg.sender);

        if (votesCount >= requiredConfirmations) {
            _activateFreeze();
        }
    }

    /// @notice Guardian can revoke their freeze vote (if freeze not yet active).
    function guardianRevokeVote() external onlyGuardian {
        if (!guardianVoted[msg.sender]) revert VoteNotFound();
        // If already frozen, votes are irrelevant for that freeze; still allow revocation
        guardianVoted[msg.sender] = false;
        if (votesCount > 0) votesCount--;
        emit GuardianVoteRevoked(msg.sender);
    }

    /* ========== FREEZE / UNFREEZE ========== */

    /// @dev internal activation sets freezeUntil = now + freezeDuration
    function _activateFreeze() internal {
        freezeUntil = block.timestamp + freezeDuration;
        // reset votes (they can vote again after unfreeze if desired)
        _clearVotes();
        emit Frozen(freezeUntil, votesCount);
    }

    /// @notice Owner can unfreeze early at any time
    function ownerUnfreeze() external onlyOwner {
        _autoUnfreezeIfExpired();
        if (block.timestamp >= freezeUntil) revert NotFrozen(); // nothing to unfreeze
        freezeUntil = 0;
        emit Unfrozen(msg.sender);
    }

    /// @notice Anyone can call to check and auto-unfreeze if time passed (keeps state clean)
    function autoUnfreezeIfExpired() external {
        _autoUnfreezeIfExpired();
    }

    function _autoUnfreezeIfExpired() internal {
        if (freezeUntil != 0 && block.timestamp >= freezeUntil) {
            freezeUntil = 0;
            emit Unfrozen(address(0)); // address(0) signals auto-unfreeze
        }
    }

    function _clearVotes() internal {
        // iterate guardian list and clear mapping
        for (uint256 i = 0; i < guardiansList.length; i++) {
            address g = guardiansList[i];
            if (guardianVoted[g]) {
                guardianVoted[g] = false;
            }
        }
        votesCount = 0;
    }

    /* ========== WALLET OPERATIONS (OWNER) ========== */

    /// @notice Withdraw ETH from contract (owner only, blocked if frozen)
    function withdrawETH(address payable to, uint256 amount) external onlyOwner notFrozen {
        if (to == address(0)) revert ZeroAddress();
        (bool ok, ) = to.call{value: amount}("");
        if (!ok) revert TransferFailed();
        emit ETHWithdrawn(to, amount);
    }

    /// @notice Transfer ERC20 tokens from this contract (owner only, blocked if frozen)
    function withdrawERC20(address token, address to, uint256 amount) external onlyOwner notFrozen {
        if (to == address(0)) revert ZeroAddress();
        bool ok = IERC20(token).transfer(to, amount);
        if (!ok) revert TransferFailed();
        emit ERC20Withdrawn(token, to, amount);
    }

    /// @notice Convenience function: execute arbitrary call (owner only, blocked if frozen)
    function execute(address target, uint256 value, bytes calldata data) external onlyOwner notFrozen returns (bytes memory) {
        (bool ok, bytes memory ret) = target.call{value: value}(data);
        if (!ok) {
            // bubble revert reason
            assembly {
                revert(add(ret, 32), mload(ret))
            }
        }
        return ret;
    }

    /* ========== VIEW HELPERS ========== */

    function getGuardians() external view returns (address[] memory) {
        return guardiansList;
    }

    function guardiansCount() external view returns (uint256) {
        return guardiansList.length;
    }

    function hasGuardianVoted(address g) external view returns (bool) {
        return guardianVoted[g];
    }

    function isFrozen() external view returns (bool) {
        return block.timestamp < freezeUntil;
    }

    /* ========== INTERNAL HELPERS ========== */

    function _addGuardianInternal(address guardian) internal {
        if (guardian == address(0)) revert ZeroAddress();
        if (isGuardian[guardian]) revert AlreadyGuardian();
        isGuardian[guardian] = true;
        guardiansList.push(guardian);
        emit GuardianAdded(guardian);
    }
}
