// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Zerem.sol";

abstract contract ZeremLinearStratagy is Zerem {
    function _getWithdrawableAmount(bytes32 transferId) internal override view returns (uint256 withdrawableAmount) {
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
}

contract ZeremLinearEther is ZeremLinearStratagy, ZeremEther {
    constructor(
        uint256 _lockThreshold,
        uint256 _unlockDelaySec,
        uint256 _unlockPeriodSec,
        address _liquidationResolver
    ) ZeremEther(
        _lockThreshold,
        _unlockDelaySec,
        _unlockPeriodSec,
        _liquidationResolver
    ) {
    }
}

contract ZeremLinearToken is ZeremLinearStratagy, ZeremToken {
    constructor(
        address _token,
        uint256 _lockThreshold,
        uint256 _unlockDelaySec,
        uint256 _unlockPeriodSec,
        address _liquidationResolver
    ) ZeremToken(
        _token,
        _lockThreshold,
        _unlockDelaySec,
        _unlockPeriodSec,
        _liquidationResolver
    ) {
    }
}