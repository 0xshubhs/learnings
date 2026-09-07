# Liquity v1 & v2 — Complete Reference

Every contract, every function, in both generations of Liquity, written against
the exact sources cloned in this folder.

| Tree | Path | Files | Solidity |
|---|---|---|---|
| **v1** (LUSD) | `v1-dev/packages/contracts/contracts/` | 82 | 0.6.11 |
| **v2** (BOLD) | `v2-bold/contracts/src/` | 102 | 0.8.24 |

Every `path:line` below is a clickable link verified with `grep -n` against these
files. Citations always carry the full path from `liquity/`, so v1 and v2 can
never be confused.

For the *why* — the mental model, the design rationale, the comparison against
Aave's auction-based liquidation — see the companion
[`LIQUITY-DEEP-DIVE.md`](LIQUITY-DEEP-DIVE.md). This document is the *what* and
the *how*: signatures, parameters, checks, state writes, call chains.

---

## Contents

**[Part 1 — Liquity v1](#part-1--liquity-v1)**

- [1.1 File inventory (82 files)](#11-file-inventory)
- [1.2 Architecture and the `setAddresses` access-control pattern](#12-architecture-and-access-control)
- [1.3 Math foundations: `LiquityMath`, `LiquityBase`, `SafeMath`](#13-math-foundations)
- [1.4 `TroveManager`](#14-trovemanager)
- [1.5 `BorrowerOperations`](#15-borroweroperations)
- [1.6 `StabilityPool` — the product-sum algorithm](#16-stabilitypool)
- [1.7 `SortedTroves` — the ordered list](#17-sortedtroves)
- [1.8 The pools: `ActivePool`, `DefaultPool`, `CollSurplusPool`, `GasPool`](#18-the-pools)
- [1.9 Tokens and staking: `LUSDToken`, `LQTYToken`, `LQTYStaking`, `CommunityIssuance`, lockups](#19-tokens-and-staking)
- [1.10 `PriceFeed` and the Tellor fallback](#110-pricefeed)
- [1.11 Periphery: `HintHelpers`, `MultiTroveGetter`, `Proxy/`, `LPRewards/`](#111-periphery)
- [1.12 v1 reference tables](#112-v1-reference-tables)
- [1.13 v1 use-case index](#113-v1-use-case-index)

**[Part 2 — Liquity v2 (BOLD)](#part-2--liquity-v2-bold)**

- [2.1 File inventory (102 files)](#21-file-inventory)
- [2.2 Architecture: branches, the registry, and what changed](#22-architecture)
- [2.3 Constants and math foundations](#23-constants-and-math)
- [2.4 The interest-rate machinery](#24-the-interest-rate-machinery)
- [2.5 `TroveManager`](#25-trovemanager-v2)
- [2.6 `BorrowerOperations`](#26-borroweroperations-v2)
- [2.7 Batches and delegation](#27-batches-and-delegation)
- [2.8 `StabilityPool` v2](#28-stabilitypool-v2)
- [2.9 `SortedTroves` v2 — ordered by interest rate](#29-sortedtroves-v2)
- [2.10 `ActivePool` and aggregate accounting](#210-activepool-v2)
- [2.11 `CollateralRegistry` and cross-branch redemption](#211-collateralregistry)
- [2.12 Shutdown and urgent redemption](#212-shutdown)
- [2.13 Price feeds](#213-price-feeds)
- [2.14 `TroveNFT` and on-chain metadata](#214-trovenft)
- [2.15 Zappers and leverage](#215-zappers)
- [2.16 v2 reference tables](#216-v2-reference-tables)
- [2.17 v2 use-case index](#217-v2-use-case-index)

**[Part 3 — v1 to v2](#part-3--v1-to-v2)**

- [3.1 Function-by-function migration map](#31-migration-map)
- [3.2 Parameter comparison](#32-parameter-comparison)
- [3.3 What was removed, and why](#33-what-was-removed)

---

# Part 1 — Liquity v1

## 1.1 File inventory

82 Solidity files. The 21 under `TestContracts/` are harnesses and are
inventoried at the end rather than documented function by function.

### Protocol contracts

| File | Lines | Purpose |
|---|--:|---|
| [`ActivePool.sol`](v1-dev/packages/contracts/contracts/ActivePool.sol) | 136 | Holds ETH collateral and records LUSD debt of all active Troves. |
| [`BorrowerOperations.sol`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol) | 666 | User entry point: open, adjust and close Troves. |
| [`CollSurplusPool.sol`](v1-dev/packages/contracts/contracts/CollSurplusPool.sol) | 123 | Holds ETH left over for borrowers after liquidation or redemption. |
| [`DefaultPool.sol`](v1-dev/packages/contracts/contracts/DefaultPool.sol) | 110 | Holds ETH and debt redistributed from liquidated Troves, pending claim. |
| [`Dependencies/AggregatorV3Interface.sol`](v1-dev/packages/contracts/contracts/Dependencies/AggregatorV3Interface.sol) | 36 | Chainlink aggregator interface. |
| [`Dependencies/BaseMath.sol`](v1-dev/packages/contracts/contracts/Dependencies/BaseMath.sol) | 7 | Defines `DECIMAL_PRECISION = 1e18`. |
| [`Dependencies/CheckContract.sol`](v1-dev/packages/contracts/contracts/Dependencies/CheckContract.sol) | 19 | Asserts an address is a non-zero contract during wiring. |
| [`Dependencies/IERC20.sol`](v1-dev/packages/contracts/contracts/Dependencies/IERC20.sol) | 86 | ERC-20 interface. |
| [`Dependencies/IERC2612.sol`](v1-dev/packages/contracts/contracts/Dependencies/IERC2612.sol) | 58 | EIP-2612 permit interface. |
| [`Dependencies/ITellor.sol`](v1-dev/packages/contracts/contracts/Dependencies/ITellor.sol) | 545 | Tellor oracle interface. |
| [`Dependencies/LiquityBase.sol`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol) | 93 | Shared constants (MCR, CCR, gas compensation) and TCR/recovery-mode helpers. |
| [`Dependencies/LiquityMath.sol`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol) | 113 | `_min`, `_max`, `decMul`, `_decPow`, `_computeNominalCR`, `_computeCR`. |
| [`Dependencies/Ownable.sol`](v1-dev/packages/contracts/contracts/Dependencies/Ownable.sol) | 66 | Single-owner access control, renounced after wiring. |
| [`Dependencies/SafeMath.sol`](v1-dev/packages/contracts/contracts/Dependencies/SafeMath.sol) | 161 | Checked arithmetic for Solidity 0.6. |
| [`Dependencies/TellorCaller.sol`](v1-dev/packages/contracts/contracts/Dependencies/TellorCaller.sol) | 53 | Wraps Tellor reads and normalises decimals. |
| [`Dependencies/console.sol`](v1-dev/packages/contracts/contracts/Dependencies/console.sol) | 1907 | Hardhat console.log shim. Dev only. |
| [`GasPool.sol`](v1-dev/packages/contracts/contracts/GasPool.sol) | 18 | Holds the 200 LUSD gas compensation reserve. No logic at all. |
| [`HintHelpers.sol`](v1-dev/packages/contracts/contracts/HintHelpers.sol) | 171 | Off-chain helper computing insert hints for SortedTroves. |
| [`Integrations/LUSDUsdToLUSDEth.sol`](v1-dev/packages/contracts/contracts/Integrations/LUSDUsdToLUSDEth.sol) | 19 | Chainlink-shaped adapter converting LUSD/USD to LUSD/ETH. |
| [`Interfaces/IActivePool.sol`](v1-dev/packages/contracts/contracts/Interfaces/IActivePool.sol) | 17 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/IBorrowerOperations.sol`](v1-dev/packages/contracts/contracts/Interfaces/IBorrowerOperations.sol) | 59 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ICollSurplusPool.sol`](v1-dev/packages/contracts/contracts/Interfaces/ICollSurplusPool.sol) | 32 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ICommunityIssuance.sol`](v1-dev/packages/contracts/contracts/Interfaces/ICommunityIssuance.sol) | 20 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/IDefaultPool.sol`](v1-dev/packages/contracts/contracts/Interfaces/IDefaultPool.sol) | 16 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ILQTYStaking.sol`](v1-dev/packages/contracts/contracts/Interfaces/ILQTYStaking.sol) | 45 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ILQTYToken.sol`](v1-dev/packages/contracts/contracts/Interfaces/ILQTYToken.sol) | 23 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ILUSDToken.sol`](v1-dev/packages/contracts/contracts/Interfaces/ILUSDToken.sol) | 27 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ILiquityBase.sol`](v1-dev/packages/contracts/contracts/Interfaces/ILiquityBase.sol) | 10 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ILockupContractFactory.sol`](v1-dev/packages/contracts/contracts/Interfaces/ILockupContractFactory.sol) | 19 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/IPool.sol`](v1-dev/packages/contracts/contracts/Interfaces/IPool.sol) | 26 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/IPriceFeed.sol`](v1-dev/packages/contracts/contracts/Interfaces/IPriceFeed.sol) | 12 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ISortedTroves.sol`](v1-dev/packages/contracts/contracts/Interfaces/ISortedTroves.sol) | 46 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/IStabilityPool.sol`](v1-dev/packages/contracts/contracts/Interfaces/IStabilityPool.sol) | 203 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ITellorCaller.sol`](v1-dev/packages/contracts/contracts/Interfaces/ITellorCaller.sol) | 7 | Interface. Declares the external surface consumed by the rest of the system. |
| [`Interfaces/ITroveManager.sol`](v1-dev/packages/contracts/contracts/Interfaces/ITroveManager.sol) | 144 | Interface. Declares the external surface consumed by the rest of the system. |
| [`LPRewards/Dependencies/Address.sol`](v1-dev/packages/contracts/contracts/LPRewards/Dependencies/Address.sol) | 165 | OpenZeppelin address utilities. |
| [`LPRewards/Dependencies/SafeERC20.sol`](v1-dev/packages/contracts/contracts/LPRewards/Dependencies/SafeERC20.sol) | 75 | OpenZeppelin SafeERC20. |
| [`LPRewards/Interfaces/ILPTokenWrapper.sol`](v1-dev/packages/contracts/contracts/LPRewards/Interfaces/ILPTokenWrapper.sol) | 11 | LP staking wrapper interface. |
| [`LPRewards/Interfaces/IUnipool.sol`](v1-dev/packages/contracts/contracts/LPRewards/Interfaces/IUnipool.sol) | 14 | Unipool interface. |
| [`LPRewards/TestContracts/ERC20Mock.sol`](v1-dev/packages/contracts/contracts/LPRewards/TestContracts/ERC20Mock.sol) | 35 | Mock ERC-20 for LP reward tests. |
| [`LPRewards/Unipool.sol`](v1-dev/packages/contracts/contracts/LPRewards/Unipool.sol) | 243 | Synthetix-style staking rewards for the Uniswap LUSD/ETH LP token. |
| [`LQTY/CommunityIssuance.sol`](v1-dev/packages/contracts/contracts/LQTY/CommunityIssuance.sol) | 132 | Issues LQTY to the Stability Pool on a decaying schedule. |
| [`LQTY/LQTYStaking.sol`](v1-dev/packages/contracts/contracts/LQTY/LQTYStaking.sol) | 247 | Stake LQTY to earn LUSD borrowing fees and ETH redemption fees. |
| [`LQTY/LQTYToken.sol`](v1-dev/packages/contracts/contracts/LQTY/LQTYToken.sol) | 366 | The LQTY governance token with a one-year transfer lockout for insiders. |
| [`LQTY/LockupContract.sol`](v1-dev/packages/contracts/contracts/LQTY/LockupContract.sol) | 86 | Holds LQTY until an unlock time. |
| [`LQTY/LockupContractFactory.sol`](v1-dev/packages/contracts/contracts/LQTY/LockupContractFactory.sol) | 74 | Deploys one-year LQTY lockup contracts. |
| [`LUSDToken.sol`](v1-dev/packages/contracts/contracts/LUSDToken.sol) | 306 | The LUSD stablecoin: ERC-20 plus EIP-2612 permit, mint/burn gated to the system. |
| [`Migrations.sol`](v1-dev/packages/contracts/contracts/Migrations.sol) | 25 | Truffle deployment bookkeeping. Not part of the protocol. |
| [`MultiTroveGetter.sol`](v1-dev/packages/contracts/contracts/MultiTroveGetter.sol) | 120 | Batch read of Trove data for front ends. |
| [`PriceFeed.sol`](v1-dev/packages/contracts/contracts/PriceFeed.sol) | 572 | Chainlink primary oracle with Tellor fallback and a status state machine. |
| [`Proxy/BorrowerOperationsScript.sol`](v1-dev/packages/contracts/contracts/Proxy/BorrowerOperationsScript.sol) | 48 | DSProxy script wrapping BorrowerOperations calls. |
| [`Proxy/BorrowerWrappersScript.sol`](v1-dev/packages/contracts/contracts/Proxy/BorrowerWrappersScript.sol) | 158 | Composite DSProxy scripts: claim-and-reopen, stake-and-deposit. |
| [`Proxy/ETHTransferScript.sol`](v1-dev/packages/contracts/contracts/Proxy/ETHTransferScript.sol) | 11 | DSProxy script sending raw ETH. |
| [`Proxy/LQTYStakingScript.sol`](v1-dev/packages/contracts/contracts/Proxy/LQTYStakingScript.sol) | 20 | DSProxy script wrapping LQTYStaking. |
| [`Proxy/StabilityPoolScript.sol`](v1-dev/packages/contracts/contracts/Proxy/StabilityPoolScript.sol) | 30 | DSProxy script wrapping StabilityPool. |
| [`Proxy/TokenScript.sol`](v1-dev/packages/contracts/contracts/Proxy/TokenScript.sol) | 42 | DSProxy script wrapping ERC-20 transfers. |
| [`Proxy/TroveManagerScript.sol`](v1-dev/packages/contracts/contracts/Proxy/TroveManagerScript.sol) | 38 | DSProxy script wrapping redemption. |
| [`SortedTroves.sol`](v1-dev/packages/contracts/contracts/SortedTroves.sol) | 420 | Doubly-linked list of Troves ordered by descending NICR. |
| [`StabilityPool.sol`](v1-dev/packages/contracts/contracts/StabilityPool.sol) | 993 | LUSD deposits absorb liquidated debt; depositors earn ETH and LQTY. |
| [`TroveManager.sol`](v1-dev/packages/contracts/contracts/TroveManager.sol) | 1562 | Liquidation, redemption, fee/base-rate logic and Trove storage. |

### Test harnesses (not deployed)

| File | Lines |
|---|--:|
| [`TestContracts/ActivePoolTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/ActivePoolTester.sol) | 16 |
| [`TestContracts/BorrowerOperationsTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/BorrowerOperationsTester.sol) | 63 |
| [`TestContracts/CDPManagerTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/CDPManagerTester.sol) | 60 |
| [`TestContracts/CommunityIssuanceTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/CommunityIssuanceTester.sol) | 25 |
| [`TestContracts/DappSys/proxy.sol`](v1-dev/packages/contracts/contracts/TestContracts/DappSys/proxy.sol) | 221 |
| [`TestContracts/DefaultPoolTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/DefaultPoolTester.sol) | 16 |
| [`TestContracts/Destructible.sol`](v1-dev/packages/contracts/contracts/TestContracts/Destructible.sol) | 12 |
| [`TestContracts/EchidnaProxy.sol`](v1-dev/packages/contracts/contracts/TestContracts/EchidnaProxy.sol) | 117 |
| [`TestContracts/EchidnaTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/EchidnaTester.sol) | 435 |
| [`TestContracts/FunctionCaller.sol`](v1-dev/packages/contracts/contracts/TestContracts/FunctionCaller.sol) | 49 |
| [`TestContracts/LQTYStakingTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/LQTYStakingTester.sol) | 12 |
| [`TestContracts/LQTYTokenTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/LQTYTokenTester.sol) | 56 |
| [`TestContracts/LUSDTokenCaller.sol`](v1-dev/packages/contracts/contracts/TestContracts/LUSDTokenCaller.sol) | 29 |
| [`TestContracts/LUSDTokenTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/LUSDTokenTester.sol) | 66 |
| [`TestContracts/LiquityMathTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/LiquityMathTester.sol) | 24 |
| [`TestContracts/MockAggregator.sol`](v1-dev/packages/contracts/contracts/TestContracts/MockAggregator.sol) | 114 |
| [`TestContracts/MockTellor.sol`](v1-dev/packages/contracts/contracts/TestContracts/MockTellor.sol) | 51 |
| [`TestContracts/NonPayable.sol`](v1-dev/packages/contracts/contracts/TestContracts/NonPayable.sol) | 24 |
| [`TestContracts/PriceFeedTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/PriceFeedTester.sol) | 16 |
| [`TestContracts/PriceFeedTestnet.sol`](v1-dev/packages/contracts/contracts/TestContracts/PriceFeedTestnet.sol) | 34 |
| [`TestContracts/SortedTrovesTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/SortedTrovesTester.sol) | 34 |
| [`TestContracts/StabilityPoolTester.sol`](v1-dev/packages/contracts/contracts/TestContracts/StabilityPoolTester.sol) | 20 |

---

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                         

## 1.2 Architecture and access control

Liquity v1 is eleven core contracts wired to each other exactly once, at
deployment, and then frozen. There is no proxy, no upgrade path, and after
wiring there is no owner.

```
                        BorrowerOperations
                     (open / adjust / close)
                                |
        +-----------------------+------------------------+
        |                       |                        |
   TroveManager           SortedTroves              ActivePool
 (liquidate, redeem,   (ordered by NICR,        (ETH + debt of all
  fees, base rate)      hint-based insert)        active Troves)
        |                                              |
        +--------> StabilityPool <---------------------+
        |          (LUSD absorbs debt,
        |           pays out ETH + LQTY)
        |
        +--------> DefaultPool  (redistributed debt/coll awaiting claim)
        +--------> CollSurplusPool (borrower's leftover ETH)
        +--------> GasPool (200 LUSD reserve per Trove)
```

### The `setAddresses` pattern

Every core contract inherits [`Ownable`](v1-dev/packages/contracts/contracts/Dependencies/Ownable.sol#L1-L66) and exposes a
one-shot `setAddresses(...)`. The deployer calls it once; the last statement
renounces ownership permanently.

`TroveManager.setAddresses` is declared at [`v1-dev/packages/contracts/contracts/TroveManager.sol:234`](v1-dev/packages/contracts/contracts/TroveManager.sol#L234) and ends
with `_renounceOwnership()` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:287`](v1-dev/packages/contracts/contracts/TroveManager.sol#L287). `StabilityPool` does
the same at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:293`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L293), `ActivePool` at
[`v1-dev/packages/contracts/contracts/ActivePool.sol:63`](v1-dev/packages/contracts/contracts/ActivePool.sol#L63).

Each address argument is validated by `checkContract` from
[`v1-dev/packages/contracts/contracts/Dependencies/CheckContract.sol:9-18`](v1-dev/packages/contracts/contracts/Dependencies/CheckContract.sol#L9-L18), which asserts the target is non-zero
and has code.

**Consequence:** after deployment there is no privileged role anywhere in v1. No
pause, no parameter change, no upgrade. Every constant in
[`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:22-36`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L22-L36) is immutable for the life of the
system. This is the single most important fact about the protocol and it is why
the rest of the design has to be self-correcting.

### Authorization at runtime

Because there are no roles, authorization is caller-address equality, checked by
small `_require*` helpers. The canonical example:

```solidity
function _requireCallerIsBorrowerOperations() internal view {
    require(msg.sender == borrowerOperationsAddress, "TroveManager: Caller is not the BorrowerOperations contract");
}
```

[`v1-dev/packages/contracts/contracts/TroveManager.sol:1476-1478`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1476-L1478). The full set of caller gates:

| Guard | Defined at | Permits |
|---|---|---|
| `_requireCallerIsBorrowerOperations` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1476`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1476) | Only `BorrowerOperations` |
| `_requireCallerIsTroveManager` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:940`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L940) | Only `TroveManager` (used by `offset`) |
| `_requireCallerIsActivePool` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:948`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L948) | Only `ActivePool` (ETH receipt) |
| `_requireCallerIsBorrowerOperationsOrDefaultPool` | [`v1-dev/packages/contracts/contracts/ActivePool.sol:107`](v1-dev/packages/contracts/contracts/ActivePool.sol#L107) | ETH receipt into `ActivePool` |
| `_requireCallerIsBOorTroveM` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:416`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L416) | List mutation |

### `LiquityBase` — the shared constants

[`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:16-93`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L16-L93) is inherited by `TroveManager`,
`BorrowerOperations` and `StabilityPool`.

| Constant | Value | Line | Meaning |
|---|---|---|---|
| `MCR` | 110% | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:22`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L22) | Minimum individual collateral ratio |
| `CCR` | 150% | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:25`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L25) | Below this TCR the system enters Recovery Mode |
| `LUSD_GAS_COMPENSATION` | 200e18 | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:28`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L28) | Liquidator's reward, held in `GasPool` |
| `MIN_NET_DEBT` | 1800e18 | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:31`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L31) | Minimum borrow, before gas compensation |
| `PERCENT_DIVISOR` | 200 | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:34`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L34) | 0.5% of collateral to the liquidator |
| `BORROWING_FEE_FLOOR` | 0.5% | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:36`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L36) | Base rate cannot push borrowing fee below this |

Its helpers:

| Function | Line | Returns |
|---|---|---|
| `_getCompositeDebt(_debt)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:47`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L47) | `_debt + 200e18`. The figure used for ICR. |
| `_getNetDebt(_debt)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:51`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L51) | `_debt - 200e18`. The inverse. |
| `_getCollGasCompensation(_coll)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:56`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L56) | `_coll / 200`, the liquidator's 0.5% cut |
| `getEntireSystemColl()` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:60`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L60) | `ActivePool.ETH + DefaultPool.ETH` |
| `getEntireSystemDebt()` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:67`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L67) | `ActivePool.debt + DefaultPool.debt` |
| `_getTCR(_price)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:74`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L74) | System-wide collateral ratio |
| `_checkRecoveryMode(_price)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:83`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L83) | `TCR < CCR` |
| `_requireUserAcceptsFee(...)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol:89`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L89) | Reverts if fee exceeds the caller's `_maxFeePercentage` |

**The composite-debt trick.** Every Trove carries a phantom 200 LUSD of debt
that the borrower never receives; it sits in `GasPool` and is returned when the
Trove closes. Because it is counted in the ICR, a Trove is always slightly
over-collateralised relative to what the borrower actually owes, which
guarantees a liquidator can be paid even at exactly the MCR boundary.

---

## 1.3 Math foundations

### `BaseMath`

[`v1-dev/packages/contracts/contracts/Dependencies/BaseMath.sol:5-7`](v1-dev/packages/contracts/contracts/Dependencies/BaseMath.sol#L5-L7). One constant: `DECIMAL_PRECISION = 1e18`
at [`v1-dev/packages/contracts/contracts/Dependencies/BaseMath.sol:6`](v1-dev/packages/contracts/contracts/Dependencies/BaseMath.sol#L6). Everything in Liquity is an 18-decimal
fixed-point number.

### `LiquityMath`

[`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:8-113`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L8-L113). A library, `using SafeMath for uint`.

| Symbol | Line | Value / signature |
|---|---|---|
| `DECIMAL_PRECISION` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:11`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L11) | `1e18` |
| `NICR_PRECISION` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:22`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L22) | `1e20` |
| `_min(a,b)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:24`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L24) | Smaller of two |
| `_max(a,b)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:28`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L28) | Larger of two |
| `decMul(x,y)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:39`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L39) | Rounded 18-dec multiply |
| `_decPow(base,n)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:63`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L63) | Exponentiation by squaring |
| `_getAbsoluteDifference(a,b)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:88`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L88) | `|a-b|` |
| `_computeNominalCR(coll,debt)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:92`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L92) | Price-independent ratio |
| `_computeCR(coll,debt,price)` | [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:102`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L102) | Price-dependent ratio |

#### `decMul` — rounding, not truncation

[`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:39-43`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L39-L43):

```solidity
function decMul(uint x, uint y) internal pure returns (uint decProd) {
    uint prod_xy = x.mul(y);
    decProd = prod_xy.add(DECIMAL_PRECISION / 2).div(DECIMAL_PRECISION);
}
```

Adding half the divisor before flooring is round-half-up. This matters because
`decMul` is used only inside `_decPow`, where a truncating multiply would
compound its downward bias across up to ~30 squarings and visibly distort the
base-rate decay.

#### `_decPow` — exponentiation by squaring

[`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:63-86`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L63-L86). Computes `base^n` in 18-decimal fixed point in `O(log n)` multiplies.

- **Cap.** [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:65`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L65) clamps `_minutes` to `525600000`, which is minutes in 1000
  years. Beyond that the decayed base rate is indistinguishable from zero, so
  clamping loses nothing and prevents overflow.
- **Identity.** [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:67`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L67) returns `1e18` for `n == 0`.
- **Loop.** [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:74-82`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L74-L82) is the standard square-and-multiply: while `n > 1`, square
  the base and halve the exponent, folding an extra factor into the accumulator
  on odd steps.

Two callers, both measuring time in minutes: `TroveManager._calcDecayedBaseRate`
and `CommunityIssuance._getCumulativeIssuanceFraction`.

#### `_computeNominalCR` versus `_computeCR`

[`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:92-111`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L92-L111). Both return `2**256 - 1` when debt is zero, representing an infinite
ratio, which sorts such a Trove to the front of the list.

```
NICR = coll * 1e20 / debt          (price-independent, for ordering)
ICR  = coll * price / debt         (price-dependent, for solvency)
```

The comment at [`v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol:14-21`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L14-L21) explains the choice of `1e20`: large enough that
truncation to zero needs a denominator 1e20 times the numerator, small enough
that overflow needs numerator above ~1e39 ETH.

**Why two.** `SortedTroves` must stay correctly ordered without re-sorting on
every price tick. Since ICR is NICR scaled by a single global price, the
*ordering* by NICR equals the ordering by ICR at any price. So the list is built
on NICR and never needs touching when the price moves; only solvency checks read
the price.

### `SafeMath`

[`v1-dev/packages/contracts/contracts/Dependencies/SafeMath.sol:1-161`](v1-dev/packages/contracts/contracts/Dependencies/SafeMath.sol#L1-L161). The OpenZeppelin 0.6 checked-arithmetic
library. v2 drops it entirely, having moved to Solidity 0.8.

---

## 1.4 `TroveManager`

[`v1-dev/packages/contracts/contracts/TroveManager.sol:17-1562`](v1-dev/packages/contracts/contracts/TroveManager.sol#L17-L1562). 1,562 lines, the largest contract in v1. Owns Trove storage,
liquidation, redemption, and the base-rate fee model.

`contract TroveManager is LiquityBase, Ownable, CheckContract, ITroveManager` at
[`v1-dev/packages/contracts/contracts/TroveManager.sol:17`](v1-dev/packages/contracts/contracts/TroveManager.sol#L17).

### 1.4.1 Storage

| Variable | Line | Meaning |
|---|---|---|
| `borrowerOperationsAddress` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:22`](v1-dev/packages/contracts/contracts/TroveManager.sol#L22) | The only address allowed to mutate Troves |
| `stabilityPool` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:24`](v1-dev/packages/contracts/contracts/TroveManager.sol#L24) | Liquidation offset target |
| `lusdToken`, `lqtyToken`, `lqtyStaking` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:30`](v1-dev/packages/contracts/contracts/TroveManager.sol#L30), [`v1-dev/packages/contracts/contracts/TroveManager.sol:32`](v1-dev/packages/contracts/contracts/TroveManager.sol#L32), [`v1-dev/packages/contracts/contracts/TroveManager.sol:34`](v1-dev/packages/contracts/contracts/TroveManager.sol#L34) | Token and fee-recipient wiring |
| `sortedTroves` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:37`](v1-dev/packages/contracts/contracts/TroveManager.sol#L37) | The ordered list |
| `baseRate` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:59`](v1-dev/packages/contracts/contracts/TroveManager.sol#L59) | Drives both borrowing and redemption fees |
| `lastFeeOperationTime` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:62`](v1-dev/packages/contracts/contracts/TroveManager.sol#L62) | Anchor for time decay |
| `Troves` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:81`](v1-dev/packages/contracts/contracts/TroveManager.sol#L81) | `address => Trove` |
| `totalStakes` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:83`](v1-dev/packages/contracts/contracts/TroveManager.sol#L83) | Sum of all Trove stakes |
| `totalStakesSnapshot` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:86`](v1-dev/packages/contracts/contracts/TroveManager.sol#L86) | Stakes at the last liquidation |
| `totalCollateralSnapshot` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:89`](v1-dev/packages/contracts/contracts/TroveManager.sol#L89) | Collateral at the last liquidation |
| `L_ETH`, `L_LUSDDebt` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:99`](v1-dev/packages/contracts/contracts/TroveManager.sol#L99), [`v1-dev/packages/contracts/contracts/TroveManager.sol:100`](v1-dev/packages/contracts/contracts/TroveManager.sol#L100) | Running redistribution accumulators |
| `rewardSnapshots` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:103`](v1-dev/packages/contracts/contracts/TroveManager.sol#L103) | Per-Trove snapshot of the accumulators |
| `TroveOwners` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:109`](v1-dev/packages/contracts/contracts/TroveManager.sol#L109) | Enumerable array of borrowers |
| `lastETHError_Redistribution` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:112`](v1-dev/packages/contracts/contracts/TroveManager.sol#L112) | Floor-division carry |
| `lastLUSDDebtError_Redistribution` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:113`](v1-dev/packages/contracts/contracts/TroveManager.sol#L113) | Floor-division carry |

**Constants.** `MINUTE_DECAY_FACTOR = 999037758833783000` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:46`](v1-dev/packages/contracts/contracts/TroveManager.sol#L46) gives a
12-hour half-life. `REDEMPTION_FEE_FLOOR = 0.5%` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:47`](v1-dev/packages/contracts/contracts/TroveManager.sol#L47),
`MAX_BORROWING_FEE = 5%` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:48`](v1-dev/packages/contracts/contracts/TroveManager.sol#L48), `BOOTSTRAP_PERIOD = 14 days` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:51`](v1-dev/packages/contracts/contracts/TroveManager.sol#L51),
`BETA = 2` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:57`](v1-dev/packages/contracts/contracts/TroveManager.sol#L57).

**The `Trove` struct** at [`v1-dev/packages/contracts/contracts/TroveManager.sol:73-79`](v1-dev/packages/contracts/contracts/TroveManager.sol#L73-L79):

```solidity
struct Trove {
    uint debt;
    uint coll;
    uint stake;
    Status status;
    uint128 arrayIndex;
}
```

`Status` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:64-70`](v1-dev/packages/contracts/contracts/TroveManager.sol#L64-L70) is `nonExistent, active, closedByOwner,
closedByLiquidation, closedByRedemption`. Distinguishing the three closed states
matters for front ends and for `_removeTroveOwner` bookkeeping.

### 1.4.2 Liquidation

#### `liquidate(address _borrower)` — [`v1-dev/packages/contracts/contracts/TroveManager.sol:303`](v1-dev/packages/contracts/contracts/TroveManager.sol#L303)

**External, no access control.** Anyone may liquidate anyone. This is the entire
enforcement mechanism of the protocol.

- **Checks:** `_requireTroveIsActive` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1480`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1480), reverting
  `"TroveManager: Trove does not exist or is closed"`.
- **Body:** wraps the borrower in a one-element array and delegates to
  `batchLiquidateTroves`. [`v1-dev/packages/contracts/contracts/TroveManager.sol:303-309`](v1-dev/packages/contracts/contracts/TroveManager.sol#L303-L309). There is no separate single-liquidation
  path; the batch path is the only implementation.

#### `batchLiquidateTroves(address[] _troveArray)` — [`v1-dev/packages/contracts/contracts/TroveManager.sol:643`](v1-dev/packages/contracts/contracts/TroveManager.sol#L643)

**Public, no access control.** The real entry point.

- **Checks:** array non-empty, reverting `"TroveManager: Calldata address array
  must not be empty"`.
- **Flow:** reads the price, asks the Stability Pool for
  `getMaxAmountToOffset()`, then branches on `_checkRecoveryMode` into
  `_getTotalFromBatchLiquidate_RecoveryMode` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:688`](v1-dev/packages/contracts/contracts/TroveManager.sol#L688) or
  `_getTotalsFromBatchLiquidate_NormalMode` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:747`](v1-dev/packages/contracts/contracts/TroveManager.sol#L747).
- **Settlement:** offsets against the Stability Pool, redistributes the
  remainder via `_redistributeDebtAndColl`, moves any collateral surplus to
  `CollSurplusPool`, updates system snapshots, and pays the liquidator.
- **Emits:** `Liquidation` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:212`](v1-dev/packages/contracts/contracts/TroveManager.sol#L212).

#### The offset / redistribution split — [`v1-dev/packages/contracts/contracts/TroveManager.sol:431-459`](v1-dev/packages/contracts/contracts/TroveManager.sol#L431-L459)

The heart of Liquity's liquidation. Given a Trove's debt and collateral and the
LUSD available in the Stability Pool:

```solidity
debtToOffset       = min(_debt, _LUSDInSPForOffsets);
collToSendToSP     = _coll * debtToOffset / _debt;
debtToRedistribute = _debt - debtToOffset;
collToRedistribute = _coll - collToSendToSP;
```

Collateral follows debt *pro rata*. If the pool can absorb 40% of the debt it
receives 40% of the collateral. Whatever the pool cannot absorb is redistributed
across all remaining Troves. When the pool is empty ([`v1-dev/packages/contracts/contracts/TroveManager.sol:449-455`](v1-dev/packages/contracts/contracts/TroveManager.sol#L449-L455)) everything is
redistributed.

**This is the design's central claim:** liquidation never needs an auction, an
external bidder, or a price discovery process. The Stability Pool is a
standing bid at a known discount, and redistribution is the unconditional
fallback. Contrast Aave, where liquidation depends on a third party choosing to
act; see [`LIQUITY-DEEP-DIVE.md`](LIQUITY-DEEP-DIVE.md).

#### `_liquidateNormalMode` — [`v1-dev/packages/contracts/contracts/TroveManager.sol:314`](v1-dev/packages/contracts/contracts/TroveManager.sol#L314)

Applies pending rewards, removes the stake, computes gas compensation as
`_getCollGasCompensation` (0.5%) plus the 200 LUSD from `GasPool`, splits the
remainder via `_getOffsetAndRedistributionVals`, closes the Trove with status
`closedByLiquidation`, and emits `TroveLiquidated` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:215`](v1-dev/packages/contracts/contracts/TroveManager.sol#L215).

#### `_liquidateRecoveryMode` — [`v1-dev/packages/contracts/contracts/TroveManager.sol:349`](v1-dev/packages/contracts/contracts/TroveManager.sol#L349)

Four branches by ICR:

| Condition | Behaviour |
|---|---|
| `ICR <= 100%` | Full redistribution; no offset. The Trove is underwater. |
| `100% < ICR < MCR` | Normal offset-and-redistribute. |
| `MCR <= ICR < TCR` and pool can cover | **Capped** offset via `_getCappedOffsetVals` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:467`](v1-dev/packages/contracts/contracts/TroveManager.sol#L467). Collateral sent to the pool is capped at `debt * MCR / price`, and the excess goes to `CollSurplusPool` for the borrower to reclaim. |
| otherwise | Trove is skipped. |

The capped branch is why Recovery Mode is not confiscatory: a borrower liquidated
while still above MCR keeps the collateral above the 110% line.

#### `liquidateTroves(uint _n)` — [`v1-dev/packages/contracts/contracts/TroveManager.sol:495`](v1-dev/packages/contracts/contracts/TroveManager.sol#L495)

Walks the sorted list from the riskiest end, liquidating up to `_n` Troves.
Recovery-mode variant at [`v1-dev/packages/contracts/contracts/TroveManager.sol:546`](v1-dev/packages/contracts/contracts/TroveManager.sol#L546), normal-mode at [`v1-dev/packages/contracts/contracts/TroveManager.sol:607`](v1-dev/packages/contracts/contracts/TroveManager.sol#L607). Both stop early when
the next Trove is no longer liquidatable, since the list is ordered.

### 1.4.3 Redistribution math — [`v1-dev/packages/contracts/contracts/TroveManager.sol:1203-1237`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1203-L1237)

When debt cannot be offset it is spread over every remaining Trove in proportion
to *stake*, using a running accumulator so that no per-Trove writes are needed.

```solidity
uint ETHNumerator = _coll.mul(DECIMAL_PRECISION).add(lastETHError_Redistribution);
uint LUSDDebtNumerator = _debt.mul(DECIMAL_PRECISION).add(lastLUSDDebtError_Redistribution);

uint ETHRewardPerUnitStaked = ETHNumerator.div(totalStakes);
uint LUSDDebtRewardPerUnitStaked = LUSDDebtNumerator.div(totalStakes);

lastETHError_Redistribution = ETHNumerator.sub(ETHRewardPerUnitStaked.mul(totalStakes));
lastLUSDDebtError_Redistribution = LUSDDebtNumerator.sub(LUSDDebtRewardPerUnitStaked.mul(totalStakes));

L_ETH = L_ETH.add(ETHRewardPerUnitStaked);
L_LUSDDebt = L_LUSDDebt.add(LUSDDebtRewardPerUnitStaked);
```

[`v1-dev/packages/contracts/contracts/TroveManager.sol:1218-1231`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1218-L1231). The four-step error feedback is the notable part:

1. Add the previous call's remainder into this call's numerator.
2. Divide to get the per-unit-staked rate.
3. Multiply back to reveal this call's floor-division remainder.
4. Store it for next time.

Without step 1 the truncation loss compounds, and `sum(pending rewards)` drifts
below the redistributed total, eventually breaking the accounting invariant that
`ActivePool + DefaultPool` covers all Trove debt. The comment at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1211-1216`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1211-L1216)
notes that static analysers flag the division-before-multiplication as a bug; it
is deliberate.

**Claiming.** A Trove's share is computed lazily at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1099-1110`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1099-L1110):

```
pendingETHReward = stake * (L_ETH - rewardSnapshots[borrower].ETH) / 1e18
```

`getPendingLUSDDebtReward` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1113`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1113) is the same shape.
`hasPendingRewards` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1126`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1126) is a cheap `snapshot.ETH < L_ETH` test.
`_applyPendingRewards` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1059`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1059) materialises them into the Trove struct and
moves the corresponding balances from `DefaultPool` to `ActivePool`.

**Stakes.** `_computeNewStake` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1186-1200`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1186-L1200) sets
`stake = coll * totalStakesSnapshot / totalCollateralSnapshot`, so a Trove
opened after redistributions has already had them priced in and does not
retroactively receive them.

### 1.4.4 Redemption

#### `redeemCollateral(...)` — [`v1-dev/packages/contracts/contracts/TroveManager.sol:925`](v1-dev/packages/contracts/contracts/TroveManager.sol#L925)

Exchanges LUSD for collateral at face value, always from the *lowest-ICR* Troves
first. This is the hard peg floor: whenever LUSD trades below $1, redeeming is
profitable, which burns supply and pushes the price back up.

**Parameters:** `_LUSDamount`, `_firstRedemptionHint`, `_upperPartialRedemptionHint`,
`_lowerPartialRedemptionHint`, `_partialRedemptionHintNICR`, `_maxIterations`,
`_maxFeePercentage`.

**Checks, in order:**

| Guard | Line | Revert |
|---|---|---|
| `_requireValidMaxFeePercentage` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1505`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1505) | `"Max fee percentage must be between 0.5% and 100%"` |
| `_requireAfterBootstrapPeriod` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1500`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1500) | `"TroveManager: Redemptions are not allowed during bootstrap phase"` |
| `_requireTCRoverMCR` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1496`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1496) | `"TroveManager: Cannot redeem when TCR < MCR"` |
| `_requireAmountGreaterThanZero` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1492`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1492) | `"TroveManager: Amount must be greater than zero"` |
| `_requireLUSDBalanceCoversRedemption` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1484`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1484) | `"TroveManager: Requested redemption amount must be <= user's LUSD token balance"` |

**Flow:** validates the hint via `_isValidFirstRedemptionHint` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:892`](v1-dev/packages/contracts/contracts/TroveManager.sol#L892),
falling back to walking from the list tail. Then loops calling
`_redeemCollateralFromTrove` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:816`](v1-dev/packages/contracts/contracts/TroveManager.sol#L816) until the requested amount is filled or
`_maxIterations` is exhausted. A Trove redeemed to below `MIN_NET_DEBT` is closed
outright by `_redeemCloseTrove` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:882`](v1-dev/packages/contracts/contracts/TroveManager.sol#L882), which moves its collateral to
`CollSurplusPool`.

Finally `_updateBaseRateFromRedemption` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1358`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1358) raises the base rate, the
fee is transferred to `LQTYStaking`, and `Redemption` is emitted ([`v1-dev/packages/contracts/contracts/TroveManager.sol:213`](v1-dev/packages/contracts/contracts/TroveManager.sol#L213)).

**The bootstrap period.** [`v1-dev/packages/contracts/contracts/TroveManager.sol:51`](v1-dev/packages/contracts/contracts/TroveManager.sol#L51) blocks redemption for 14 days after
deployment, protecting early borrowers from being redeemed against before the
peg has stabilised.

### 1.4.5 The base rate and fees

#### `_updateBaseRateFromRedemption` — [`v1-dev/packages/contracts/contracts/TroveManager.sol:1358-1377`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1358-L1377)

```solidity
uint decayedBaseRate = _calcDecayedBaseRate();
uint redeemedLUSDFraction = _ETHDrawn.mul(_price).div(_totalLUSDSupply);
uint newBaseRate = decayedBaseRate.add(redeemedLUSDFraction.div(BETA));
newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION);
```

Decay first, then add the redeemed fraction divided by `BETA = 2`, capped at
100%. The `assert(newBaseRate > 0)` at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1373`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1373) encodes that a redemption always
moves the rate.

#### Decay — [`v1-dev/packages/contracts/contracts/TroveManager.sol:1463-1468`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1463-L1468)

```solidity
uint minutesPassed = _minutesPassedSinceLastFeeOp();
uint decayFactor = LiquityMath._decPow(MINUTE_DECAY_FACTOR, minutesPassed);
return baseRate.mul(decayFactor).div(DECIMAL_PRECISION);
```

`MINUTE_DECAY_FACTOR^720 ≈ 0.5`, a 12-hour half-life. `_updateLastFeeOpTime` at
[`v1-dev/packages/contracts/contracts/TroveManager.sol:1454`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1454) only advances the anchor once a full minute has passed, so rapid
successive operations cannot reset the clock and stall decay.

#### Fee schedule

| Function | Line | Formula |
|---|---|---|
| `getRedemptionRate` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1379`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1379) | `min(0.5% + baseRate, 100%)` |
| `getRedemptionRateWithDecay` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1383`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1383) | Same on the decayed rate |
| `_calcRedemptionFee` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1402`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1402) | `rate * ETHDrawn / 1e18`, reverts if it would consume all collateral |
| `getBorrowingRate` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1410`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1410) | `min(0.5% + baseRate, 5%)` |
| `getBorrowingFee` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1425`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1425) | `rate * LUSDDebt / 1e18` |
| `decayBaseRateFromBorrowing` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1439`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1439) | Called by `BorrowerOperations` on every borrow |

Borrowing is capped at 5% ([`v1-dev/packages/contracts/contracts/TroveManager.sol:48`](v1-dev/packages/contracts/contracts/TroveManager.sol#L48)) while redemption is not. A borrower can be
priced out of borrowing, but a redeemer is never blocked, because redemption is
the peg mechanism and must always function.

### 1.4.6 Trove accessors and mutators

All of these are gated by `_requireCallerIsBorrowerOperations`:

| Function | Line |
|---|---|
| `setTroveStatus` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1530`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1530) |
| `increaseTroveColl` / `decreaseTroveColl` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1535`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1535) / [`v1-dev/packages/contracts/contracts/TroveManager.sol:1542`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1542) |
| `increaseTroveDebt` / `decreaseTroveDebt` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1549`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1549) / [`v1-dev/packages/contracts/contracts/TroveManager.sol:1556`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1556) |
| `addTroveOwnerToArray` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1282`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1282) |
| `applyPendingRewards` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1053`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1053) |
| `removeStake` / `updateStakeAndTotalStakes` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1156`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1156) / [`v1-dev/packages/contracts/contracts/TroveManager.sol:1168`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1168) |
| `updateTroveRewardSnapshots` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1087`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1087) |
| `closeTrove` | [`v1-dev/packages/contracts/contracts/TroveManager.sol:1239`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1239) |

Public views: `getNominalICR` [`v1-dev/packages/contracts/contracts/TroveManager.sol:1028`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1028), `getCurrentICR` [`v1-dev/packages/contracts/contracts/TroveManager.sol:1036`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1036),
`getEntireDebtAndColl` [`v1-dev/packages/contracts/contracts/TroveManager.sol:1138`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1138), `getTCR` [`v1-dev/packages/contracts/contracts/TroveManager.sol:1327`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1327),
`checkRecoveryMode` [`v1-dev/packages/contracts/contracts/TroveManager.sol:1331`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1331), `getTroveStatus/Stake/Debt/Coll`
[`v1-dev/packages/contracts/contracts/TroveManager.sol:1512`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1512)–[`v1-dev/packages/contracts/contracts/TroveManager.sol:1524`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1524).

**`_removeTroveOwner`** at [`v1-dev/packages/contracts/contracts/TroveManager.sol:1305`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1305) is the classic swap-and-pop: the last
element replaces the removed one and its `arrayIndex` is rewritten, keeping
removal O(1).

---

                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     