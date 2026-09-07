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

## 1.5 `BorrowerOperations`

[`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:16-666`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L16-L666). The only contract a borrower ever calls to mutate a Trove.
`TroveManager` holds the storage but refuses every write that does not come from
here.

`contract BorrowerOperations is LiquityBase, Ownable, CheckContract, IBorrowerOperations`.

### 1.5.1 Structs

`LocalVariables_openTrove` at [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:58-67`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L58-L67) and `LocalVariables_adjustTrove` at
[`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:40-56`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L40-L56) exist purely to dodge stack-too-deep. `ContractsCache` at [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:69-73`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L69-L73)
caches `troveManager`, `activePool` and `lusdToken` in memory so the hot path
avoids repeated `SLOAD`s. `enum BorrowerOperation { openTrove, closeTrove,
adjustTrove }` at [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:75-79`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L75-L79) tags events.

### 1.5.2 `openTrove(uint _maxFeePercentage, uint _LUSDAmount, address _upperHint, address _lowerHint)` — [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:156`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L156)

**External, payable.** Collateral arrives as `msg.value`.

| Parameter | Meaning |
|---|---|
| `_maxFeePercentage` | Slippage guard on the borrowing fee |
| `_LUSDAmount` | Net LUSD requested, before fee and gas compensation |
| `_upperHint`, `_lowerHint` | Neighbours for the `SortedTroves` insert |

**Checks, in order:**

| Guard | Line | Revert |
|---|---|---|
| `_requireValidMaxFeePercentage` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:567`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L567) | `"Max fee percentage must be between 0.5% and 100%"` |
| `_requireTroveisNotActive` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:483`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L483) | `"BorrowerOps: Trove is active"` |
| ICR check | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:535`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L535) | `"BorrowerOps: An operation that would result in ICR < MCR is not permitted"` |
| Recovery-mode ICR | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:539`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L539) | `"BorrowerOps: Operation must leave trove with ICR >= CCR"` |
| TCR check | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:547`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L547) | `"BorrowerOps: An operation that would result in TCR < CCR is not permitted"` |

**Body.** Fetches the price, decides Recovery Mode, charges the borrowing fee
via `_triggerBorrowingFee` (skipped entirely in Recovery Mode), computes
`compositeDebt = netDebt + 200e18`, derives the ICR, then:

1. `setTroveStatus(borrower, 1)`
2. `increaseTroveColl` / `increaseTroveDebt`
3. `updateTroveRewardSnapshots`
4. `updateStakeAndTotalStakes`
5. `sortedTroves.insert(borrower, NICR, upperHint, lowerHint)`
6. `addTroveOwnerToArray`
7. Move ETH into `ActivePool`, mint `_LUSDAmount` to the borrower, mint 200 LUSD to `GasPool`

**Emits** `TroveUpdated` and `TroveCreated`.

**Note the ordering:** the borrower receives LUSD only after every state write.
There is no callback and no external call to the borrower, so reentrancy has no
foothold. Compare Aave, which needs an explicit guard because aTokens can hook
transfers.

### 1.5.3 The adjust family

Five thin wrappers over one implementation:

| Function | Line | Delegates to |
|---|---|---|
| `addColl` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:213`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L213) | `_adjustTrove(msg.sender, 0, 0, false, ...)` |
| `moveETHGainToTrove` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:218`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L218) | Same, but callable only by the Stability Pool |
| `withdrawColl` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:224`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L224) | `_adjustTrove(msg.sender, _collWithdrawal, 0, false, ...)` |
| `withdrawLUSD` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:229`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L229) | `_adjustTrove(..., _LUSDAmount, true, ...)` |
| `repayLUSD` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:234`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L234) | `_adjustTrove(..., _LUSDAmount, false, ...)` |
| `adjustTrove` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:238`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L238) | Everything at once |

`moveETHGainToTrove` is gated by `_requireCallerIsStabilityPool` at [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:559`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L559),
reverting `"BorrowerOps: Caller is not Stability Pool"`. It is how a depositor
compounds an ETH gain straight back into their Trove.

#### `_adjustTrove(...)` — [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:249`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L249)

The single mutation path. Checks in order:

| Guard | Line | Revert |
|---|---|---|
| `_requireValidMaxFeePercentage` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:567`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L567) | Fee band |
| `_requireSingularCollChange` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:465`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L465) | `"BorrowerOperations: Cannot withdraw and add coll"` |
| `_requireCallerIsBorrower` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:469`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L469) | `"BorrowerOps: Caller must be the borrower for a withdrawal"` |
| `_requireNonZeroAdjustment` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:473`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L473) | `"BorrowerOps: There must be either a collateral change or a debt change"` |
| `_requireTroveisActive` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:478`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L478) | `"BorrowerOps: Trove does not exist or is closed"` |
| `_requireNonZeroDebtChange` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:487`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L487) | `"BorrowerOps: Debt increase requires non-zero debtChange"` |
| `_requireNotInRecoveryMode` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:491`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L491) | `"BorrowerOps: Operation not permitted during Recovery Mode"` |
| `_requireNoCollWithdrawal` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:495`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L495) | `"BorrowerOps: Collateral withdrawal not permitted Recovery Mode"` |
| `_requireValidLUSDRepayment` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:555`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L555) | `"BorrowerOps: Amount repaid must not be larger than the Trove's debt"` |
| `_requireSufficientLUSDBalance` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:563`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L563) | `"BorrowerOps: Caller doesnt have enough LUSD to make repayment"` |

**Recovery Mode is far stricter.** `_requireValidAdjustmentInCurrentMode` at
[`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:500`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L500) forbids collateral withdrawal and any debt increase that does not
improve ICR ([`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:543`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L543), `"BorrowerOps: Cannot decrease your Trove's ICR in
Recovery Mode"`). Normal mode only requires the result to clear MCR and keep TCR
above CCR.

**Body.** Applies pending redistribution rewards first, charges the borrowing
fee on a debt increase, computes the new ICR, re-inserts into `SortedTroves`
using `sortedTroves.reInsert`, then moves tokens through
`_moveTokensAndETHfromAdjustment` at [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:419`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L419).

### 1.5.4 `closeTrove()` — [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:321`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L321)

- **Checks:** Trove active; not in Recovery Mode ([`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:491`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L491)); the caller holds
  enough LUSD to repay `debt - 200e18`.
- **Body:** applies pending rewards, removes the stake, closes with status
  `closedByOwner`, removes from `SortedTroves`, burns the borrower's LUSD, burns
  the 200 LUSD from `GasPool`, and returns all collateral.
- The 200 LUSD gas compensation is returned here, which is why the borrower only
  needs to repay the net debt.

### 1.5.5 `claimCollateral()` — [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:356`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L356)

Pulls the caller's balance out of `CollSurplusPool`. This is the money left over
after a Recovery-Mode capped liquidation or a full redemption.

### 1.5.6 Fee and helper internals

| Function | Line | Role |
|---|---|---|
| `_triggerBorrowingFee` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:363`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L363) | Decays the base rate, computes the fee, mints it to `LQTYStaking`, calls `increaseF_LUSD` |
| `_getCollChange` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:382`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L382) | Normalises `msg.value` versus `_collWithdrawal` into `(collChange, isCollIncrease)` |
| `_updateTroveFromAdjustment` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:399`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L399) | Applies the deltas to `TroveManager` storage |
| `_moveTokensAndETHfromAdjustment` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:419`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L419) | Routes ETH and LUSD between pools and the borrower |
| `_activePoolAddColl` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:446`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L446) | Low-level ETH send, reverts `"BorrowerOps: Sending ETH to ActivePool failed"` ([`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:448`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L448)) |
| `_withdrawLUSD` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:452`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L452) | Increases `ActivePool` debt and mints |
| `_repayLUSD` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:458`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L458) | Decreases `ActivePool` debt and burns |

**Fee accrues to stakers, not to the protocol.** `_triggerBorrowingFee` mints
LUSD directly to `LQTYStaking` and calls `increaseF_LUSD`, so the fee enters the
staking accumulator in the same transaction. There is no treasury and no
governance-controlled fee switch anywhere in v1.

### 1.5.7 ICR / TCR projection helpers

| Function | Line | Purpose |
|---|---|---|
| `_getNewNominalICRFromTroveChange` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:580`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L580) | Projected NICR, for the list hint |
| `_getNewICRFromTroveChange` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:600`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L600) | Projected ICR, for the MCR check |
| `_getNewTroveAmounts` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:620`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L620) | Applies deltas without writing |
| `_getNewTCRFromTroveChange` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:641`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L641) | Projected system TCR |
| `getCompositeDebt` | [`v1-dev/packages/contracts/contracts/BorrowerOperations.sol:663`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L663) | Public wrapper over `_getCompositeDebt` |

These compute the *post-state* before committing to it, which is how the
contract enforces "an operation that would result in ICR < MCR is not permitted"
rather than discovering the violation afterwards.

---

## 1.6 `StabilityPool`

[`v1-dev/packages/contracts/contracts/StabilityPool.sol:1-993`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L1-L993). The counterparty to every liquidation, and the most mathematically
interesting contract in v1.

**The problem it solves.** N depositors share the pool. A liquidation must
decrease every depositor's LUSD proportionally and credit every depositor ETH
proportionally. Doing that with N storage writes is impossible on-chain. The
product-sum algorithm does it with O(1) writes per liquidation and O(1) reads
per depositor.

### 1.6.1 The product-sum algorithm

Two accumulators, described in the contract's own header comment at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:30-110`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L30-L110):

| Symbol | Line | Role |
|---|---|---|
| `P` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:193`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L193) | Running **product**. Each liquidation multiplies it by `(1 - lossPerUnit)`. |
| `S` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:203`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L203) | Running **sum** of ETH gained per unit of deposit. |
| `G` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:215`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L215) | Same shape as `S`, for LQTY issuance. |

A depositor snapshots `(P, S, G)` at deposit time ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:170-177`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L170-L177)):

```solidity
struct Snapshots {
    uint S;
    uint P;
    uint G;
    uint128 scale;
    uint128 epoch;
}
```

Then:

```
compoundedDeposit = initialDeposit * P_now / P_snapshot
ETHGain           = initialDeposit * (S_now - S_snapshot) / P_snapshot
```

Both are O(1). `P` decreasing multiplicatively is exactly a proportional haircut
applied to everyone at once, and dividing the `S` delta by `P_snapshot` scales
the ETH credit to the depositor's *then-current* share.

### 1.6.2 Epochs and scales, the two precision problems

**Problem one: `P` hits zero.** If a liquidation empties the pool,
`lossPerUnit = 1` and `P` would become 0, destroying every future division.
Solution at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:596-600`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L596-L600): when the pool is fully drained, increment
`currentEpoch`, reset `P` to `1e18`, and reset `S`. Deposits from a prior epoch
are worth exactly zero, which `_getCompoundedStakeFromSnapshots` detects by
comparing `epoch` snapshots ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:792-795`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L792-L795)).

**Problem two: `P` underflows toward zero.** Many partial liquidations shrink `P`
multiplicatively. Once it drops below `1e9` the fixed-point precision collapses.
Solution at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:605-617`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L605-L617): multiply `P` by `SCALE_FACTOR = 1e9` ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:195`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L195)) and
increment `currentScale`. Reads then correct for the scale difference.

`_getCompoundedStakeFromSnapshots` at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:781-812`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L781-L812) handles all three cases:

| `scaleDiff` | Treatment |
|---|---|
| `0` | `initialStake * P / snapshot_P` |
| `1` | `initialStake * P / snapshot_P / SCALE_FACTOR` |
| `>= 2` | Return `0`. The stake has shrunk by at least 1e-18. |

There is also a dust floor: a compounded stake below `initialStake / 1e9` is
truncated to zero ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:808-810`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L808-L810)), so the pool never carries unreclaimable dust.

### 1.6.3 `offset(uint _debtToOffset, uint _collToAdd)` — [`v1-dev/packages/contracts/contracts/StabilityPool.sol:514`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L514)

**Only callable by `TroveManager`** ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:940`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L940),
`"StabilityPool: Caller is not TroveManager"`).

1. `_triggerLQTYIssuance` ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:450`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L450)) mints pending LQTY and folds it into `G`.
2. `_computeRewardsPerUnitStaked` ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:531`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L531)) derives the per-unit ETH gain and
   LUSD loss.
3. `_updateRewardSumAndProduct` ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:580`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L580)) writes the new `S` and `P`, handling
   epoch and scale transitions.
4. `_moveOffsetCollAndDebt` ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:628`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L628)) burns the LUSD and pulls the ETH from
   `ActivePool`.

#### The rounding, and who it favours — [`v1-dev/packages/contracts/contracts/StabilityPool.sol:531-577`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L531-L577)

Same four-step error feedback as redistribution, plus one deliberate asymmetry:

```solidity
LUSDLossPerUnitStaked = (LUSDLossNumerator.div(_totalLUSDDeposits)).add(1);
```

[`v1-dev/packages/contracts/contracts/StabilityPool.sol:569`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L569). The `+1` makes the loss *slightly too large*. The comment at
[`v1-dev/packages/contracts/contracts/StabilityPool.sol:566-568`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L566-L568) says why: "We want 'slightly too much' LUSD loss, which ensures the
error in any given compoundedLUSDDeposit favors the Stability Pool." Rounding
against the depositor by one wei guarantees the pool can always pay out what it
claims. Rounding the other way would eventually leave it one wei short.

`assert(_debtToOffset < _totalLUSDDeposits)` at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:552`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L552) is enforced upstream by
`getMaxAmountToOffset` at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:495`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L495), which is what `batchLiquidateTroves` queries
before deciding how much to offset.

### 1.6.4 Deposit lifecycle

#### `provideToSP(uint _amount, address _frontEndTag)` — [`v1-dev/packages/contracts/contracts/StabilityPool.sol:316`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L316)

- **Checks:** `_requireNonZeroAmount`; if the depositor is new,
  `_requireFrontEndNotRegistered` and `_requireValidFrontEndTag`.
- **Body:** triggers LQTY issuance, pays out any accrued LQTY to the depositor
  and their front end, computes the compounded deposit, adds `_amount`, writes
  fresh snapshots, transfers LUSD in, and **sends any accrued ETH gain to the
  depositor**.
- **Emits:** `UserDepositChanged`, `ETHGainWithdrawn`.

#### `withdrawFromSP(uint _amount)` — [`v1-dev/packages/contracts/contracts/StabilityPool.sol:363`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L363)

- **Checks:** `_requireNoUnderCollateralizedTroves` ([`v1-dev/packages/contracts/contracts/StabilityPool.sol:957`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L957)) blocks withdrawal
  while the riskiest Trove sits below MCR. This stops depositors from fleeing
  ahead of a liquidation they can see coming.
- **Body:** mirror of `provideToSP`. Withdrawing `type(uint).max` exits fully.

#### `withdrawETHGainToTrove(address _upperHint, address _lowerHint)` — [`v1-dev/packages/contracts/contracts/StabilityPool.sol:408`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L408)

Routes the ETH gain into the caller's Trove via
`BorrowerOperations.moveETHGainToTrove` instead of to their wallet. Requires an
active Trove and a non-zero gain.

### 1.6.5 Views

| Function | Line | Returns |
|---|---|---|
| `getDepositorETHGain` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:655`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L655) | Accrued ETH |
| `_getETHGainFromSnapshots` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:666`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L666) | The `(S_now - S_snap) / P_snap` computation, scale-aware |
| `getDepositorLQTYGain` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:690`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L690) | Accrued LQTY |
| `getFrontEndLQTYGain` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:725`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L725) | Front-end share |
| `getCompoundedLUSDDeposit` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:753`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L753) | Post-haircut deposit |
| `getCompoundedFrontEndStake` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:770`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L770) | Front-end equivalent |
| `getMaxAmountToOffset` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:495`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L495) | Ceiling that preserves the `offset` assert |

### 1.6.6 Front ends

[`v1-dev/packages/contracts/contracts/StabilityPool.sol:838-870`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L838-L870). `registerFrontEnd(uint _kickbackRate)` lets a UI register once and
claim a share of LQTY rewards; the depositor's `_frontEndTag` is fixed at first
deposit and immutable afterwards. `kickbackRate` is the fraction passed back to
the depositor. This is Liquity's answer to having no marketing budget: front ends
are paid in protocol tokens for bringing deposits.

### 1.6.7 Access control

| Guard | Line |
|---|---|
| `_requireCallerIsActivePool` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:948`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L948) |
| `_requireCallerIsTroveManager` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:940`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L940) |
| `_requireCallerIsBorrowerOperations` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:944`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L944) |
| `_requireNoUnderCollateralizedTroves` | [`v1-dev/packages/contracts/contracts/StabilityPool.sol:957`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L957) |

`receive()` at [`v1-dev/packages/contracts/contracts/StabilityPool.sol:985`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L985) accepts ETH only from `ActivePool` and adds it to the
internal balance.

---

## 1.7 `SortedTroves`

[`v1-dev/packages/contracts/contracts/SortedTroves.sol:46-420`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L46-L420). A doubly-linked list of Troves ordered by descending NICR. It
exists so that liquidation and redemption can find the riskiest Troves in O(1)
instead of scanning.

### Storage

```solidity
struct Node { bool exists; address nextId; address prevId; }
struct Data { address head; address tail; uint256 maxSize; uint256 size; mapping (address => Node) nodes; }
```

[`v1-dev/packages/contracts/contracts/SortedTroves.sol:61-74`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L61-L74). `head` is the highest NICR, `tail` the lowest. Liquidation walks
from `tail`; redemption also starts at `tail`.

### Functions

| Function | Line | Notes |
|---|---|---|
| `setParams` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:80`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L80) | One-shot, `onlyOwner`, renounces afterwards |
| `insert` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:104`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L104) | External wrapper, gated to BorrowerOperations or TroveManager |
| `_insert` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:111`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L111) | Validates the hint, else finds the position |
| `remove` / `_remove` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:158`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L158) / [`v1-dev/packages/contracts/contracts/SortedTroves.sol:167`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L167) | O(1) unlink |
| `reInsert` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:211`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L211) | Remove then insert, used on every Trove adjustment |
| `contains` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:229`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L229) | |
| `isFull` / `isEmpty` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:236`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L236) / [`v1-dev/packages/contracts/contracts/SortedTroves.sol:243`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L243) | |
| `getSize` / `getMaxSize` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:250`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L250) / [`v1-dev/packages/contracts/contracts/SortedTroves.sol:257`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L257) | |
| `getFirst` / `getLast` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:264`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L264) / [`v1-dev/packages/contracts/contracts/SortedTroves.sol:271`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L271) | |
| `getNext` / `getPrev` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:279`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L279) / [`v1-dev/packages/contracts/contracts/SortedTroves.sol:287`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L287) | |
| `validInsertPosition` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:297`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L297) | Public hint check |
| `_validInsertPosition` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:301`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L301) | Confirms `prev.NICR >= NICR >= next.NICR` |
| `_descendList` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:325`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L325) | Walk down from a hint that was too high |
| `_ascendList` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:352`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L352) | Walk up from a hint that was too low |
| `_findInsertPosition` | [`v1-dev/packages/contracts/contracts/SortedTroves.sol:387`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L387) | Picks a direction and walks |

### The hint pattern

Callers pass `_prevId` and `_lowerHint` computed **off-chain**. If the hint is
still valid the insert is O(1). If the price moved between hint computation and
execution, `_findInsertPosition` walks from the hint, which is usually a short
distance. A wrong hint costs gas but never correctness, because
`_validInsertPosition` re-checks on-chain.

`HintHelpers` at [`v1-dev/packages/contracts/contracts/HintHelpers.sol:10-171`](v1-dev/packages/contracts/contracts/HintHelpers.sol#L10-L171) is the off-chain helper: 
`getApproxHint` at [`v1-dev/packages/contracts/contracts/HintHelpers.sol:56`](v1-dev/packages/contracts/contracts/HintHelpers.sol#L56) samples the list with a
pseudo-random walk to find a starting point, and
`getRedemptionHints` at [`v1-dev/packages/contracts/contracts/HintHelpers.sol:22`](v1-dev/packages/contracts/contracts/HintHelpers.sol#L22) computes the redemption entry
point plus the partial-redemption NICR.

**This is the same design tension as Uniswap V3's tick bitmap:** an on-chain
ordered structure that would be too expensive to maintain naively, made cheap by
pushing search off-chain and verifying on-chain.

---

## 1.8 The pools

Four contracts that hold funds. None contains logic beyond bookkeeping and caller
checks.

### `ActivePool` — [`v1-dev/packages/contracts/contracts/ActivePool.sol:18-130`](v1-dev/packages/contracts/contracts/ActivePool.sol#L18-L130)

Holds the ETH and tracks the LUSD debt of all **active** Troves.

| Function | Line | Caller |
|---|---|---|
| `getETH` | [`v1-dev/packages/contracts/contracts/ActivePool.sol:73`](v1-dev/packages/contracts/contracts/ActivePool.sol#L73) | anyone |
| `getLUSDDebt` | [`v1-dev/packages/contracts/contracts/ActivePool.sol:77`](v1-dev/packages/contracts/contracts/ActivePool.sol#L77) | anyone |
| `sendETH` | [`v1-dev/packages/contracts/contracts/ActivePool.sol:83`](v1-dev/packages/contracts/contracts/ActivePool.sol#L83) | BorrowerOperations, TroveManager, StabilityPool |
| `increaseLUSDDebt` | [`v1-dev/packages/contracts/contracts/ActivePool.sol:93`](v1-dev/packages/contracts/contracts/ActivePool.sol#L93) | BorrowerOperations, TroveManager |
| `decreaseLUSDDebt` | [`v1-dev/packages/contracts/contracts/ActivePool.sol:99`](v1-dev/packages/contracts/contracts/ActivePool.sol#L99) | BorrowerOperations, TroveManager, StabilityPool |

Guards at [`v1-dev/packages/contracts/contracts/ActivePool.sol:107`](v1-dev/packages/contracts/contracts/ActivePool.sol#L107), [`v1-dev/packages/contracts/contracts/ActivePool.sol:114`](v1-dev/packages/contracts/contracts/ActivePool.sol#L114), [`v1-dev/packages/contracts/contracts/ActivePool.sol:122`](v1-dev/packages/contracts/contracts/ActivePool.sol#L122). `receive()` accepts ETH only from
BorrowerOperations or DefaultPool.

### `DefaultPool` — [`v1-dev/packages/contracts/contracts/DefaultPool.sol:18-105`](v1-dev/packages/contracts/contracts/DefaultPool.sol#L18-L105)

Holds ETH and debt that has been **redistributed** but not yet claimed by the
receiving Troves. A Trove's share moves to `ActivePool` when
`_applyPendingRewards` runs.

| Function | Line | Caller |
|---|---|---|
| `getETH` / `getLUSDDebt` | [`v1-dev/packages/contracts/contracts/DefaultPool.sol:60`](v1-dev/packages/contracts/contracts/DefaultPool.sol#L60) / [`v1-dev/packages/contracts/contracts/DefaultPool.sol:64`](v1-dev/packages/contracts/contracts/DefaultPool.sol#L64) | anyone |
| `sendETHToActivePool` | [`v1-dev/packages/contracts/contracts/DefaultPool.sol:70`](v1-dev/packages/contracts/contracts/DefaultPool.sol#L70) | TroveManager only |
| `increaseLUSDDebt` / `decreaseLUSDDebt` | [`v1-dev/packages/contracts/contracts/DefaultPool.sol:81`](v1-dev/packages/contracts/contracts/DefaultPool.sol#L81) / [`v1-dev/packages/contracts/contracts/DefaultPool.sol:87`](v1-dev/packages/contracts/contracts/DefaultPool.sol#L87) | TroveManager only |

The split between Active and Default is what makes lazy redistribution work: the
system's totals stay correct without touching individual Troves.

### `CollSurplusPool` — [`v1-dev/packages/contracts/contracts/CollSurplusPool.sol:12-120`](v1-dev/packages/contracts/contracts/CollSurplusPool.sol#L12-L120)

Holds collateral owed back to borrowers after a capped Recovery-Mode liquidation
or a full redemption.

| Function | Line | Caller |
|---|---|---|
| `getETH` | [`v1-dev/packages/contracts/contracts/CollSurplusPool.sol:63`](v1-dev/packages/contracts/contracts/CollSurplusPool.sol#L63) | anyone |
| `getCollateral` | [`v1-dev/packages/contracts/contracts/CollSurplusPool.sol:67`](v1-dev/packages/contracts/contracts/CollSurplusPool.sol#L67) | anyone |
| `accountSurplus` | [`v1-dev/packages/contracts/contracts/CollSurplusPool.sol:73`](v1-dev/packages/contracts/contracts/CollSurplusPool.sol#L73) | TroveManager |
| `claimColl` | [`v1-dev/packages/contracts/contracts/CollSurplusPool.sol:82`](v1-dev/packages/contracts/contracts/CollSurplusPool.sol#L82) | BorrowerOperations |

### `GasPool` — [`v1-dev/packages/contracts/contracts/GasPool.sol:16-20`](v1-dev/packages/contracts/contracts/GasPool.sol#L16-L20)

Four lines of code and no functions. It holds the 200 LUSD gas compensation for
every open Trove. `LUSDToken` mints to it on open and burns from it on close.
Having a dedicated address rather than an internal counter means the LUSD
`totalSupply` always equals real circulating supply plus reserves, with no
special-casing.

---

