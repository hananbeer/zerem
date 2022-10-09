// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "./Zerem.sol";
import "./FixedMath.sol";

abstract contract ZeremLinear is Zerem {
    function _unlockFunc(uint256 t) internal override view returns (uint256) {
        return t;
    }
}

abstract contract ZeremSCurve is Zerem {
    using FixedMath for int256;

    int256 immutable public steepness = 1e8;
    int256 immutable public midpoint = 1e5;
    int256 immutable public maxpoint = 2e5;

    function _unlockFunc(uint256 t) internal override view returns (uint256) {
        int256 numerator = int256(t) - midpoint;
        int256 innerSqrt = (steepness + (numerator) ** 2);
        int256 fixedInner = innerSqrt.toFixed();
        int256 fixedDenominator = fixedInner.sqrt();
        int256 fixedNumerator = numerator.toFixed();
        int256 midVal = fixedNumerator.divide(fixedDenominator) + 1e24;
        int256 fixedFinal = maxpoint.toFixed() * midVal;
        return uint256(fixedFinal / 1e30);
    }
}
