// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Zerem.sol";
import "./ZeremEther.sol";

contract ZeremFactory {
    mapping (bytes32 => address) public zerems;
    function deploy(address _token, uint256 _minLockAmount, uint256 _unlockDelaySec, uint256 _unlockPeriodSec) public returns (address) {
        bytes32 id = keccak256(abi.encode(msg.sender, _token)); //??}

        if (_token == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE)) {
          ZeremEther zeremEth = new ZeremEther{ salt: id }(_token, _minLockAmount, _unlockDelaySec, _unlockPeriodSec);
          zerems[id] = address(zeremEth);

          return address(zeremEth);
        }

        Zerem zerem = new Zerem{ salt: id }(_token, _minLockAmount, _unlockDelaySec, _unlockPeriodSec);
        zerems[id] = address(zerem);

        return address(zerem);
    }

   function getZerem(address deployer, address token) public view returns (address) {
        bytes32 id = keccak256(abi.encode(deployer, token));
        return zerems[id];
   }
   
   function getZerem(bytes32 id) public view returns (address) {
        return zerems[id];
   }
}
