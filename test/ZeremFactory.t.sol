pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/ZeremFactory.sol";

interface CheatCodes {
   // Gets address for a given private key, (privateKey) => (address)
   function addr(uint256) external returns (address);
}

contract ZeremFactoryTest is Test {
    ZeremFactory public zeremFactory;
    address public addr1;
    
    address underlyingToken = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // usdc
    uint256 minLockAmount = 1000e18; // 1k units
    uint256 unlockDelaySec = 24 hours;
    uint256 unlockPeriodSec = 48 hours;
    uint8   unlockExponent = 1;

    CheatCodes cheats = CheatCodes(HEVM_ADDRESS);

    function setUp() public {
       zeremFactory = new ZeremFactory();
       addr1 = cheats.addr(1);
    }

    function testShouldDeploy() public {
        Zerem addr = zeremFactory.deploy(underlyingToken, minLockAmount, unlockDelaySec, unlockPeriodSec, unlockExponent);
        assert(address(addr) != address(0));
    }

    function testGetZeremFromID() public {
        vm.prank(addr1);

        bytes32 id = keccak256(abi.encode(addr1, underlyingToken));
        Zerem deployed_address = zeremFactory.deploy(underlyingToken, minLockAmount, unlockDelaySec, unlockPeriodSec, unlockExponent);
        assert(zeremFactory.getZerem(id) == address(deployed_address));

        vm.stopPrank();
    }

    function testGetZeremFromParams() public {
        vm.prank(addr1);

        Zerem deployed_address = zeremFactory.deploy(underlyingToken, minLockAmount, unlockDelaySec, unlockPeriodSec, unlockExponent);
        assert(zeremFactory.getZerem(addr1, underlyingToken) == address(deployed_address));

        vm.stopPrank();
    }
}