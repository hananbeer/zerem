// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Zerem {
    address public underlyingToken;
    uint256 public lockThreshold; // minimum amount before locking funds, otherwise direct transfer
    uint256 public unlockDelaySec; // timeframe without unlocking, in seconds
    uint256 public unlockPeriodSec; // timeframe of gradual, linear unlock, in seconds
    address public liquidationResolver; // an address used to resolve liquidations

    struct TransferRecord {
        address sender;
        uint256 lockTimestamp;
        uint256 totalAmount;
        uint256 remainingAmount;
        bool isFrozen;
    }

    // keccak256(address user, uint256 timestamp) => Transfer
    mapping (bytes32 => TransferRecord) public pendingTransfers;

    // user => amount
    mapping (address => uint256) public pendingTotalBalances;

    uint256 totalTokenBalance;

    event TransferLocked(address indexed user, uint256 amount, uint256 timestamp);
    event TransferFulfilled(address indexed user, uint256 amountUnlocked, uint256 amountRemaining);

    constructor(
        address _token,
        uint256 _lockThreshold,
        uint256 _unlockDelaySec,
        uint256 _unlockPeriodSec,
        address _liquidationResolver
    ) {
        underlyingToken = _token;
        lockThreshold = _lockThreshold;
        unlockDelaySec = _unlockDelaySec;
        unlockPeriodSec = _unlockPeriodSec;
        liquidationResolver = _liquidationResolver;
    }

    function _getLockedBalance() internal virtual returns (uint256) {}
    function _sendFunds(address receiver, uint256 amount) internal virtual {}

    function _getTransferId(address user, uint256 lockTimestamp) internal pure returns (bytes32) {
        bytes32 transferId = keccak256(abi.encode(user, lockTimestamp));
        return transferId;
    }

    function _getRecord(bytes32 transferId) internal view returns (TransferRecord storage) {
        TransferRecord storage record = pendingTransfers[transferId];
        require(record.totalAmount > 0, "no such transfer record");
        return record;
    }

    function _getRecord(address user, uint256 lockTimestamp) internal view returns (TransferRecord storage) {
        bytes32 transferId = keccak256(abi.encode(user, lockTimestamp));
        return _getRecord(transferId);
    }

    function _lockFunds(address user, uint256 amount) internal {
        bytes32 transferId = _getTransferId(user, block.timestamp);
        TransferRecord storage record = pendingTransfers[transferId];
        if (record.totalAmount == 0) {
            record.sender = msg.sender;
            record.lockTimestamp = block.timestamp;
        } else {
            require(record.sender == msg.sender, "multiple senders per same transfer id");
        }

        record.totalAmount += amount;
        record.remainingAmount += amount;
        pendingTotalBalances[user] += amount;
    }

    function _unlockFor(address user, uint256 lockTimestamp, address receiver) internal {
        bytes32 transferId = keccak256(abi.encode(user, lockTimestamp));
        uint256 amount = _getWithdrawableAmount(transferId);
        require(amount > 0, "no withdrawable funds");
        TransferRecord storage record = pendingTransfers[transferId];
        uint256 remainingAmount = record.remainingAmount - amount;
        record.remainingAmount = remainingAmount;
        pendingTotalBalances[user] -= amount;

        _sendFunds(receiver, amount);
        emit TransferFulfilled(user, amount, remainingAmount);
    }

    function _getWithdrawableAmount(bytes32 transferId) internal view returns (uint256 withdrawableAmount) {
        TransferRecord storage record = _getRecord(transferId);

        // calculate unlock function
        // in this case, we are using a delayed linear unlock:
        // f(t) = amount * delta
        // delta = clamp(now - lockTime + unlockDelay, 0%, 100%)
        // for example, start delay of 24 hours and end delay of 72 hours/
        // give us initial 24 hours period with no unlock, following 48 hours period
        // of gradual unlocking
        // need to normalize between 0..1
        // so (deltaTime - startDelay) / (endDelay - startDelay) = (deltaDelayed / 48hr)
        // then clamp 0..1

        uint256 deltaTime = block.timestamp - record.lockTimestamp;
        if (deltaTime < unlockDelaySec)
            return 0;

        uint256 deltaTimeDelayed = (deltaTime - unlockDelaySec);
        if (deltaTimeDelayed >= unlockPeriodSec)
            withdrawableAmount = record.remainingAmount;
        else {
            // calculate the total amount unlocked amount
            uint256 totalUnlockedAmount = (record.totalAmount * 1e5 * deltaTimeDelayed) / (1e5 * unlockPeriodSec);
            // subtract the already withdrawn amount from the unlocked amount
            uint256 withdrawnAmount = record.totalAmount - record.remainingAmount;
            if (totalUnlockedAmount < withdrawnAmount)
                return 0;

            withdrawableAmount = totalUnlockedAmount - withdrawnAmount;
            if (withdrawableAmount > record.remainingAmount)
                withdrawableAmount = record.remainingAmount;
        }
    }

    function getWithdrawableAmount(address user, uint256 lockTimestamp) public view returns (uint256 amount) {
        bytes32 transferId = _getTransferId(user, lockTimestamp);
        return _getWithdrawableAmount(transferId);
    }

    // 1. Transfer funds to Zerem
    // 2. Calculate funds user owns (amount < lockThreshold)
    // 3. Check if user can recive funds now or funds must be locked
    function transferTo(address user, uint256 amount) payable public {
        uint256 oldBalance = totalTokenBalance;
        totalTokenBalance = _getLockedBalance();
        uint256 transferredAmount = totalTokenBalance - oldBalance;
        // if this requirement fails it implies calling contract failure
        // to transfer this contract `amount` tokens.
        require(transferredAmount >= amount, "not enough tokens");
        
        if (amount < lockThreshold) {
            _sendFunds(user, amount);
            emit TransferFulfilled(user, amount, 0);
        } else {
            _lockFunds(user, amount);
            emit TransferLocked(user, amount, block.timestamp);
        }
    }

    // 1. check for user his withdrawable amount (_getWithdrawableAmount)
    // 2. if user_withdrawable_funds > 0 then send user his funds
    function unlockFor(address user, uint256 lockTimestamp) public {
        // TOOD: send relayer fees here
        // (but only allow after unlockDelay + unlockPeriod + relayerGracePeriod)
        _unlockFor(user, lockTimestamp, user);
    }

    // allow a user to freeze his own funds
    function freezeFunds(address user, uint256 lockTimestamp) public {
        TransferRecord storage record = _getRecord(user, lockTimestamp);
        require(msg.sender == record.sender, "must be funds sender");
        record.isFrozen = true;
        // TODO: emit event
    }

    // allow a user to freeze his own funds
    function unfreezeFunds(address user, uint256 lockTimestamp) public {
        TransferRecord storage record = _getRecord(user, lockTimestamp);
        require(msg.sender == record.sender, "must be funds sender");
        record.isFrozen = false;
        // TODO: emit event
    }

    function liquidateFunds(address user, uint256 lockTimestamp) public {
        TransferRecord storage record = _getRecord(user, lockTimestamp);
        require(msg.sender == record.sender, "must be funds sender");
        // NOTE: to avoid sender unrightfully liquidating funds right before a user unlocks
        // it would be redundant to check if funds are frozen since it only requires a simple additional txn
        // just using a multiple of two for the total lock period
        require(block.timestamp > lockTimestamp + 2 * (unlockDelaySec + unlockPeriodSec), "liquidation too early");
        _unlockFor(user, lockTimestamp, liquidationResolver);
    }
}

contract ZeremEther is Zerem {
    constructor(
        uint256 _lockThreshold,
        uint256 _unlockDelaySec,
        uint256 _unlockPeriodSec,
        address _liquidationResolver
    ) Zerem(
        address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE),
        _lockThreshold,
        _unlockDelaySec,
        _unlockPeriodSec,
        _liquidationResolver
    ) {
    }

    function _getLockedBalance() internal view override returns (uint256) {
        return address(this).balance;
    }

    function _sendFunds(address receiver, uint256 amount) internal override {
        (bool success, ) = payable(receiver).call{gas: 3000, value: amount}(hex"");
        require(success, "sending ether failed");
    }
}

contract ZeremToken is Zerem {
    constructor(
        address _token,
        uint256 _lockThreshold,
        uint256 _unlockDelaySec,
        uint256 _unlockPeriodSec,
        address _liquidationResolver
    ) Zerem(
        _token,
        _lockThreshold,
        _unlockDelaySec,
        _unlockPeriodSec,
        _liquidationResolver
    ) {
    }

    function _getLockedBalance() internal view override returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(this));
    }

    function _sendFunds(address receiver, uint256 amount) internal override {
        // TODO: use safeTransfer
        require(msg.value == 0, "msg.value must be zero");
        IERC20(underlyingToken).transfer(receiver, amount);
    }
}
