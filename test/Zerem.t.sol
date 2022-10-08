// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/Zerem.sol";

contract ZeremTest is Test {
    Zerem public zerem;
    function setUp() public {
        // usdc
        address underlyingToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        uint256 minLockAmount = 1000e18; // 1k units
        uint256 unlockDelaySec = 24 hours;
        uint256 unlockPeriodSec = 48 hours;

       zerem = new Zerem(underlyingToken, minLockAmount, unlockDelaySec, unlockPeriodSec);

        deal(zerem.underlyingToken(), address(this), 1000e18);
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
        console.log(entries.length);
        assertEq(entries.length, 1);
        console.logBytes32(entries[0].topics[0]);
        console.logAddress(address(this));
        console.logBytes32(entries[0].topics[1]);
        return;
        assertEq(entries[0].topics[0], keccak256("TransferFulfilled(address,uint256,uint256)"));
        assertEq(uint256(entries[0].topics[1]), uint256(uint160(address(this))));
        return;

        (uint256 withdrawnAmount, uint256 remainingAmount) = abi.decode(entries[0].data, (uint256, uint256));
        assertEq(withdrawnAmount, amount);
        assertEq(remainingAmount, uint256(0));
    }

    function testTransferLock() public {
        
    }

    function testTransferUnlock() public {
        
    }


    // function testSetNumber(uint256 x) public {
    //     counter.setNumber(x);
    //     assertEq(counter.number(), x);
    // }
}
