// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Zerem {
    address public underlyingToken;
    uint256 public minLockAmount;
    uint256 public unlockDelaySec; // timeframe without unlocking, in seconds
    uint256 public unlockPeriodSec; // timeframe of gradual, linear unlock, in seconds

    struct TransferRecord {
        uint256 lockTimestamp;
        uint256 totalAmount;
        uint256 remainingAmount;
    }

    // constructor() {
    //     revert("cannot deploy base class");
    // }

    // keccak256(address user, uint256 timestamp) => Transfer
    mapping (bytes32 => TransferRecord) public pendingTransfers;

    // user => amount
    mapping (address => uint256) public pendingTotalBalances;

    uint256 totalTokenBalance;

    event TransferLocked(address indexed user, uint256 amount, uint256 timestamp);
    event TransferFulfilled(address indexed user, uint256 amountUnlocked, uint256 amountRemaining);
    
    function _getBalance() internal virtual returns (uint256) {}
    function _sendFunds(address user, uint256 amount) internal virtual {}

    function _lockFunds(address user, uint256 amount) internal {
        bytes32 transferId = keccak256(abi.encode(user, block.timestamp));
        require(pendingTransfers[transferId].totalAmount == 0, "record already exists");
        pendingTransfers[transferId] = TransferRecord({
            lockTimestamp: block.timestamp,
            totalAmount: amount,
            remainingAmount: amount
        });
        pendingTotalBalances[user] += amount;
    }

    function _getWithdrawableAmount(TransferRecord storage record) internal returns (uint256 withdrawableAmount) {
        require(record.totalAmount > 0, "no such record");
        uint256 delta = block.timestamp - record.lockTimestamp;
        
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
            withdrawableAmount = (record.totalAmount * 1e5 * deltaTimeDelayed) / (1e5 * unlockPeriodSec);
            if (withdrawableAmount > record.remainingAmount)
                withdrawableAmount = record.remainingAmount;
        }
    }

    function getWithdrawableAmount(address user, uint256 timestamp) public returns (uint256 amount) {
        bytes32 transferId = keccak256(abi.encode(user, timestamp));
        return _getWithdrawableAmount(pendingTransfers[transferId]);
    }

    function transferTo(address user, uint256 amount) public {
        // TODO: require(onlyBank)

        uint256 oldBalance = totalTokenBalance;
        totalTokenBalance = _getBalance();
        uint256 transferredAmount = totalTokenBalance - oldBalance;
        // if this requirement fails it implies calling contract failure
        // to transfer this contract `amount` tokens.
        require(transferredAmount >= amount, "not enough tokens");
        
        if (amount < minLockAmount) {
            _sendFunds(user, amount);
            emit TransferFulfilled(user, amount, 0);
        } else {
            _lockFunds(user, amount);
            emit TransferLocked(user, amount, block.timestamp);
        }
    }

    function unlockFor(address user, uint256 lockTimestamp) public {
        bytes32 transferId = keccak256(abi.encode(user, lockTimestamp));
        TransferRecord storage record = pendingTransfers[transferId];
        uint256 amount = _getWithdrawableAmount(record);
        uint256 remainingAmount = record.remainingAmount - amount;
        record.remainingAmount = remainingAmount;
        pendingTotalBalances[user] -= amount;

        _sendFunds(user, amount);
        emit TransferFulfilled(user, amount, remainingAmount);
    }
}

contract ZeremEther is Zerem {
    constructor(uint256 _minLockAmount, uint256 _unlockDelaySec, uint256 _unlockPeriodSec) {
        underlyingToken = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        minLockAmount = _minLockAmount;
        unlockDelaySec = _unlockDelaySec;
        unlockPeriodSec = _unlockPeriodSec;
    }

    function _getBalance() internal override returns (uint256) {
        return address(this).balance;
    }

    function _sendFunds(address user, uint256 amount) internal override {
        payable(user).call{gas: 3000, value: amount}(hex"");
    }
}

contract ZeremToken is Zerem {
    constructor(address _token, uint256 _minLockAmount, uint256 _unlockDelaySec, uint256 _unlockPeriodSec) {
        underlyingToken = _token;
        minLockAmount = _minLockAmount;
        unlockDelaySec = _unlockDelaySec;
        unlockPeriodSec = _unlockPeriodSec;
    }

    function _getBalance() internal override returns (uint256) {
        return IERC20(underlyingToken).balanceOf(address(this));
    }

    function _sendFunds(address user, uint256 amount) internal override {
        // TODO: use safeTransfer
        IERC20(underlyingToken).transfer(user, amount);
    }
}
