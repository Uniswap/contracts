# Counter
[Git Source](https://github.com/Uniswap/foundry-template/blob/6ed2d53f10b4739f84426a12bef01482d7a2e669/src/Counter.sol)

**Inherits:**
[ICounter](/src/interface/ICounter.sol/interface.ICounter.md)


## State Variables
### number

```solidity
uint256 public number;
```


## Functions
### constructor


```solidity
constructor(uint256 initialNumber);
```

### setNumber

Sets the number


```solidity
function setNumber(uint256 newNumber) public;
```
**Parameters**

|Name|Type|Description|
|----|----|-----------|
|`newNumber`|`uint256`|The new number|


### increment

Increments the number by 1


```solidity
function increment() public;
```

