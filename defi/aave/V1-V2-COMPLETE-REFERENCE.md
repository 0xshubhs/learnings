# Aave v1 & v2 — Complete Contract & Function Reference

A mechanical, file-by-file, function-by-function reference for the two Aave
generations cloned in this folder:

| Version | Path | Solidity | .sol files | Contract LOC |
|---|---|---|---|---|
| **v1** (Jan 2020) | `aave/v1-aave-protocol/contracts/` | `^0.5.0` | 73 | 7,356 |
| **v2** (Dec 2020) | `aave/v2-protocol/contracts/` | `0.6.12` | 121 | 15,170 |

Every `path:line` below was verified with `grep -n` against these exact files.
**Every citation is written as a full path from `aave/`** so v1 and v2 can never
be confused.

**Companion documents.** `aave/AAVE-V1-V2-DEEP-DIVE.md` explains *why* these
designs look the way they do — the architecture story, the rate models, the
rebasing aToken, the migration narrative, with end-to-end traces. This file is
the opposite: it assumes you want the exhaustive surface, one entry per
function. For v3 and v4 see `aave/AAVE-DEEP-DIVE.md`,
`aave/V3-PROTOCOL-COMPLETE-REFERENCE.md`, `aave/AAVE-V4-DEEP-DIVE.md` and
`aave/V4-COMPLETE-REFERENCE.md`.

---

## Table of contents

- [Part 0 — File inventories](#part-0--file-inventories)
  - [0.1 v1 file inventory (73 files)](#01-v1-file-inventory-73-files)
  - [0.2 v2 file inventory (121 files)](#02-v2-file-inventory-121-files)
- [Part 1 — Aave v1](#part-1--aave-v1)
  - [1.1 Architecture and the delegatecall storage contract](#11-architecture-and-the-delegatecall-storage-contract)
  - [1.2 `CoreLibrary`](#12-corelibrary)
  - [1.3 `WadRayMath` (v1)](#13-wadraymath-v1)
  - [1.4 `LendingPool`](#14-lendingpool)
  - [1.5 `LendingPoolCore`](#15-lendingpoolcore)
  - [1.6 `LendingPoolDataProvider`](#16-lendingpooldataprovider)
  - [1.7 `LendingPoolLiquidationManager`](#17-lendingpoolliquidationmanager)
  - [1.8 `DefaultReserveInterestRateStrategy` (v1)](#18-defaultreserveinterestratestrategy-v1)
  - [1.9 `AToken` (v1) — the rebasing token with interest redirection](#19-atoken-v1--the-rebasing-token-with-interest-redirection)
  - [1.10 `LendingPoolConfigurator` (v1)](#110-lendingpoolconfigurator-v1)
  - [1.11 Configuration, fees, flashloan, misc, mocks](#111-configuration-fees-flashloan-misc-mocks)
  - [1.12 v1 revert-string table](#112-v1-revert-string-table)
  - [1.13 v1 events reference](#113-v1-events-reference)
  - [1.14 v1 storage layouts](#114-v1-storage-layouts)
  - [1.15 v1 ABI / selector tables](#115-v1-abi--selector-tables)
  - [1.16 v1 use cases](#116-v1-use-cases)
- [Part 2 — Aave v2](#part-2--aave-v2)
  - [2.1 Architecture](#21-architecture)
  - [2.2 `DataTypes` and `LendingPoolStorage`](#22-datatypes-and-lendingpoolstorage)
  - [2.3 Math libraries](#23-math-libraries)
  - [2.4 `ReserveConfiguration` — the bitmap](#24-reserveconfiguration--the-bitmap)
  - [2.5 `UserConfiguration` — 2 bits per reserve](#25-userconfiguration--2-bits-per-reserve)
  - [2.6 `ReserveLogic`](#26-reservelogic)
  - [2.7 `GenericLogic`](#27-genericlogic)
  - [2.8 `ValidationLogic`](#28-validationlogic)
  - [2.9 `Helpers`](#29-helpers)
  - [2.10 `LendingPool`](#210-lendingpool)
  - [2.11 `LendingPoolCollateralManager`](#211-lendingpoolcollateralmanager)
  - [2.12 `DefaultReserveInterestRateStrategy` (v2)](#212-defaultreserveinterestratestrategy-v2)
  - [2.13 Tokenization](#213-tokenization)
  - [2.14 `LendingPoolConfigurator` (v2)](#214-lendingpoolconfigurator-v2)
  - [2.15 Configuration and upgradeability](#215-configuration-and-upgradeability)
  - [2.16 `misc/` — oracle, gateway, data providers](#216-misc--oracle-gateway-data-providers)
  - [2.17 `adapters/` — flash-loan-powered position management](#217-adapters--flash-loan-powered-position-management)
  - [2.18 `flashloan/`, `deployments/`, `dependencies/`, `mocks/`](#218-flashloan-deployments-dependencies-mocks)
  - [2.19 The complete `Errors.sol` table](#219-the-complete-errorssol-table)
  - [2.20 v2 events reference](#220-v2-events-reference)
  - [2.21 v2 storage layouts](#221-v2-storage-layouts)
  - [2.22 v2 ABI / selector tables](#222-v2-abi--selector-tables)
  - [2.23 v2 use cases](#223-v2-use-cases)
- [Part 3 — v1 → v2 migration table](#part-3--v1--v2-migration-table)

---

# Part 0 — File inventories

Nothing in either repository is skipped. Files whose content is a vendored
dependency, a test mock, or a one-line interface get a short entry; everything
that carries protocol logic gets a full section later.

## 0.1 v1 file inventory (73 files)

### Core protocol (`aave/v1-aave-protocol/contracts/lendingpool/`)

| File | Lines | Purpose | Section |
|---|---:|---|---|
| `LendingPool.sol` | 1007 | User-facing entry point. Holds no funds; validates and forwards to `LendingPoolCore`. | [1.4](#14-lendingpool) |
| `LendingPoolCore.sol` | 1775 | **Holds every reserve's funds** and all reserve/user state. The largest contract in v1. | [1.5](#15-lendingpoolcore) |
| `LendingPoolDataProvider.sol` | 475 | Read-only aggregation: global account data, health factor, collateral checks. | [1.6](#16-lendingpooldataprovider) |
| `LendingPoolLiquidationManager.sol` | 355 | Liquidation logic, invoked by `LendingPool` via `delegatecall`. | [1.7](#17-lendingpoolliquidationmanager) |
| `LendingPoolConfigurator.sol` | 449 | Admin surface for listing and configuring reserves. | [1.10](#110-lendingpoolconfigurator-v1) |
| `DefaultReserveInterestRateStrategy.sol` | 199 | Kinked rate curve plus the weighted overall borrow rate. | [1.8](#18-defaultreserveinterestratestrategy-v1) |

### Libraries (`aave/v1-aave-protocol/contracts/libraries/`)

| File | Lines | Purpose | Section |
|---|---:|---|---|
| `CoreLibrary.sol` | 439 | `ReserveData` / `UserReserveData` structs plus index and rate math. | [1.2](#12-corelibrary) |
| `WadRayMath.sol` | 85 | Wad (1e18) and ray (1e27) fixed-point arithmetic, including `rayPow`. | [1.3](#13-wadraymath-v1) |
| `EthAddressLib.sol` | 11 | Returns the `0xEeee…EEeE` pseudo-address used to mean native ETH. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/Proxy.sol` | 71 | Abstract delegatecall fallback. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/BaseUpgradeabilityProxy.sol` | 64 | Implementation slot storage plus `_upgradeTo`. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/UpgradeabilityProxy.sol` | 27 | Constructor-initialised upgradeable proxy. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/BaseAdminUpgradeabilityProxy.sol` | 121 | Adds an admin able to upgrade, with the `ifAdmin` routing. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/AdminUpgradeabilityProxy.sol` | 24 | Concrete admin proxy. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/InitializableUpgradeabilityProxy.sol` | 28 | Proxy initialised after deployment rather than in the constructor. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/InitializableAdminUpgradeabilityProxy.sol` | 27 | The proxy Aave actually deploys for every component. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/Initializable.sol` | 62 | Single-shot `initializer` modifier. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `openzeppelin-upgradeability/VersionedInitializable.sol` | 70 | Revision-numbered initializer allowing re-initialisation on upgrade. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |

### Tokenization, configuration, fees, flashloan, misc

| File | Lines | Purpose | Section |
|---|---:|---|---|
| `tokenization/AToken.sol` | 674 | Rebasing interest-bearing token with the interest-redirection feature. | [1.9](#19-atoken-v1--the-rebasing-token-with-interest-redirection) |
| `configuration/LendingPoolAddressesProvider.sol` | 238 | Registry of every component address; deploys and upgrades their proxies. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `configuration/LendingPoolParametersProvider.sol` | 53 | Three global parameters: max stable-rate loan %, rebalance delta, flash-loan fees. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `configuration/AddressStorage.sol` | 14 | `bytes32 => address` key-value store backing the provider. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `configuration/UintStorage.sol` | 14 | `bytes32 => uint256` key-value store backing the parameters provider. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `fees/FeeProvider.sol` | 51 | Computes the loan origination fee. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `fees/TokenDistributor.sol` | 162 | Splits collected fees between receivers, burning the LEND share. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `flashloan/base/FlashLoanReceiverBase.sol` | 51 | Base class for flash-loan receivers; repayment helper. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `flashloan/interfaces/IFlashLoanReceiver.sol` | 12 | Declares `executeOperation(address,uint256,uint256,bytes)`. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `misc/ChainlinkProxyPriceProvider.sol` | 108 | Chainlink aggregation with a fallback oracle; prices denominated in ETH. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `misc/WalletBalanceProvider.sol` | 76 | Batch balance reads for front-ends. | [1.11](#111-configuration-fees-flashloan-misc-mocks) |
| `misc/IERC20DetailedBytes.sol` | 7 | ERC20 variant whose `symbol()` returns `bytes32` (for MKR-style tokens). | [1.11](#111-configuration-fees-flashloan-misc-mocks) |

### Interfaces (`aave/v1-aave-protocol/contracts/interfaces/`)

| File | Lines | Declares |
|---|---:|---|
| `ILendingPoolAddressesProvider.sol` | 43 | Every getter/setter of the address registry. |
| `IReserveInterestRateStrategy.sol` | 29 | `calculateInterestRates`, plus base-rate getters. |
| `IKyberNetworkProxyInterface.sol` | 21 | Kyber swap interface (unused by the core flow). |
| `IPriceOracle.sol` | 17 | `getAssetPrice` / `setAssetPrice` (mock-oriented). |
| `ILendingRateOracle.sol` | 18 | `getMarketBorrowRate` — the off-chain stable-rate anchor. |
| `IFeeProvider.sol` | 11 | `calculateLoanOriginationFee`, `getLoanOriginationFeePercentage`. |
| `IPriceOracleGetter.sol` | 11 | `getAssetPrice(address)`. |
| `IChainlinkAggregator.sol` | 11 | `latestAnswer` and its events. |

### Mocks and test helpers (35 files)

All under `aave/v1-aave-protocol/contracts/mocks/`. They carry no protocol logic
and exist only for the test suite:

- `flashloan/MockFlashLoanReceiver.sol` (50) — a receiver that can be told to fail, used to prove the flash-loan balance check reverts.
- `oracle/CLAggregators/MockAggregatorBase.sol` (15) plus 14 per-asset subclasses (`MockAggregatorBAT/DAI/KNC/LEND/LINK/MANA/MKR/REP/SUSD/TUSD/USDC/USDT/WBTC/ZRX.sol`, 6 lines each) — hardcoded Chainlink answers.
- `oracle/GenericOracleI.sol` (19), `oracle/LendingRateOracle.sol` (26), `oracle/PriceOracle.sol` (30) — settable oracles for tests.
- `tokens/MintableERC20.sol` (19) plus 13 per-asset subclasses (`MockBAT/DAI/KNC/LEND/LINK/MANA/MKR/REP/SUSD/TUSD/USDC/USDT/WBTC/ZRX.sol`, 11–12 lines each) — freely mintable test tokens with per-asset decimals.
- `upgradeability/MockLendingPoolCore.sol` (46) — a `LendingPoolCore` with a bumped revision, used to test that `VersionedInitializable` permits exactly one re-initialisation per revision.

## 0.2 v2 file inventory (121 files)

### Core protocol (`aave/v2-protocol/contracts/protocol/`)

| File | Lines | Purpose | Section |
|---|---:|---|---|
| `lendingpool/LendingPool.sol` | 946 | The single entry point. Holds no funds and no reserve math; delegates to libraries. | [2.10](#210-lendingpool) |
| `lendingpool/LendingPoolStorage.sol` | 32 | The storage layout `LendingPool` and `LendingPoolCollateralManager` must share. | [2.2](#22-datatypes-and-lendingpoolstorage) |
| `lendingpool/LendingPoolCollateralManager.sol` | 317 | Liquidation logic, `delegatecall`ed from `LendingPool`. | [2.11](#211-lendingpoolcollateralmanager) |
| `lendingpool/LendingPoolConfigurator.sol` | 487 | Admin surface: list reserves, deploy token proxies, set risk parameters. | [2.14](#214-lendingpoolconfigurator-v2) |
| `lendingpool/DefaultReserveInterestRateStrategy.sol` | 260 | Kinked rate curve; applies the reserve factor to the supply rate. | [2.12](#212-defaultreserveinterestratestrategy-v2) |
| `libraries/logic/ReserveLogic.sol` | 373 | Index accrual, treasury minting, rate refresh. | [2.6](#26-reservelogic) |
| `libraries/logic/GenericLogic.sol` | 275 | Health factor, account aggregation, collateral withdrawal checks. | [2.7](#27-genericlogic) |
| `libraries/logic/ValidationLogic.sol` | 469 | Every precondition for every user action. | [2.8](#28-validationlogic) |
| `libraries/configuration/ReserveConfiguration.sol` | 366 | The packed reserve configuration bitmap. | [2.4](#24-reserveconfiguration--the-bitmap) |
| `libraries/configuration/UserConfiguration.sol` | 111 | Two bits per reserve: borrowing, collateral. | [2.5](#25-userconfiguration--2-bits-per-reserve) |
| `libraries/math/WadRayMath.sol` | 135 | Wad/ray arithmetic with half-rounding. | [2.3](#23-math-libraries) |
| `libraries/math/PercentageMath.sol` | 54 | Basis-point arithmetic. | [2.3](#23-math-libraries) |
| `libraries/math/MathUtils.sol` | 84 | Linear interest and the binomial compounded-interest approximation. | [2.3](#23-math-libraries) |
| `libraries/types/DataTypes.sol` | 49 | `ReserveData`, the two configuration maps, `InterestRateMode`. | [2.2](#22-datatypes-and-lendingpoolstorage) |
| `libraries/helpers/Errors.sol` | 119 | All 80 numeric error codes. | [2.19](#219-the-complete-errorssol-table) |
| `libraries/helpers/Helpers.sol` | 39 | `getUserCurrentDebt` in storage and memory flavours. | [2.9](#29-helpers) |
| `libraries/aave-upgradeability/VersionedInitializable.sol` | 77 | Revision-gated initializer. | [2.15](#215-configuration-and-upgradeability) |
| `libraries/aave-upgradeability/BaseImmutableAdminUpgradeabilityProxy.sol` | 80 | Proxy whose admin is an immutable, saving an SLOAD per call. | [2.15](#215-configuration-and-upgradeability) |
| `libraries/aave-upgradeability/InitializableImmutableAdminUpgradeabilityProxy.sol` | 23 | The proxy used for aTokens and debt tokens. | [2.15](#215-configuration-and-upgradeability) |
| `configuration/LendingPoolAddressesProvider.sol` | 215 | Per-market registry; owns every proxy. | [2.15](#215-configuration-and-upgradeability) |
| `configuration/LendingPoolAddressesProviderRegistry.sol` | 89 | Registry of markets (each market is one addresses provider). | [2.15](#215-configuration-and-upgradeability) |

### Tokenization (`aave/v2-protocol/contracts/protocol/tokenization/`)

| File | Lines | Purpose | Section |
|---|---:|---|---|
| `AToken.sol` | 406 | Interest-bearing collateral token; **holds the reserve's underlying**. | [2.13](#213-tokenization) |
| `StableDebtToken.sol` | 435 | Non-transferable stable-rate debt with weighted-average rate bookkeeping. | [2.13](#213-tokenization) |
| `VariableDebtToken.sol` | 209 | Non-transferable variable-rate debt, scaled by the borrow index. | [2.13](#213-tokenization) |
| `IncentivizedERC20.sol` | 255 | ERC20 base that pings the incentives controller on every balance change. | [2.13](#213-tokenization) |
| `base/DebtTokenBase.sol` | 137 | Credit delegation allowances; disables all ERC20 transfer paths. | [2.13](#213-tokenization) |
| `DelegationAwareAToken.sol` | 30 | aToken variant that can delegate the underlying's voting power. | [2.13](#213-tokenization) |

### `misc/` (18 files)

| File | Lines | Purpose |
|---|---:|---|
| `AaveOracle.sol` | 127 | Chainlink sources plus fallback oracle; `getAssetPrice` in the base currency. |
| `WETHGateway.sol` | 189 | Wraps/unwraps ETH around deposit, withdraw, repay and borrow. |
| `AaveProtocolDataProvider.sol` | 180 | Canonical read API for reserve and user data. |
| `UiPoolDataProvider.sol` | 399 | Front-end aggregation (original). |
| `UiPoolDataProviderV2.sol` | 224 | Front-end aggregation (v2 markets). |
| `UiPoolDataProviderV2V3.sol` | 241 | Front-end aggregation compatible with both v2 and v3 markets. |
| `UiIncentiveDataProviderV2.sol` | 287 | Incentives aggregation for v2 markets. |
| `UiIncentiveDataProviderV2V3.sol` | 397 | Incentives aggregation for v2 and v3 markets. |
| `WalletBalanceProvider.sol` | 111 | Batch balance reads. |
| `interfaces/IAaveOracle.sol` | 24 | Oracle interface. |
| `interfaces/IERC20DetailedBytes.sol` | 11 | `bytes32` symbol variant. |
| `interfaces/IUiPoolDataProvider.sol` | 110 | Structs and signatures for the UI provider. |
| `interfaces/IUiPoolDataProviderV2.sol` | 81 | Same, v2 flavour. |
| `interfaces/IUiPoolDataProviderV3.sol` | 111 | Same, v3 flavour. |
| `interfaces/IUiIncentiveDataProviderV2.sol` | 57 | Incentives structs, v2. |
| `interfaces/IUiIncentiveDataProviderV3.sol` | 74 | Incentives structs, v3. |
| `interfaces/IWETH.sol` | 16 | `deposit`/`withdraw`/`approve`. |
| `interfaces/IWETHGateway.sol` | 30 | Gateway interface. |
| `interfaces/IUniswapV2Router01.sol` | 161 | Router surface used by the adapters. |
| `interfaces/IUniswapV2Router02.sol` | 51 | Router02 additions. |

### `adapters/` (8 files)

| File | Lines | Purpose | Section |
|---|---:|---|---|
| `BaseUniswapAdapter.sol` | 566 | Shared swap, pricing and aToken-pull logic for all Uniswap adapters. | [2.17](#217-adapters--flash-loan-powered-position-management) |
| `UniswapLiquiditySwapAdapter.sol` | 283 | Swap one collateral for another, optionally inside a flash loan. | [2.17](#217-adapters--flash-loan-powered-position-management) |
| `UniswapRepayAdapter.sol` | 266 | Repay debt using collateral. | [2.17](#217-adapters--flash-loan-powered-position-management) |
| `FlashLiquidationAdapter.sol` | 184 | Liquidate with no capital, funded by a flash loan. | [2.17](#217-adapters--flash-loan-powered-position-management) |
| `BaseParaSwapAdapter.sol` | 122 | ParaSwap equivalent of the Uniswap base. | [2.17](#217-adapters--flash-loan-powered-position-management) |
| `BaseParaSwapSellAdapter.sol` | 109 | Exact-in ParaSwap sell helper. | [2.17](#217-adapters--flash-loan-powered-position-management) |
| `ParaSwapLiquiditySwapAdapter.sol` | 210 | Collateral swap routed through ParaSwap. | [2.17](#217-adapters--flash-loan-powered-position-management) |
| `interfaces/IBaseUniswapAdapter.sol` | 90 | `PermitSignature`, `AmountCalc` and the adapter surface. | [2.17](#217-adapters--flash-loan-powered-position-management) |

### `interfaces/` (25 files)

`ILendingPool.sol` (410) is the full pool ABI including every event.
`IAaveIncentivesController.sol` (148) declares `handleAction` and the claim
surface. `IAToken.sol` (107), `IStableDebtToken.sol` (133),
`IVariableDebtToken.sol` (62), `IScaledBalanceToken.sol` (26),
`ICreditDelegationToken.sol` (28), `IInitializableAToken.sol` (55) and
`IInitializableDebtToken.sol` (51) describe the token layer.
`ILendingPoolAddressesProvider.sol` (60),
`ILendingPoolAddressesProviderRegistry.sol` (26),
`ILendingPoolConfigurator.sol` (179) and
`ILendingPoolCollateralManager.sol` (60) cover configuration.
`IPriceOracle.sol` (17), `IPriceOracleGetter.sol` (16),
`ILendingRateOracle.sol` (19), `IChainlinkAggregator.sol` (18) and
`IReserveInterestRateStrategy.sol` (47) cover pricing and rates.
`IERC20WithPermit.sol` (16), `IDelegationToken.sol` (11),
`IExchangeAdapter.sol` (23), `IUniswapExchange.sol` (21),
`IUniswapV2Router02.sol` (30), `IParaSwapAugustus.sol` (7) and
`IParaSwapAugustusRegistry.sol` (7) cover integrations.

### `flashloan/`, `deployments/`, `dependencies/`, `mocks/`

| File | Lines | Purpose |
|---|---:|---|
| `flashloan/base/FlashLoanReceiverBase.sol` | 22 | Stores `ADDRESSES_PROVIDER` and `LENDING_POOL`. |
| `flashloan/interfaces/IFlashLoanReceiver.sol` | 25 | Multi-asset `executeOperation(address[],uint256[],uint256[],address,bytes)`. |
| `deployments/ATokensAndRatesHelper.sol` | 86 | Batch-deploys tokens and rate strategies during market setup. |
| `deployments/StableAndVariableTokensHelper.sol` | 47 | Batch-deploys the two debt token implementations. |
| `deployments/StringLib.sol` | 8 | `concat` for building token names. |
| `dependencies/openzeppelin/contracts/*` | 9 files, 936 | Vendored `ERC20`, `IERC20`, `IERC20Detailed`, `SafeERC20`, `SafeMath`, `Address`, `Context`, `Ownable`, `ReentrancyGuard`. |
| `dependencies/openzeppelin/upgradeability/*` | 8 files, 465 | Vendored proxy set, mirroring v1's. |
| `mocks/dependencies/weth/WETH9.sol` | 758 | The canonical WETH9 source, for tests. |
| `mocks/flashloan/MockFlashLoanReceiver.sol` | 84 | Configurable-failure receiver. |
| `mocks/attacks/SefldestructTransfer.sol` | 8 | Force-sends ETH via `selfdestruct` to test balance assumptions. |
| `mocks/oracle/*` | 6 files, 124 | Settable price and lending-rate oracles, aggregator mocks. |
| `mocks/swap/*` | 4 files, 199 | Mock Uniswap router and ParaSwap Augustus, registry and transfer proxy. |
| `mocks/tokens/*` | 3 files, 74 | `MintableERC20`, `MintableDelegationERC20`, `WETH9Mocked`. |
| `mocks/upgradeability/*` | 3 files, 32 | Revision-bumped `MockAToken`, `MockStableDebtToken`, `MockVariableDebtToken`. |

---

# Part 1 — Aave v1

## 1.1 Architecture and the delegatecall storage contract

```
                            ┌──────────────────────────────────┐
                            │  LendingPoolAddressesProvider    │
                            │  bytes32 => address registry,    │
                            │  owns every component's proxy    │
                            └───────────────┬──────────────────┘
                                            │ getX()
   user ──deposit/borrow/repay/…──►  ┌──────┴───────┐
                                     │ LendingPool  │  logic + validation, holds NOTHING
                                     └──┬────┬───┬──┘
                     updateStateOn*()   │    │   │  delegatecall("liquidationCall(...)")
                     transferTo*()      │    │   └────────────► LendingPoolLiquidationManager
                                        │    │                   (must share LendingPool's
                                        │    │                    storage prefix — see below)
                                        │    │ calculateUserGlobalData()
                                        │    └──────────────────► LendingPoolDataProvider
                                        ▼                              │ getAssetPrice()
                              ┌──────────────────┐                     ▼
                              │ LendingPoolCore  │◄──────── ChainlinkProxyPriceProvider
                              │  **HOLDS ALL     │
                              │    FUNDS**       │ calculateInterestRates()
                              │  reserves[]      │────────► DefaultReserveInterestRateStrategy
                              │  usersReserveData│                     │ getMarketBorrowRate()
                              └────────┬─────────┘                     ▼
                                       │ mintOnDeposit / burnOnLiquidation   LendingRateOracle
                                       ▼
                                    AToken  ──redeem()──► LendingPool.redeemUnderlying()
```

Two structural facts define v1 and both were reversed in v2:

1. **`LendingPoolCore` custodies every asset.** `transferToReserve` pulls
   underlying into the Core; `transferToUser` pays out of it
   (`aave/v1-aave-protocol/contracts/lendingpool/LendingPoolCore.sol:397`,
   `:472`). aTokens hold nothing.
2. **`LendingPool` is a thin validator.** It reads via
   `LendingPoolDataProvider`, mutates via `LendingPoolCore.updateStateOn*`, and
   moves value via `LendingPoolCore.transferTo*`.

### Why the `delegatecall` into `LendingPoolLiquidationManager` is safe

`LendingPool.liquidationCall`
(`aave/v1-aave-protocol/contracts/lendingpool/LendingPool.sol:805`) does not
call the manager — it `delegatecall`s it, so the manager executes against
`LendingPool`'s storage. That only works because the two contracts declare an
identical storage prefix, with identical inheritance order:

```solidity
// LendingPool.sol:27-36
contract LendingPool is ReentrancyGuard, VersionedInitializable {
    LendingPoolAddressesProvider public addressesProvider;   // slot n+0
    LendingPoolCore public core;                             // slot n+1
    LendingPoolDataProvider public dataProvider;             // slot n+2
    LendingPoolParametersProvider public parametersProvider; // slot n+3
    IFeeProvider feeProvider;                                // slot n+4
```

```solidity
// LendingPoolLiquidationManager.sol:23-33
contract LendingPoolLiquidationManager is ReentrancyGuard, VersionedInitializable {
    LendingPoolAddressesProvider public addressesProvider;   // slot n+0
    LendingPoolCore core;                                    // slot n+1
    LendingPoolDataProvider dataProvider;                    // slot n+2
    LendingPoolParametersProvider parametersProvider;        // slot n+3
    IFeeProvider feeProvider;                                // slot n+4
    address ethereumAddress;                                 // slot n+5  (extra, harmless)
```

The manager's variables are never written, only read, so the trailing extra slot
is inert. Note `LendingPoolLiquidationManager.getRevision()` returns `0`
(`:111-113`) precisely because it is never initialised as a proxy itself; it only
exists to be delegated into.

## 1.2 `CoreLibrary`

`aave/v1-aave-protocol/contracts/libraries/CoreLibrary.sol` — 439 lines. Defines
the two state structs and every piece of index/rate math. `using CoreLibrary for
CoreLibrary.ReserveData` is applied in `LendingPoolCore.sol:29-30`.

### `enum InterestRateMode` — `:15`

`{NONE, STABLE, VARIABLE}` — so `1` means stable and `2` means variable. Callers
pass a raw `uint256` and it is cast at `LendingPool.sol:410`.

### `struct UserReserveData` — `:19-31`

| Field | Type | Meaning |
|---|---|---|
| `principalBorrowBalance` | `uint256` | Debt as of the user's last interaction, in token units. **Not** scaled by an index. |
| `lastVariableBorrowCumulativeIndex` | `uint256` (ray) | The reserve's variable index snapshot when the user last acted. Zero for stable borrowers. |
| `originationFee` | `uint256` | Accumulated unpaid origination fees. |
| `stableBorrowRate` | `uint256` (ray) | The rate locked in at borrow time. Zero for variable borrowers. |
| `lastUpdateTimestamp` | `uint40` | When the user last acted, used for stable-rate compounding. |
| `useAsCollateral` | `bool` | Whether this deposit backs borrows. |

The v1 signature is that **debt is per-user principal plus a per-user index or
rate**, not a scaled balance. `stableBorrowRate > 0` is the discriminator for
which mode a user is in (`getUserCurrentBorrowRateMode`,
`LendingPoolCore.sol:926`).

### `struct ReserveData` — `:33-79`

| Field | Type | Meaning |
|---|---|---|
| `lastLiquidityCumulativeIndex` | `uint256` (ray) | Supply index; grows **linearly**. |
| `currentLiquidityRate` | `uint256` (ray) | Current supply APR. |
| `totalBorrowsStable` | `uint256` | Stable-rate principal outstanding. |
| `totalBorrowsVariable` | `uint256` | Variable-rate principal outstanding. |
| `currentVariableBorrowRate` | `uint256` (ray) | Current variable APR. |
| `currentStableBorrowRate` | `uint256` (ray) | Rate a *new* stable borrower would lock in. |
| `currentAverageStableBorrowRate` | `uint256` (ray) | Weighted average across all existing stable loans. |
| `lastVariableBorrowCumulativeIndex` | `uint256` (ray) | Variable borrow index; **compounds**. |
| `baseLTVasCollateral` | `uint256` | LTV in whole percent (0–100), not bps. |
| `liquidationThreshold` | `uint256` | Threshold in whole percent. |
| `liquidationBonus` | `uint256` | Bonus in whole percent (e.g. `105` = 5% bonus). |
| `decimals` | `uint256` | Underlying decimals. |
| `aTokenAddress` | `address` | Overlying token. |
| `interestRateStrategyAddress` | `address` | Rate model. |
| `lastUpdateTimestamp` | `uint40` | Last index update. |
| `borrowingEnabled` / `usageAsCollateralEnabled` / `isStableBorrowRateEnabled` / `isActive` / `isFreezed` | `bool` | Flags, each a full storage slot — v2 packs all of these into one word. |

Everything is a full `uint256`: a `ReserveData` costs roughly 20 storage slots.
This is the single biggest reason v1 was gas-expensive, and directly motivated
v2's `ReserveConfigurationMap` bitmap ([2.4](#24-reserveconfiguration--the-bitmap)).

### `getNormalizedIncome(ReserveData storage) internal view returns (uint256)` — `:89`

- **Purpose.** Current supply index including interest accrued since the last write.
- **Returns.** `calculateLinearInterest(currentLiquidityRate, lastUpdateTimestamp) × lastLiquidityCumulativeIndex`, in ray.
- **Callers.** `LendingPoolCore.getReserveNormalizedIncome` (`:621`), which the aToken calls on every balance read (`AToken.sol:466`, `:531`).
- **Gotcha.** A pure view — it never writes the index, so an aToken balance can grow between two calls with no transaction in between.

### `updateCumulativeIndexes(ReserveData storage)` — `:111`

- **Purpose.** Advance both indexes to `block.timestamp`.
- **Checks.** `if (totalBorrows > 0)` — with no debt, no interest accrues and both indexes are left untouched.
- **State writes.** `lastLiquidityCumulativeIndex` via linear interest, `lastVariableBorrowCumulativeIndex` via compounded interest.
- **Gotcha.** It does **not** write `lastUpdateTimestamp`; that happens in `LendingPoolCore.updateReserveInterestRatesAndTimestampInternal` (`:1703`). Every mutator therefore calls `updateCumulativeIndexes()` first and the rate/timestamp refresh last, and the order matters: reversing them would accrue interest over a zero interval.

```solidity
// CoreLibrary.sol:111-131
function updateCumulativeIndexes(ReserveData storage _self) internal {
    uint256 totalBorrows = getTotalBorrows(_self);
    if (totalBorrows > 0) {
        uint256 cumulatedLiquidityInterest = calculateLinearInterest(
            _self.currentLiquidityRate, _self.lastUpdateTimestamp);
        _self.lastLiquidityCumulativeIndex = cumulatedLiquidityInterest.rayMul(
            _self.lastLiquidityCumulativeIndex);
        uint256 cumulatedVariableBorrowInterest = calculateCompoundedInterest(
            _self.currentVariableBorrowRate, _self.lastUpdateTimestamp);
        _self.lastVariableBorrowCumulativeIndex = cumulatedVariableBorrowInterest.rayMul(
            _self.lastVariableBorrowCumulativeIndex);
    }
}
```

**Suppliers earn linear, borrowers pay compound.** The difference is retained by
the protocol as a rounding-level surplus. v2 keeps exactly this asymmetry
([2.6](#26-reservelogic)).

### `cumulateToLiquidityIndex(ReserveData storage, uint256 _totalLiquidity, uint256 _amount)` — `:142`

- **Purpose.** Distribute a one-off income (the flash-loan fee) to all suppliers at once.
- **Math.** `index *= (1 + amount/totalLiquidity)`.
- **Callers.** `LendingPoolCore.updateStateOnFlashLoan` (`:150`).
- **Gotcha.** `_totalLiquidity` must be the pre-fee total, which is why `LendingPool.flashLoan` snapshots `availableLiquidityBefore` and passes it down (`LendingPool.sol:851`, `LendingPoolCore.sol:161`).

### `init(ReserveData storage, address _aTokenAddress, uint256 _decimals, address _interestRateStrategyAddress) external` — `:163`

- **Checks.** `require(_self.aTokenAddress == address(0), "Reserve has already been initialized")`.
- **State writes.** Sets both indexes to `1e27` if zero, stores the aToken, decimals and strategy, sets `isActive = true`, `isFreezed = false`.
- **Note.** Declared `external` on a library, so it is a real `DELEGATECALL` to a deployed library rather than inlined — the same linking arrangement v2 uses for its logic libraries.

### `enableBorrowing(ReserveData storage, bool) external` — `:194` / `disableBorrowing(ReserveData storage) external` — `:206`

`enableBorrowing` reverts with `"Reserve is already enabled"` if borrowing is on;
it also sets `isStableBorrowRateEnabled`. `disableBorrowing` is unconditional.

### `enableAsCollateral(ReserveData storage, uint256 _baseLTVasCollateral, uint256 _liquidationThreshold, uint256 _liquidationBonus) external` — `:217` / `disableAsCollateral` — `:242`

Reverts with `"Reserve is already enabled as collateral"` when already enabled.
Also initialises `lastLiquidityCumulativeIndex` to ray if it is still zero, which
covers a reserve enabled as collateral before being enabled for borrowing.

### `getCompoundedBorrowBalance(UserReserveData storage, ReserveData storage) internal view returns (uint256)` — `:254`

This is the heart of v1 debt accounting.

- **Returns `0`** when `principalBorrowBalance == 0`.
- **Stable branch** (`_self.stableBorrowRate > 0`): compound the user's own fixed rate from the user's own `lastUpdateTimestamp`.
- **Variable branch**: `compoundedInterest(reserveRate, reserveTimestamp) × reserveIndex / userIndex` — the classic index-ratio, but computed live rather than from a stored index.

```solidity
// CoreLibrary.sol:275-286
} else {
    //variable interest
    cumulatedInterest = calculateCompoundedInterest(
        _reserve.currentVariableBorrowRate,
        _reserve.lastUpdateTimestamp
    )
        .rayMul(_reserve.lastVariableBorrowCumulativeIndex)
        .rayDiv(_self.lastVariableBorrowCumulativeIndex);
}
compoundedBalance = principalBorrowBalanceRay.rayMul(cumulatedInterest).rayToWad();
```

- **The 1 wei rule** (`:288-296`): if rounding produced no growth but time has passed, return `principal + 1 wei`. The comment says it plainly — *"no interest cumulation because of the rounding - we add 1 wei as symbolic cumulated interest to avoid interest free loans."* Without it, dust-sized borrows would be free.

### `increaseTotalBorrowsStableAndUpdateAverageRate(ReserveData storage, uint256 _amount, uint256 _rate) internal` — `:303`

Weighted average update:
`avg' = (amount·rate + prevTotal·avg) / (prevTotal + amount)`.

### `decreaseTotalBorrowsStableAndUpdateAverageRate(ReserveData storage, uint256 _amount, uint256 _rate) internal` — `:331`

- **Checks.** `require(_reserve.totalBorrowsStable >= _amount, "Invalid amount to decrease")`, then `require(weightedPreviousTotalBorrows >= weightedLastBorrow, "The amounts to subtract don't match")`.
- **Edge case.** If `totalBorrowsStable` reaches zero the average rate is zeroed and the function returns early.
- **Gotcha.** The second `require` is a real failure mode: accumulated rounding can make the removed weight exceed the stored aggregate. v2 replaced the revert with a silent clamp to zero (`StableDebtToken.sol:220-222`).

### `increaseTotalBorrowsVariable` — `:370` / `decreaseTotalBorrowsVariable` — `:379`

Plain add/subtract. The decrease reverts with *"The amount that is being
subtracted from the variable total borrows is incorrect"*.

### `calculateLinearInterest(uint256 _rate, uint40 _lastUpdateTimestamp) internal view returns (uint256)` — `:394`

`1 + rate × Δt / SECONDS_PER_YEAR`, all in ray. `SECONDS_PER_YEAR = 365 days`
(`:17`).

### `calculateCompoundedInterest(uint256 _rate, uint40 _lastUpdateTimestamp) internal view returns (uint256)` — `:413`

```solidity
uint256 ratePerSecond = _rate.div(SECONDS_PER_YEAR);
return ratePerSecond.add(WadRayMath.ray()).rayPow(timeDifference);
```

**True exponentiation** via `rayPow` — an O(log n) square-and-multiply
(`WadRayMath.sol:72`). This is exact but expensive, and it is exactly what v2
replaced with a three-term binomial approximation to save gas
([2.3](#23-math-libraries)).

### `getTotalBorrows(ReserveData storage) internal view returns (uint256)` — `:431`

`totalBorrowsStable + totalBorrowsVariable`.

## 1.3 `WadRayMath` (v1)

`aave/v1-aave-protocol/contracts/libraries/WadRayMath.sol` — 85 lines.

| Function | Line | Behaviour |
|---|---:|---|
| `ray()` | `:22` | `1e27` |
| `wad()` | `:25` | `1e18` |
| `halfRay()` | `:29` | `0.5e27` |
| `halfWad()` | `:33` | `0.5e18` |
| `wadMul(a,b)` | `:37` | `(a·b + halfWAD) / WAD` — rounds half up |
| `wadDiv(a,b)` | `:41` | `(a·WAD + b/2) / b` |
| `rayMul(a,b)` | `:47` | `(a·b + halfRAY) / RAY` |
| `rayDiv(a,b)` | `:51` | `(a·RAY + b/2) / b` |
| `rayToWad(a)` | `:57` | `(a + 0.5e9) / 1e9` |
| `wadToRay(a)` | `:63` | `a · 1e9` |
| `rayPow(x,n)` | `:72` | Square-and-multiply exponentiation in ray |

Constants at `:14-20`: `WAD = 1e18`, `RAY = 1e27`, `WAD_RAY_RATIO = 1e9`.
Everything rounds half-up, so v1 has no systematic protocol-favouring rounding
direction — a design v3 later reversed deliberately with its `TokenMath` helpers.

---

## 1.4 `LendingPool`

`aave/v1-aave-protocol/contracts/lendingpool/LendingPool.sol` — 1007 lines.
`contract LendingPool is ReentrancyGuard, VersionedInitializable` (`:27`).

### State, constants, modifiers

| Item | Line | Notes |
|---|---:|---|
| `addressesProvider` | `:32` | `public` |
| `core` | `:33` | `public LendingPoolCore` |
| `dataProvider` | `:34` | `public LendingPoolDataProvider` |
| `parametersProvider` | `:35` | `public LendingPoolParametersProvider` |
| `feeProvider` | `:36` | internal `IFeeProvider` |
| `UINT_MAX_VALUE` | `:269` | `uint256(-1)`, the "repay everything" sentinel |
| `LENDINGPOOL_REVISION` | `:271` | `0x3` |
| `onlyOverlyingAToken(address)` | `:232` | `msg.sender` must be the reserve's aToken. Revert: *"The caller of this function can only be the aToken contract of this reserve"* |
| `onlyActiveReserve(address)` | `:244` | delegates to `requireReserveActiveInternal` (`:990`) |
| `onlyUnfreezedReserve(address)` | `:254` | delegates to `requireReserveNotFreezedInternal` (`:997`) |
| `onlyAmountGreaterThanZero(uint256)` | `:264` | delegates to `requireAmountGreaterThanZeroInternal` (`:1004`) |

The three modifiers delegate to internal functions purely to keep bytecode below
the 24 KB limit — a modifier body is inlined at every use site, an internal
function call is not.

### `getRevision() internal pure returns (uint256)` — `:273`
Returns `LENDINGPOOL_REVISION` (`0x3`), consumed by `VersionedInitializable`.

### `initialize(LendingPoolAddressesProvider _addressesProvider) public initializer` — `:282`
- **State writes.** Caches `core`, `dataProvider`, `parametersProvider`, `feeProvider` from the provider.
- **Access.** `initializer` — once per revision.
- **Gotcha.** These are cached, not read live. Changing the Core address in the provider requires re-initialising the pool at a new revision.

### `deposit(address _reserve, uint256 _amount, uint16 _referralCode) external payable` — `:299`
Modifiers: `nonReentrant`, `onlyActiveReserve`, `onlyUnfreezedReserve`, `onlyAmountGreaterThanZero`.

1. Resolve `aToken = core.getReserveATokenAddress(_reserve)`.
2. `isFirstDeposit = aToken.balanceOf(msg.sender) == 0`.
3. `core.updateStateOnDeposit(...)` — accrues indexes, refreshes rates, and if first deposit flips the collateral flag on.
4. `aToken.mintOnDeposit(msg.sender, _amount)`.
5. `core.transferToReserve.value(msg.value)(_reserve, msg.sender, _amount)` — pulls the underlying (or forwards ETH).
6. `emit Deposit(_reserve, msg.sender, _amount, _referralCode, block.timestamp)` (`:46`).

- **Gotcha.** Minting happens *before* the transfer in. Safe only because `mintOnDeposit` is `onlyLendingPool` and the transfer reverts on failure, unwinding everything.
- **Gotcha.** Deposits are always credited to `msg.sender`; there is no `onBehalfOf`. v2 added one.

### `redeemUnderlying(address _reserve, address payable _user, uint256 _amount, uint256 _aTokenBalanceAfterRedeem) external` — `:331`
Modifiers: `nonReentrant`, `onlyOverlyingAToken`, `onlyActiveReserve`, `onlyAmountGreaterThanZero`.

- **Access.** **Only the aToken may call this.** Users call `AToken.redeem` (`:218`), which burns and then calls back here.
- **Checks.** `require(currentAvailableLiquidity >= _amount, "There is not enough liquidity available to redeem")`.
- **State.** `core.updateStateOnRedeem(...)`; clears the collateral flag when `_aTokenBalanceAfterRedeem == 0`.
- **Transfer.** `core.transferToUser`.
- **Event.** `RedeemUnderlying` (`:61`).

### `borrow(address _reserve, uint256 _amount, uint256 _interestRateMode, uint16 _referralCode) external` — `:388`
Modifiers: `nonReentrant`, `onlyActiveReserve`, `onlyUnfreezedReserve`, `onlyAmountGreaterThanZero`. Uses `BorrowLocalVars` (`:362`) to dodge stack-too-deep.

Checks in order:

| # | Check | Revert string | Line |
|---|---|---|---:|
| 1 | `core.isReserveBorrowingEnabled` | `"Reserve is not enabled for borrowing"` | `:404` |
| 2 | mode is `STABLE` or `VARIABLE` | `"Invalid interest rate mode selected"` | `:409` |
| 3 | `availableLiquidity >= _amount` | `"There is not enough liquidity available in the reserve"` | `:420` |
| 4 | `userCollateralBalanceETH > 0` | `"The collateral balance is 0"` | `:434` |
| 5 | `!healthFactorBelowThreshold` | `"The borrower can already be liquidated so he cannot borrow more"` | `:438` |
| 6 | `borrowFee > 0` | `"The amount to borrow is too small"` | `:444` |
| 7 | `amountOfCollateralNeededETH <= userCollateralBalanceETH` | `"There is not enough collateral to cover a new borrow"` | `:457` |
| 8 | stable only: `core.isUserAllowedToBorrowAtStable` | `"User cannot borrow the selected amount with a stable rate"` | `:473` |
| 9 | stable only: `_amount <= maxLoanSizeStable` | `"User is trying to borrow too much liquidity at a stable rate"` | `:483` |

Then `core.updateStateOnBorrow(...)` returns `(finalUserBorrowRate,
borrowBalanceIncrease)`, `core.transferToUser` pays out, and `Borrow` (`:80`) is
emitted with nine fields.

- **Gotcha.** Check 6 means a borrow so small that `amount × 0.0025` rounds to zero is rejected outright.
- **Gotcha.** Check 9 reads `parametersProvider.getMaxStableRateBorrowSizePercent()` and applies it to *available* liquidity, not total.

### `repay(address _reserve, uint256 _amount, address payable _onBehalfOf) external payable` — `:533`
Modifiers: `nonReentrant`, `onlyActiveReserve`, `onlyAmountGreaterThanZero`. Uses `RepayLocalVars` (`:522`).

1. Read `(principal, compounded, balanceIncrease)` and `originationFee`.
2. `require(compoundedBorrowBalance > 0, "The user does not have any borrow pending")`.
3. `require(_amount != UINT_MAX_VALUE || msg.sender == _onBehalfOf, "To repay on behalf of an user an explicit amount to repay is needed.")`.
4. `paybackAmount = compounded + originationFee`, capped by `_amount`.
5. `require(!isETH || msg.value >= paybackAmount, "Invalid msg.value sent for the repayment")`.
6. **Fee-only branch** (`:572`): when `paybackAmount <= originationFee`, the whole payment goes to the `TokenDistributor` via `transferToFeeCollectionAddress`, the `Repay` event reports `0` principal, and the function **returns early**.
7. Otherwise `updateStateOnRepay`, then the fee transfer (if any), then `transferToReserve` for the principal.
8. `emit Repay(...)` (`:102`).

- **Gotcha.** Fees are paid **before** principal. A partial repayment always clears the origination fee first.
- **Gotcha.** In the ETH path, `msg.value.sub(vars.originationFee)` is forwarded and `transferToReserve` refunds the excess (`LendingPoolCore.sol:486`).

### `swapBorrowRateMode(address _reserve) external` — `:648`
Modifiers: `nonReentrant`, `onlyActiveReserve`, `onlyUnfreezedReserve`.

- **Checks.** `require(compoundedBorrowBalance > 0, "User does not have a borrow in progress on this reserve")`; when switching variable→stable, `require(core.isUserAllowedToBorrowAtStable(...), "User cannot borrow the selected amount at stable")`.
- **Gotcha.** The stable check applies **only** in the variable→stable direction. Going stable→variable is unconditional.
- **Event.** `Swap` (`:121`).

### `rebalanceStableBorrowRate(address _reserve, address _user) external` — `:709`
Modifiers: `nonReentrant`, `onlyActiveReserve`. **Permissionless** — anyone may rebalance anyone.

- **Checks.** Non-zero balance; `require(core.getUserCurrentBorrowRateMode(...) == STABLE, "The user borrow is variable and cannot be rebalanced")`.
- **Trigger condition** (`:742-745`): rebalance if `userRate < liquidityRate` (the user could earn more by re-depositing than they pay — a self-arbitrage) **or** `userRate > reserveStableRate × (1 + rebalanceDownRateDelta)` (the user is overpaying).
- **Fallthrough.** `revert("Interest rate rebalance conditions were not met")` (`:764`).

### `setUserUseReserveAsCollateral(address _reserve, bool _useAsCollateral) external` — `:772`
- **Checks.** `require(underlyingBalance > 0, "User does not have any liquidity deposited")`; `require(dataProvider.balanceDecreaseAllowed(...), "User deposit is already being used as collateral")`.
- **Gotcha.** The second revert string is misleading — the real meaning is *"disabling this collateral would make you liquidatable"*. Note it is evaluated even when enabling.
- **Events.** `ReserveUsedAsCollateralEnabled` (`:135`) / `Disabled` (`:142`).

### `liquidationCall(address _collateral, address _reserve, address _user, uint256 _purchaseAmount, bool _receiveAToken) external payable` — `:805`
Modifiers: `nonReentrant`, `onlyActiveReserve(_reserve)`, `onlyActiveReserve(_collateral)`.

- **Mechanism.** `delegatecall` into the liquidation manager, `require(success, "Liquidation call failed")`, then decode `(uint256 returnCode, string returnMessage)` and, if non-zero, `revert("Liquidation failed: " + returnMessage)`.
- **Gotcha.** The manager returns error *codes* rather than reverting, so the pool can prefix the message. Every failure therefore costs a full execution.

### `flashLoan(address _receiver, address _reserve, uint256 _amount, bytes memory _params) public` — `:843`
Modifiers: `nonReentrant`, `onlyActiveReserve`, `onlyAmountGreaterThanZero`.

1. Snapshot `availableLiquidityBefore` by reading the Core's balance directly (the comment at `:850` says this avoids a Core call to save gas).
2. `require(availableLiquidityBefore >= _amount, "There is not enough liquidity available to borrow")`.
3. Fees from `parametersProvider.getFlashLoanFeesInBips()`: `amountFee = amount × totalFeeBips / 10000`, `protocolFee = amountFee × protocolFeeBips / 10000`.
4. `require(amountFee > 0 && protocolFee > 0, "The requested amount is too small for a flashLoan.")`.
5. `core.transferToUser` → `receiver.executeOperation(_reserve, _amount, amountFee, _params)`.
6. `require(availableLiquidityAfter == availableLiquidityBefore.add(amountFee), "The actual balance of the protocol is inconsistent")` — note **equality**, not `>=`.
7. `core.updateStateOnFlashLoan(...)` splits `amountFee - protocolFee` to suppliers and `protocolFee` to the distributor.
8. `emit FlashLoan` (`:169`).

- **Gotcha.** v1 flash loans are **single-asset** and cannot end as debt. v2 added both ([2.10](#210-lendingpool)).
- **Gotcha.** The strict equality in step 6 means over-repaying reverts.

### View passthroughs

| Function | Line | Returns |
|---|---:|---|
| `getReserveConfigurationData` | `:908` | LTV, threshold, bonus, strategy, flags |
| `getReserveData` | `:925` | Liquidity, borrows, rates, indexes, aToken, timestamp |
| `getUserAccountData` | `:947` | Aggregated collateral/debt/fees/LTV/threshold/HF |
| `getUserReserveData` | `:964` | Per-reserve user position |
| `getReserves` | `:983` | The reserve list |

### Internal helpers

- `requireReserveActiveInternal` — `:990` — *"Action requires an active reserve"*
- `requireReserveNotFreezedInternal` — `:997` — *"Action requires an unfreezed reserve"*
- `requireAmountGreaterThanZeroInternal` — `:1004` — *"Amount must be greater than 0"*

## 1.5 `LendingPoolCore`

`aave/v1-aave-protocol/contracts/lendingpool/LendingPoolCore.sol` — 1775 lines,
the largest contract in either version. `contract LendingPoolCore is
VersionedInitializable` (`:26`).

### State

| Item | Line | Notes |
|---|---:|---|
| `lendingPoolAddress` | `:52` | `public address` — cached from the provider |
| `addressesProvider` | — | inherited slot, set in `initialize` |
| `reserves` | `:75` | `mapping(address => CoreLibrary.ReserveData) internal` |
| `usersReserveData` | `:76` | `mapping(address => mapping(address => CoreLibrary.UserReserveData)) internal` — **user first, then reserve** |
| `reservesList` | `:78` | `address[] public` |
| `CORE_REVISION` | `:80` | `0x6` |

Note the index order of `usersReserveData`: `usersReserveData[_user][_reserve]`.
Getting it backwards is the classic v1 integration bug.

### Modifiers

- `onlyLendingPool` — `:59` — *"The caller must be a lending pool contract"*
- `onlyLendingPoolConfigurator` — `:67` — *"The caller must be a lending pool configurator contract"*

### `initialize(LendingPoolAddressesProvider) public initializer` — `:94`
Stores the provider and calls `refreshConfigInternal()` (`:1759`), which caches
`lendingPoolAddress`.

### `function() external payable` — `:385`
```solidity
require(msg.sender.isContract(), "Only contracts can send ether to the Lending pool core");
```
- **Purpose.** Accept ETH repayments and flash-loan returns while rejecting accidental EOA sends.
- **Gotcha.** `isContract` is code-size based, so a contract in its constructor cannot repay ETH here.

### State mutators — all `onlyLendingPool`

Every one follows the same shape: accrue indexes → mutate → refresh rates and
timestamp.

#### `updateStateOnDeposit(address _reserve, address _user, uint256 _amount, bool _isFirstDeposit) external` — `:107`
`updateCumulativeIndexes()` → `updateReserveInterestRatesAndTimestampInternal(_reserve, _amount, 0)` → if first deposit, `setUserUseReserveAsCollateral(..., true)`.

#### `updateStateOnRedeem(address _reserve, address _user, uint256 _amountRedeemed, bool _userRedeemedEverything) external` — `:129`
Mirror image; clears the collateral flag on a full redeem.

#### `updateStateOnFlashLoan(address _reserve, uint256 _availableLiquidityBefore, uint256 _income, uint256 _protocolFee) external` — `:150`
1. `transferFlashLoanProtocolFeeInternal` (`:1744`) sends the protocol cut to the `TokenDistributor`.
2. `updateCumulativeIndexes()`.
3. `cumulateToLiquidityIndex(totalLiquidityBefore, _income)` — the supplier cut, distributed by bumping the index.
4. `updateReserveInterestRatesAndTimestampInternal(_reserve, _income, 0)`.

#### `updateStateOnBorrow(...) external returns (uint256, uint256)` — `:181`
Reads the user's balances, calls `updateReserveStateOnBorrowInternal` (`:1281`)
and `updateUserStateOnBorrowInternal` (`:1314`), refreshes rates, and returns
`(getUserCurrentBorrowRate(...), balanceIncrease)`.

`updateUserStateOnBorrowInternal` is where the mode discriminator is written:

```solidity
// LendingPoolCore.sol:1327-1339
if (_rateMode == CoreLibrary.InterestRateMode.STABLE) {
    user.stableBorrowRate = reserve.currentStableBorrowRate;
    user.lastVariableBorrowCumulativeIndex = 0;
} else if (_rateMode == CoreLibrary.InterestRateMode.VARIABLE) {
    user.stableBorrowRate = 0;
    user.lastVariableBorrowCumulativeIndex = reserve.lastVariableBorrowCumulativeIndex;
} else {
    revert("Invalid borrow rate mode");
}
user.principalBorrowBalance = user.principalBorrowBalance.add(_amountBorrowed).add(_balanceIncrease);
user.originationFee = user.originationFee.add(_fee);
```

The accrued interest is **capitalised into the principal**. A v1 user therefore
has exactly one debt position per reserve, and switching modes rewrites it.

#### `updateStateOnRepay(...) external` — `:227`
`updateReserveStateOnRepayInternal` (`:1357`) + `updateUserStateOnRepayInternal` (`:1396`) + rate refresh with `_paybackAmountMinusFees` as liquidity added.

#### `updateStateOnSwapRate(...) external returns (InterestRateMode, uint256)` — `:262`
`updateReserveStateOnSwapRateInternal` (`:1434`) moves the principal between the
stable and variable totals; `updateUserStateOnSwapRateInternal` (`:1478`) flips
the user's discriminator and returns the new mode.

#### `updateStateOnLiquidation(...) external` — `:302`
Nine parameters. Calls `updatePrincipalReserveStateOnLiquidationInternal`
(`:1517`), `updateCollateralReserveStateOnLiquidationInternal` (`:1561`),
`updateUserStateOnLiquidationInternal` (`:1577`), then refreshes rates on the
principal reserve and — **only when `!_liquidatorReceivesAToken`** — on the
collateral reserve too, since aTokens changing hands does not move underlying.

#### `updateStateOnRebalance(address _reserve, address _user, uint256 _balanceIncrease) external returns (uint256)` — `:351`
Returns the user's new `stableBorrowRate`.

#### `setUserUseReserveAsCollateral(address _reserve, address _user, bool _useAsCollateral) public onlyLendingPool` — `:370`
The only `public` mutator, because `updateStateOnDeposit` and
`updateStateOnRedeem` call it internally.

### Value movement — all `onlyLendingPool`

| Function | Line | Behaviour |
|---|---:|---|
| `transferToUser(address,address payable,uint256)` | `:397` | `safeTransfer` for ERC20; for ETH a `call.value(...).gas(50000)` with `require(result, "Transfer of ETH failed")` |
| `transferToFeeCollectionAddress(address,address,uint256,address) payable` | `:418` | Pushes fees to the distributor. ERC20 path requires `msg.value == 0`; ETH path requires `msg.value >= _amount` |
| `liquidateFee(address,uint256,address) payable` | `:446` | Same, but from the Core's own balance. Requires `msg.value == 0` — *"Fee liquidation does not require any transfer of value"* |
| `transferToReserve(address,address payable,uint256) payable` | `:473` | Pulls funds in. ERC20 requires `msg.value == 0`; ETH requires `msg.value >= _amount` and **refunds the excess** |

**The 50,000 gas stipend** on every ETH send is the notable constraint: a
contract with an expensive `receive()` cannot be a v1 ETH recipient.

### Read surface

`getUserBasicReserveData` `:505` · `isUserAllowedToBorrowAtStable` `:535` ·
`getUserUnderlyingAssetBalance` `:558` ·
`getReserveInterestRateStrategyAddress` `:573` · `getReserveATokenAddress`
`:584` · `getReserveAvailableLiquidity` `:594` · `getReserveTotalLiquidity`
`:610` · `getReserveNormalizedIncome` `:621` · `getReserveTotalBorrows` `:631` ·
`getReserveTotalBorrowsStable` `:640` · `getReserveTotalBorrowsVariable` `:651` ·
`getReserveLiquidationThreshold` `:662` · `getReserveLiquidationBonus` `:673` ·
`getReserveCurrentVariableBorrowRate` `:684` ·
`getReserveCurrentStableBorrowRate` `:701` ·
`getReserveCurrentAverageStableBorrowRate` `:719` ·
`getReserveCurrentLiquidityRate` `:733` · `getReserveLiquidityCumulativeIndex`
`:743` · `getReserveVariableBorrowsCumulativeIndex` `:753` ·
`getReserveConfiguration` `:772` · `getReserveDecimals` `:796` ·
`isReserveBorrowingEnabled` `:806` · `isReserveUsageAsCollateralEnabled` `:817` ·
`getReserveIsStableBorrowRateEnabled` `:827` · `getReserveIsActive` `:837` ·
`getReserveIsFreezed` `:848` · `getReserveLastUpdate` `:859` ·
`getReserveUtilizationRate` `:870` · `getReserves` `:887` ·
`isUserUseReserveAsCollateralEnabled` `:896` · `getUserOriginationFee` `:910` ·
`getUserCurrentBorrowRateMode` `:926` · `getUserCurrentBorrowRate` `:949` ·
`getUserCurrentStableBorrowRate` `:972` · `getUserBorrowBalances` `:988` ·
`getUserVariableBorrowCumulativeIndex` `:1013` · `getUserLastUpdate` `:1029`.

Two worth calling out:

- **`getReserveCurrentStableBorrowRate` (`:701`)** falls back to the
  `LendingRateOracle` market rate when the stored rate is zero, so an unused
  reserve still quotes a sane stable rate.
- **`getUserBorrowBalances` (`:988`)** returns
  `(principal, compounded, compounded - principal)`. That third value,
  `balanceIncrease`, is threaded through every mutator as the interest to
  capitalise.

### Admin surface — all `onlyLendingPoolConfigurator`

`refreshConfiguration` `:1041` · `initReserve` `:1052` ·
`removeLastAddedReserve` `:1069` · `setReserveInterestRateStrategyAddress`
`:1100` · `enableBorrowingOnReserve` `:1113` · `disableBorrowingOnReserve`
`:1125` · `enableReserveAsCollateral` `:1133` · `disableReserveAsCollateral`
`:1150` · `enableReserveStableBorrowRate` `:1158` ·
`disableReserveStableBorrowRate` `:1167` · `activateReserve` `:1176` ·
`deactivateReserve` `:1191` · `freezeReserve` `:1201` · `unfreezeReserve`
`:1210` · `setReserveBaseLTVasCollateral` `:1220` ·
`setReserveLiquidationThreshold` `:1233` · `setReserveLiquidationBonus` `:1246` ·
`setReserveDecimals` `:1259`.

`deactivateReserve` (`:1191`) requires the reserve's total liquidity to be zero —
a reserve with users cannot be switched off, only frozen.

### `updateReserveInterestRatesAndTimestampInternal(address _reserve, uint256 _liquidityAdded, uint256 _liquidityTaken) internal` — `:1703`

Calls the strategy with `(availableLiquidity + added − taken, totalBorrowsStable,
totalBorrowsVariable, currentAverageStableBorrowRate)`, stores the three returned
rates, writes `lastUpdateTimestamp`, and emits `ReserveUpdated` (`:43`). Every
mutator ends here — this is the single point at which a v1 reserve's clock
advances.

---

## 1.6 `LendingPoolDataProvider`

`aave/v1-aave-protocol/contracts/lendingpool/LendingPoolDataProvider.sol` — 475
lines. `contract LendingPoolDataProvider is VersionedInitializable` (`:21`).
Pure reads; it never writes state.

| Item | Line |
|---|---:|
| `HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1e18` | `:32` |
| `DATA_PROVIDER_REVISION = 0x1` | `:34` |
| `getRevision()` | `:36` |
| `initialize(LendingPoolAddressesProvider)` | `:40` |
| `struct UserGlobalDataLocalVars` | `:48` |
| `struct balanceDecreaseAllowedLocalVars` | `:158` |

### `calculateUserGlobalData(address _user) public view returns (uint256 totalLiquidityBalanceETH, uint256 totalCollateralBalanceETH, uint256 totalBorrowBalanceETH, uint256 totalFeesETH, uint256 currentLtv, uint256 currentLiquidationThreshold, uint256 healthFactor, bool healthFactorBelowThreshold)` — `:70`

The v1 health-factor engine. It loops over **every** listed reserve:

```solidity
// LendingPoolDataProvider.sol:86-101 (excerpt)
address[] memory reserves = core.getReserves();
for (uint256 i = 0; i < reserves.length; i++) {
    vars.currentReserve = reserves[i];
    ( vars.compoundedLiquidityBalance, vars.compoundedBorrowBalance,
      vars.originationFee, vars.userUsesReserveAsCollateral
    ) = core.getUserBasicReserveData(vars.currentReserve, _user);
    if (vars.compoundedLiquidityBalance == 0 && vars.compoundedBorrowBalance == 0) continue;
```

- Collateral counts only when `usageAsCollateralEnabled && userUsesReserveAsCollateral`.
- `currentLtv` and `currentLiquidationThreshold` are accumulated as
  ETH-value-weighted sums and divided by total collateral at the end, producing
  weighted averages.
- **Origination fees are part of the debt** for health purposes — the v1-only
  `totalFeesETH` term.
- **Gotcha.** The loop is unbounded over the reserve list and makes an oracle
  call per reserve. This is exactly why v2 introduced the `UserConfigurationMap`
  bitmap so it could skip untouched reserves in O(1) per reserve.

### `balanceDecreaseAllowed(address _reserve, address _user, uint256 _amount) external view returns (bool)` — `:180`

Answers *"may this user lose `_amount` of this collateral?"*. Returns `true`
immediately when the reserve is not collateral-enabled or the user is not using
it. Otherwise it recomputes the post-decrease collateral and liquidation
threshold and returns whether the resulting health factor stays above `1e18`.

### `calculateCollateralNeededInETH(address _reserve, uint256 _amount, uint256 _fee, uint256 _userCurrentBorrowBalanceTH, uint256 _userCurrentFeesETH, uint256 _userCurrentLtv) external view returns (uint256)` — `:258`

```
collateralNeeded = (existingDebtETH + existingFeesETH + (amount + fee)·price/1eDecimals) × 100 / ltv
```

The `× 100 / ltv` is because v1 LTV is whole percent. Note the parameter name
typo `_userCurrentBorrowBalanceTH` — preserved here so a `grep` finds it.

### `calculateAvailableBorrowsETHInternal(uint256 collateralBalanceETH, uint256 borrowBalanceETH, uint256 totalFeesETH, uint256 ltv) internal view returns (uint256)` — `:296`

`collateral × ltv / 100`, minus existing debt and fees, minus the origination fee
on the remainder. Returns `0` when already at the limit.

### `calculateHealthFactorFromBalancesInternal(uint256 collateralBalanceETH, uint256 borrowBalanceETH, uint256 totalFeesETH, uint256 liquidationThreshold) internal pure returns (uint256)` — `:322`

```solidity
if (borrowBalanceETH == 0) return uint256(-1);
return (collateralBalanceETH.mul(liquidationThreshold).div(100))
         .wadDiv(borrowBalanceETH.add(totalFeesETH));
```

No debt means `type(uint256).max`. Fees sit in the denominator.

### Remaining views

`getHealthFactorLiquidationThreshold()` `:339` · `getReserveConfigurationData`
`:346` · `getReserveData` `:371` · `getUserAccountData` `:405` ·
`getUserReserveData` `:438`.

## 1.7 `LendingPoolLiquidationManager`

`aave/v1-aave-protocol/contracts/lendingpool/LendingPoolLiquidationManager.sol`
— 355 lines. Executed **only** via `delegatecall` from `LendingPool`
([1.1](#11-architecture-and-the-delegatecall-storage-contract)).

| Item | Line | Notes |
|---|---:|---|
| `LIQUIDATION_CLOSE_FACTOR_PERCENT = 50` | `:35` | Half the debt per call, hardcoded |
| `enum LiquidationErrors` | `:79` | `{NO_ERROR, NO_COLLATERAL_AVAILABLE, COLLATERAL_CANNOT_BE_LIQUIDATED, CURRRENCY_NOT_BORROWED, HEALTH_FACTOR_ABOVE_THRESHOLD, NOT_ENOUGH_LIQUIDITY}` — note the triple-R typo, carried into v2 |
| `struct LiquidationCallLocalVars` | `:88` | |
| `struct AvailableCollateralToLiquidateLocalVars` | `:295` | |
| `getRevision()` | `:111` | returns `0` |

### `liquidationCall(address _collateral, address _reserve, address _user, uint256 _purchaseAmount, bool _receiveAToken) external payable returns (uint256, string memory)` — `:124`

Returns `(code, message)` rather than reverting, so `LendingPool` can prefix the
message.

| Guard | Returned error | Line |
|---|---|---:|
| Health factor not below threshold | `HEALTH_FACTOR_ABOVE_THRESHOLD` | `:136` |
| User holds none of this collateral | `NO_COLLATERAL_AVAILABLE` | `:145` |
| Collateral not enabled (globally or by the user) | `COLLATERAL_CANNOT_BE_LIQUIDATED` | `:157` |
| User has no debt in this currency | `CURRRENCY_NOT_BORROWED` | `:170` |
| `!_receiveAToken` and reserve lacks the collateral | `NOT_ENOUGH_LIQUIDITY` | `:219` |

Then:

1. `maxPrincipalAmountToLiquidate = compoundedBorrow × 50 / 100`; the actual amount is `min(_purchaseAmount, max)`.
2. `calculateAvailableCollateralToLiquidate` for the debt.
3. **If an origination fee is outstanding**, a *second* call computes the collateral needed to also seize the fee, out of whatever collateral remains.
4. If the collateral is insufficient, `actualAmountToLiquidate` is reduced to `principalAmountNeeded`.
5. `core.updateStateOnLiquidation(...)` with all nine arguments.
6. Either `collateralAtoken.transferOnLiquidation` (aToken path) or `burnOnLiquidation` + `core.transferToUser` (underlying path).
7. `core.transferToReserve.value(msg.value)` pulls the repayment from the liquidator.
8. Fee seizure, if any, burns more aTokens and calls `core.liquidateFee`, emitting `OriginationFeeLiquidated` (`:44` in `LendingPool.sol:194`).
9. `emit LiquidationCall(...)`.

- **Gotcha.** The fee seizure is a *second* collateral grab on top of the 50% close factor, so a liquidation can take more collateral than the headline bonus suggests. v2 dropped origination fees entirely and this whole branch with them.

### `calculateAvailableCollateralToLiquidate(address _collateral, address _principal, uint256 _purchaseAmount, uint256 _userCollateralBalance) internal view returns (uint256 collateralAmount, uint256 principalAmountNeeded)` — `:314`

```
maxAmountCollateralToLiquidate = principalPrice × purchaseAmount / collateralPrice × liquidationBonus / 100
```

If that exceeds the user's balance, the collateral is capped and the principal is
back-solved. Otherwise the requested amount stands.

- **Gotcha.** Token decimals are **not** normalised here — v1 prices are per whole token in ETH and the multiplication assumes matching scales. v2's `_calculateAvailableCollateralToLiquidate` fixed this by dividing by `10**decimals` explicitly.

## 1.8 `DefaultReserveInterestRateStrategy` (v1)

`aave/v1-aave-protocol/contracts/lendingpool/DefaultReserveInterestRateStrategy.sol`
— 199 lines.

| Constant | Line | Value |
|---|---:|---|
| `OPTIMAL_UTILIZATION_RATE` | `:28` | `0.8e27` |
| `EXCESS_UTILIZATION_RATE` | `:36` | `0.2e27` |

Immutables: `baseVariableBorrowRate`, `variableRateSlope1`, `variableRateSlope2`,
`stableRateSlope1`, `stableRateSlope2`, exposed by getters at `:79`, `:83`,
`:87`, `:91`, `:95`.

### `calculateInterestRates(address _reserve, uint256 _availableLiquidity, uint256 _totalBorrowsStable, uint256 _totalBorrowsVariable, uint256 _averageStableBorrowRate) external view returns (uint256 currentLiquidityRate, uint256 currentStableBorrowRate, uint256 currentVariableBorrowRate)` — `:108`

1. `U = totalBorrows / (availableLiquidity + totalBorrows)`, or `0` when both are zero.
2. Base stable rate comes from `ILendingRateOracle.getMarketBorrowRate(_reserve)` — an **off-chain anchor**, unique to v1/v2.
3. Above the kink: both rates add their full slope1 plus `slope2 × (U − U*)/(1 − U*)`. Below: `slope1 × U/U*`.
4. `currentLiquidityRate = overallBorrowRate × U`.

### `getOverallBorrowRateInternal(uint256 _totalBorrowsStable, uint256 _totalBorrowsVariable, uint256 _currentVariableBorrowRate, uint256 _currentAverageStableBorrowRate) internal pure returns (uint256)` — `:175`

```
overall = (variableTotal·variableRate + stableTotal·avgStableRate) / totalBorrows
```

Returns `0` when there is no debt.

- **The v1 gap.** `currentLiquidityRate = overallBorrowRate × U` with **no reserve factor**. v1 took no protocol cut of interest at all — its revenue was the origination fee and the flash-loan protocol fee. v2 multiplies by `(1 − reserveFactor)` ([2.12](#212-defaultreserveinterestratestrategy-v2)).

## 1.9 `AToken` (v1) — the rebasing token with interest redirection

`aave/v1-aave-protocol/contracts/tokenization/AToken.sol` — 674 lines.
`contract AToken is ERC20, ERC20Detailed` (`:18`).

### State

| Field | Line | Meaning |
|---|---:|---|
| `userIndexes` | `:125` | Each user's snapshot of the reserve's normalized income |
| `interestRedirectionAddresses` | `:126` | Who receives this user's interest |
| `redirectedBalances` | `:127` | Total balance redirected **to** this address |
| `interestRedirectionAllowances` | `:128` | Who may redirect on this user's behalf |

### Modifiers

- `onlyLendingPool` — `:135` — *"The caller of this function must be a lending pool"*
- `whenTransferAllowed(address _from, uint256 _amount)` — `:143` — requires `isTransferAllowed`

### `balanceOf(address _user) public view returns (uint256)` — `:338`

The most subtle function in v1:

```solidity
// AToken.sol:352-372
if (interestRedirectionAddresses[_user] == address(0)) {
    return calculateCumulatedBalanceInternal(
        _user, currentPrincipalBalance.add(redirectedBalance)
    ).sub(redirectedBalance);
} else {
    return currentPrincipalBalance.add(
        calculateCumulatedBalanceInternal(_user, redirectedBalance).sub(redirectedBalance)
    );
}
```

- **Not redirecting:** your principal *and* everything redirected to you accrue; the redirected principal is then subtracted so you keep only the interest on it.
- **Redirecting:** your own principal stops accruing for you; only the balance others redirected to you earns.

This is why `redirectedBalances` is a *balance*, not an interest figure — it is
the notional on which someone else's interest is computed.

### `calculateCumulatedBalanceInternal(address _user, uint256 _balance) internal view returns (uint256)` — `:522`

```solidity
return _balance.wadToRay()
    .rayMul(core.getReserveNormalizedIncome(underlyingAssetAddress))
    .rayDiv(userIndexes[_user])
    .rayToWad();
```

The scaled-balance idea in embryo — except the index snapshot lives in a side
mapping instead of being folded into the stored balance, which is precisely what
v2 changed.

### `cumulateBalanceInternal(address _user) internal returns (uint256, uint256, uint256, uint256)` — `:452`

Materialises accrued interest by **actually minting** it, then refreshes
`userIndexes[_user]`. Returns `(previousPrincipal, newPrincipal, balanceIncrease,
newIndex)`. Every mutating path calls this first.

### `updateRedirectedBalanceOfRedirectionAddressInternal(address _user, uint256 _balanceToAdd, uint256 _balanceToRemove) internal` — `:479`

Returns immediately if the user is not redirecting. Otherwise it compounds the
redirection target's balance, adjusts `redirectedBalances`, and — if the target
is *itself* redirecting — propagates the balance increase one more hop. Emits
`RedirectedBalanceUpdated` (`:110`).

- **Gotcha.** Only **one** hop is propagated. A three-deep redirection chain does not fully update in a single transaction.

### User-facing functions

| Function | Line | Behaviour |
|---|---:|---|
| `redirectInterestStream(address _to)` | `:179` | Redirect your own interest. Reverts *"Interest stream can only be redirected to a different address"* / *"Interest stream can only be redirected if there is a valid balance"* |
| `redirectInterestStreamOf(address _from, address _to)` | `:191` | Redirect someone else's, if allowed. Reverts *"Caller is not allowed to redirect the interest of the user"* |
| `allowInterestRedirectionTo(address _to)` | `:205` | Grant that permission. Emits `InterestRedirectionAllowanceChanged` (`:118`) |
| `redeem(uint256 _amount)` | `:218` | Burn and call `pool.redeemUnderlying`. `_amount == UINT_MAX_VALUE` redeems everything |
| `mintOnDeposit(address _account, uint256 _amount)` | `:271` | `onlyLendingPool` |
| `burnOnLiquidation(address _account, uint256 _value)` | `:297` | `onlyLendingPool` |
| `transferOnLiquidation(address _from, address _to, uint256 _value)` | `:325` | `onlyLendingPool`; bypasses `whenTransferAllowed` |
| `_transfer(address,address,uint256)` | `:167` | Overrides ERC20; gated by `whenTransferAllowed` |
| `principalBalanceOf(address)` | `:381` | `super.balanceOf` — the stored, non-accruing figure |
| `totalSupply()` | `:392` | Principal supply scaled by normalized income |
| `isTransferAllowed(address,uint256)` | `:413` | `pool.balanceDecreaseAllowed(...)` |
| `getUserIndex(address)` | `:422` | |
| `getInterestRedirectionAddress(address)` | `:432` | |
| `getRedirectedBalance(address)` | `:442` | |
| `executeTransferInternal(address,address,uint256)` | `:540` | Compounds both sides, moves redirected balances, transfers |
| `redirectInterestStreamInternal(address,address)` | `:598` | Shared body of both redirect entry points |
| `resetDataOnZeroBalanceInternal(address)` | `:657` | Clears index and redirection when a balance hits zero |

- **Gotcha.** `redeem` is the user entry point and it calls back into
  `LendingPool.redeemUnderlying`, which is `onlyOverlyingAToken`. The
  circular trust between pool and token is a v1 signature; v2 inverted it so the
  pool drives the token.

## 1.10 `LendingPoolConfigurator` (v1)

`aave/v1-aave-protocol/contracts/lendingpool/LendingPoolConfigurator.sol` — 449
lines. `CONFIGURATOR_REVISION = 0x3` (`:157`). Every mutator carries
`onlyLendingPoolManager` (`:149`) — *"The caller must be a lending pool
manager"*.

| Function | Line | Effect |
|---|---:|---|
| `initialize(LendingPoolAddressesProvider)` | `:163` | |
| `initReserve(...)` | `:173` | Deploys an `AToken` then calls `initReserveWithData` |
| `initReserveWithData(...)` | `:201` | Registers an existing aToken. Emits `ReserveInitialized` (`:26`) |
| `removeLastAddedReserve(address)` | `:235` | Emits `ReserveRemoved` (`:36`) |
| `enableBorrowingOnReserve(address,bool)` | `:246` | `BorrowingEnabledOnReserve` (`:45`) |
| `disableBorrowingOnReserve(address)` | `:259` | `BorrowingDisabledOnReserve` (`:51`) |
| `enableReserveAsCollateral(address,uint256,uint256,uint256)` | `:273` | `ReserveEnabledAsCollateral` (`:60`) |
| `disableReserveAsCollateral(address)` | `:298` | `ReserveDisabledAsCollateral` (`:71`) |
| `enableReserveStableBorrowRate(address)` | `:309` | `StableRateEnabledOnReserve` (`:77`) |
| `disableReserveStableBorrowRate(address)` | `:320` | `StableRateDisabledOnReserve` (`:83`) |
| `activateReserve(address)` | `:331` | `ReserveActivated` (`:89`) |
| `deactivateReserve(address)` | `:342` | `ReserveDeactivated` (`:95`) |
| `freezeReserve(address)` | `:354` | `ReserveFreezed` (`:101`) |
| `unfreezeReserve(address)` | `:365` | `ReserveUnfreezed` (`:107`) |
| `setReserveBaseLTVasCollateral(address,uint256)` | `:377` | `ReserveBaseLtvChanged` (`:114`) |
| `setReserveLiquidationThreshold(address,uint256)` | `:391` | `ReserveLiquidationThresholdChanged` (`:121`) |
| `setReserveLiquidationBonus(address,uint256)` | `:404` | `ReserveLiquidationBonusChanged` (`:128`) |
| `setReserveDecimals(address,uint256)` | `:420` | `ReserveDecimalsChanged` (`:135`) |
| `setReserveInterestRateStrategyAddress(address,address)` | `:433` | `ReserveInterestRateStrategyChanged` (`:143`) |
| `refreshLendingPoolCoreConfiguration()` | `:444` | Re-caches the pool address inside the Core |

**One admin key.** There is a single `LENDING_POOL_MANAGER` role and no
timelock, emergency admin or risk admin. v2 split off an emergency admin; v3
added a full `ACLManager`.

## 1.11 Configuration, fees, flashloan, misc, mocks

### `LendingPoolAddressesProvider` — `configuration/LendingPoolAddressesProvider.sol`, 238 lines

Fourteen `bytes32` ids at `:33-46`: `LENDING_POOL`, `LENDING_POOL_CORE`,
`LENDING_POOL_CONFIGURATOR`, `PARAMETERS_PROVIDER`, `LENDING_POOL_MANAGER`,
`LIQUIDATION_MANAGER`, `FLASHLOAN_PROVIDER`, `DATA_PROVIDER`,
`ETHEREUM_ADDRESS`, `PRICE_ORACLE`, `LENDING_RATE_ORACLE`, `FEE_PROVIDER`,
`WALLET_BALANCE_PROVIDER`, `TOKEN_DISTRIBUTOR`.

Getters and `onlyOwner` setters at `:53`–`:211`. The pattern splits in two:
`setXImpl` routes through `updateImplInternal` (`:222`), which deploys or
upgrades an `InitializableAdminUpgradeabilityProxy` and calls
`initialize(address)` on it; plain `setX` (price oracle, lending rate oracle,
token distributor, manager) writes the address directly with no proxy.

- **Gotcha.** `setLendingPoolLiquidationManager` (`:168`) is a direct set, not a
  proxy — correct, since the manager is only ever `delegatecall`ed.

### `LendingPoolParametersProvider` — `configuration/LendingPoolParametersProvider.sol`, 53 lines

Four hardcoded `private constant`s:

| Constant | Line | Value | Meaning |
|---|---:|---|---|
| `MAX_STABLE_RATE_BORROW_SIZE_PERCENT` | `:15` | `25` | A stable borrow may take at most 25% of available liquidity |
| `REBALANCE_DOWN_RATE_DELTA` | `:16` | `1e27/5` | The 20% band above the reserve stable rate that triggers a rebalance-down |
| `FLASHLOAN_FEE_TOTAL` | `:17` | `35` | 0.35% total flash-loan fee (bips) |
| `FLASHLOAN_FEE_PROTOCOL` | `:18` | `3000` | 30% of that fee goes to the protocol |

Exposed by `getMaxStableRateBorrowSizePercent` (`:35`),
`getRebalanceDownRateDelta` (`:43`), `getFlashLoanFeesInBips` (`:50`).

- **Gotcha.** All four are `constant` and every getter is `pure`. Changing any of
  them requires deploying a new implementation — there is no setter, despite the
  contract being proxied.

### `AddressStorage` (`:14`) / `UintStorage` (`:14`)

Minimal `bytes32 => address` and `bytes32 => uint256` stores with
`getAddress`/`_setAddress` and `getUint`/`_setUint`.

### `FeeProvider` — `fees/FeeProvider.sol`, 51 lines

`originationFeePercentage` is set in `initialize` (`:30`) to `0.0025 * 1e18`.
`calculateLoanOriginationFee(address _user, uint256 _amount)` (`:39`) returns
`_amount.wadMul(originationFeePercentage)`.
`getLoanOriginationFeePercentage()` at `:46`. `FEE_PROVIDER_REVISION = 0x1` (`:20`).

> **Documentation bug, preserved in the source.** The NatSpec at
> `aave/v1-aave-protocol/contracts/fees/FeeProvider.sol:30` says *"origination
> fee is set as default as 25 basis points of the loan amount (0.0025%)"*. 25
> basis points is **0.25%**, and `0.0025 * 1e18` is indeed 0.25%. The code is
> right; the parenthetical is wrong by a factor of 100.

- **Gotcha.** The `_user` parameter is unused — the NatSpec says it exists so a
  future version could give stakers a discount. It never shipped.

### `TokenDistributor` — `fees/TokenDistributor.sol`, 162 lines

Receives every protocol fee and splits it by configured percentages.

| Item | Line | Notes |
|---|---:|---|
| `IMPLEMENTATION_REVISION` | `:27` | `0x4` |
| `MAX_UINT` / `MAX_UINT_MINUS_ONE` | `:30`, `:33` | Sentinels |
| `MIN_CONVERSION_RATE` | `:36` | `1` |
| `KYBER_ETH_MOCK_ADDRESS` | `:39` | Kyber's native-ETH pseudo-address |
| `DISTRIBUTION_BASE` | `:45` | `10000` |
| `tokenToBurn` / `recipientBurn` | `:51`, `:54` | The LEND burn leg |
| `initialize(...)` | `:60` | |
| `distribute(IERC20[])` | `:75` | Distribute full balances |
| `distributeWithAmounts(IERC20[],uint256[])` | `:91` | Distribute specific amounts |
| `distributeWithPercentages(IERC20[],uint256[])` | `:100` | Distribute a percentage of each balance |
| `internalSetTokenDistribution(...)` | `:117` | Emits `DistributionUpdated` (`:24`) |
| `internalDistributeTokenWithAmount(...)` | `:127` | Emits `Distributed` (`:25`) per receiver |
| `getDistribution()` | `:152` | |

- **Gotcha.** Anyone may call `distribute` — it is permissionless because the
  receivers and percentages are fixed by the owner.

### `ChainlinkProxyPriceProvider` — `misc/ChainlinkProxyPriceProvider.sol`, 108 lines

`setAssetSources` (`:37`, `onlyOwner`) · `setFallbackOracle` (`:44`,
`onlyOwner`) · `internalSetAssetsSources` (`:51`, emits `AssetSourceUpdated`
`:18`) · `internalSetFallbackOracle` (`:61`, emits `FallbackOracleUpdated`
`:19`) · `getAssetPrice` (`:68`) · `getAssetsPrices` (`:89`) ·
`getSourceOfAsset` (`:100`) · `getFallbackOracle` (`:106`).

`getAssetPrice` returns `1 ether` for the ETH pseudo-address, otherwise
`latestAnswer()`; a zero or missing answer falls through to the fallback oracle.

- **Gotcha.** `latestAnswer()` carries **no staleness check** — no `updatedAt`,
  no heartbeat. Prices are denominated in ETH, not USD.

### `WalletBalanceProvider` — `misc/WalletBalanceProvider.sol`, 76 lines

`balanceOf` (`:29`), `batchBalanceOf` (`:44`), `getUserWalletBalances` (`:65`).
Front-end convenience only.

### `IERC20DetailedBytes` — `misc/IERC20DetailedBytes.sol`, 7 lines

Declares `symbol()` returning `bytes32`, for tokens like MKR that predate the
string convention.

### `flashloan/`

- `IFlashLoanReceiver.sol` (12) — `executeOperation(address _reserve, uint256 _amount, uint256 _fee, bytes calldata _params)`.
- `FlashLoanReceiverBase.sol` (51) — stores the addresses provider, exposes `transferFundsBackInternal` / `transferInternal` and `getBalanceInternal`, and handles the ETH branch.

### Upgradeability set (`libraries/openzeppelin-upgradeability/`)

`Proxy.sol` (71) provides the assembly `delegatecall` fallback.
`BaseUpgradeabilityProxy.sol` (64) stores the implementation at
`keccak256("org.zeppelinos.proxy.implementation")` and emits `Upgraded`.
`UpgradeabilityProxy.sol` (27) sets it in the constructor;
`InitializableUpgradeabilityProxy.sol` (28) sets it post-deployment.
`BaseAdminUpgradeabilityProxy.sol` (121) adds the admin slot and the `ifAdmin`
router, so admin calls never fall through to the implementation.
`AdminUpgradeabilityProxy.sol` (24) and
`InitializableAdminUpgradeabilityProxy.sol` (27) are the concrete forms; the
latter is what the addresses provider deploys.

`Initializable.sol` (62) gives a one-shot `initializer`.
**`VersionedInitializable.sol` (70)** is the important one: it stores
`lastInitializedRevision` and its `initializer` modifier (`:32`) requires
`isConstructor() || revision > lastInitializedRevision`. Each contract's
`getRevision()` (`:56`) returns a bumped constant on upgrade, so a fresh
implementation may run `initialize` exactly once. `isConstructor()` (`:61`)
checks `extcodesize(address()) == 0`.

## 1.12 v1 revert-string table

v1 has no error library — every failure is an inline string. Complete list, with
the file and line where it is raised.

| Message | Where |
|---|---|
| `"The caller must be a lending pool contract"` | `LendingPoolCore.sol:59` |
| `"The caller must be a lending pool configurator contract"` | `LendingPoolCore.sol:67` |
| `"Only contracts can send ether to the Lending pool core"` | `LendingPoolCore.sol:387` |
| `"Transfer of ETH failed"` | `LendingPoolCore.sol:405`, `:436`, `:461`, `:492` |
| `"User is sending ETH along with the ERC20 transfer. Check the value attribute of the transaction"` | `LendingPoolCore.sol:427` |
| `"The amount and the value sent to deposit do not match"` | `LendingPoolCore.sol:433`, `:481` |
| `"Fee liquidation does not require any transfer of value"` | `LendingPoolCore.sol:453` |
| `"User is sending ETH along with the ERC20 transfer."` | `LendingPoolCore.sol:478` |
| `"Invalid borrow rate mode"` | `LendingPoolCore.sol:1338` |
| `"The caller of this function can only be the aToken contract of this reserve"` | `LendingPool.sol:235` |
| `"Action requires an active reserve"` | `LendingPool.sol:991` |
| `"Action requires an unfreezed reserve"` | `LendingPool.sol:998` |
| `"Amount must be greater than 0"` | `LendingPool.sol:1005` |
| `"There is not enough liquidity available to redeem"` | `LendingPool.sol:346` |
| `"Reserve is not enabled for borrowing"` | `LendingPool.sol:404` |
| `"Invalid interest rate mode selected"` | `LendingPool.sol:409` |
| `"There is not enough liquidity available in the reserve"` | `LendingPool.sol:420` |
| `"The collateral balance is 0"` | `LendingPool.sol:434` |
| `"The borrower can already be liquidated so he cannot borrow more"` | `LendingPool.sol:438` |
| `"The amount to borrow is too small"` | `LendingPool.sol:444` |
| `"There is not enough collateral to cover a new borrow"` | `LendingPool.sol:457` |
| `"User cannot borrow the selected amount with a stable rate"` | `LendingPool.sol:473` |
| `"User is trying to borrow too much liquidity at a stable rate"` | `LendingPool.sol:483` |
| `"The user does not have any borrow pending"` | `LendingPool.sol:552` |
| `"To repay on behalf of an user an explicit amount to repay is needed."` | `LendingPool.sol:556` |
| `"Invalid msg.value sent for the repayment"` | `LendingPool.sol:568` |
| `"User does not have a borrow in progress on this reserve"` | `LendingPool.sol:659` |
| `"User cannot borrow the selected amount at stable"` | `LendingPool.sol:677` |
| `"User does not have any borrow for this reserve"` | `LendingPool.sol:720` |
| `"The user borrow is variable and cannot be rebalanced"` | `LendingPool.sol:725` |
| `"Interest rate rebalance conditions were not met"` | `LendingPool.sol:764` |
| `"User does not have any liquidity deposited"` | `LendingPool.sol:780` |
| `"User deposit is already being used as collateral"` | `LendingPool.sol:784` |
| `"Liquidation call failed"` | `LendingPool.sol:825` |
| `"Liquidation failed: " + message` | `LendingPool.sol:831` |
| `"There is not enough liquidity available to borrow"` | `LendingPool.sol:857` |
| `"The requested amount is too small for a flashLoan."` | `LendingPool.sol:869` |
| `"The actual balance of the protocol is inconsistent"` | `LendingPool.sol:890` |
| `"Reserve has already been initialized"` | `CoreLibrary.sol:170` |
| `"Reserve is already enabled"` | `CoreLibrary.sol:195` |
| `"Reserve is already enabled as collateral"` | `CoreLibrary.sol:223` |
| `"Invalid amount to decrease"` | `CoreLibrary.sol:336` |
| `"The amounts to subtract don't match"` | `CoreLibrary.sol:357` |
| `"The amount that is being subtracted from the variable total borrows is incorrect"` | `CoreLibrary.sol:381` |
| `"The caller of this function must be a lending pool"` | `AToken.sol:138` |
| `"Transfer cannot be allowed."` | `AToken.sol:145` |
| `"Interest stream can only be redirected to a different address"` | `AToken.sol:611` |
| `"Interest stream can only be redirected if there is a valid balance"` | `AToken.sol:617` |
| `"Caller is not allowed to redirect the interest of the user"` | `AToken.sol:196` |
| `"Amount to redeem needs to be > 0"` | `AToken.sol:228` |
| `"User cannot redeem more than the available balance"` | `AToken.sol:238` |
| `"Transfer cannot be allowed."` | `AToken.sol:241` |
| `"The caller must be a lending pool manager"` | `LendingPoolConfigurator.sol:152` |

Liquidation failures are **return codes**, not reverts — see the
`LiquidationErrors` enum at `LendingPoolLiquidationManager.sol:79` and the
message strings paired with them at `:137`, `:146`, `:158`, `:171`, `:221`.

## 1.13 v1 events reference

| Event | Declared | Emitted when |
|---|---|---|
| `Deposit(reserve, user, amount, referral, timestamp)` | `LendingPool.sol:46` | `deposit` succeeds |
| `RedeemUnderlying(reserve, user, amount, timestamp)` | `LendingPool.sol:61` | `redeemUnderlying` succeeds |
| `Borrow(reserve, user, amount, borrowRateMode, borrowRate, originationFee, borrowBalanceIncrease, referral, timestamp)` | `LendingPool.sol:80` | `borrow` succeeds |
| `Repay(reserve, user, repayer, amountMinusFees, fees, borrowBalanceIncrease, timestamp)` | `LendingPool.sol:102` | `repay`, both branches |
| `Swap(reserve, user, newRateMode, newRate, borrowBalanceIncrease, timestamp)` | `LendingPool.sol:121` | `swapBorrowRateMode` |
| `ReserveUsedAsCollateralEnabled(reserve, user)` | `LendingPool.sol:135` | Collateral flag on |
| `ReserveUsedAsCollateralDisabled(reserve, user)` | `LendingPool.sol:142` | Collateral flag off |
| `RebalanceStableBorrowRate(reserve, user, newStableRate, borrowBalanceIncrease, timestamp)` | `LendingPool.sol:152` | `rebalanceStableBorrowRate` |
| `FlashLoan(target, reserve, amount, totalFee, protocolFee, timestamp)` | `LendingPool.sol:169` | `flashLoan` |
| `OriginationFeeLiquidated(collateral, reserve, user, feeLiquidated, liquidatedCollateralForFee, timestamp)` | `LendingPool.sol:194` | Liquidation that also seizes fees |
| `LiquidationCall(collateral, reserve, user, purchaseAmount, liquidatedCollateralAmount, accruedBorrowInterest, liquidator, receiveAToken, timestamp)` | `LendingPool.sol:215` | Liquidation |
| `ReserveUpdated(reserve, liquidityRate, stableBorrowRate, variableBorrowRate, liquidityIndex, variableBorrowIndex)` | `LendingPoolCore.sol:43` | Every rate/timestamp refresh |
| `Redeem(from, value, fromBalanceIncrease, fromIndex)` | `AToken.sol:30` | `AToken.redeem` |
| `MintOnDeposit(from, value, fromBalanceIncrease, fromIndex)` | `AToken.sol:44` | `mintOnDeposit` |
| `BurnOnLiquidation(from, value, fromBalanceIncrease, fromIndex)` | `AToken.sol:59` | `burnOnLiquidation` |
| `BalanceTransfer(from, to, value, fromBalanceIncrease, toBalanceIncrease, fromIndex, toIndex)` | `AToken.sol:76` | aToken transfer |
| `InterestStreamRedirected(from, to, redirectedBalance, fromBalanceIncrease, fromIndex)` | `AToken.sol:94` | Redirection set or reset |
| `RedirectedBalanceUpdated(targetAddress, targetBalanceIncrease, targetIndex, redirectedBalanceAdded, redirectedBalanceRemoved)` | `AToken.sol:110` | Redirected notional changes |
| `InterestRedirectionAllowanceChanged(from, to)` | `AToken.sol:118` | `allowInterestRedirectionTo` |
| `DistributionUpdated(receivers, percentages)` | `TokenDistributor.sol:24` | Distribution reconfigured |
| `Distributed(receiver, percentage, amount)` | `TokenDistributor.sol:25` | Per-receiver payout |
| `AssetSourceUpdated(asset, source)` | `ChainlinkProxyPriceProvider.sol:18` | Oracle source set |
| `FallbackOracleUpdated(fallbackOracle)` | `ChainlinkProxyPriceProvider.sol:19` | Fallback set |

Plus the 19 configurator events listed in [1.10](#110-lendingpoolconfigurator-v1).

- **Indexer gotcha.** v1 events carry an explicit `timestamp` field. They mostly
  do **not** use `indexed`, so filtering by user requires scanning. v2 fixed both.

## 1.14 v1 storage layouts

### `LendingPool` (proxied)

| Slot | Source | Type | Name |
|---:|---|---|---|
| 0 | `ReentrancyGuard` | `uint256` | `_guardCounter` |
| 1 | `VersionedInitializable` | `uint256` | `lastInitializedRevision` |
| 2 | `LendingPool.sol:32` | `address` | `addressesProvider` |
| 3 | `LendingPool.sol:33` | `address` | `core` |
| 4 | `LendingPool.sol:34` | `address` | `dataProvider` |
| 5 | `LendingPool.sol:35` | `address` | `parametersProvider` |
| 6 | `LendingPool.sol:36` | `address` | `feeProvider` |

`LendingPoolLiquidationManager` reproduces slots 0–6 exactly and adds
`ethereumAddress` at slot 7 — the invariant that makes the `delegatecall` sound.

### `LendingPoolCore` (proxied)

| Slot | Source | Type | Name |
|---:|---|---|---|
| 0 | `VersionedInitializable` | `uint256` | `lastInitializedRevision` |
| 1 | `LendingPoolCore.sol:52` | `address` | `lendingPoolAddress` |
| 2 | inherited field | `address` | `addressesProvider` |
| 3 | `LendingPoolCore.sol:75` | mapping | `reserves` |
| 4 | `LendingPoolCore.sol:76` | mapping | `usersReserveData` |
| 5 | `LendingPoolCore.sol:78` | `address[]` | `reservesList` |

Each `ReserveData` occupies roughly 20 slots; each `UserReserveData` roughly 6.

### `AToken`

Slots 0–4 come from OpenZeppelin `ERC20` and `ERC20Detailed` (balances,
allowances, total supply, name, symbol, decimals), followed by
`addressesProvider`, `core`, `pool`, `dataProvider`, `underlyingAssetAddress`,
then the four redirection mappings at `AToken.sol:125-128`.

- **Gotcha.** v1 aTokens are **not** proxied — `AToken` has no
  `VersionedInitializable`. Upgrading one means deploying a new token and
  re-listing the reserve.

## 1.15 v1 ABI / selector tables

### `LendingPool`

| Signature | Mutability | Access |
|---|---|---|
| `initialize(address)` | non-payable | `initializer` |
| `deposit(address,uint256,uint16)` | payable | anyone |
| `redeemUnderlying(address,address,uint256,uint256)` | non-payable | aToken only |
| `borrow(address,uint256,uint256,uint16)` | non-payable | anyone |
| `repay(address,uint256,address)` | payable | anyone |
| `swapBorrowRateMode(address)` | non-payable | anyone |
| `rebalanceStableBorrowRate(address,address)` | non-payable | anyone |
| `setUserUseReserveAsCollateral(address,bool)` | non-payable | anyone |
| `liquidationCall(address,address,address,uint256,bool)` | payable | anyone |
| `flashLoan(address,address,uint256,bytes)` | non-payable | anyone |
| `getReserveConfigurationData(address)` | view | anyone |
| `getReserveData(address)` | view | anyone |
| `getUserAccountData(address)` | view | anyone |
| `getUserReserveData(address,address)` | view | anyone |
| `getReserves()` | view | anyone |

### `AToken`

`redeem(uint256)` · `redirectInterestStream(address)` ·
`redirectInterestStreamOf(address,address)` ·
`allowInterestRedirectionTo(address)` · `mintOnDeposit(address,uint256)` * ·
`burnOnLiquidation(address,uint256)` * ·
`transferOnLiquidation(address,address,uint256)` * · `balanceOf(address)` ·
`principalBalanceOf(address)` · `totalSupply()` ·
`isTransferAllowed(address,uint256)` · `getUserIndex(address)` ·
`getInterestRedirectionAddress(address)` · `getRedirectedBalance(address)` ·
plus the full ERC20 surface. Entries marked * are `onlyLendingPool`.

### `LendingPoolCore`

All 8 `updateStateOn*` mutators and `setUserUseReserveAsCollateral` are
`onlyLendingPool`. The 4 `transferTo*`/`liquidateFee` functions are
`onlyLendingPool`. The 19 configuration setters are
`onlyLendingPoolConfigurator`. The ~35 getters listed in
[1.5](#15-lendingpoolcore) are open.

## 1.16 v1 use cases

| Goal | Call | Internal chain |
|---|---|---|
| Supply an ERC20 | `LendingPool.deposit(asset, amt, 0)` | `core.updateStateOnDeposit` → `aToken.mintOnDeposit` → `core.transferToReserve` |
| Supply ETH | same, `asset = 0xEeee…`, with `msg.value` | as above; `transferToReserve` refunds excess |
| Withdraw | `AToken.redeem(amt)` | `cumulateBalanceInternal` → `_burn` → `pool.redeemUnderlying` → `core.updateStateOnRedeem` → `core.transferToUser` |
| Withdraw everything | `AToken.redeem(uint256(-1))` | as above with the full balance |
| Borrow variable | `LendingPool.borrow(asset, amt, 2, 0)` | 9 checks → `core.updateStateOnBorrow` → `core.transferToUser` |
| Borrow stable | `LendingPool.borrow(asset, amt, 1, 0)` | as above, plus the two stable-rate limits |
| Repay | `LendingPool.repay(asset, amt, self)` | fee first, then principal |
| Repay everything | `repay(asset, uint256(-1), self)` | `paybackAmount = compounded + fee` |
| Repay for someone else | `repay(asset, explicitAmt, other)` | the `UINT_MAX_VALUE` guard forbids max-repay on behalf |
| Switch rate mode | `swapBorrowRateMode(asset)` | `core.updateStateOnSwapRate` |
| Rebalance someone's stable rate | `rebalanceStableBorrowRate(asset, user)` | two trigger conditions or revert |
| Toggle collateral | `setUserUseReserveAsCollateral(asset, bool)` | `dataProvider.balanceDecreaseAllowed` gate |
| Liquidate, take underlying | `liquidationCall(coll, debt, user, amt, false)` | delegatecall → `burnOnLiquidation` + `transferToUser` |
| Liquidate, take aTokens | `liquidationCall(coll, debt, user, amt, true)` | delegatecall → `transferOnLiquidation` |
| Flash loan | `flashLoan(receiver, asset, amt, params)` | `transferToUser` → `executeOperation` → strict equality balance check |
| Redirect your interest | `AToken.redirectInterestStream(to)` | `redirectInterestStreamInternal` |
| Let someone redirect for you | `AToken.allowInterestRedirectionTo(who)` | then they call `redirectInterestStreamOf` |
| List a reserve | `LendingPoolConfigurator.initReserve(...)` | deploys the aToken, then `core.initReserve` |
| Freeze a reserve | `LendingPoolConfigurator.freezeReserve(asset)` | deposits and new borrows blocked; repay and redeem still work |

---

# Part 2 — Aave v2

Aave v2 shipped in December 2020. It keeps v1's economics almost intact — the
same kinked rate curve, the same stable/variable duality, the same liquidation
bonus — and rewrites the plumbing underneath. Three structural changes account
for nearly every difference in this Part:

1. **Funds moved out of a monolith and into the aTokens.** v1's
   `LendingPoolCore` held every reserve's balance. In v2 each aToken holds its
   own underlying, and there is no core contract at all.
2. **Debt became a token.** v1 stored `principalBorrowBalance` in a struct. v2
   mints `StableDebtToken` or `VariableDebtToken` to the borrower, which makes
   debt readable by any ERC20-aware tool and makes credit delegation possible.
3. **Logic moved into linked libraries.** `LendingPool` is a thin dispatcher
   over `ReserveLogic`, `ValidationLogic` and `GenericLogic`, which keeps the
   deployed bytecode under the 24 KB limit that v1's 1,775-line core was
   straining against.

## 2.1 Architecture

```
                        LendingPoolAddressesProvider
                     (per-market registry, owns every proxy)
                                    |
        +---------------------------+---------------------------+
        |                           |                           |
   LendingPool               LendingPoolConfigurator      AaveOracle
   (proxied, entry point)    (proxied, admin surface)     LendingRateOracle
        |
        |  linked libraries (delegatecall at the EVM level, but
        |  `internal` at the language level — no storage of their own)
        +-- ReserveLogic       index accrual, rate refresh, treasury mint
        +-- ValidationLogic    every precondition
        +-- GenericLogic       health factor, account aggregation
        +-- Helpers            debt lookups
        |
        |  delegatecall (shares LendingPoolStorage layout)
        +-- LendingPoolCollateralManager    liquidationCall
        |
        |  external calls, one set per reserve
        +-- AToken              holds the underlying, mints/burns scaled balances
        +-- StableDebtToken     non-transferable, weighted-average rate
        +-- VariableDebtToken   non-transferable, scaled by borrow index
        +-- DefaultReserveInterestRateStrategy   pure rate math
```

Compare with v1's diagram in [1.1](#11-architecture-and-the-delegatecall-storage-contract).
The `delegatecall` trick survives in exactly one place — the collateral manager —
and for the same reason: `liquidationCall` is too big to inline into
`LendingPool` without breaching the contract size limit. `LendingPoolStorage`
exists solely so that the two contracts agree on the layout, exactly as
`LendingPoolLiquidationManager` had to mirror `LendingPool`'s first seven slots
in v1.

- **What v1's `LendingPoolCore` became.** Its state split into
  `LendingPoolStorage._reserves` (reserve data) and the two debt tokens (user
  debt). Its funds moved into the aTokens. Its ~35 getters became
  `AaveProtocolDataProvider`. Its `updateStateOn*` mutators became
  `ReserveLogic.updateState` plus token mints and burns.

## 2.2 `DataTypes` and `LendingPoolStorage`

### `DataTypes.ReserveData` (`aave/v2-protocol/contracts/protocol/libraries/types/DataTypes.sol:6-28`)

| Field | Type | Unit | Meaning |
|---|---|---|---|
| `configuration` | `ReserveConfigurationMap` | packed | The 256-bit risk bitmap, [2.4](#24-reserveconfiguration--the-bitmap) |
| `liquidityIndex` | `uint128` | ray | Cumulative supply interest. Starts at `1e27`, only grows |
| `variableBorrowIndex` | `uint128` | ray | Cumulative variable-borrow interest, same scale |
| `currentLiquidityRate` | `uint128` | ray/yr | Supply APR at the last update |
| `currentVariableBorrowRate` | `uint128` | ray/yr | Variable borrow APR at the last update |
| `currentStableBorrowRate` | `uint128` | ray/yr | The rate a **new** stable borrow would receive |
| `lastUpdateTimestamp` | `uint40` | seconds | When the indexes were last accrued |
| `aTokenAddress` | `address` | — | Holds the underlying |
| `stableDebtTokenAddress` | `address` | — | |
| `variableDebtTokenAddress` | `address` | — | |
| `interestRateStrategyAddress` | `address` | — | Pure math, swappable by the configurator |
| `id` | `uint8` | — | Index into `_reservesList`; the bit position in every user's config map |

- **Packing.** `configuration` takes slot 0. The five `uint128` rates and
  indexes plus `uint40 lastUpdateTimestamp` pack into slots 1–3. The four
  addresses take slots 4–7, with `id` sharing slot 7. Eight slots per reserve
  against roughly twenty in v1.
- **Gotcha.** `id` is `uint8`, and `_maxNumberOfReserves` defaults to 128,
  because each reserve consumes **two** bits of a user's 256-bit configuration
  word. 128 reserves is the hard ceiling of the design, not a policy choice.
- **No stable-rate aggregate here.** v1 kept `currentStableBorrowRate` *and* the
  weighted average on the reserve. v2 delegates the average to
  `StableDebtToken.getAverageStableRate()`, so the reserve struct only carries
  the offer rate for new borrows.

### `DataTypes.ReserveConfigurationMap` / `UserConfigurationMap` (`:30-45`)

Both are a lone `uint256 data`. Wrapping them in structs lets Solidity attach
the `using ... for` libraries and prevents accidentally passing one where the
other is expected.

### `DataTypes.InterestRateMode` (`:47`)

`NONE = 0`, `STABLE = 1`, `VARIABLE = 2`. The numeric values are part of the
public ABI: `borrow(asset, amount, 2, ...)` means variable, and the same
convention carried into v3.

### `LendingPoolStorage` (`aave/v2-protocol/contracts/protocol/lendingpool/LendingPoolStorage.sol:10-32`)

| Slot | Type | Name | Purpose |
|---:|---|---|---|
| 0 | `ILendingPoolAddressesProvider` | `_addressesProvider` | The market registry |
| 1 | `mapping(address => ReserveData)` | `_reserves` | Per-asset reserve state |
| 2 | `mapping(address => UserConfigurationMap)` | `_usersConfig` | Per-user 256-bit flags |
| 3 | `mapping(uint256 => address)` | `_reservesList` | `id` → asset, a mapping not an array |
| 4 | `uint256` | `_reservesCount` | Length of the list |
| 5 | `bool` | `_paused` | Global emergency stop |
| 6 | `uint256` | `_maxStableRateBorrowSizePercent` | Cap on a single stable borrow |
| 7 | `uint256` | `_flashLoanPremiumTotal` | Flash loan fee in bps |
| 8 | `uint256` | `_maxNumberOfReserves` | Listing ceiling |

- **Why `_reservesList` is a mapping.** The comment at `:21` says "structured as
  a mapping for gas savings reasons". An `address[]` would pay for a length
  SLOAD on every access and for bounds checks; the mapping plus a separate
  `_reservesCount` is cheaper because the count is read once per loop.
- **The delegatecall contract.** `LendingPool` and
  `LendingPoolCollateralManager` both inherit this contract in the same
  position, so slots 0–8 line up. Any reordering here silently corrupts
  liquidations — the same class of hazard as v1's slot mirroring, but at least
  now expressed as shared inheritance rather than duplicated declarations.

## 2.3 Math libraries

### `WadRayMath` (`aave/v2-protocol/contracts/protocol/libraries/math/WadRayMath.sol`)

Identical in spirit to v1's, with overflow guards moved into `require`s.

| Constant | Line | Value |
|---|---:|---|
| `WAD` | `:13` | `1e18` |
| `halfWAD` | `:14` | `0.5e18` |
| `RAY` | `:16` | `1e27` |
| `halfRAY` | `:17` | `0.5e27` |
| `WAD_RAY_RATIO` | `:19` | `1e9` |

`rayMul(a,b)` (`:87`) computes `(a*b + halfRAY) / RAY`; `rayDiv(a,b)` (`:103`)
computes `(a*RAY + b/2) / b`. Both **round half up**, which is the single most
consequential rounding decision in the protocol: it means a scaled balance can
round in the user's favour by one wei, and v3 spent several releases (the
`TokenMath` library) undoing exactly this.

`rayToWad` (`:117`) and `wadToRay` (`:130`) convert with the same half-rounding.

### `PercentageMath` (`aave/v2-protocol/contracts/protocol/libraries/math/PercentageMath.sol`)

`PERCENTAGE_FACTOR = 1e4` (`:15`), so "100.00%" is `10000` and one basis point
is `1`. `percentMul` (`:24`) is `(value * pct + HALF_PERCENT) / 1e4` and
`percentDiv` (`:43`) is `(value * 1e4 + pct/2) / pct`. Both revert with
`Errors.MATH_MULTIPLICATION_OVERFLOW` / `MATH_DIVISION_BY_ZERO` on the guards at
`:30` and `:48`.

Every risk parameter — LTV, liquidation threshold, liquidation bonus, reserve
factor, flash loan premium — is a bps number consumed through these two.

### `MathUtils` (`aave/v2-protocol/contracts/protocol/libraries/math/MathUtils.sol`)

`SECONDS_PER_YEAR = 365 days`, i.e. exactly `31_536_000`. Leap seconds and leap
days are ignored, so a "year" of interest is a fixed number of seconds.

**`calculateLinearInterest(rate, lastUpdateTimestamp)` (`:21-30`)**

```solidity
uint256 timeDifference = block.timestamp.sub(uint256(lastUpdateTimestamp));
return (rate.mul(timeDifference) / SECONDS_PER_YEAR).add(WadRayMath.ray());
```

Returns `1 + r·Δt/T` in ray. Used for the **supply** side only.

- **Why suppliers get simple interest.** Their principal is not itself lent out
  and re-lent; the compounding a supplier experiences comes from borrowers'
  compounded debt flowing into the reserve, which raises `liquidityRate` at the
  next update. Applying compounding here as well would double-count.

**`calculateCompoundedInterest(rate, lastUpdateTimestamp, currentTimestamp)` (`:45-70`)**

The exact figure is `(1 + r/T)^Δt`. Computing that on-chain needs a loop or a
fixed-point `exp`; v2 instead truncates the binomial series after three terms.
With `x = r/T` (the per-second rate) and `n = Δt`:

```
(1+x)^n  =  1 + n·x + [n(n-1)/2]·x² + [n(n-1)(n-2)/6]·x³ + …
```

and the code computes exactly the first four terms:

| Code | Line | Series term |
|---|---:|---|
| `ratePerSecond = rate / SECONDS_PER_YEAR` | `:61` | `x` |
| `basePowerTwo = ratePerSecond.rayMul(ratePerSecond)` | `:63` | `x²` |
| `basePowerThree = basePowerTwo.rayMul(ratePerSecond)` | `:64` | `x³` |
| `secondTerm = exp·expMinusOne·basePowerTwo / 2` | `:66` | `[n(n-1)/2]·x²` |
| `thirdTerm = exp·expMinusOne·expMinusTwo·basePowerThree / 6` | `:67` | `[n(n-1)(n-2)/6]·x³` |
| `ray() + ratePerSecond·exp + secondTerm + thirdTerm` | `:69` | the sum |

Two guards matter. `exp == 0` returns `ray()` immediately (`:53-55`), so a
same-block second call is a no-op. `expMinusTwo` is clamped to `0` when
`exp <= 2` (`:59`), because `exp - 2` would underflow on `uint256` for `exp` of
0, 1 or 2 — and at those values the third term is genuinely zero anyway.

**Bounding the error.** The truncation drops the fourth term onward, which is
positive, so the approximation always **under**-estimates. The dominant omitted
term is `[n(n-1)(n-2)(n-3)/24]·x⁴ ≈ (n·x)⁴/24` for large `n`. Writing
`y = n·x` for the nominal simple interest over the period:

| Period without an update | `y` at 5% APR | Relative shortfall ≈ `y⁴/24` |
|---|---|---|
| 1 day | `1.37e-4` | `1.5e-17` |
| 30 days | `4.1e-3` | `1.2e-11` |
| 1 year | `0.05` | `2.6e-7` |
| 5 years | `0.25` | `1.6e-4` |

At any realistic update cadence the error is far below one ray. Even a reserve
untouched for a year is off by roughly 0.26 parts per million, and the sign is
always in the protocol's favour, which is why the doc comment at `:38` says it
"slightly underpays liquidity providers and undercharges borrowers". That
asymmetry is safe: the protocol never over-credits.

- **Gotcha.** The error compounds with *neglect*, not with usage. A busy reserve
  updates every block and the approximation is exact to the wei. A dormant
  reserve is where the drift lives.

The two-argument overload at `:77-83` just passes `block.timestamp`.

## 2.4 `ReserveConfiguration` — the bitmap

`aave/v2-protocol/contracts/protocol/libraries/configuration/ReserveConfiguration.sol`.
One `uint256` holds every risk parameter for a reserve.

```
 bit  255                                    80 79      64 63  60 59 58 57 56 55    48 47      32 31      16 15       0
     +----------------------------------------+----------+------+--+--+--+--+--------+----------+----------+----------+
     |                unused                  | reserve  |unused|S |B |F |A |decimals| liq.     | liq.     |   LTV    |
     |                                        | factor   |      |t |o |r |c |        | bonus    | threshold|          |
     +----------------------------------------+----------+------+--+--+--+--+--------+----------+----------+----------+
                                                 16 bits    4     1  1  1  1   8 bits   16 bits    16 bits    16 bits
```

| Field | Bits | Mask constant | Start-bit constant | Getter | Setter | Max |
|---|---|---|---|---|---|---|
| LTV | 0–15 | `LTV_MASK` `:13` | — (0) | `getLtv` `:55` | `setLtv` `:44` | 65535 |
| Liquidation threshold | 16–31 | `LIQUIDATION_THRESHOLD_MASK` `:14` | `:24` = 16 | `:80` | `:64` | 65535 |
| Liquidation bonus | 32–47 | `LIQUIDATION_BONUS_MASK` `:15` | `:25` = 32 | `:109` | `:93` | 65535 |
| Decimals | 48–55 | `DECIMALS_MASK` `:16` | `:26` = 48 | `:136` | `:122` | 255 |
| Active | 56 | `ACTIVE_MASK` `:17` | `:27` = 56 | `:160` | `:149` | flag |
| Frozen | 57 | `FROZEN_MASK` `:18` | `:28` = 57 | `:180` | `:169` | flag |
| Borrowing enabled | 58 | `BORROWING_MASK` `:19` | `:29` = 58 | `:203` | `:189` | flag |
| Stable borrowing enabled | 59 | `STABLE_BORROWING_MASK` `:20` | `:30` = 59 | `:230` | `:216` | flag |
| *(reserved)* | 60–63 | — | — | — | — | — |
| Reserve factor | 64–79 | `RESERVE_FACTOR_MASK` `:21` | `:31` = 64 | `:259` | `:243` | 65535 |
| *(unused)* | 80–255 | — | — | — | — | — |

Every mask is the **complement** of its field: `LTV_MASK` is all-ones except the
low 16 bits. So a setter is `(data & MASK) | (value << START)` — clear then
write — and a getter is `(data & ~MASK) >> START`. The flag getters skip the
shift entirely and just test `!= 0` (`:161`, `:181`, `:208`, `:235`), which is
one opcode cheaper than shifting down to a boolean.

Each setter `require`s its bound with a specific error: `RC_INVALID_LTV` (`:45`),
`RC_INVALID_LIQ_THRESHOLD` (`:68`), `RC_INVALID_LIQ_BONUS` (`:97`),
`RC_INVALID_DECIMALS` (`:126`), `RC_INVALID_RESERVE_FACTOR` (`:247`).

**Batch readers.** Four functions exist so callers pay one SLOAD instead of five:

| Function | Line | Returns |
|---|---:|---|
| `getFlags(storage)` | `:272` | `(active, frozen, borrowingEnabled, stableBorrowingEnabled)` |
| `getParams(storage)` | `:297` | `(ltv, liqThreshold, liqBonus, decimals, reserveFactor)` |
| `getParamsMemory(memory)` | `:324` | same, for a struct already in memory |
| `getFlagsMemory(memory)` | `:349` | same as `getFlags`, memory flavour |

`getParams` caches `self.data` into `dataLocal` at `:305` before the five
extractions — the whole point of the batch form.

- **Gotcha.** Setters take `memory`, getters take `storage`. The configurator
  therefore reads the map into memory, mutates, and writes the whole word back
  (see [2.14](#214-lendingpoolconfigurator-v2)). Calling a setter on a storage
  copy would compile but silently discard the write.
- **The four reserved bits (60–63)** are what v3 later spent on `borrowCap`
  boundaries and the eMode category, which is why v3's map looks like a
  continuation rather than a redesign.

## 2.5 `UserConfiguration` — 2 bits per reserve

`aave/v2-protocol/contracts/protocol/libraries/configuration/UserConfiguration.sol`.
One `uint256` per user describes their relationship to all 128 possible
reserves:

```
   reserve id:      2         1         0
                 +----+----+ +----+----+ +----+----+
                 | C  | B  | | C  | B  | | C  | B  |     C = using as collateral
                 +----+----+ +----+----+ +----+----+     B = borrowing
   bit index:      5    4      3    2      1    0
```

Reserve `i` owns bits `2i` (borrowing) and `2i+1` (collateral).

| Function | Line | Expression | Note |
|---|---:|---|---|
| `setBorrowing(self, i, bool)` | `:22` | `(data & ~(1 << 2i)) \| (b << 2i)` | Clear then set |
| `setUsingAsCollateral(self, i, bool)` | `:39` | `(data & ~(1 << (2i+1))) \| (b << (2i+1))` | |
| `isUsingAsCollateralOrBorrowing(self, i)` | `:56` | `(data >> 2i) & 3 != 0` | Both bits at once |
| `isBorrowing(self, i)` | `:70` | `(data >> 2i) & 1 != 0` | |
| `isUsingAsCollateral(self, i)` | `:85` | `(data >> (2i+1)) & 1 != 0` | |
| `isBorrowingAny(self)` | `:99` | `data & BORROWING_MASK != 0` | |
| `isEmpty(self)` | `:108` | `data == 0` | |

`BORROWING_MASK` (`:13`) is `0x5555…5555` — every even bit set — so
`isBorrowingAny` answers "does this user have *any* debt?" in one AND. `isEmpty`
answers "can I skip this user's whole loop?" in one comparison.

- **Why this matters for gas.** `GenericLogic.calculateUserAccountData` loops
  over every listed reserve, and the health-factor check runs on nearly every
  action. These two constant-time early exits are what keep an unused reserve
  from costing an SLOAD per user per action.
- **Gotcha.** The bit position is `reserve.id`, assigned at listing time from
  `_reservesCount` and **never reused**. `LendingPoolConfigurator` has no
  `dropReserve`, so a delisted reserve permanently burns its two bits. v3 added
  `dropReserve` and with it the requirement that the reserve be completely
  empty first.

## 2.6 `ReserveLogic`

`aave/v2-protocol/contracts/protocol/libraries/logic/ReserveLogic.sol`. The
interest engine. Everything that changes a reserve's balance calls
`updateState()` first and `updateInterestRates()` last; this library is what
sits between those two bookends.

### `event ReserveDataUpdated(...)` (`:38-45`)

`(address indexed asset, uint256 liquidityRate, uint256 stableBorrowRate,
uint256 variableBorrowRate, uint256 liquidityIndex, uint256
variableBorrowIndex)`. Emitted by `updateInterestRates` only — the single event
an indexer needs to reconstruct a reserve's rate history. Note it is emitted
*after* the indexes were written by `updateState`, so the indexes in the event
are always the fresh ones.

### `getNormalizedIncome(reserve) internal view returns (uint256)` (`:57-77`)

- **Purpose.** The liquidity index *as of now*, without writing storage. This is
  the multiplier `AToken.balanceOf` uses.
- **Checks.** None.
- **State writes.** None (`view`).
- **Body.** If `reserve.lastUpdateTimestamp == block.timestamp` it returns the
  stored index unchanged (`:65-68`) — the index was already accrued this block.
  Otherwise it returns
  `calculateLinearInterest(currentLiquidityRate, timestamp).rayMul(liquidityIndex)`.
- **Returns.** Ray. `1e27` means no income has ever accrued.
- **Called by.** `LendingPool.getReserveNormalizedIncome`, `AToken.balanceOf`,
  `AToken.totalSupply`, `AToken.transfer`, `GenericLogic`, the data providers.
- **Gotcha.** This is a *projection* using the rate captured at the last update.
  If utilization changed since, the projection is still based on the stale rate
  — which is correct, because the rate genuinely was that value for the whole
  elapsed interval. No action can change a rate without first calling
  `updateState`.

### `getNormalizedDebt(reserve) internal view returns (uint256)` (`:85-105`)

Identical in shape, but uses `calculateCompoundedInterest` against
`currentVariableBorrowRate` and `variableBorrowIndex`. Same same-block short
circuit at `:93-96`.

### `updateState(reserve) internal` (`:110-141`)

- **Purpose.** Accrue both indexes to now, then hand the reserve factor's share
  of the newly accrued debt to the treasury. **This is the first line of every
  state-changing pool action.**
- **Parameters.** The reserve storage pointer only.
- **Checks.** None directly; the overflow `require`s live in the two callees.
- **Body, in order:**
  1. Read `scaledVariableDebt = IVariableDebtToken.scaledTotalSupply()` (`:111`).
  2. Cache `previousVariableBorrowIndex`, `previousLiquidityIndex`,
     `lastUpdatedTimestamp` (`:113-115`).
  3. `_updateIndexes(...)` → new indexes, and `lastUpdateTimestamp = now`.
  4. `_mintToTreasury(...)` using **both** the previous and new indexes.
- **External calls.** One `staticcall` to the variable debt token, plus whatever
  the two internal helpers make.
- **Returns / events.** Nothing. `ReserveDataUpdated` comes later, from
  `updateInterestRates`.
- **Gotcha — ordering is load-bearing.** The previous indexes must be captured
  *before* `_updateIndexes` overwrites them, because `_mintToTreasury` computes
  accrued debt as the difference between debt-at-new-index and
  debt-at-old-index. Reordering these two calls silently mints zero to the
  treasury forever.

### `cumulateToLiquidityIndex(reserve, totalLiquidity, amount) internal` (`:143-158`)

- **Purpose.** Distribute a lump sum to *all current suppliers at once* by
  ratcheting the liquidity index, rather than minting aTokens to anyone.
- **Parameters.** `totalLiquidity` is the aToken total supply before the
  distribution; `amount` is the windfall.
- **Body.**
  ```solidity
  uint256 amountToLiquidityRatio = amount.wadToRay().rayDiv(totalLiquidity.wadToRay());
  uint256 result = amountToLiquidityRatio.add(WadRayMath.ray());
  result = result.rayMul(reserve.liquidityIndex);
  require(result <= type(uint128).max, Errors.RL_LIQUIDITY_INDEX_OVERFLOW);
  reserve.liquidityIndex = uint128(result);
  ```
  i.e. `index *= (1 + amount/totalLiquidity)`.
- **State writes.** `reserve.liquidityIndex`.
- **Called by.** `LendingPool.flashLoan`
  (`aave/v2-protocol/contracts/protocol/lendingpool/LendingPool.sol:523`) to
  spread the flash-loan premium, and nothing else.
- **Gotcha.** Every existing holder is diluted *upward* proportionally. Someone
  who deposits one block later gets none of it. This is also the only place in
  v2 where the liquidity index moves for a reason other than elapsed time.
- **Gotcha.** `totalLiquidity` of zero would divide by zero; the flash loan path
  cannot reach it because a flash loan requires liquidity to exist.

### `init(reserve, aToken, stableDebt, variableDebt, strategy) external` (`:164-179`)

- **Purpose.** First-time setup of a reserve.
- **Checks.** `require(reserve.aTokenAddress == address(0),
  Errors.RL_RESERVE_ALREADY_INITIALIZED)` (`:171`) — listing is one-shot.
- **State writes.** Both indexes set to `1e27` (`:173-174`), the four addresses
  stored (`:175-178`).
- **Access.** Reachable only through `LendingPool.initReserve`, which is
  `onlyLendingPoolConfigurator`.
- **Gotcha.** Declared `external`, not `internal`, so it is a genuine
  `delegatecall` into the linked library rather than inlined code. That is
  deliberate: it runs once per reserve and keeping it out of `LendingPool`'s
  bytecode saves deployed size on the hot path.

### `updateInterestRates(reserve, reserveAddress, aTokenAddress, liquidityAdded, liquidityTaken) internal` (`:198-249`)

- **Purpose.** Recompute all three rates after a balance change. **The last line
  of every state-changing action.**
- **Parameters.** `liquidityAdded` / `liquidityTaken` describe the change that
  is *about to* or *has just* happened, so the strategy prices the post-action
  utilization. Exactly one is non-zero in practice.
- **Body, in order:**
  1. `(totalStableDebt, avgStableRate) = IStableDebtToken.getTotalSupplyAndAvgRate()` (`:210`).
  2. `totalVariableDebt = IVariableDebtToken.scaledTotalSupply().rayMul(reserve.variableBorrowIndex)` (`:216`).
     The comment at `:213-215` explains why: `scaledTotalSupply` is one SLOAD
     versus `totalSupply()`'s recomputation, and the index is already fresh
     because `updateState` ran first.
  3. `IReserveInterestRateStrategy.calculateInterestRates(...)` with eight
     arguments including `reserve.configuration.getReserveFactor()` (`:222-232`).
  4. Three `require`s that each rate fits `uint128`:
     `RL_LIQUIDITY_RATE_OVERFLOW`, `RL_STABLE_BORROW_RATE_OVERFLOW`,
     `RL_VARIABLE_BORROW_RATE_OVERFLOW` (`:233-235`).
  5. Write all three rates (`:237-239`), emit `ReserveDataUpdated` (`:241-248`).
- **External calls.** Stable debt token, variable debt token, rate strategy.
- **Gotcha.** `UpdateInterestRatesLocalVars` (`:181-190`) exists purely to dodge
  "stack too deep". The same pattern recurs in `_mintToTreasury`,
  `GenericLogic`, `LendingPool` and the collateral manager — a v2 house style.
- **Gotcha.** The strategy is called with the aToken address so it can read
  `availableLiquidity` as the aToken's own underlying balance. That is why
  donating tokens directly to an aToken lowers the utilization ratio and hence
  everyone's borrow rate. v3 replaced this with an explicit
  `virtualUnderlyingBalance` for exactly this reason.

### `_mintToTreasury(reserve, scaledVariableDebt, previousVariableBorrowIndex, newLiquidityIndex, newVariableBorrowIndex, timestamp) internal` (`:274-324`)

- **Purpose.** Mint the reserve factor's cut of newly accrued interest to the
  treasury, as aTokens.
- **Early exit.** `if (reserveFactor == 0) return;` (`:285-287`) — most reserves
  in the original deployment had a zero factor, so this saves the whole path.
- **Body.**
  1. `getSupplyData()` returns `(principalStableDebt, currentStableDebt,
     avgStableRate, stableSupplyUpdatedTimestamp)` (`:290-296`).
  2. `previousVariableDebt = scaledVariableDebt.rayMul(previousVariableBorrowIndex)` (`:299`).
  3. `currentVariableDebt = scaledVariableDebt.rayMul(newVariableBorrowIndex)` (`:302`).
  4. `cumulatedStableInterest = calculateCompoundedInterest(avgStableRate,
     stableSupplyUpdatedTimestamp, timestamp)` (`:305-309`), then
     `previousStableDebt = principalStableDebt.rayMul(cumulatedStableInterest)` (`:311`).
  5. ```
     totalDebtAccrued = currentVariableDebt + currentStableDebt
                      - previousVariableDebt - previousStableDebt
     ```
     (`:314-318`).
  6. `amountToMint = totalDebtAccrued.percentMul(reserveFactor)` (`:320`); if
     non-zero, `IAToken.mintToTreasury(amountToMint, newLiquidityIndex)` (`:323`).
- **External calls.** Stable debt token (`getSupplyData`), aToken
  (`mintToTreasury`).
- **Gotcha — the stable side is reconstructed, not read.** `currentStableDebt`
  comes straight from the token, but `previousStableDebt` must be *recomputed*
  by compounding the principal forward to `timestamp`, because the stable token
  keeps only a principal and its own timestamp. This is why
  `stableSupplyUpdatedTimestamp` is returned at all.
- **Gotcha.** The treasury receives *aTokens*, not underlying, minted against
  `newLiquidityIndex`. The protocol's fee therefore earns supply interest from
  the moment it is taken.

### `_updateIndexes(reserve, scaledVariableDebt, liquidityIndex, variableBorrowIndex, timestamp) internal returns (uint256, uint256)` (`:334-370`)

- **Purpose.** Advance both indexes to `block.timestamp`.
- **Body.**
  - Guard `if (currentLiquidityRate > 0)` (`:346`). With no supply rate there is
    no income to accrue and both indexes stay put.
  - Liquidity: `newLiquidityIndex = calculateLinearInterest(rate,
    timestamp).rayMul(liquidityIndex)`, `require(<= type(uint128).max,
    RL_LIQUIDITY_INDEX_OVERFLOW)`, store (`:347-352`).
  - Variable: nested guard `if (scaledVariableDebt != 0)` (`:356`), then
    `calculateCompoundedInterest(currentVariableBorrowRate, timestamp)`,
    `require(<= type(uint128).max, RL_VARIABLE_BORROW_INDEX_OVERFLOW)`, store
    (`:357-364`).
  - Unconditionally `reserve.lastUpdateTimestamp = uint40(block.timestamp)` (`:368`).
- **Returns.** `(newLiquidityIndex, newVariableBorrowIndex)` for
  `_mintToTreasury` to use without re-reading storage.
- **Gotcha — the nested guard.** The comment at `:354-355` explains it: the
  liquidity rate can be entirely produced by *stable* borrowers, in which case
  there is income to distribute but no variable debt to index. Advancing
  `variableBorrowIndex` then would charge interest to variable borrowers who do
  not exist yet, and the first one to appear would inherit it.
- **Gotcha.** The timestamp is written even when both indexes are frozen, which
  is what makes the `> 0` guard safe: the skipped interval can never be
  re-accrued later.

## 2.7 `GenericLogic`

`aave/v2-protocol/contracts/protocol/libraries/logic/GenericLogic.sol`. Answers
one question — "is this user solvent?" — and two derived ones.

`HEALTH_FACTOR_LIQUIDATION_THRESHOLD = 1 ether` (`:28`), i.e. `1e18`. Health
factor is a **wad**, so `1e18` means exactly 1.0.

### `balanceDecreaseAllowed(asset, user, amount, reservesData, userConfig, reserves, reservesCount, oracle) internal view returns (bool)` (`:55-116`)

- **Purpose.** May this user lose `amount` of `asset` collateral and still be
  solvent? Used for withdrawals and aToken transfers.
- **Fast paths, in order:**
  - `if (!userConfig.isBorrowingAny() || !userConfig.isUsingAsCollateral(reserve.id)) return true;`
    — no debt at all, or this asset is not collateral, so nothing can break.
  - After computing account data, `if (vars.totalDebtInETH == 0) return true;`.
- **Body.** Reads the reserve's liquidation threshold and decimals via
  `getParams()`, calls `calculateUserAccountData`, converts `amount` to ETH with
  the oracle, then recomputes the health factor with collateral and the weighted
  threshold both reduced by the withdrawn amount, and compares against
  `HEALTH_FACTOR_LIQUIDATION_THRESHOLD`.
- **Returns.** `true` if the post-withdrawal health factor is still `>= 1e18`.
- **Called by.** `ValidationLogic.validateWithdraw`, `ValidationLogic.validateTransfer`.
- **Gotcha.** It recomputes the *weighted average* threshold after removal, not
  just the collateral total. Removing high-threshold collateral hurts twice:
  the numerator shrinks and the average threshold falls.

### `calculateUserAccountData(user, reservesData, userConfig, reserves, reservesCount, oracle) internal view returns (uint256,uint256,uint256,uint256,uint256)` (`:150-232`)

- **Purpose.** The whole-account aggregation. Returns
  `(totalCollateralETH, totalDebtETH, avgLtv, avgLiquidationThreshold, healthFactor)`.
- **Fast path.** `if (userConfig.isEmpty()) return (0, 0, 0, 0, uint256(-1));`
  (`:170-172`) — an untouched account is infinitely healthy for free.
- **The loop** (`:173-214`), once per listed reserve:
  1. `if (!userConfig.isUsingAsCollateralOrBorrowing(i)) continue;` — one shift
     and mask, no SLOAD, for reserves the user never touched.
  2. `(ltv, liquidationThreshold, , decimals, ) = configuration.getParams()`.
  3. `tokenUnit = 10**decimals`, `reserveUnitPrice = oracle.getAssetPrice(asset)`.
  4. **Collateral leg**, if `liquidationThreshold != 0 && isUsingAsCollateral(i)`:
     ```solidity
     vars.compoundedLiquidityBalance = IERC20(currentReserve.aTokenAddress).balanceOf(user);
     uint256 liquidityBalanceETH =
       vars.reserveUnitPrice.mul(vars.compoundedLiquidityBalance).div(vars.tokenUnit);
     vars.totalCollateralInETH = vars.totalCollateralInETH.add(liquidityBalanceETH);
     vars.avgLtv = vars.avgLtv.add(liquidityBalanceETH.mul(vars.ltv));
     vars.avgLiquidationThreshold = vars.avgLiquidationThreshold.add(
       liquidityBalanceETH.mul(vars.liquidationThreshold)
     );
     ```
     The two averages accumulate **value-weighted sums**, divided down later.
  5. **Debt leg**, if `isBorrowing(i)`: `stableDebtToken.balanceOf(user) +
     variableDebtToken.balanceOf(user)`, converted to ETH and added to
     `totalDebtInETH`.
- **After the loop** (`:216-232`): divide both weighted sums by
  `totalCollateralInETH` (guarded against zero), then
  `calculateHealthFactorFromBalances`.
- **External calls.** Per participating reserve: one oracle call and one to
  three `balanceOf` calls. This is the protocol's dominant gas cost.
- **Gotcha — the `liquidationThreshold != 0` test.** A reserve whose threshold
  was set to zero (risk admin disabling it as collateral) stops counting as
  collateral for *existing* positions immediately, without any user action.
- **Gotcha — "ETH" is nominal.** The unit is whatever the oracle's base
  currency is. On the original Ethereum market that was ETH; later markets used
  USD. The variable names never caught up, and v3 renamed them to `...InBaseCurrency`.
- **Gotcha.** `balanceOf` on the aToken is the *rebased* balance, so this
  function sees accrued interest even if no index write has happened this block
  — because `AToken.balanceOf` itself calls `getNormalizedIncome`.

### `calculateHealthFactorFromBalances(totalCollateralInETH, totalDebtInETH, liquidationThreshold) internal pure returns (uint256)` (`:242-250`)

```solidity
if (totalDebtInETH == 0) return uint256(-1);
return (totalCollateralInETH.percentMul(liquidationThreshold)).wadDiv(totalDebtInETH);
```

`HF = (collateral × threshold_bps / 1e4) × 1e18 / debt`. No debt returns
`type(uint256).max`, which every caller treats as "infinitely safe".

### `calculateAvailableBorrowsETH(totalCollateralInETH, totalDebtInETH, ltv) internal pure returns (uint256)` (`:261-274`)

`collateral × ltv − debt`, floored at zero (`:269-271`). Note it uses **LTV**,
not the liquidation threshold: borrowing power is strictly tighter than
solvency, and the gap between the two is the buffer a healthy position lives in.

- **Gotcha.** Both helpers are `public constant`/`pure` on a library that
  `LendingPool` links against, so `HEALTH_FACTOR_LIQUIDATION_THRESHOLD` is
  readable on-chain from the deployed `GenericLogic` address.

## 2.8 `ValidationLogic`

`aave/v2-protocol/contracts/protocol/libraries/logic/ValidationLogic.sol`. Every
precondition in the protocol, one function per action. `LendingPool` calls
these before touching state, so a revert here costs only the checks.

Two constants govern stable-rate rebalancing:
`REBALANCE_UP_LIQUIDITY_RATE_THRESHOLD = 4000` (40% in bps, `:33`) and
`REBALANCE_UP_USAGE_RATIO_THRESHOLD = 0.95 * 1e27` (95% in ray, `:34`).

| Function | Line | Guards |
|---|---:|---|
| `validateDeposit(reserve, amount)` | `:41` | `amount != 0` → `VL_INVALID_AMOUNT`; reserve active → `VL_NO_ACTIVE_RESERVE`; not frozen → `VL_RESERVE_FROZEN` |
| `validateWithdraw(...)` | `:60` | `amount != 0`; `amount <= userBalance` → `VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE`; active; `balanceDecreaseAllowed` → `VL_TRANSFER_NOT_ALLOWED` |
| `validateBorrow(...)` | `:120` | see below |
| `validateRepay(...)` | `:223` | active; `amount != 0`; debt exists in the chosen mode → `VL_NO_DEBT_OF_SELECTED_TYPE`; `amount != uint(-1) \|\| msg.sender == onBehalfOf` → `VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF` |
| `validateSwapRateMode(...)` | `:259` | active; not frozen; debt exists in the *current* mode; when switching **to** stable, the same stable-rate rules as borrowing |
| `validateRebalanceStableBorrowRate(...)` | `:303` | active; the two threshold conditions below, else `VL_INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET` |
| `validateSetUseReserveAsCollateral(...)` | `:344` | `underlyingBalance > 0` → `VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0`; `balanceDecreaseAllowed` when disabling → `VL_DEPOSIT_ALREADY_IN_USE` |
| `validateFlashloan(assets, amounts)` | `:379` | `assets.length == amounts.length` → `VL_INCONSISTENT_FLASHLOAN_PARAMS` |
| `validateLiquidationCall(...)` | `:392` | see [2.11](#211-lendingpoolcollateralmanager) |
| `validateTransfer(from, ...)` | `:446` | health factor `>= 1e18` → `VL_TRANSFER_NOT_ALLOWED` |

### `validateBorrow` (`:120-221`) in detail

The densest validator in the protocol. In order:

1. Reserve `isActive` → `VL_NO_ACTIVE_RESERVE`; `!isFrozen` → `VL_RESERVE_FROZEN`.
2. `amount != 0` → `VL_INVALID_AMOUNT`.
3. `borrowingEnabled` → `VL_BORROWING_NOT_ENABLED`.
4. Mode is `STABLE` or `VARIABLE` → `VL_INVALID_INTEREST_RATE_MODE_SELECTED`.
5. `calculateUserAccountData` → collateral, debt, ltv, threshold, health factor.
6. `userCollateralBalanceETH > 0` → `VL_COLLATERAL_BALANCE_IS_0`.
7. `healthFactor > HEALTH_FACTOR_LIQUIDATION_THRESHOLD` →
   `VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD`.
8. Convert the requested amount to ETH, add to existing debt, and require it
   `<= availableBorrowsETH` → `VL_COLLATERAL_CANNOT_COVER_NEW_BORROW`.
9. **Stable-rate only:**
   - `stableRateBorrowingEnabled` → `VL_STABLE_BORROWING_NOT_ENABLED`.
   - The user must not be using *this same asset* as collateral, or must have an
     aToken balance smaller than the amount borrowed →
     `VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY`.
   - `amount <= availableLiquidity × maxStableLoanPercent` →
     `VL_AMOUNT_BIGGER_THAN_MAX_LOAN_SIZE_STABLE`.

- **Gotcha — step 9's second rule.** Without it a user could deposit USDC, borrow
  USDC at a fixed stable rate, redeposit, and repeat, locking in a spread
  against the pool at zero risk. The rule breaks the loop at the first hop.
- **Gotcha — step 7 uses strict `>`.** A position sitting exactly at `1e18`
  cannot borrow, though it also cannot yet be liquidated (liquidation uses `<`).

### `validateRebalanceStableBorrowRate` (`:303-342`)

Anyone may force another user's stable rate to be re-set, but only when the
reserve has drifted far from the assumptions under which that rate was granted.
Both conditions must hold:

- `totalDebt / (availableLiquidity + totalDebt) >= 0.95e27` — utilization above
  95%, so liquidity is scarce; **and**
- `currentLiquidityRate <= maxVariableBorrowRate.percentMul(4000)` — the supply
  rate is below 40% of the maximum variable rate, meaning old stable borrowers
  are paying far less than current conditions justify.

Otherwise `VL_INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET`.

- **Gotcha.** This is v2's answer to v1's identical problem: stable rates are
  only "stable" until the reserve is stressed. The permissionless rebalance is
  what keeps a stable borrower from holding a below-market rate forever. v3.2
  removed stable borrowing entirely rather than keep patching this.

## 2.9 `Helpers`

`aave/v2-protocol/contracts/protocol/libraries/helpers/Helpers.sol`. Two
functions, one job: fetch both debt balances at once.

### `getUserCurrentDebt(user, reserve) internal view returns (uint256, uint256)` (`:18-27`)

Returns `(stableDebt, variableDebt)` as
`IERC20(reserve.stableDebtTokenAddress).balanceOf(user)` and
`IERC20(reserve.variableDebtTokenAddress).balanceOf(user)`.

### `getUserCurrentDebtMemory(user, reserve) internal view returns (uint256, uint256)` (`:29-38`)

Identical, but takes `DataTypes.ReserveData memory`. The duplication exists
because Solidity 0.6 cannot overload on the data location of a struct parameter
through a `using ... for` binding, and `LendingPoolCollateralManager` works with
a memory copy.

## 2.10 `LendingPool`

`aave/v2-protocol/contracts/protocol/lendingpool/LendingPool.sol` (946 lines).
The single entry point. It holds no funds, does no arithmetic beyond an oracle
conversion, and mostly sequences four steps: **validate → `updateState` →
mint/burn tokens → `updateInterestRates`**.

`LENDINGPOOL_REVISION = 0x2` (`:52`), returned by `getRevision()` (`:75`) for
`VersionedInitializable`.

### Modifiers

| Modifier | Line | Effect |
|---|---:|---|
| `whenNotPaused` | `:54` | Calls `_whenNotPaused()` (`:64`): `require(!_paused, Errors.LP_IS_PAUSED)` |
| `onlyLendingPoolConfigurator` | `:59` | `_onlyLendingPoolConfigurator()` (`:68`): sender must equal `_addressesProvider.getLendingPoolConfigurator()`, else `Errors.LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR` |

- **Gotcha.** The bodies are separate `internal` functions rather than inline
  modifier code. Modifiers are inlined at every use site; a function is a single
  `JUMP`. With a dozen guarded functions this measurably shrinks bytecode — the
  same size pressure that forced the library split.

### `initialize(ILendingPoolAddressesProvider provider) public initializer` (`:86-91`)

Sets `_addressesProvider`, `_maxStableRateBorrowSizePercent = 2500` (25%),
`_flashLoanPremiumTotal = 9` (0.09%), `_maxNumberOfReserves = 128`. Guarded by
`VersionedInitializable.initializer`.

### `deposit(asset, amount, onBehalfOf, referralCode) external whenNotPaused` (`:104-129`)

- **Checks.** `ValidationLogic.validateDeposit(reserve, amount)`.
- **Body, in order:**
  ```solidity
  reserve.updateState();
  reserve.updateInterestRates(asset, aToken, amount, 0);
  IERC20(asset).safeTransferFrom(msg.sender, aToken, amount);
  bool isFirstDeposit = IAToken(aToken).mint(onBehalfOf, amount, reserve.liquidityIndex);
  if (isFirstDeposit) {
    _usersConfig[onBehalfOf].setUsingAsCollateral(reserve.id, true);
    emit ReserveUsedAsCollateralEnabled(asset, onBehalfOf);
  }
  ```
- **External calls.** Underlying `transferFrom` (sender → aToken), then
  `AToken.mint`.
- **Events.** `Deposit(asset, msg.sender, onBehalfOf, amount, referralCode)`,
  optionally `ReserveUsedAsCollateralEnabled`.
- **Gotcha — auto-collateral.** The *first* deposit of an asset silently enables
  it as collateral. Subsequent deposits do not re-enable it, so a user who
  deliberately disabled an asset keeps it disabled when topping up.
- **Gotcha — the underlying goes straight to the aToken**, never through the
  pool. `LendingPool` is never a token custodian, which is the central
  difference from v1's `LendingPoolCore`.

### `withdraw(asset, amount, to) external whenNotPaused returns (uint256)` (`:142-190`)

- **Max handling.** `amount == type(uint256).max` becomes the caller's full
  aToken balance (`:157-159`).
- **Checks.** `ValidationLogic.validateWithdraw(...)` — includes the
  `balanceDecreaseAllowed` solvency test.
- **Body.** `updateState()` → `updateInterestRates(asset, aToken, 0,
  amountToWithdraw)` → if withdrawing the entire balance, clear the collateral
  bit and emit `ReserveUsedAsCollateralDisabled` → `IAToken.burn(msg.sender, to,
  amountToWithdraw, reserve.liquidityIndex)`.
- **Returns.** `amountToWithdraw`.
- **Events.** `Withdraw(asset, msg.sender, to, amount)`.
- **Gotcha.** The collateral bit is cleared *before* the burn, so the
  `ReserveUsedAsCollateralDisabled` event precedes the transfer in the log
  ordering.

### `borrow(asset, amount, interestRateMode, referralCode, onBehalfOf) external whenNotPaused` (`:201-215`)

Packs its arguments into `ExecuteBorrowParams` (`:844-853`) with
`releaseUnderlying = true` and delegates to `_executeBorrow`. The `aTokenAddress`
is read from the reserve here so `_executeBorrow` need not.

- **Credit delegation.** `onBehalfOf` may differ from `msg.sender`; the debt
  token's `mint` is what enforces the allowance (see
  [2.13](#213-tokenization)).

### `_executeBorrow(ExecuteBorrowParams memory vars) internal` (`:855-929`)

- **Body, in order:**
  1. `amountInETH = oracle.getAssetPrice(asset) * amount / 10**decimals` (`:861-864`).
  2. `ValidationLogic.validateBorrow(...)` with twelve arguments (`:866-879`).
  3. `reserve.updateState()`.
  4. Mint debt. Stable branch captures `currentStableRate =
     reserve.currentStableBorrowRate` first, then
     `IStableDebtToken.mint(user, onBehalfOf, amount, currentStableRate)`.
     Variable branch calls `IVariableDebtToken.mint(user, onBehalfOf, amount,
     reserve.variableBorrowIndex)`. Both return `isFirstBorrowing`.
  5. `if (isFirstBorrowing) userConfig.setBorrowing(reserve.id, true);`
  6. `updateInterestRates(asset, aTokenAddress, 0, releaseUnderlying ? amount : 0)`.
  7. `if (releaseUnderlying) IAToken.transferUnderlyingTo(user, amount);`
- **Events.** `Borrow(asset, user, onBehalfOf, amount, interestRateMode, rate,
  referralCode)` where `rate` is the stable rate just locked in or the reserve's
  current variable rate.
- **Gotcha — `releaseUnderlying`.** `false` only in the flash-loan mode-1/2 path,
  where the borrower already holds the funds. The flag also removes the amount
  from `liquidityTaken` in step 6, because the aToken's balance was already
  reduced when the flash loan was dispensed.

### `repay(asset, amount, rateMode, onBehalfOf) external whenNotPaused returns (uint256)` (`:236-289`)

- **Body.** `Helpers.getUserCurrentDebt` → `validateRepay` → clamp
  `paybackAmount` to the debt in the chosen mode, then to `amount` if smaller →
  `updateState()` → burn from the stable or variable debt token →
  `updateInterestRates(asset, aToken, paybackAmount, 0)` → if total debt now
  zero, `setBorrowing(reserve.id, false)` → `safeTransferFrom(msg.sender, aToken,
  paybackAmount)` → `IAToken.handleRepayment(msg.sender, paybackAmount)`.
- **Returns.** `paybackAmount`.
- **Events.** `Repay(asset, onBehalfOf, msg.sender, paybackAmount)`.
- **Gotcha.** Repaying `type(uint256).max` clears the whole debt of that mode,
  but `validateRepay` forbids it when `onBehalfOf != msg.sender`
  (`VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF`) — otherwise a griefer could drain
  an approving wallet by repaying someone else's unbounded debt.
- **Gotcha.** `handleRepayment` is a no-op hook in the standard `AToken`
  (`:395`), present so a custom aToken can react. It is called *after* the
  transfer, so the aToken already holds the funds.

### `swapBorrowRateMode(asset, rateMode) external whenNotPaused` (`:297-341`)

Burns the entire debt in the current mode and mints the same amount in the
other, at the reserve's current rate for that mode. `validateSwapRateMode`
re-applies the stable-rate eligibility rules when switching to stable. Emits
`Swap(asset, msg.sender, rateMode)`.

### `rebalanceStableBorrowRate(asset, user) external whenNotPaused` (`:350-378`)

Permissionless. Validates the two stress conditions, burns and re-mints the
user's stable debt at `reserve.currentStableBorrowRate`, and emits
`RebalanceStableBorrowRate(asset, user)`.

### `setUserUseReserveAsCollateral(asset, useAsCollateral) external whenNotPaused` (`:387-417`)

Validates via `validateSetUseReserveAsCollateral`, flips the bit, and emits
`ReserveUsedAsCollateralEnabled` or `...Disabled`.

### `liquidationCall(collateralAsset, debtAsset, user, debtToCover, receiveAToken) external whenNotPaused` (`:425-449`)

```solidity
address collateralManager = _addressesProvider.getLendingPoolCollateralManager();
(bool success, bytes memory result) = collateralManager.delegatecall(
  abi.encodeWithSignature(
    'liquidationCall(address,address,address,uint256,bool)',
    collateralAsset, debtAsset, user, debtToCover, receiveAToken
  )
);
require(success, Errors.LP_LIQUIDATION_CALL_FAILED);
(uint256 returnCode, string memory returnMessage) = abi.decode(result, (uint256, string));
require(returnCode == 0, string(abi.encodePacked(returnMessage)));
```

- **Gotcha — two failure layers.** A reverting `delegatecall` gives
  `LP_LIQUIDATION_CALL_FAILED`; a *successful* call that returns a non-zero code
  re-reverts with the manager's own message. This mirrors v1's
  `LiquidationErrors` enum, and exists because the manager cannot cheaply bubble
  a revert reason through `delegatecall` in Solidity 0.6.
- **Gotcha.** The selector is built with `encodeWithSignature`, a plain string.
  A typo would compile and fail only at runtime.

### `flashLoan(receiverAddress, assets, amounts, modes, onBehalfOf, params, referralCode) external whenNotPaused` (`:483-563`)

- **Checks.** `validateFlashloan(assets, amounts)` — arrays must be equal length.
- **Phase 1** (`:502-508`): for each asset, record the aToken, compute
  `premium = amount * _flashLoanPremiumTotal / 10000`, and
  `transferUnderlyingTo(receiverAddress, amount)`.
- **Callback** (`:510-513`): `require(receiver.executeOperation(assets, amounts,
  premiums, msg.sender, params), Errors.LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN)`.
- **Phase 2** (`:515-562`), per asset, branching on `modes[i]`:
  - `NONE` (0) — repay. `updateState()`, then
    `cumulateToLiquidityIndex(aToken.totalSupply(), premium)` to hand the fee to
    suppliers, then `updateInterestRates(..., amount + premium, 0)`, then
    `safeTransferFrom(receiver, aToken, amount + premium)`.
  - `STABLE` (1) or `VARIABLE` (2) — keep the funds and open debt via
    `_executeBorrow(... releaseUnderlying: false)`.
- **Events.** `FlashLoan(receiver, msg.sender, asset, amount, premium,
  referralCode)` per asset.
- **Gotcha — no reentrancy guard on the pool itself.** Safety comes from the
  balance being pulled back with `safeTransferFrom` at the end. A receiver *can*
  re-enter `LendingPool` during `executeOperation`; that is the whole point, and
  it is what the adapters in [2.17](#217-adapters--flash-loan-powered-position-management) rely on.
- **Gotcha — mode 1/2 opens debt against `onBehalfOf`**, so a flash loan can
  create a debt position for a third party who has granted credit delegation.
  v1 had no equivalent.
- **Gotcha.** `cumulateToLiquidityIndex` reads `aToken.totalSupply()` *after*
  `updateState`, so the index ratchet is computed against the post-accrual
  supply. Doing it in the other order would over-distribute.

### Admin functions

| Function | Line | Access | Effect |
|---|---:|---|---|
| `initReserve(asset, aToken, stableDebt, variableDebt, strategy)` | `:785` | configurator | `reserve.init(...)`, then `_addReserveToList(asset)` |
| `setReserveInterestRateStrategyAddress(asset, strategy)` | `:808` | configurator | Swap the rate strategy |
| `setConfiguration(asset, configuration)` | `:822` | configurator | Write the whole 256-bit risk word |
| `setPause(bool)` | `:835` | configurator | Global stop; emits `Paused`/`Unpaused` |

`_addReserveToList(asset)` (`:932-946`) requires
`reservesCount < _maxNumberOfReserves` (`LP_NO_MORE_RESERVES_ALLOWED`), assigns
`reserve.id = uint8(reservesCount)`, appends to `_reservesList`, and increments
the count. It is idempotent: a reserve already in the list is skipped.

### `finalizeTransfer(asset, from, to, amount, balanceFromBefore, balanceToBefore) external whenNotPaused` (`:739-778`)

- **Access.** `require(msg.sender == reserve.aTokenAddress,
  Errors.LP_CALLER_MUST_BE_AN_ATOKEN)`.
- **Body.** `ValidationLogic.validateTransfer(from, ...)` — the sender must stay
  solvent. Then, if `from != to`: if `balanceFromBefore - amount == 0`, clear
  `from`'s collateral bit and emit `ReserveUsedAsCollateralDisabled`; if
  `balanceToBefore == 0 && amount != 0`, set `to`'s collateral bit and emit
  `ReserveUsedAsCollateralEnabled`.
- **Gotcha.** Receiving an aToken transfer silently turns that asset into
  collateral for the recipient, exactly as a first deposit does. Sending someone
  aTokens therefore changes their risk profile without their consent — harmless
  in itself, since it only ever adds collateral.

### View functions

| Function | Line | Returns |
|---|---:|---|
| `getReserveData(asset)` | `:571` | The whole `ReserveData` struct |
| `getUserAccountData(user)` | `:590` | `(totalCollateralETH, totalDebtETH, availableBorrowsETH, currentLiquidationThreshold, ltv, healthFactor)` |
| `getConfiguration(asset)` | `:630` | `ReserveConfigurationMap` |
| `getUserConfiguration(user)` | `:644` | `UserConfigurationMap` |
| `getReserveNormalizedIncome(asset)` | `:658` | Projected liquidity index |
| `getReserveNormalizedVariableDebt(asset)` | `:673` | Projected variable borrow index |
| `paused()` | `:685` | `_paused` |
| `getReservesList()` | `:692` | Materialises `_reservesList` into an array |
| `getAddressesProvider()` | `:704` | The provider |
| `MAX_STABLE_RATE_BORROW_SIZE_PERCENT()` | `:711` | `2500` |
| `FLASHLOAN_PREMIUM_TOTAL()` | `:718` | `9` |
| `MAX_NUMBER_RESERVES()` | `:725` | `128` |

## 2.11 `LendingPoolCollateralManager`

`aave/v2-protocol/contracts/protocol/lendingpool/LendingPoolCollateralManager.sol`
(317 lines). Reached only through `LendingPool.liquidationCall`'s `delegatecall`,
so it executes **in `LendingPool`'s storage context**. It inherits
`LendingPoolStorage` and `VersionedInitializable` so the slot layout matches
exactly.

`LIQUIDATION_CLOSE_FACTOR_PERCENT = 5000` (`:39`) — at most 50% of a borrower's
debt in one call.

`getRevision()` (`:66`) returns `0x1` with a comment explaining the value is
irrelevant, because `initialize` is never called on this contract — it has no
proxy of its own.

### `liquidationCall(collateralAsset, debtAsset, user, debtToCover, receiveAToken) external returns (uint256, string memory)` (`:81-197`)

Returns a `(code, message)` pair instead of reverting, which `LendingPool`
decodes and re-reverts on.

- **Step 1 — health factor.** `GenericLogic.calculateUserAccountData(...)`
  (`:94`), keeping only `healthFactor`.
- **Step 2 — debts.** `Helpers.getUserCurrentDebt(user, debtReserve)` (`:103`).
- **Step 3 — validate.** `ValidationLogic.validateLiquidationCall(...)` (`:105`)
  returns an error code; if non-zero the function returns early (`:114-116`).
  The codes come from `Errors.CollateralManagerErrors`.
- **Step 4 — close factor.**
  ```solidity
  vars.maxLiquidatableDebt = vars.userStableDebt.add(vars.userVariableDebt).percentMul(
    LIQUIDATION_CLOSE_FACTOR_PERCENT
  );
  vars.actualDebtToLiquidate = debtToCover > vars.maxLiquidatableDebt
    ? vars.maxLiquidatableDebt
    : debtToCover;
  ```
- **Step 5 — collateral.** `_calculateAvailableCollateralToLiquidate(...)`
  returns `(maxCollateralToLiquidate, debtAmountNeeded)`. If the borrower does
  not hold enough collateral, `debtAmountNeeded < actualDebtToLiquidate` and the
  debt figure is revised down (`:146-148`).
- **Step 6 — liquidity check when `receiveAToken == false`** (`:152-160`): the
  aToken's actual underlying balance must cover the seizure, else
  `LP_LIQUIDATION_CALL_FAILED` / `NOT_ENOUGH_LIQUIDITY`.
- **Step 7 — burn debt** (`:164-185`). `debtReserve.updateState()` first, then:
  - If `userVariableDebt >= actualDebtToLiquidate`, burn it all from the
    variable token.
  - Otherwise burn the entire variable debt (if any), then burn
    `actualDebtToLiquidate - userVariableDebt` from the stable token.
- **Step 8 — rates.** `debtReserve.updateInterestRates(debtAsset, aToken,
  actualDebtToLiquidate, 0)`.
- **Step 9 — move collateral** (`:193-218`):
  - `receiveAToken == true`: record the liquidator's prior aToken balance, call
    `collateralAtoken.transferOnLiquidation(user, msg.sender,
    maxCollateralToLiquidate)`, and if the liquidator held none before, set
    their collateral bit and emit `ReserveUsedAsCollateralEnabled`.
  - `receiveAToken == false`: `collateralReserve.updateState()`,
    `updateInterestRates(collateralAsset, aToken, 0, maxCollateralToLiquidate)`,
    then `collateralAtoken.burn(user, msg.sender, maxCollateralToLiquidate,
    collateralReserve.liquidityIndex)`.
- **Step 10 — collateral bit.** If the seizure took the borrower's entire
  balance, clear their collateral bit and emit
  `ReserveUsedAsCollateralDisabled` (`:222-225`).
- **Step 11 — pull the debt payment.** `safeTransferFrom(msg.sender,
  debtReserve.aTokenAddress, actualDebtToLiquidate)`.
- **Event.** `LiquidationCall(collateralAsset, debtAsset, user,
  actualDebtToLiquidate, maxCollateralToLiquidate, msg.sender, receiveAToken)`.
- **Returns.** `(uint256(Errors.CollateralManagerErrors.NO_ERROR), Errors.LPCM_NO_ERRORS)`.

- **Gotcha — variable debt is burned first.** The borrower's cheaper, floating
  debt is retired before their fixed-rate debt. This is not neutral: it leaves
  the borrower holding proportionally more stable debt after a partial
  liquidation.
- **Gotcha — `receiveAToken` skips the liquidity check.** Taking aTokens moves a
  claim, not underlying, so it works even when the reserve is fully utilised.
  That is precisely when liquidations matter most.
- **Gotcha.** The liquidator's payment lands in the aToken at the very end,
  after the collateral has already moved. The `delegatecall` context means a
  revert anywhere unwinds everything, so the ordering is safe.

### `_calculateAvailableCollateralToLiquidate(collateralReserve, debtReserve, collateralAsset, debtAsset, debtToCover, userCollateralBalance) internal view returns (uint256, uint256)` (`:272-317`)

- **Purpose.** Convert a debt amount into the collateral amount to seize,
  applying the liquidation bonus and the borrower's balance ceiling.
- **Body.**
  ```solidity
  vars.collateralPrice = oracle.getAssetPrice(collateralAsset);
  vars.debtAssetPrice = oracle.getAssetPrice(debtAsset);
  (, , vars.liquidationBonus, vars.collateralDecimals, ) =
      collateralReserve.configuration.getParams();
  vars.debtAssetDecimals = debtReserve.configuration.getDecimals();

  vars.maxAmountCollateralToLiquidate = vars.debtAssetPrice
      .mul(debtToCover)
      .mul(10**vars.collateralDecimals)
      .percentMul(vars.liquidationBonus)
      .div(vars.collateralPrice.mul(10**vars.debtAssetDecimals));
  ```
  i.e. `collateral = debt × P_debt / P_coll × bonus`, with the decimal factors
  making the units line up.
- **The ceiling** (`:303-313`): if that exceeds `userCollateralBalance`, the
  collateral is capped at the balance and the *debt* is recomputed backwards
  with `percentDiv(liquidationBonus)` — the exact inverse — so the liquidator is
  never charged for collateral that does not exist.
- **Returns.** `(collateralAmount, debtAmountNeeded)`.
- **Gotcha — the bonus is a multiplier above 100%.** A `liquidationBonus` of
  `10500` means the liquidator receives 105% of the value they repay. The 5%
  spread is their entire profit and the borrower's entire penalty.
- **Gotcha.** Both prices come from the same oracle in the same call, so a stale
  or manipulated feed on either side moves the seizure amount directly. This is
  the protocol's sharpest oracle dependency.

## 2.12 `DefaultReserveInterestRateStrategy` (v2)

`aave/v2-protocol/contracts/protocol/lendingpool/DefaultReserveInterestRateStrategy.sol`
(260 lines). Pure math, no storage beyond immutables set in the constructor.

| Immutable | Meaning |
|---|---|
| `OPTIMAL_UTILIZATION_RATE` | The kink, in ray |
| `EXCESS_UTILIZATION_RATE` | `1e27 − OPTIMAL_UTILIZATION_RATE`, precomputed |
| `_baseVariableBorrowRate` | Rate at 0% utilization |
| `_variableRateSlope1` / `_variableRateSlope2` | Below and above the kink |
| `_stableRateSlope1` / `_stableRateSlope2` | Same, for stable |
| `addressesProvider` | To reach the lending rate oracle |

### `calculateInterestRates(...)` (the 8-argument overload)

- **Inputs.** `reserve`, `aToken`, `liquidityAdded`, `liquidityTaken`,
  `totalStableDebt`, `totalVariableDebt`, `averageStableBorrowRate`,
  `reserveFactor`.
- **Step 1.** `availableLiquidity = IERC20(reserve).balanceOf(aToken) +
  liquidityAdded − liquidityTaken`. The pending action is applied *before*
  pricing, so rates reflect the post-action state.
- **Step 2.** Forward to the internal overload with that figure.

### The internal overload — the kinked curve

```
utilizationRate = totalDebt == 0 ? 0 : totalDebt.rayDiv(availableLiquidity + totalDebt)

if utilizationRate > OPTIMAL:
    excessRatio = (U − OPTIMAL) / EXCESS_UTILIZATION_RATE
    variableRate = base + slope1 + slope2 × excessRatio
    stableRate   = marketRate + stableSlope1 + stableSlope2 × excessRatio
else:
    variableRate = base + slope1 × (U / OPTIMAL)
    stableRate   = marketRate + stableSlope1 × (U / OPTIMAL)
```

`marketRate` comes from `ILendingRateOracle.getMarketBorrowRate(reserve)` — the
stable curve is anchored to an external rate rather than to zero.

### The supply rate

```
overallBorrowRate = weighted average of (totalStableDebt @ avgStableRate)
                    and (totalVariableDebt @ currentVariableRate)

liquidityRate = overallBorrowRate × utilizationRate × (1 − reserveFactor)
```

computed as `.rayMul(utilizationRate).percentMul(PERCENTAGE_FACTOR − reserveFactor)`.

- **The reserve factor appears here and nowhere else in the rate math.** It is
  the wedge between what borrowers pay and what suppliers receive, and the same
  fraction is minted to the treasury by `_mintToTreasury`. Both must use the
  same number or the accounting drifts.
- **Gotcha — `availableLiquidity` is the aToken's raw ERC20 balance.** Anyone can
  donate underlying to an aToken and push utilization down, cutting every
  borrower's rate. Harmless as an attack, expensive as a subsidy, and the reason
  v3 tracks a `virtualUnderlyingBalance` instead.
- **Gotcha — v1 parity.** The shape is identical to v1's
  `DefaultReserveInterestRateStrategy` ([1.8](#18-defaultreserveinterestratestrategy-v1))
  including the weighted overall borrow rate. The only economic addition is the
  reserve factor.

## 2.13 Tokenization

Six contracts in
`aave/v2-protocol/contracts/protocol/tokenization/`. This is the layer that most
distinguishes v2 from v1: supply *and* debt are ERC20s, and the aToken is the
custodian.

```
        IncentivizedERC20 (ERC20 + handleAction hook)
            |                              |
            +-- AToken                     +-- DebtTokenBase (abstract, non-transferable)
            |     |                              |          |
            |     +-- DelegationAwareAToken      |          +-- VariableDebtToken
            |                                    +-- StableDebtToken
```

### `IncentivizedERC20` (`IncentivizedERC20.sol`, 255 lines)

A plain ERC20 with one addition: `_transfer`, `_mint` and `_burn` each call
`_getIncentivesController().handleAction(user, oldTotalSupply, oldBalance)`
before mutating. That is how liquidity mining accrues without a separate
staking step — every balance change is a checkpoint.

The full ERC20 surface is present: `name`, `symbol`, `decimals`, `totalSupply`,
`balanceOf`, `transfer`, `allowance`, `approve`, `transferFrom`,
`increaseAllowance`, `decreaseAllowance`.

- **Gotcha.** `handleAction` receives the balances *before* the change, and the
  controller re-reads current state itself. A controller that reverts bricks
  every transfer of that token, so the address is set once at initialization and
  is not user-settable.

### `AToken` (`AToken.sol`, 406 lines)

Holds the reserve's underlying and represents a supplier's claim. Rebasing:
`balanceOf` grows without transfers.

| Function | Access | Behaviour |
|---|---|---|
| `initialize(...)` | `initializer` | Sets pool, treasury, underlying, incentives controller, name, symbol, decimals |
| `mint(user, amount, index)` | `onlyLendingPool` | `amountScaled = amount.rayDiv(index)`, `require(amountScaled != 0, CT_INVALID_MINT_AMOUNT)`, `_mint(user, amountScaled)`. Returns `previousBalance == 0` |
| `burn(user, receiverOfUnderlying, amount, index)` | `onlyLendingPool` | `amountScaled = amount.rayDiv(index)`, `require(amountScaled != 0, CT_INVALID_BURN_AMOUNT)`, `_burn`, then `safeTransfer(receiverOfUnderlying, amount)` |
| `mintToTreasury(amount, index)` | `onlyLendingPool` | `_mint(RESERVE_TREASURY_ADDRESS, amount.rayDiv(index))`; returns early if `amount == 0` |
| `transferOnLiquidation(from, to, value)` | `onlyLendingPool` | `_transfer(from, to, value, false)` — skips the health check |
| `transferUnderlyingTo(target, amount)` | `onlyLendingPool` | Sends raw underlying; used by borrow and flash loan |
| `handleRepayment(user, amount)` | `onlyLendingPool` | Empty hook for subclasses |
| `balanceOf(user)` | view | `super.balanceOf(user).rayMul(POOL.getReserveNormalizedIncome(underlying))` |
| `scaledBalanceOf(user)` | view | The raw stored balance |
| `getScaledUserBalanceAndSupply(user)` | view | Both at once, for the incentives controller |
| `totalSupply()` | view | `super.totalSupply().rayMul(normalizedIncome)` |
| `scaledTotalSupply()` | view | Raw |
| `permit(...)` | anyone | EIP-2612, with `PERMIT_TYPEHASH` and a cached `DOMAIN_SEPARATOR` |
| `_transfer(from, to, amount, validate)` | internal | See below |

**`_transfer`** reads `index = POOL.getReserveNormalizedIncome(underlying)`,
records both parties' balances *before*, moves `amount.rayDiv(index)` scaled
units, and if `validate` is true calls
`POOL.finalizeTransfer(underlying, from, to, amount, fromBalanceBefore,
toBalanceBefore)`. It emits `BalanceTransfer(from, to, amount, index)` in
addition to the ERC20 `Transfer`.

- **Gotcha — two `Transfer` semantics.** The ERC20 `Transfer` event carries the
  *scaled* amount from `IncentivizedERC20._transfer`, while `BalanceTransfer`
  carries the *underlying* amount plus the index. Indexers that read only
  `Transfer` will under-report aToken movements.
- **Gotcha — `require(amountScaled != 0)`.** Depositing an amount so small it
  scales to zero reverts rather than silently taking the funds. As the index
  grows this threshold rises: at index `2e27` the minimum meaningful deposit is
  2 wei.
- **Gotcha.** `RESERVE_TREASURY_ADDRESS` is immutable after initialization, so
  redirecting protocol revenue requires deploying a new aToken implementation
  and upgrading the proxy.

### `DelegationAwareAToken` (`DelegationAwareAToken.sol`, 30 lines)

Adds `delegateUnderlyingTo(address delegatee)`, `onlyPoolAdmin`, which calls
`IDelegationToken(underlying).delegate(delegatee)`. Exists so that governance
tokens deposited into Aave do not lose their voting power. Used for aAAVE and
aUNI.

### `DebtTokenBase` (`base/DebtTokenBase.sol`, 137 lines)

Abstract. Two jobs.

1. **Disable transferability.** `transfer`, `allowance`, `approve`,
   `transferFrom`, `increaseAllowance`, `decreaseAllowance` all
   `revert('TRANSFER_NOT_SUPPORTED')`. Debt cannot be sold.
2. **Credit delegation.** `_borrowAllowances[delegator][delegatee]`, exposed as
   `approveDelegation(delegatee, amount)` (emits `BorrowAllowanceDelegated`) and
   `borrowAllowanceDelegated`. `_decreaseBorrowAllowance(delegator, delegatee,
   amount)` subtracts with `Errors.BORROW_ALLOWANCE_NOT_ENOUGH`.

- **Gotcha.** Delegation is per debt token, so delegating variable USDC debt
  says nothing about stable USDC debt. Both must be approved separately.
- **Gotcha.** The allowance is denominated in underlying, not scaled units, and
  is not re-indexed. An old allowance therefore buys progressively less debt as
  interest accrues.

### `VariableDebtToken` (`VariableDebtToken.sol`, 209 lines)

The simple case: debt is a scaled balance times the borrow index, exactly
mirroring the aToken.

| Function | Access | Behaviour |
|---|---|---|
| `mint(user, onBehalfOf, amount, index)` | `onlyLendingPool` | If `user != onBehalfOf`, `_decreaseBorrowAllowance(onBehalfOf, user, amount)`. Then `amountScaled = amount.rayDiv(index)`, `require(amountScaled != 0, CT_INVALID_MINT_AMOUNT)`, `_mint(onBehalfOf, amountScaled)`. Returns `previousBalance == 0` |
| `burn(user, amount, index)` | `onlyLendingPool` | `amountScaled = amount.rayDiv(index)`, `require(amountScaled != 0, CT_INVALID_BURN_AMOUNT)`, `_burn(user, amountScaled)` |
| `balanceOf(user)` | view | `scaledBalance.rayMul(POOL.getReserveNormalizedVariableDebt(underlying))` |
| `scaledBalanceOf` / `scaledTotalSupply` / `getScaledUserBalanceAndSupply` | view | Raw |
| `totalSupply()` | view | `super.totalSupply().rayMul(normalizedDebt)` |

### `StableDebtToken` (`StableDebtToken.sol`, 435 lines)

The hard case. Each borrower has their **own** fixed rate, and the reserve needs
a single weighted-average rate for the supply-side math. Storage:
`_avgStableRate`, `_timestamps[user]`, `_usersStableRate[user]`,
`_totalSupplyTimestamp`.

**`_calculateBalanceIncrease(user)` (`:264-290`)** returns
`(previousPrincipal, currentBalance, balanceIncrease)`. It reads
`super.balanceOf(user)` (the stored principal), returns `(0,0,0)` if that is
zero, and otherwise computes `balanceIncrease = balanceOf(user) −
previousPrincipal` — where the public `balanceOf` compounds the user's own rate
from `_timestamps[user]` to now.

**`balanceOf(account)` (`:106`)** is
`principal.rayMul(calculateCompoundedInterest(_usersStableRate[account], _timestamps[account]))`.

**`_calcTotalSupply(avgRate)` (`:385-397`)** compounds the *principal* total
supply at the average rate from `_totalSupplyTimestamp`. So supply and
individual balances accrue on two independent clocks — the source of the
rounding caveats below.

**`mint(user, onBehalfOf, amount, rate) onlyLendingPool returns (bool)` (`:136-195`)**

1. Credit delegation check if `user != onBehalfOf`.
2. `(, currentBalance, balanceIncrease) = _calculateBalanceIncrease(onBehalfOf)`.
3. Cache `previousSupply`, `currentAvgStableRate`; set
   `_totalSupply = previousSupply + amount`.
4. **The user's new personal rate** — a balance-weighted blend of their old rate
   and the new borrow's rate:
   ```solidity
   vars.newStableRate = _usersStableRate[onBehalfOf]
     .rayMul(currentBalance.wadToRay())
     .add(vars.amountInRay.rayMul(rate))
     .rayDiv(currentBalance.add(amount).wadToRay());
   ```
   i.e. `r_new = (r_old·B + r·A) / (B + A)`. Guarded by
   `require(<= type(uint128).max, Errors.SDT_STABLE_DEBT_OVERFLOW)`.
5. `_totalSupplyTimestamp = _timestamps[onBehalfOf] = block.timestamp`.
6. **The reserve's new average rate**, weighted by supply the same way:
   ```solidity
   _avgStableRate = currentAvgStableRate
     .rayMul(previousSupply.wadToRay())
     .add(rate.rayMul(vars.amountInRay))
     .rayDiv(vars.nextSupply.wadToRay());
   ```
7. `_mint(onBehalfOf, amount + balanceIncrease, previousSupply)` — the accrued
   interest is capitalised into principal at the same moment.
8. Emits `Transfer(0, onBehalfOf, amount)` and `Mint(...)` with eight fields.
9. Returns `currentBalance == 0` as `isFirstBorrowing`.

**`burn(user, amount) onlyLendingPool` (`:197-257`)**

1. `_calculateBalanceIncrease(user)`.
2. **Supply and average rate.** If `previousSupply <= amount`, set both
   `_avgStableRate` and `_totalSupply` to zero. Otherwise
   `nextSupply = previousSupply − amount` and
   ```
   newAvgStableRate = (avgRate·previousSupply − userRate·amount) / nextSupply
   ```
   with a second guard: if `secondTerm >= firstTerm`, zero everything.
3. If the user is fully repaid, clear `_usersStableRate[user]` and
   `_timestamps[user]`; otherwise refresh the timestamp.
4. **Mint or burn.** If `balanceIncrease > amount` the interest accrued since
   the last touch exceeds the repayment, so the net effect is a `_mint` of the
   difference. Otherwise `_burn(user, amount − balanceIncrease)`.
5. Emits `Mint` or `Burn`, then `Transfer(user, 0, amount)`.

- **Gotcha — the two zeroing guards are not defensive padding.** The comments at
  `:205-208` and `:217-219` state the reason: total supply and individual
  balances compound on separate timestamps, so tiny divergences accumulate. The
  *last* borrower repaying can legitimately owe more than the recorded total
  supply. Without the clamps the subtraction would underflow and the final
  repayment would be impossible.
- **Gotcha — line `:221`.** `newAvgStableRate = _avgStableRate = _totalSupply = 0`
  assigns zero to `_totalSupply` as well, inside a branch where `nextSupply` was
  already written. The chained assignment is deliberate: hitting this case means
  the accounting has degenerated and the only consistent state is empty.
- **Gotcha — interest capitalises on every touch.** Both `mint` and `burn` fold
  `balanceIncrease` into principal. A stable borrower who repeatedly borrows
  small amounts compounds more often than one who does not.

**Views.** `getAverageStableRate()` (`:81`), `getUserLastUpdated(user)` (`:89`),
`getUserStableRate(user)` (`:98`), `getSupplyData()` (`:292`) returning
`(principalSupply, calcTotalSupply, avgRate, totalSupplyTimestamp)`,
`getTotalSupplyAndAvgRate()` (`:310`), `totalSupply()` (`:318`),
`getTotalSupplyLastUpdated()` (`:325`), `principalBalanceOf(user)` (`:334`).

`getSupplyData` is the four-tuple `_mintToTreasury` needs; `getTotalSupplyAndAvgRate`
is the two-tuple `updateInterestRates` needs. Two accessors instead of one
because each caller pays only for what it reads.

## 2.14 `LendingPoolConfigurator` (v2)

`aave/v2-protocol/contracts/protocol/lendingpool/LendingPoolConfigurator.sol`
(487 lines). The admin surface. Proxied, `VersionedInitializable`.

### Access

| Modifier | Line | Requirement |
|---|---:|---|
| `onlyPoolAdmin` | `:36` | `addressesProvider.getPoolAdmin() == msg.sender`, else `Errors.CALLER_NOT_POOL_ADMIN` |
| `onlyEmergencyAdmin` | `:41` | `addressesProvider.getEmergencyAdmin() == msg.sender`, else `Errors.LPC_CALLER_NOT_EMERGENCY_ADMIN` |

Two roles, not one: the emergency admin can *only* pause, so the pause key can
be held by a faster-moving multisig than the parameter key.

### Listing

**`batchInitReserve(InitReserveInput[] calldata input) external onlyPoolAdmin` (`:63-68`)**
loops over `_initReserve`.

**`_initReserve(pool, input) internal` (`:70-145`)** does, per reserve:

1. `_initTokenWithProxy(input.aTokenImpl, encoded initialize params)` — deploys
   an `InitializableImmutableAdminUpgradeabilityProxy` and calls `initialize`.
2. The same for the stable and variable debt tokens.
3. `pool.initReserve(asset, aTokenProxy, stableDebtProxy, variableDebtProxy,
   input.interestRateStrategyAddress)`.
4. Reads the reserve configuration into memory, calls `setDecimals`,
   `setActive(true)`, `setFrozen(false)`, then `pool.setConfiguration(asset,
   currentConfig.data)`.
5. Emits `ReserveInitialized(asset, aToken, stableDebtToken, variableDebtToken,
   interestRateStrategyAddress)`.

- **Gotcha — three proxies per reserve.** Listing an asset deploys three
  contracts. That is why `batchInitReserve` exists at all: one transaction per
  asset would be prohibitively expensive for a market launch.
- **Gotcha — step 4 is the memory/storage dance** described in
  [2.4](#24-reserveconfiguration--the-bitmap). The setters take `memory`, so the
  whole word is read, mutated locally, and written back through
  `pool.setConfiguration`.

### Upgrades

`updateAToken(UpdateATokenInput)` (`:147`), `updateStableDebtToken(UpdateDebtTokenInput)`
(`:178`) and `updateVariableDebtToken(UpdateDebtTokenInput)` (`:212`) each call
`_upgradeTokenImplementation` (`:466`), which invokes `upgradeToAndCall` on the
proxy. Events: `ATokenUpgraded`, `StableDebtTokenUpgraded`,
`VariableDebtTokenUpgraded`.

### Risk parameters

| Function | Line | Effect | Event |
|---|---:|---|---|
| `enableBorrowingOnReserve(asset, stableBorrowRateEnabled)` | `:251` | Sets borrowing enabled and optionally stable | `BorrowingEnabledOnReserve` |
| `disableBorrowingOnReserve(asset)` | `:269` | | `BorrowingDisabledOnReserve` |
| `configureReserveAsCollateral(asset, ltv, liquidationThreshold, liquidationBonus)` | `:287` | Sets all three at once | `CollateralConfigurationChanged` |
| `enableReserveStableRate(asset)` | `:335` | | `StableRateEnabledOnReserve` |
| `disableReserveStableRate(asset)` | `:349` | | `StableRateDisabledOnReserve` |
| `activateReserve(asset)` | `:363` | | `ReserveActivated` |
| `deactivateReserve(asset)` | `:377` | Requires `_checkNoLiquidity` | `ReserveDeactivated` |
| `freezeReserve(asset)` | `:394` | | `ReserveFrozen` |
| `unfreezeReserve(asset)` | `:408` | | `ReserveUnfrozen` |
| `setReserveFactor(asset, reserveFactor)` | `:423` | | `ReserveFactorChanged` |
| `setReserveInterestRateStrategyAddress(asset, strategy)` | `:438` | | `ReserveInterestRateStrategyChanged` |
| `setPoolPause(bool)` | `:450` | `onlyEmergencyAdmin` | via `LendingPool` |

**`configureReserveAsCollateral`** enforces three invariants beyond the bitmap
bounds: `ltv <= liquidationThreshold` (`LPC_INVALID_CONFIGURATION`), a non-zero
threshold requires `liquidationBonus > PERCENTAGE_FACTOR`, and
`threshold.percentMul(bonus) <= PERCENTAGE_FACTOR` — that last one guarantees a
liquidation can never seize more value than the position holds. Setting the
threshold to zero requires the liquidation bonus to be zero as well.

**`_checkNoLiquidity(asset)` (`:477-486`)** requires the aToken's underlying
balance to be zero *and* the reserve's liquidity rate to be zero, else
`LPC_RESERVE_LIQUIDITY_NOT_0`. Only `deactivateReserve` uses it.

- **Gotcha — freeze versus deactivate.** Freezing blocks deposits and new
  borrows while allowing repay, withdraw and liquidate. Deactivating blocks
  everything and is only possible on an empty reserve. Freeze is the tool for a
  live incident; deactivate is for delisting.
- **Gotcha.** There is no `dropReserve` in v2, so a deactivated reserve keeps its
  `id` and its two bits in every user's configuration word forever.

## 2.15 Configuration and upgradeability

### `LendingPoolAddressesProvider` (`protocol/configuration/LendingPoolAddressesProvider.sol`, 215 lines)

`Ownable`. A `mapping(bytes32 => address) _addresses` plus a market id string.
Owner in production is the Aave governance timelock.

| Function | Line | Notes |
|---|---:|---|
| `getMarketId()` / `setMarketId(string)` | `:39` / `:47` | Human-readable market label |
| `setAddress(bytes32 id, address)` | `:75` | **Hard replacement**, no proxy |
| `setAddressAsProxy(bytes32 id, address impl)` | `:60` | Deploys or upgrades a proxy for that id |
| `getAddress(bytes32 id)` | `:84` | Raw lookup |
| `getLendingPool()` / `setLendingPoolImpl(address)` | `:92` / `:101` | Proxied |
| `getLendingPoolConfigurator()` / `setLendingPoolConfiguratorImpl(address)` | `:110` / `:119` | Proxied |
| `getLendingPoolCollateralManager()` / `setLendingPoolCollateralManager(address)` | `:131` / `:139` | **Not** proxied — it is a delegatecall target |
| `getPoolAdmin()` / `setPoolAdmin(address)` | `:149` / `:153` | Plain address |
| `getEmergencyAdmin()` / `setEmergencyAdmin(address)` | `:158` / `:162` | Plain address |
| `getPriceOracle()` / `setPriceOracle(address)` | `:167` / `:171` | Plain address |
| `getLendingRateOracle()` / `setLendingRateOracle(address)` | `:176` / `:180` | Plain address |

**`_updateImpl(bytes32 id, address newAddress) internal` (`:194-209`)** is the
core: if no proxy exists for `id`, deploy an
`InitializableImmutableAdminUpgradeabilityProxy` with the provider as admin and
call `initialize(address(this))` through `initialize(logic, data)`; otherwise
call `upgradeToAndCall`. Either way the new implementation's `initialize` runs
with the provider as argument.

- **Gotcha — the two setter families.** `setAddress` replaces an address
  outright; `setAddressAsProxy` upgrades behind a proxy. Using the wrong one for
  the pool would strand every user position, which is why `getLendingPool` has a
  dedicated typed setter rather than relying on the generic path.
- **Gotcha.** The collateral manager is deliberately *not* proxied: it is only
  ever reached by `delegatecall`, so a proxy would add a hop and, worse, a
  second storage layout to keep aligned.

### `LendingPoolAddressesProviderRegistry` (`:89 lines`)

A registry of markets. `registerAddressesProvider(provider, id)`,
`unregisterAddressesProvider(provider)`, `getAddressesProvidersList()`,
`getAddressesProviderIdByAddress(provider)`. Purely informational — nothing in
the protocol reads it at runtime.

### `VersionedInitializable` (`protocol/libraries/aave-upgradeability/VersionedInitializable.sol`, 77 lines)

`lastInitializedRevision` plus the `initializer` modifier, which requires
`isConstructor() || revision > lastInitializedRevision`. Each implementation
overrides `getRevision()`. Upgrading to a *lower or equal* revision silently
skips re-initialization rather than reverting, which is what allows
`initialize` to be safely present on every version.

### The proxy set

`BaseImmutableAdminUpgradeabilityProxy` (80 lines) stores the admin as an
`immutable` in bytecode instead of a storage slot, saving an SLOAD on every
delegatecall. `InitializableImmutableAdminUpgradeabilityProxy` (23 lines) adds
`initialize(logic, data)`. Both refuse calls from the admin address to anything
but the admin functions — the standard transparent-proxy selector-clash defence.

## 2.16 `misc/` — oracle, gateway, data providers

### `AaveOracle` (`misc/AaveOracle.sol`, 127 lines)

`Ownable`. `mapping(address => IChainlinkAggregator) private assetsSources`, a
`_fallbackOracle`, and an immutable `BASE_CURRENCY` / `BASE_CURRENCY_UNIT`.

| Function | Behaviour |
|---|---|
| `setAssetSources(assets, sources)` | Owner only; emits `AssetSourceUpdated` per asset |
| `setFallbackOracle(fallbackOracle)` | Owner only; emits `FallbackOracleUpdated` |
| `getAssetPrice(asset)` | Returns `BASE_CURRENCY_UNIT` if `asset == BASE_CURRENCY`; else `source.latestAnswer()`; if the source is unset **or the answer is `<= 0`**, falls back to `_fallbackOracle.getAssetPrice(asset)` |
| `getAssetsPrices(assets)` | Batch |
| `getSourceOfAsset(asset)` / `getFallbackOracle()` | Views |

- **Gotcha — `latestAnswer()` only.** No `latestRoundData`, so there is **no
  staleness or round-completeness check**. A Chainlink feed that stops updating
  keeps returning its last value indefinitely, and the protocol cannot tell.
  This is the single largest oracle weakness in v2 and the reason integrators
  were told to monitor feeds externally. v3 added the price oracle sentinel for
  L2 sequencer downtime but still reads `latestAnswer` for the price itself.
- **Gotcha.** A zero or negative answer routes to the fallback rather than
  reverting, so a misconfigured fallback silently becomes the price source.

### `WETHGateway` (`misc/WETHGateway.sol`, 189 lines)

Wraps ETH so users can interact with a WETH reserve holding native currency.

| Function | Behaviour |
|---|---|
| `depositETH(pool, onBehalfOf, referralCode)` | `payable`; wraps `msg.value`, approves, `pool.deposit` |
| `withdrawETH(pool, amount, to)` | Pulls aWETH from the user, `pool.withdraw`, unwraps, sends ETH |
| `repayETH(pool, amount, rateMode, onBehalfOf)` | `payable`; wraps and repays, refunding any excess |
| `borrowETH(pool, amount, interestRateMode, referralCode)` | Requires prior `approveDelegation` on the WETH debt token, then borrows and unwraps |
| `emergencyTokenTransfer` / `emergencyEtherTransfer` | Owner-only rescue |
| `receive()` | Accepts ETH only from the WETH contract |

- **Gotcha — `borrowETH` needs credit delegation.** The gateway borrows *on
  behalf of itself* against the user's collateral, so the user must first call
  `approveDelegation(gateway, amount)` on the variable or stable WETH debt
  token. This trips up nearly every first integration.
- **Gotcha — `withdrawETH` requires an aWETH approval** to the gateway, because
  the gateway must pull the aTokens before burning them.

### Data providers

**`AaveProtocolDataProvider`** (180 lines) is the canonical read API:
`getAllReservesTokens()`, `getAllATokens()`, `getReserveConfigurationData(asset)`,
`getReserveData(asset)`, `getUserReserveData(asset, user)`,
`getReserveTokensAddresses(asset)`. This is what integrations should use rather
than reading `LendingPool.getReserveData` and decoding the bitmap themselves.

**`UiPoolDataProvider`** (399), **`UiPoolDataProviderV2`** (224) and
**`UiPoolDataProviderV2V3`** (241) aggregate a whole market plus one user into a
single call for front-ends. **`UiIncentiveDataProviderV2`** (287) and
**`UiIncentiveDataProviderV2V3`** (397) do the same for reward emissions.
**`WalletBalanceProvider`** (111) batches plain token balances.

- **Gotcha.** The three `UiPoolDataProvider` variants exist because the returned
  struct is part of the ABI and changing it would break deployed front-ends. The
  `V2V3` suffix means "works against both a v2 and a v3 market", which is how
  the Aave interface served both during the migration.

## 2.17 `adapters/` — flash-loan-powered position management

`aave/v2-protocol/contracts/adapters/` (8 files). These are not part of the
protocol; they are `IFlashLoanReceiver` implementations that compose
`flashLoan` with a DEX to do in one transaction what would otherwise need
several and would break the health factor in between.

Every adapter follows the same shape:

```
user ──► adapter.<entry point>(...)
              │  (path A: no flash loan needed)
              └─► _pullAToken ──► pool.withdraw ──► swap ──► pool.deposit/repay

user ──► pool.flashLoan(adapter, ...)
              └─► adapter.executeOperation(assets, amounts, premiums, initiator, params)
                        │  decode params
                        │  do the work with the borrowed funds
                        └─► approve pool for amount + premium, return true
```

### `BaseUniswapAdapter` (`BaseUniswapAdapter.sol`, 566 lines)

Shared machinery. `Ownable`, holds `UNISWAP_ROUTER`, `WETH_ADDRESS` and the
oracle.

| Function | Line | Purpose |
|---|---:|---|
| `getAmountsOut(amountIn, reserveIn, reserveOut)` | `:60` | Best exact-in quote, with USD values and the chosen path |
| `getAmountsIn(amountOut, reserveIn, reserveOut)` | `:97` | Best exact-out quote |
| `_swapExactTokensForTokens(...)` | `:132` | Executes exact-in, enforcing a max slippage against oracle prices |
| `_swapTokensForExactTokens(...)` | `:191` | Executes exact-out |
| `_getPrice(asset)` | `:247` | Oracle price |
| `_getDecimals(asset)` | `:255` | |
| `_getReserveData(asset)` | `:263` | Reserve struct from the pool |
| `_pullAToken(reserve, aToken, user, amount, permitSignature)` | `:275` | Optionally `permit`, then `transferFrom` the user's aTokens and `pool.withdraw` |
| `_usePermit(signature)` | `:307` | True when the signature is non-empty |
| `_calcUsdValue(reserve, amount, decimals)` | `:319` | Oracle value in USD |
| `_getAmountsOutData(...)` | `:341` | Compares the direct pair against the WETH-routed path and picks the better |
| `_getAmountsInData(...)` | `:433` | Same for exact-out |
| `_getAmountsInAndPath(...)` | `:486` | Path selection helper |
| `_getAmountsIn(...)` | `:536` | Raw router call |
| `rescueTokens(token)` | `:563` | `onlyOwner` sweep |

- **Slippage defence.** The swap helpers compare the DEX output against the
  Aave oracle's valuation and revert if the gap exceeds `MAX_SLIPPAGE_PERCENT`.
  The adapters therefore inherit the oracle's trust assumptions on top of the
  DEX's.
- **Gotcha — `useEthPath`.** Several entry points take a `bool[] useEthPath`
  telling the adapter to route through WETH rather than a direct pair. It is a
  caller-supplied hint, not a computed optimum, so a bad hint costs the user
  slippage.

### `UniswapLiquiditySwapAdapter` (283 lines) — swap one collateral for another

- **`swapAndDeposit(assetToSwapFromList, assetToSwapToList, amountToSwapList,
  minAmountsToReceive, permitParams, useEthPath)` (`:130`)** is the no-flash-loan
  path: pull aTokens, withdraw, swap, deposit the proceeds back on behalf of the
  user. Requires the user to be over-collateralised enough to withdraw first.
- **`executeOperation(assets, amounts, premiums, initiator, params)` (`:57`)** is
  the flash-loan path: the borrowed asset is the *destination* collateral, which
  is deposited for the user immediately; then the user's original collateral is
  pulled and swapped to repay the loan plus premium. `_swapLiquidity` (`:200`)
  does the work.
- **`_decodeParams(bytes)` (`:257`)** unpacks the `SwapParams` struct from the
  flash loan's `params` blob.
- **Why the flash loan matters.** Withdrawing collateral first would drop the
  health factor below 1 for a leveraged position. Depositing the new collateral
  *before* removing the old one keeps the position solvent at every intermediate
  step.

### `UniswapRepayAdapter` (266 lines) — repay debt with collateral

- **`swapAndRepay(collateralAsset, debtAsset, collateralAmount, debtRepayAmount,
  debtRateMode, permitSignature, useEthPath)` (`:91`)** pulls collateral, swaps
  to the debt asset, repays.
- **`executeOperation` (`:51`)** flash-borrows the *debt* asset, repays the
  user's debt with it, then pulls and swaps collateral to close the flash loan.
  `_swapAndRepay` (`:162`) is the internal.
- **Gotcha.** Repaying first raises the health factor, which is what makes the
  subsequent collateral withdrawal legal. Same ordering trick as the liquidity
  adapter, mirrored.

### `FlashLiquidationAdapter` (184 lines) — liquidate with no capital

- **`executeOperation` (`:64`)** → `_liquidateAndSwap` (`:102`): use the
  flash-borrowed debt asset to call `pool.liquidationCall`, receive the
  discounted collateral, swap enough of it back to the debt asset to repay the
  loan plus premium, and send the remainder to the initiator as profit.
- **`LiquidationParams`** (`:24`) carries `collateralAsset`, `borrowedAsset`,
  `user`, `debtToCover`, `useEthPath`.
- **Gotcha.** The liquidation bonus must exceed the flash-loan premium (0.09%)
  plus DEX fees plus slippage, or the transaction reverts on the repayment. This
  is the practical floor on how thin a liquidation bonus can be set.

### ParaSwap variants

`BaseParaSwapAdapter` (122), `BaseParaSwapSellAdapter` (109) and
`ParaSwapLiquiditySwapAdapter` (210) mirror the Uniswap trio against ParaSwap's
Augustus router. The structural difference is that ParaSwap swaps are executed
from **off-chain-built calldata** passed in by the caller, so the adapter
validates the Augustus address against `IParaSwapAugustusRegistry` and checks
the received amount, rather than constructing the route itself.

### `interfaces/IBaseUniswapAdapter.sol` (90 lines)

Declares `PermitSignature` (`deadline, v, r, s, amount`), `AmountCalc`
(`calculatedAmount, relativePrice, amountInUsd, amountOutUsd, path`) and the
adapter surface.

## 2.18 `flashloan/`, `deployments/`, `dependencies/`, `mocks/`

### `flashloan/`

**`interfaces/IFlashLoanReceiver.sol`** (25 lines) declares the multi-asset
callback:

```solidity
function executeOperation(
  address[] calldata assets,
  uint256[] calldata amounts,
  uint256[] calldata premiums,
  address initiator,
  bytes calldata params
) external returns (bool);
```

plus `ADDRESSES_PROVIDER()` and `LENDING_POOL()`.

**`base/FlashLoanReceiverBase.sol`** (22 lines) is an abstract contract storing
those two as immutables. Note it does **not** implement `executeOperation` and
does **not** approve the pool — both are the integrator's responsibility, and
forgetting the approval is the most common flash-loan integration bug.

- **Gotcha — `initiator` is not `msg.sender`.** `msg.sender` inside
  `executeOperation` is the `LendingPool`; `initiator` is whoever called
  `flashLoan`. A receiver that trusts `initiator` without also checking
  `msg.sender == LENDING_POOL` can be called directly by anyone with forged
  arguments.

### `deployments/`

`ATokensAndRatesHelper.sol` (86) batch-deploys token implementations and rate
strategies and calls `configureReserves` during market setup.
`StableAndVariableTokensHelper.sol` (47) deploys the two debt token
implementations. `StringLib.sol` (8) is a `concat` helper for building token
names like `"Aave interest bearing USDC"`. All three are deployment-time only.

### `dependencies/`

Nine vendored OpenZeppelin contracts (936 lines) — `ERC20`, `IERC20`,
`IERC20Detailed`, `SafeERC20`, `SafeMath`, `Address`, `Context`, `Ownable`,
`ReentrancyGuard` — and eight upgradeability contracts (465 lines) mirroring
v1's set. Vendored rather than imported so the compiler version and the exact
source are pinned.

### `mocks/`

`WETH9.sol` (758) is the canonical WETH source. `MockFlashLoanReceiver.sol` (84)
is a configurable-failure receiver for testing the revert paths.
`SefldestructTransfer.sol` (8, the typo is in the repo) force-sends ETH via
`selfdestruct` to test that no contract depends on its own balance being
un-donatable. `mocks/oracle/*` (6 files) provide settable price and lending-rate
oracles. `mocks/swap/*` (4 files) mock the Uniswap router and the ParaSwap
Augustus, registry and transfer proxy. `mocks/tokens/*` (3 files) give
`MintableERC20`, `MintableDelegationERC20` and `WETH9Mocked`.
`mocks/upgradeability/*` (3 files) are revision-bumped token implementations
used to exercise `VersionedInitializable`.

## 2.19 The complete `Errors.sol` table

`aave/v2-protocol/contracts/protocol/libraries/helpers/Errors.sol` (119 lines).
v2 replaced v1's long revert strings with **numeric codes as strings** — the
revert reason is literally `"1"`, `"32"` and so on. The saving is real: each
long string was a separate constant in bytecode.

The prefix encodes the origin: `VL` validation logic, `LP` lending pool, `CT`
common token, `RL` reserve logic, `LPC` configurator, `RC` reserve
configuration, `SDT` stable debt token, `MATH` math libraries, `LPCM` collateral
manager.

| Code | Identifier | Line | Meaning |
|---:|---|---:|---|
| 1 | `VL_INVALID_AMOUNT` | `:28` | Amount must be greater than 0 |
| 2 | `VL_NO_ACTIVE_RESERVE` | `:29` | Reserve deactivated |
| 3 | `VL_RESERVE_FROZEN` | `:30` | Reserve frozen |
| 4 | `VL_CURRENT_AVAILABLE_LIQUIDITY_NOT_ENOUGH` | `:31` | Not enough liquidity |
| 5 | `VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE` | `:32` | Withdrawing more than held |
| 6 | `VL_TRANSFER_NOT_ALLOWED` | `:33` | Would break the health factor |
| 7 | `VL_BORROWING_NOT_ENABLED` | `:34` | Borrowing disabled for this reserve |
| 8 | `VL_INVALID_INTEREST_RATE_MODE_SELECTED` | `:35` | Mode is not 1 or 2 |
| 9 | `VL_COLLATERAL_BALANCE_IS_0` | `:36` | No collateral at all |
| 10 | `VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD` | `:37` | Already unhealthy |
| 11 | `VL_COLLATERAL_CANNOT_COVER_NEW_BORROW` | `:38` | Exceeds borrowing power |
| 12 | `VL_STABLE_BORROWING_NOT_ENABLED` | `:39` | Stable disabled for this reserve |
| 13 | `VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY` | `:40` | The stable self-borrow guard |
| 14 | `VL_AMOUNT_BIGGER_THAN_MAX_LOAN_SIZE_STABLE` | `:41` | Above 25% of liquidity |
| 15 | `VL_NO_DEBT_OF_SELECTED_TYPE` | `:42` | No debt in the chosen mode |
| 16 | `VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF` | `:43` | `uint256.max` repay on behalf |
| 17 | `VL_NO_STABLE_RATE_LOAN_IN_RESERVE` | `:44` | Swapping a non-existent stable loan |
| 18 | `VL_NO_VARIABLE_RATE_LOAN_IN_RESERVE` | `:45` | Swapping a non-existent variable loan |
| 19 | `VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0` | `:46` | Enabling collateral with no balance |
| 20 | `VL_DEPOSIT_ALREADY_IN_USE` | `:47` | Disabling collateral that backs debt |
| 21 | `LP_NOT_ENOUGH_STABLE_BORROW_BALANCE` | `:48` | No stable loan for this reserve |
| 22 | `LP_INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET` | `:49` | Rebalance thresholds unmet |
| 23 | `LP_LIQUIDATION_CALL_FAILED` | `:50` | The delegatecall reverted |
| 24 | `LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW` | `:51` | |
| 25 | `LP_REQUESTED_AMOUNT_TOO_SMALL` | `:52` | Flash loan amount too small |
| 26 | `LP_INCONSISTENT_PROTOCOL_ACTUAL_BALANCE` | `:53` | |
| 27 | `LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR` | `:54` | |
| 28 | `LP_INCONSISTENT_FLASHLOAN_PARAMS` | `:55` | |
| 29 | `CT_CALLER_MUST_BE_LENDING_POOL` | `:56` | `onlyLendingPool` on a token |
| 30 | `CT_CANNOT_GIVE_ALLOWANCE_TO_HIMSELF` | `:57` | |
| 31 | `CT_TRANSFER_AMOUNT_NOT_GT_0` | `:58` | |
| 32 | `RL_RESERVE_ALREADY_INITIALIZED` | `:59` | Double listing |
| 33 | `CALLER_NOT_POOL_ADMIN` | `:24` | Not the pool admin |
| 34 | `LPC_RESERVE_LIQUIDITY_NOT_0` | `:60` | Deactivating a non-empty reserve |
| 35 | `LPC_INVALID_ATOKEN_POOL_ADDRESS` | `:61` | Token wired to the wrong pool |
| 36 | `LPC_INVALID_STABLE_DEBT_TOKEN_POOL_ADDRESS` | `:62` | |
| 37 | `LPC_INVALID_VARIABLE_DEBT_TOKEN_POOL_ADDRESS` | `:63` | |
| 38 | `LPC_INVALID_STABLE_DEBT_TOKEN_UNDERLYING_ADDRESS` | `:64` | |
| 39 | `LPC_INVALID_VARIABLE_DEBT_TOKEN_UNDERLYING_ADDRESS` | `:65` | |
| 40 | `LPC_INVALID_ADDRESSES_PROVIDER_ID` | `:66` | |
| 41 | `LPAPR_PROVIDER_NOT_REGISTERED` | `:69` | Registry lookup miss |
| 42 | `LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD` | `:70` | Target is healthy |
| 43 | `LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED` | `:71` | Not collateral, or threshold 0 |
| 44 | `LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER` | `:72` | |
| 45 | `LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE` | `:73` | |
| 46 | `LPCM_NO_ERRORS` | `:74` | Success sentinel |
| 47 | `LP_INVALID_FLASHLOAN_MODE` | `:75` | |
| 48 | `MATH_MULTIPLICATION_OVERFLOW` | `:76` | |
| 49 | `MATH_ADDITION_OVERFLOW` | `:77` | |
| 50 | `MATH_DIVISION_BY_ZERO` | `:78` | |
| 51 | `RL_LIQUIDITY_INDEX_OVERFLOW` | `:79` | Index exceeded `uint128` |
| 52 | `RL_VARIABLE_BORROW_INDEX_OVERFLOW` | `:80` | |
| 53 | `RL_LIQUIDITY_RATE_OVERFLOW` | `:81` | |
| 54 | `RL_VARIABLE_BORROW_RATE_OVERFLOW` | `:82` | |
| 55 | `RL_STABLE_BORROW_RATE_OVERFLOW` | `:83` | |
| 56 | `CT_INVALID_MINT_AMOUNT` | `:84` | Scaled amount rounded to zero |
| 57 | `LP_FAILED_REPAY_WITH_COLLATERAL` | `:85` | |
| 58 | `CT_INVALID_BURN_AMOUNT` | `:86` | Scaled amount rounded to zero |
| 59 | `BORROW_ALLOWANCE_NOT_ENOUGH` | `:25` | Credit delegation allowance too small |
| 60 | `LP_FAILED_COLLATERAL_SWAP` | `:87` | |
| 61 | `LP_INVALID_EQUAL_ASSETS_TO_SWAP` | `:88` | |
| 62 | `LP_REENTRANCY_NOT_ALLOWED` | `:89` | |
| 63 | `LP_CALLER_MUST_BE_AN_ATOKEN` | `:90` | `finalizeTransfer` caller check |
| 64 | `LP_IS_PAUSED` | `:91` | Global pause active |
| 65 | `LP_NO_MORE_RESERVES_ALLOWED` | `:92` | 128-reserve ceiling |
| 66 | `LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN` | `:93` | `executeOperation` returned false |
| 67 | `RC_INVALID_LTV` | `:94` | Above 65535 |
| 68 | `RC_INVALID_LIQ_THRESHOLD` | `:95` | |
| 69 | `RC_INVALID_LIQ_BONUS` | `:96` | |
| 70 | `RC_INVALID_DECIMALS` | `:97` | Above 255 |
| 71 | `RC_INVALID_RESERVE_FACTOR` | `:98` | |
| 72 | `LPAPR_INVALID_ADDRESSES_PROVIDER_ID` | `:99` | |
| 73 | `VL_INCONSISTENT_FLASHLOAN_PARAMS` | `:100` | Array lengths differ |
| 74 | `LP_INCONSISTENT_PARAMS_LENGTH` | `:101` | |
| 75 | `LPC_INVALID_CONFIGURATION` | `:67` | LTV/threshold/bonus inconsistent |
| 76 | `LPC_CALLER_NOT_EMERGENCY_ADMIN` | `:68` | |
| 77 | `UL_INVALID_INDEX` | `:102` | User configuration index out of range |
| 78 | `LP_NOT_CONTRACT` | `:103` | |
| 79 | `SDT_STABLE_DEBT_OVERFLOW` | `:104` | Blended rate exceeded `uint128` |
| 80 | `SDT_BURN_EXCEEDS_BALANCE` | `:105` | |

All 80 codes are declared as `string public constant` in
`aave/v2-protocol/contracts/protocol/libraries/helpers/Errors.sol:24-105`. Note
that the numbering is **not** in declaration order: `CALLER_NOT_POOL_ADMIN` is
code 33 but declared first, and `LPC_INVALID_CONFIGURATION` (75) and
`LPC_CALLER_NOT_EMERGENCY_ADMIN` (76) sit between codes 40 and 41 in the file.
Codes were assigned as they were added, then grouped by prefix for readability.

Plus the `CollateralManagerErrors` enum used by the liquidation return-code
protocol: `NO_ERROR`, `NO_COLLATERAL_AVAILABLE`, `COLLATERAL_CANNOT_BE_LIQUIDATED`,
`CURRRENCY_NOT_BORROWED` (the triple-R typo is in the source),
`HEALTH_FACTOR_ABOVE_THRESHOLD`, `NOT_ENOUGH_LIQUIDITY`, `NO_ACTIVE_RESERVE`,
`HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD`, `INVALID_EQUAL_ASSETS_TO_SWAP`,
`FROZEN_RESERVE`.

- **How to read a v2 revert in practice.** The transaction fails with reason
  `"33"` or similar. Grep `Errors.sol` for the numeric literal to recover the
  identifier, then grep the codebase for that identifier to find every throw
  site. `grep -n "'33'" aave/v2-protocol/contracts/protocol/libraries/helpers/Errors.sol`
  is the first step; the constants are declared with their codes as string
  literals.
- **Gotcha.** Several codes are reused across prefixes because the numbering
  restarted per group during development. Always match on the *identifier*, not
  the number, when reading the source.

## 2.20 v2 events reference

Declared in `aave/v2-protocol/contracts/interfaces/ILendingPool.sol`, emitted by
`LendingPool` (and, for `LiquidationCall`, by the collateral manager executing in
the pool's context).

| Event | Declared | Emitted when |
|---|---|---|
| `Deposit(reserve, user, onBehalfOf, amount, referral)` | `:17` | `deposit` succeeds. `reserve`, `user`, `onBehalfOf` are indexed |
| `Withdraw(reserve, user, to, amount)` | `:32` | `withdraw` succeeds; all three addresses indexed |
| `Borrow(reserve, user, onBehalfOf, amount, borrowRateMode, borrowRate, referral)` | `:45` | Any borrow, including the flash-loan mode 1/2 path |
| `Repay(reserve, user, repayer, amount)` | `:62` | `repay` succeeds |
| `Swap(reserve, user, rateMode)` | `:75` | `swapBorrowRateMode` |
| `ReserveUsedAsCollateralEnabled(reserve, user)` | `:82` | First deposit, aToken receipt, or explicit enable |
| `ReserveUsedAsCollateralDisabled(reserve, user)` | `:89` | Full withdrawal, full seizure, or explicit disable |
| `RebalanceStableBorrowRate(reserve, user)` | `:96` | Permissionless rebalance |
| `FlashLoan(target, initiator, asset, amount, premium, referralCode)` | `:107` | Once per asset in the loop |
| `Paused()` / `Unpaused()` | `:119` / `:124` | `setPause` |
| `LiquidationCall(collateralAsset, debtAsset, user, debtToCover, liquidatedCollateralAmount, liquidator, receiveAToken)` | `:139` | Liquidation. Declared here but fired via the delegatecall |
| `ReserveDataUpdated(asset, liquidityRate, stableBorrowRate, variableBorrowRate, liquidityIndex, variableBorrowIndex)` | `:161` | Every `updateInterestRates`. Declared in **both** `ILendingPool` and `ReserveLogic` — the comment at `:150-153` explains the duplication is for ABI completeness |

Configurator events, from `interfaces/ILendingPoolConfigurator.sol`:
`ReserveInitialized` (`:52`), `BorrowingEnabledOnReserve` (`:65`),
`BorrowingDisabledOnReserve` (`:71`), `CollateralConfigurationChanged` (`:80`),
`StableRateEnabledOnReserve` (`:91`), `StableRateDisabledOnReserve` (`:97`),
`ReserveActivated` (`:103`), `ReserveDeactivated` (`:109`), `ReserveFrozen`
(`:115`), `ReserveUnfrozen` (`:121`), `ReserveFactorChanged` (`:128`),
`ReserveDecimalsChanged` (`:135`), `ReserveInterestRateStrategyChanged` (`:142`),
`ATokenUpgraded` (`:150`), `StableDebtTokenUpgraded` (`:162`),
`VariableDebtTokenUpgraded` (`:174`).

Token events: `AToken` adds `BalanceTransfer(from, to, value, index)` and
`Mint`/`Burn`; `StableDebtToken` adds an eight-field `Mint` and a six-field
`Burn`; `DebtTokenBase` adds `BorrowAllowanceDelegated(fromUser, toUser, asset,
amount)`.

- **Indexer note versus v1.** Every v2 event indexes its addresses and drops the
  explicit `timestamp` field, so a log filter by user works directly and the
  block timestamp is taken from the block. Both were pain points in v1
  ([1.13](#113-v1-events-reference)).

## 2.21 v2 storage layouts

### `LendingPool` (proxied)

| Slot | Source | Type | Name |
|---:|---|---|---|
| 0 | `VersionedInitializable` | `uint256` | `lastInitializedRevision` |
| 1 | `LendingPoolStorage:16` | `ILendingPoolAddressesProvider` | `_addressesProvider` |
| 2 | `LendingPoolStorage:18` | mapping | `_reserves` |
| 3 | `LendingPoolStorage:19` | mapping | `_usersConfig` |
| 4 | `LendingPoolStorage:22` | mapping | `_reservesList` |
| 5 | `LendingPoolStorage:24` | `uint256` | `_reservesCount` |
| 6 | `LendingPoolStorage:26` | `bool` | `_paused` |
| 7 | `LendingPoolStorage:28` | `uint256` | `_maxStableRateBorrowSizePercent` |
| 8 | `LendingPoolStorage:30` | `uint256` | `_flashLoanPremiumTotal` |
| 9 | `LendingPoolStorage:32` | `uint256` | `_maxNumberOfReserves` |

`LendingPoolCollateralManager` inherits `VersionedInitializable` and
`LendingPoolStorage` in the same order, so its layout is identical — the
precondition for the `delegatecall`.

Each `DataTypes.ReserveData` value occupies 8 slots (see
[2.2](#22-datatypes-and-lendingpoolstorage)), against roughly 20 in v1.

### `AToken`

Slots 0–2 from `VersionedInitializable` and `IncentivizedERC20` (`_balances`,
`_allowances`, `_totalSupply`), then `_name`, `_symbol`, `_decimals`,
`_incentivesController`, followed by the aToken's own `_treasury`,
`_underlyingAsset`, `_pool` and the EIP-2612 `_nonces`.

- **Difference from v1.** v2 aTokens **are** proxied and versioned, so an aToken
  can be upgraded in place. v1's could not ([1.14](#114-v1-storage-layouts)).

### `StableDebtToken`

After the shared `IncentivizedERC20` and `DebtTokenBase` slots:
`_avgStableRate`, `mapping(address => uint40) _timestamps`,
`mapping(address => uint256) _usersStableRate`, `_totalSupplyTimestamp`, plus
`_pool`, `_underlyingAsset`, `_incentivesController`.

`VariableDebtToken` adds only `_pool`, `_underlyingAsset` and
`_incentivesController` — the scaled balance lives in the inherited
`_balances`.

## 2.22 v2 ABI / selector tables

Selectors computed with `cast sig`.

### `LendingPool`

| Signature | Selector | Access |
|---|---|---|
| `deposit(address,uint256,address,uint16)` | `0xe8eda9df` | anyone, `whenNotPaused` |
| `withdraw(address,uint256,address)` | `0x69328dec` | anyone |
| `borrow(address,uint256,uint256,uint16,address)` | `0xa415bcad` | anyone (delegation for `onBehalfOf`) |
| `repay(address,uint256,uint256,address)` | `0x573ade81` | anyone |
| `swapBorrowRateMode(address,uint256)` | `0x94ba89a2` | borrower |
| `rebalanceStableBorrowRate(address,address)` | `0xcd112382` | anyone |
| `setUserUseReserveAsCollateral(address,bool)` | `0x5a3b74b9` | depositor |
| `liquidationCall(address,address,address,uint256,bool)` | `0x00a718a9` | anyone |
| `flashLoan(address,address[],uint256[],uint256[],address,bytes,uint16)` | `0xab9c4b5d` | anyone |
| `getUserAccountData(address)` | `0xbf92857c` | view |
| `finalizeTransfer(address,address,address,uint256,uint256,uint256)` | `0xd5ed3933` | the aToken only |

Plus `initReserve`, `setReserveInterestRateStrategyAddress`, `setConfiguration`
and `setPause`, all `onlyLendingPoolConfigurator`, and the view surface listed
in [2.10](#210-lendingpool).

### Tokens

| Signature | Selector | Contract |
|---|---|---|
| `scaledBalanceOf(address)` | `0x1da24f3e` | `AToken`, `VariableDebtToken` |
| `mintToTreasury(uint256,uint256)` | `0x7df5bd3b` | `AToken`, `onlyLendingPool` |
| `approveDelegation(address,uint256)` | `0xc04a8a10` | both debt tokens |

`AToken` also exposes `mint`, `burn`, `transferOnLiquidation`,
`transferUnderlyingTo`, `handleRepayment` (all `onlyLendingPool`),
`getScaledUserBalanceAndSupply`, `scaledTotalSupply`, `permit`,
`UNDERLYING_ASSET_ADDRESS`, `RESERVE_TREASURY_ADDRESS`, `POOL`, and the full
ERC20 surface. Both debt tokens revert on every ERC20 transfer entry point.

## 2.23 v2 use cases

| Goal | Call | Internal chain |
|---|---|---|
| Supply an ERC20 | `LendingPool.deposit(asset, amt, self, 0)` | `validateDeposit` → `updateState` → `updateInterestRates` → `transferFrom(user, aToken)` → `AToken.mint` |
| Supply for someone else | same with `onBehalfOf = other` | aTokens mint to `other`; collateral bit set on *their* config |
| Supply ETH | `WETHGateway.depositETH{value}(pool, self, 0)` | wrap → approve → `pool.deposit` |
| Withdraw | `withdraw(asset, amt, to)` | `validateWithdraw` (health factor) → `updateState` → `AToken.burn` → `safeTransfer(to)` |
| Withdraw everything | `withdraw(asset, type(uint256).max, to)` | resolves to the full aToken balance |
| Borrow variable | `borrow(asset, amt, 2, 0, self)` | `_executeBorrow` → `validateBorrow` → `VariableDebtToken.mint` → `transferUnderlyingTo` |
| Borrow stable | `borrow(asset, amt, 1, 0, self)` | as above via `StableDebtToken.mint`, rate blended |
| Borrow against someone's credit | delegator calls `approveDelegation(you, amt)` on the debt token, then you call `borrow(..., onBehalfOf = delegator)` | `_decreaseBorrowAllowance` inside the debt token's `mint` |
| Borrow ETH | `approveDelegation(gateway, amt)` on the WETH debt token, then `WETHGateway.borrowETH(...)` | gateway borrows and unwraps |
| Repay | `repay(asset, amt, 2, self)` | `validateRepay` → burn debt → `transferFrom(user, aToken)` → `handleRepayment` |
| Repay everything | `repay(asset, type(uint256).max, mode, self)` | clamps to the debt in that mode |
| Repay for someone else | `repay(asset, explicitAmt, mode, other)` | `uint256.max` is rejected here |
| Switch rate mode | `swapBorrowRateMode(asset, currentMode)` | burn all of one, mint the same into the other |
| Rebalance someone's stable rate | `rebalanceStableBorrowRate(asset, user)` | requires U ≥ 95% **and** supply rate ≤ 40% of max variable |
| Toggle collateral | `setUserUseReserveAsCollateral(asset, bool)` | `balanceDecreaseAllowed` gate when disabling |
| Liquidate, take underlying | `liquidationCall(coll, debt, user, amt, false)` | delegatecall → close factor 50% → `AToken.burn` |
| Liquidate, take aTokens | `liquidationCall(coll, debt, user, amt, true)` | → `transferOnLiquidation`; works even at 100% utilization |
| Liquidate with no capital | `pool.flashLoan(FlashLiquidationAdapter, ...)` | flash → `liquidationCall` → swap collateral → repay |
| Flash loan, repay | `flashLoan(receiver, assets, amounts, [0,…], self, params, 0)` | `transferUnderlyingTo` → `executeOperation` → `cumulateToLiquidityIndex(premium)` → pull back |
| Flash loan, keep as debt | same with `modes = [1 or 2]` | `_executeBorrow(releaseUnderlying: false)` |
| Swap collateral A → B | `pool.flashLoan(UniswapLiquiditySwapAdapter, ...)` | deposit B first, then pull and swap A |
| Repay debt with collateral | `pool.flashLoan(UniswapRepayAdapter, ...)` | repay first, then pull and swap collateral |
| Read a user's position | `AaveProtocolDataProvider.getUserReserveData(asset, user)` | |
| Read the whole market | `UiPoolDataProviderV2.getReservesData(provider)` | |
| List a reserve | `LendingPoolConfigurator.batchInitReserve([...])` | 3 proxies deployed, then `pool.initReserve` |
| Freeze a reserve | `freezeReserve(asset)` | deposits and new borrows blocked; repay/withdraw/liquidate still work |
| Delist a reserve | `deactivateReserve(asset)` | requires zero liquidity **and** zero liquidity rate |
| Emergency stop | `setPoolPause(true)` | `onlyEmergencyAdmin` |
| Upgrade an aToken | `updateAToken(input)` | `upgradeToAndCall` on the token proxy |

---

# Part 3 — v1 → v2 migration table

For each v1 external function, what became of it.

| v1 function | v1 location | v2 equivalent | Notes |
|---|---|---|---|
| `deposit(reserve, amount, referralCode)` | `LendingPool.sol:299` | `deposit(asset, amount, onBehalfOf, referralCode)` | Gained `onBehalfOf`. ETH is no longer a pseudo-asset; use `WETHGateway` |
| `redeemUnderlying(reserve, user, amount, aTokenBalanceAfterRedeem)` | `LendingPool.sol:355` | `withdraw(asset, amount, to)` | **Inverted.** In v1 the *aToken* called the pool; in v2 the *pool* calls the aToken. `AToken.redeem` is gone |
| `borrow(reserve, amount, interestRateMode, referralCode)` | `LendingPool.sol:409` | `borrow(asset, amount, interestRateMode, referralCode, onBehalfOf)` | Gained credit delegation. The origination fee is gone |
| `repay(reserve, amount, onBehalfOf)` | `LendingPool.sol:521` | `repay(asset, amount, rateMode, onBehalfOf)` | Gained an explicit `rateMode`, because debt is now two separate tokens |
| `swapBorrowRateMode(reserve)` | `LendingPool.sol:604` | `swapBorrowRateMode(asset, rateMode)` | Gained the target mode as an argument |
| `rebalanceStableBorrowRate(reserve, user)` | `LendingPool.sol:667` | `rebalanceStableBorrowRate(asset, user)` | Same semantics, thresholds moved into `ValidationLogic` |
| `setUserUseReserveAsCollateral(reserve, useAsCollateral)` | `LendingPool.sol:723` | `setUserUseReserveAsCollateral(asset, useAsCollateral)` | Unchanged |
| `liquidationCall(collateral, reserve, user, purchaseAmount, receiveAToken)` | `LendingPool.sol:764` | `liquidationCall(collateralAsset, debtAsset, user, debtToCover, receiveAToken)` | Still a `delegatecall`, now to `LendingPoolCollateralManager`. Origination-fee seizure removed |
| `flashLoan(receiver, reserve, amount, params)` | `LendingPool.sol:806` | `flashLoan(receiver, assets[], amounts[], modes[], onBehalfOf, params, referralCode)` | Multi-asset, and can end as debt instead of repayment |
| `getReserveConfigurationData(reserve)` | `LendingPool.sol:874` | `AaveProtocolDataProvider.getReserveConfigurationData(asset)` | Moved out of the pool |
| `getReserveData(reserve)` | `LendingPool.sol:906` | `LendingPool.getReserveData(asset)` + the data provider | Pool now returns the raw struct |
| `getUserAccountData(user)` | `LendingPool.sol:947` | `getUserAccountData(user)` | Same six fields, no origination-fee field |
| `getUserReserveData(reserve, user)` | `LendingPool.sol:987` | `AaveProtocolDataProvider.getUserReserveData(asset, user)` | Moved |
| `getReserves()` | `LendingPool.sol:1000` | `getReservesList()` | Renamed |
| `AToken.redeem(amount)` | `AToken.sol:222` | **Removed** | Replaced by `LendingPool.withdraw` |
| `AToken.redirectInterestStream(to)` | `AToken.sol:167` | **Removed** | Interest redirection did not survive. Its use cases moved to holding aTokens directly |
| `AToken.redirectInterestStreamOf(from, to)` | `AToken.sol:190` | **Removed** | |
| `AToken.allowInterestRedirectionTo(to)` | `AToken.sol:205` | **Removed** | |
| `AToken.mintOnDeposit(account, amount)` | `AToken.sol:262` | `AToken.mint(user, amount, index)` | Now takes the index and returns `isFirstDeposit` |
| `AToken.burnOnLiquidation(account, value)` | `AToken.sol:279` | `AToken.burn(user, receiver, amount, index)` | Unified with withdrawal |
| `AToken.transferOnLiquidation(from, to, value)` | `AToken.sol:296` | `AToken.transferOnLiquidation(from, to, value)` | Kept |
| `AToken.principalBalanceOf(user)` | `AToken.sol:436` | `AToken.scaledBalanceOf(user)` | Renamed and re-based on the scaled model |
| `AToken.getUserIndex(user)` | `AToken.sol:497` | **Removed** | There is no per-user index in v2; one global index suffices |
| `LendingPoolCore.*` (all ~60) | `LendingPoolCore.sol` | Split | State → `LendingPoolStorage._reserves` and the debt tokens. Funds → the aTokens. Mutators → `ReserveLogic`. Getters → `AaveProtocolDataProvider` |
| `LendingPoolDataProvider.calculateUserGlobalData` | `LendingPoolDataProvider.sol:87` | `GenericLogic.calculateUserAccountData` | Same job, now a linked library |
| `LendingPoolDataProvider.balanceDecreaseAllowed` | `LendingPoolDataProvider.sol:174` | `GenericLogic.balanceDecreaseAllowed` | Moved |
| `FeeProvider.calculateLoanOriginationFee` | `FeeProvider.sol` | **Removed** | v2 charges no origination fee; revenue comes from the reserve factor instead |
| `TokenDistributor` | `fees/TokenDistributor.sol` | **Removed** | Replaced by the treasury address on each aToken |
| `LendingPoolParametersProvider` | `configuration/` | **Removed** | Its constants became `LendingPool` state (`_maxStableRateBorrowSizePercent`, `_maxNumberOfReserves`) |
| `ChainlinkProxyPriceProvider` | `misc/` | `AaveOracle` | Renamed, same `latestAnswer` + fallback design |
| — | — | `StableDebtToken` / `VariableDebtToken` | **New.** Debt became transferable-in-principle ERC20s (transfers disabled) |
| — | — | `approveDelegation` | **New.** Credit delegation has no v1 equivalent |
| — | — | Reserve factor + `mintToTreasury` | **New.** Protocol revenue mechanism replacing the origination fee |
| — | — | `setPause` / emergency admin | **New.** v1 had per-reserve freeze only |
| — | — | The `adapters/` suite | **New.** Flash-loan-composed collateral swaps and repayments |

**The one-line summary.** v1 asked "where is the money and who owes what?" and
answered with a single 1,775-line contract. v2 asked the same question and
answered with tokens: an aToken per reserve holding the funds, two debt tokens
per reserve holding the liabilities, and a pool contract that owns nothing and
only sequences the four steps. Every other difference in this Part follows from
that one decision.
