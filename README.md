# Zerem

Zerem is a circuit breaker to help keep funds safe.

## Architecture

Bridge.sol -> Zerem.sol -> user address

When calling `withdrawBalance(address user)` from `Bridge.sol` instead of transferring funds to the user directly.
We first transfer the funds to `Zerem.sol` contract and associate them with a user by calling `zerem.transferTo(address user, uint256 amount)`.

`Zerem.sol` lets us configure a unlock function and amount lock threshold.

```
 constructor(
        address _token,
        uint256 _lockThreshold,
        uint256 _unlockDelaySec,
        uint256 _unlockPeriodSec,
        address _liquidationResolver
    )
```
1. `_unlockDelaySec`, `_unlockPeriodSec` - the unlock function is implemented as a delayed linear unlock function.
Where the delta is defined as `clamp(now - lockTime + unlockDelay, 0%,100%)`.
An example would be `unlockDelaySec = 12 hours`,`unlockPeriodSec = 24 hours`, would give us initial 12 hours period with no unlock, following 24 hours period of gradual unlocking.

2. `lockThreshold` - if `transferTo` is called with `amount < lockThreshold` then the amount is automatically transfer to user. So only funds above the level of lockThreshold will be locked in Zerem.

```
lockThreshold - this will configure the max amount a user is able to withdrawl 
