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