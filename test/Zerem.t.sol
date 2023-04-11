// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Zerem.sol";
import "./MockERC20.sol";

contract ZeremTest is Test {
    Zerem public zerem;
    bool testToken;

    function setUp() public {
        address underlyingToken = address(new MockERC20("mock", "mock", 1e28));
        uint256 minLockAmount = 1000e18; // 1k units
        uint256 unlockDelaySec = 24 hours;
        uint256 unlockPeriodSec = 48 hours;
        uint8   unlockExponent = 1; // linear release

        testToken = true;
        if (!testToken)
            underlyingToken = address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);

        zerem = new Zerem(underlyingToken, minLockAmount, unlockDelaySec, unlockPeriodSec, unlockExponent, address(this));
    }

    function testTransferNoFunds() public {
        vm.expectRevert("not enough tokens");
        zerem.transferTo(address(this), 1234);
    }

    function testTransferNoLock() public {
        uint256 amount = 1e18;
        IERC20(zerem.underlyingToken()).transfer(address(zerem), amount);
        
        vm.recordLogs();
        zerem.transferTo(address(this), amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(entries[1].topics[0], keccak256("TransferFulfilled(address,uint256,uint256)"));
        assertEq(uint256(entries[1].topics[1]), uint256(uint160(address(this))));

        (uint256 withdrawnAmount, uint256 remainingAmount) = abi.decode(entries[1].data, (uint256, uint256));
        assertEq(withdrawnAmount, amount);
        assertEq(remainingAmount, uint256(0));
    }

    function testTransferLock() public {
        uint256 amount = 1000e18;
        IERC20(zerem.underlyingToken()).transfer(address(zerem), amount);

        vm.recordLogs();
        zerem.transferTo(address(this), amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("TransferLocked(address,uint256,uint256)"));
        assertEq(uint256(entries[0].topics[1]), uint256(uint160(address(this))));

        (uint256 amountLocked, uint256 lockTimestamp) = abi.decode(entries[0].data, (uint256, uint256));
        assertEq(amountLocked, amount);
        assertEq(lockTimestamp, uint256(block.timestamp));

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount0 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount0, 0);

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount0_5 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount0_5, amount / 2);

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount1 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount1, amount);
    }

    function testTransferLockAndUnlock() public {
        uint256 amount = 1000e18;
        IERC20(zerem.underlyingToken()).transfer(address(zerem), amount);

        vm.recordLogs();
        zerem.transferTo(address(this), amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("TransferLocked(address,uint256,uint256)"));
        assertEq(uint256(entries[0].topics[1]), uint256(uint160(address(this))));

        (uint256 amountLocked, uint256 lockTimestamp) = abi.decode(entries[0].data, (uint256, uint256));
        assertEq(amountLocked, amount);
        assertEq(lockTimestamp, uint256(block.timestamp));

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount0 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount0, 0);

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount0_5 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount0_5, amount / 2);

        uint256 balanceBefore = IERC20(zerem.underlyingToken()).balanceOf(address(this));
        zerem.unlockFor(address(this), lockTimestamp);
        uint256 balanceAfter = IERC20(zerem.underlyingToken()).balanceOf(address(this));
        assertEq(balanceBefore + withdrawableAmount0_5 >= balanceAfter, true);

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount1 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount1, amount - (balanceAfter - balanceBefore));

        zerem.unlockFor(address(this), lockTimestamp);
    }

    function testEarlyUnlock() public {
        uint256 amount = 1000e18;
        IERC20(zerem.underlyingToken()).transfer(address(zerem), amount);

        vm.recordLogs();
        zerem.transferTo(address(this), amount);
        Vm.Log[] memory entries = vm.getRecordedLogs();

        assertEq(entries.length, 1);
        assertEq(entries[0].topics[0], keccak256("TransferLocked(address,uint256,uint256)"));
        assertEq(uint256(entries[0].topics[1]), uint256(uint160(address(this))));

        (uint256 amountLocked, uint256 lockTimestamp) = abi.decode(entries[0].data, (uint256, uint256));
        assertEq(amountLocked, amount);
        assertEq(lockTimestamp, uint256(block.timestamp));

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount0 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount0, 0);

        vm.warp(block.timestamp + 24 hours);
        uint256 withdrawableAmount0_5 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        assertEq(withdrawableAmount0_5, amount / 2);

        uint256 balanceBefore = IERC20(zerem.underlyingToken()).balanceOf(address(this));
        zerem.unlockFor(address(this), lockTimestamp);
        uint256 balanceAfter = IERC20(zerem.underlyingToken()).balanceOf(address(this));
        assertEq(balanceBefore + withdrawableAmount0_5 >= balanceAfter, true);

        uint256 withdrawableAmount1 = zerem.getWithdrawableAmount(address(this), lockTimestamp);
        console.log(withdrawableAmount1);
        assertEq(withdrawableAmount1, 0);
        vm.expectRevert("no withdrawable funds");
        zerem.unlockFor(address(this), lockTimestamp);
    }

    // test written by STARZ
    function testTransferNoLock2() public {
        uint256 amount2 = 2e18;
        IERC20(zerem.underlyingToken()).transfer(address(zerem), amount2);

        vm.recordLogs();
        zerem.transferTo(address(this), amount2);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(
            entries[1].topics[0],
            keccak256("TransferFulfilled(address,uint256,uint256)")
        );
        assertEq(
            uint256(entries[1].topics[1]),
            uint256(uint160(address(this)))
        );

        (uint256 withdrawnAmount, uint256 remainingAmount) = abi.decode(
            entries[1].data,
            (uint256, uint256)
        );
        assertEq(withdrawnAmount, amount2);
        assertEq(remainingAmount, uint256(0));

        uint256 amount = 1e18;
        IERC20(zerem.underlyingToken()).transfer(address(zerem), amount);

        vm.recordLogs();
        
        zerem.transferTo(address(this), amount);
        entries = vm.getRecordedLogs();
        assertEq(entries.length, 2);
        assertEq(
            entries[1].topics[0],
            keccak256("TransferFulfilled(address,uint256,uint256)")
        );
        assertEq(
            uint256(entries[1].topics[1]),
            uint256(uint160(address(this)))
        );

        (withdrawnAmount, remainingAmount) = abi.decode(
            entries[1].data,
            (uint256, uint256)
        );
        assertEq(withdrawnAmount, amount);
        assertEq(remainingAmount, uint256(0));
    }
}
