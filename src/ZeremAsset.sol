// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Zerem.sol";
import "./ZeremFuncs.sol";

contract ZeremEther is ZeremLinear {
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

contract ZeremToken is ZeremLinear {
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
