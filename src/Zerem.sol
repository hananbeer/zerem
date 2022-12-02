// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "../lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "../lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

contract Zerem {
    uint256 public immutable precision = 1e8;
    address immutable NATIVE = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

    // a single token per zerem contract
    address public immutable underlyingToken;

    // minimum amount before locking funds, otherwise direct transfer
    uint256 public immutable lockThreshold;

    // time frame without unlocking, in seconds
    uint256 public immutable unlockDelaySec;

    // time frame of gradual, linear unlock, in seconds
    uint256 public immutable unlockPeriodSec;

    // an address used to resolve liquidations (multisig, governance, etc.)
    address public liquidationResolver;

    struct TransferRecord {
        address sender;
        uint256 lockTimestamp;
        uint256 totalAmount;
        uint256 remainingAmount;
        bool isFrozen;
    }

    // keccak256(address user, uint256 timestamp) => Transfer
    mapping(bytes32 => TransferRecord) public pendingTransfers;

    // user => amount
    mapping(address => uint256) public pendingTotalBalances;

    uint256 public totalTokenBalance;

    event TransferLocked(address indexed user, uint256 amount, uint256 timestamp);
    event TransferFulfilled(address indexed user, uint256 amountUnlocked, uint256 amountRemaining);

    event FundsFreezeStateUpdate(address indexed user, uint256 timestamp, bool isFrozen);
    event FundsLiquidated(address indexed user, uint256 timestamp);

    constructor(
        address _token,
        uint256 _lockThreshold,
        uint256 _unlockDelaySec,
        uint256 _unlockPeriodSec,
        address _liquidationResolver
    ) {
        require(_token != address(0), "must specify token");
        require(_unlockDelaySec < 90 days, "warning: delay might be too large");
        require(_unlockPeriodSec < 90 days, "warning: delay might be too large");

        underlyingToken = _token;
        lockThreshold = _lockThreshold;
        unlockDelaySec = _unlockDelaySec;
        unlockPeriodSec = _unlockPeriodSec;
        liquidationResolver = _liquidationResolver;
    }

    function _getLockedBalance() internal view returns (uint256) {
        if (underlyingToken == NATIVE) {
            return address(this).balance;
        } else {
            return IERC20(underlyingToken).balanceOf(address(this));
        }
    }

    function _sendFunds(address receiver, uint256 amount) internal {
        if (underlyingToken == NATIVE) {
            bool success;
            assembly {
                success := call(6000, receiver, amount, 0, 0, 0, 0)
            }
            require(success, "sending ether failed");
        } else {
            require(msg.value == 0, "msg.value must be zero");
            // SECURITY NOTE: as audit [M-06] suggests, if underlyingToken has
            // transfer fees then accounting may be incorrect.
            SafeERC20.safeTransfer(IERC20(underlyingToken), receiver, amount);
        }
    }

    function _getTransferId(address user, uint256 lockTimestamp) internal pure returns (bytes32) {
        bytes32 transferId = keccak256(abi.encode(user, lockTimestamp));
        return transferId;
    }

    function _getRecordById(bytes32 transferId) internal view returns (TransferRecord storage) {
        TransferRecord storage record = pendingTransfers[transferId];
        require(record.totalAmount > 0, "no such transfer record");
        return record;
    }

    function _getRecord(address user, uint256 lockTimestamp) internal view returns (TransferRecord storage) {
        bytes32 transferId = _getTransferId(user, lockTimestamp);
        return _getRecordById(transferId);
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
        TransferRecord storage record = _getRecordById(transferId);

        // first make sure funds were not frozen
        if (record.isFrozen) {
            return 0;
        }

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

        // t = block.timestamp
        // t0 = record.lockTimestamp
        // d = unlockDelaySec
        // p = unlockPeriodSec

        // delta time:
        // dt = t - t0
        uint256 deltaTime = block.timestamp - record.lockTimestamp;
        if (deltaTime < unlockDelaySec) {
            return 0;
        }

        // delta time delayed:
        // ddt = dt - d
        uint256 deltaTimeDelayed = (deltaTime - unlockDelaySec);

        // ensure 0 <= (ddt / p) <= 1
        if (deltaTimeDelayed >= unlockPeriodSec) {
            return record.remainingAmount;
        }

        // r = precision
        // normalized delta time: (0..1)r
        //       ddt * r
        // ndt = -------
        //          p
        uint256 deltaTimeNormalized = (deltaTimeDelayed * precision) / unlockPeriodSec;

        // clamp f(ndt)
        if (deltaTimeNormalized > precision) {
            deltaTimeNormalized = precision;
        }

        // a = locked totalAmount
        // u = totalUnlockedAmount

        // u = a * f(ndt)
        uint256 totalUnlockedAmount = (record.totalAmount * deltaTimeNormalized) / precision;

        // q = withdrawnAmount
        // subtract the already withdrawn amount from the unlocked amount
        uint256 withdrawnAmount = record.totalAmount - record.remainingAmount;
        if (totalUnlockedAmount < withdrawnAmount) {
            return 0;
        }

        // w = withdrawableAmount
        // w = u - q
        withdrawableAmount = totalUnlockedAmount - withdrawnAmount;
        if (withdrawableAmount > record.remainingAmount) {
            withdrawableAmount = record.remainingAmount;
        }
    }

    function getWithdrawableAmount(address user, uint256 lockTimestamp) public view returns (uint256 amount) {
        bytes32 transferId = _getTransferId(user, lockTimestamp);
        return _getWithdrawableAmount(transferId);
    }

    // 1. Transfer funds to Zerem
    // 2. Calculate funds user owns (amount < lockThreshold)
    // 3. Check if user can receive funds now or funds must be locked
    function transferTo(address user, uint256 amount) public payable {
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

    function unlockFor(address user, uint256 lockTimestamp) public {
        // TODO: send relayer fees here
        // (but only allow after unlockDelay + unlockPeriod + relayerGracePeriod)
        _unlockFor(user, lockTimestamp, user);
    }

    modifier onlyLiquidator() {
        require(msg.sender == liquidationResolver, "must be liquidation resolver");
        _;
    }

    function updateFreezeState(address user, uint256 lockTimestamp, bool isFrozen) public onlyLiquidator {
        TransferRecord storage record = _getRecord(user, lockTimestamp);
        record.isFrozen = isFrozen;
        emit FundsFreezeStateUpdate(user, lockTimestamp, isFrozen);
    }

    function liquidateFunds(address user, uint256 lockTimestamp) public onlyLiquidator {
        // NOTE: to avoid sender unrightfully liquidating funds right before a user unlocks
        // it would be redundant to check if funds are frozen since it only requires a simple additional txn
        // just using a multiple of two for the total lock period
        require(block.timestamp > lockTimestamp + 2 * (unlockDelaySec + unlockPeriodSec), "liquidation too early");
        _unlockFor(user, lockTimestamp, liquidationResolver);
        emit FundsLiquidated(user, lockTimestamp);
    }
}
