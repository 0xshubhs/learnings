# Morpho — Complete Reference

An exhaustive, function-by-function reference for the four repositories that make up the
Morpho stack, written against the exact sources cloned in this folder.

| Repo | Folder | Files | What it is |
|---|---|---|---|
| Morpho Blue | `morpho-blue/` | 22 | The immutable lending primitive. One contract, 557 lines. |
| MetaMorpho | `metamorpho/` | 15 | ERC-4626 vaults that allocate across Blue markets. |
| Oracles | `morpho-blue-oracles/` | 12 | Chainlink-composing oracle adapters producing Blue's 1e36 price. |
| Bundlers | `morpho-blue-bundlers/` | 53 | `delegatecall` multicall batching, permits, and migrations. |

For the *why* — the design argument, the comparison against Aave, the end-to-end narrative —
read [`MORPHO-DEEP-DIVE.md`](MORPHO-DEEP-DIVE.md) first. This document is the *what* and the
*how*: every contract, every function, every parameter, every revert.

Every citation below is a clickable link to the exact line. All line numbers were verified
with `grep -n` against these files, storage slots were confirmed with `forge inspect`, and
selectors were computed with `cast sig` rather than transcribed.

---

## Table of contents

- [0. File inventory](#0-file-inventory)
- [1. Morpho Blue: the data model](#1-morpho-blue-the-data-model)
- [2. Morpho Blue: the math, derived](#2-morpho-blue-the-math-derived)
- [3. `Morpho.sol` — every function](#3-morphosol--every-function)
- [4. Morpho Blue libraries](#4-morpho-blue-libraries)
- [5. Morpho Blue periphery libraries](#5-morpho-blue-periphery-libraries)
- [6. Morpho Blue interfaces and mocks](#6-morpho-blue-interfaces-and-mocks)
- [7. MetaMorpho: roles, timelocks, queues](#7-metamorpho-roles-timelocks-queues)
- [8. `MetaMorpho.sol` — every function](#8-metamorphosol--every-function)
- [9. MetaMorpho factory, libraries, interfaces, mocks](#9-metamorpho-factory-libraries-interfaces-mocks)
- [10. Oracles](#10-oracles)
- [11. Bundlers](#11-bundlers)
- [12. Storage layouts](#12-storage-layouts)
- [13. Selector / ABI tables](#13-selector--abi-tables)
- [14. Events reference](#14-events-reference)
- [15. Errors reference](#15-errors-reference)
- [16. Use-case index](#16-use-case-index)
- [17. Gotchas, collected](#17-gotchas-collected)

---

<a id="0-file-inventory"></a>
## 0. File inventory

All 102 Solidity files across the four repos. Nothing is omitted.

### Morpho Blue — `morpho-blue/` (22 files)

| File | Lines | Kind | Purpose |
|---|---:|---|---|
| [`morpho-blue/src/Morpho.sol`](morpho-blue/src/Morpho.sol) | 558 | contract | The Morpho contract. |
| [`morpho-blue/src/interfaces/IERC20.sol`](morpho-blue/src/interfaces/IERC20.sol) | 10 | interface | IERC20 |
| [`morpho-blue/src/interfaces/IIrm.sol`](morpho-blue/src/interfaces/IIrm.sol) | 20 | interface | Interface that Interest Rate Models (IRMs) used by Morpho must implement. |
| [`morpho-blue/src/interfaces/IMorpho.sol`](morpho-blue/src/interfaces/IMorpho.sol) | 356 | interface | The EIP-712 domain separator. |
| [`morpho-blue/src/interfaces/IMorphoCallbacks.sol`](morpho-blue/src/interfaces/IMorphoCallbacks.sol) | 53 | interface | Interface that liquidators willing to use `liquidate`'s callback must implement. |
| [`morpho-blue/src/interfaces/IOracle.sol`](morpho-blue/src/interfaces/IOracle.sol) | 16 | interface | Interface that oracles used by Morpho must implement. |
| [`morpho-blue/src/libraries/ConstantsLib.sol`](morpho-blue/src/libraries/ConstantsLib.sol) | 22 | contract |  |
| [`morpho-blue/src/libraries/ErrorsLib.sol`](morpho-blue/src/libraries/ErrorsLib.sol) | 81 | library | Library exposing error messages. |
| [`morpho-blue/src/libraries/EventsLib.sol`](morpho-blue/src/libraries/EventsLib.sol) | 151 | library | Library exposing events. |
| [`morpho-blue/src/libraries/MarketParamsLib.sol`](morpho-blue/src/libraries/MarketParamsLib.sol) | 22 | library | Library to convert a market to its id. |
| [`morpho-blue/src/libraries/MathLib.sol`](morpho-blue/src/libraries/MathLib.sol) | 46 | library | Library to manage fixed-point arithmetic. |
| [`morpho-blue/src/libraries/SafeTransferLib.sol`](morpho-blue/src/libraries/SafeTransferLib.sol) | 37 | interface | Library to manage transfers of tokens, even if calls to the transfer or transferFrom functions a |
| [`morpho-blue/src/libraries/SharesMathLib.sol`](morpho-blue/src/libraries/SharesMathLib.sol) | 46 | library | Shares management library. |
| [`morpho-blue/src/libraries/UtilsLib.sol`](morpho-blue/src/libraries/UtilsLib.sol) | 39 | library | Library exposing helpers. |
| [`morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol) | 119 | library | Helper library exposing getters with the expected value after interest accrual. |
| [`morpho-blue/src/libraries/periphery/MorphoLib.sol`](morpho-blue/src/libraries/periphery/MorphoLib.sol) | 64 | library | Helper library to access Morpho storage variables. |
| [`morpho-blue/src/libraries/periphery/MorphoStorageLib.sol`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol) | 111 | library | Helper library exposing getters to access Morpho storage variables' slot. |
| [`morpho-blue/src/mocks/ERC20Mock.sol`](morpho-blue/src/mocks/ERC20Mock.sol) | 53 | contract |  |
| [`morpho-blue/src/mocks/FlashBorrowerMock.sol`](morpho-blue/src/mocks/FlashBorrowerMock.sol) | 25 | contract |  |
| [`morpho-blue/src/mocks/IrmMock.sol`](morpho-blue/src/mocks/IrmMock.sol) | 26 | contract |  |
| [`morpho-blue/src/mocks/OracleMock.sol`](morpho-blue/src/mocks/OracleMock.sol) | 13 | contract |  |
| [`morpho-blue/src/mocks/interfaces/IERC20.sol`](morpho-blue/src/mocks/interfaces/IERC20.sol) | 25 | interface |  |

### MetaMorpho — `metamorpho/` (15 files)

| File | Lines | Kind | Purpose |
|---|---:|---|---|
| [`metamorpho/src/MetaMorpho.sol`](metamorpho/src/MetaMorpho.sol) | 912 | contract | ERC4626 compliant vault allowing users to deposit assets to Morpho. |
| [`metamorpho/src/MetaMorphoFactory.sol`](metamorpho/src/MetaMorphoFactory.sol) | 59 | contract | This contract allows to create MetaMorpho vaults, and to index them easily. |
| [`metamorpho/src/interfaces/IMetaMorpho.sol`](metamorpho/src/interfaces/IMetaMorpho.sol) | 223 | interface | The market to allocate. |
| [`metamorpho/src/interfaces/IMetaMorphoFactory.sol`](metamorpho/src/interfaces/IMetaMorphoFactory.sol) | 33 | interface | Interface of MetaMorpho's factory. |
| [`metamorpho/src/libraries/ConstantsLib.sol`](metamorpho/src/libraries/ConstantsLib.sol) | 21 | library | Library exposing constants. |
| [`metamorpho/src/libraries/ErrorsLib.sol`](metamorpho/src/libraries/ErrorsLib.sol) | 99 | library | Library exposing error messages. |
| [`metamorpho/src/libraries/EventsLib.sol`](metamorpho/src/libraries/EventsLib.sol) | 110 | library | Library exposing events. |
| [`metamorpho/src/libraries/PendingLib.sol`](metamorpho/src/libraries/PendingLib.sol) | 49 | library | The maximum amount of assets that can be allocated to the market. |
| [`metamorpho/src/mocks/ERC1820Registry.sol`](metamorpho/src/mocks/ERC1820Registry.sol) | 222 | interface | Indicates whether the contract implements the interface 'interfaceHash' for the address 'addr' o |
| [`metamorpho/src/mocks/ERC20Mock.sol`](metamorpho/src/mocks/ERC20Mock.sol) | 24 | contract |  |
| [`metamorpho/src/mocks/ERC777Mock.sol`](metamorpho/src/mocks/ERC777Mock.sol) | 532 | contract |  |
| [`metamorpho/src/mocks/IrmMock.sol`](metamorpho/src/mocks/IrmMock.sol) | 26 | contract |  |
| [`metamorpho/src/mocks/MetaMorphoMock.sol`](metamorpho/src/mocks/MetaMorphoMock.sol) | 28 | contract |  |
| [`metamorpho/src/mocks/MorphoImport.sol`](metamorpho/src/mocks/MorphoImport.sol) | 8 | contract |  |
| [`metamorpho/src/mocks/OracleMock.sol`](metamorpho/src/mocks/OracleMock.sol) | 13 | contract |  |

### Oracles — `morpho-blue-oracles/` (12 files)

| File | Lines | Kind | Purpose |
|---|---:|---|---|
| [`morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol) | 158 | contract | Morpho Blue oracle using Chainlink-compliant feeds. |
| [`morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2Factory.sol`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2Factory.sol) | 55 | contract | This contract allows to create MorphoChainlinkOracleV2 oracles, and to index them easily. |
| [`morpho-blue-oracles/src/morpho-chainlink/interfaces/AggregatorV3Interface.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/AggregatorV3Interface.sol) | 23 | interface |  |
| [`morpho-blue-oracles/src/morpho-chainlink/interfaces/IERC4626.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/IERC4626.sol) | 7 | interface |  |
| [`morpho-blue-oracles/src/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2.sol) | 40 | interface | Interface of MorphoChainlinkOracleV2. |
| [`morpho-blue-oracles/src/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2Factory.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2Factory.sol) | 57 | interface | Interface for MorphoChainlinkOracleV2Factory |
| [`morpho-blue-oracles/src/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol`](morpho-blue-oracles/src/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol) | 37 | library | Library exposing functions to interact with a Chainlink-compliant feed. |
| [`morpho-blue-oracles/src/morpho-chainlink/libraries/ErrorsLib.sol`](morpho-blue-oracles/src/morpho-chainlink/libraries/ErrorsLib.sol) | 18 | library | Library exposing error messages. |
| [`morpho-blue-oracles/src/morpho-chainlink/libraries/VaultLib.sol`](morpho-blue-oracles/src/morpho-chainlink/libraries/VaultLib.sol) | 19 | library | Library exposing functions to price shares of an ERC4626 vault. |
| [`morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol) | 31 | contract | wstETH/stETH exchange rate price feed. |
| [`morpho-blue-oracles/src/wsteth-exchange-rate-adapter/interfaces/IStEth.sol`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/interfaces/IStEth.sol) | 7 | interface |  |
| [`morpho-blue-oracles/src/wsteth-exchange-rate-adapter/interfaces/MinimalAggregatorV3Interface.sol`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/interfaces/MinimalAggregatorV3Interface.sol) | 18 | interface | Returns the precision of the feed. |

### Bundlers — `morpho-blue-bundlers/` (53 files)

| File | Lines | Kind | Purpose |
|---|---:|---|---|
| [`morpho-blue-bundlers/src/BaseBundler.sol`](morpho-blue-bundlers/src/BaseBundler.sol) | 99 | abstract | Enables calling multiple functions in a single call to the same contract (self). |
| [`morpho-blue-bundlers/src/ERC20WrapperBundler.sol`](morpho-blue-bundlers/src/ERC20WrapperBundler.sol) | 59 | abstract | Enables the wrapping and unwrapping of ERC20 tokens. The largest usecase is to wrap permissionle |
| [`morpho-blue-bundlers/src/ERC4626Bundler.sol`](morpho-blue-bundlers/src/ERC4626Bundler.sol) | 123 | abstract | Bundler contract managing interactions with ERC4626 compliant tokens. |
| [`morpho-blue-bundlers/src/MorphoBundler.sol`](morpho-blue-bundlers/src/MorphoBundler.sol) | 272 | abstract | Bundler contract managing interactions with Morpho. |
| [`morpho-blue-bundlers/src/Permit2Bundler.sol`](morpho-blue-bundlers/src/Permit2Bundler.sol) | 51 | abstract | Bundler contract managing interactions with Uniswap's Permit2. |
| [`morpho-blue-bundlers/src/PermitBundler.sol`](morpho-blue-bundlers/src/PermitBundler.sol) | 33 | abstract | Bundler contract managing interactions with tokens implementing EIP-2612. |
| [`morpho-blue-bundlers/src/StEthBundler.sol`](morpho-blue-bundlers/src/StEthBundler.sol) | 82 | abstract | Contract allowing to bundle multiple interactions with stETH together. |
| [`morpho-blue-bundlers/src/TransferBundler.sol`](morpho-blue-bundlers/src/TransferBundler.sol) | 66 | abstract | Enables transfer of ERC20 and native tokens. |
| [`morpho-blue-bundlers/src/UrdBundler.sol`](morpho-blue-bundlers/src/UrdBundler.sol) | 41 | abstract | Bundler that allows to claim token rewards on the Universal Rewards Distributor. |
| [`morpho-blue-bundlers/src/WNativeBundler.sol`](morpho-blue-bundlers/src/WNativeBundler.sol) | 66 | abstract | Bundler contract managing interactions with network's wrapped native token. |
| [`morpho-blue-bundlers/src/chain-agnostic/ChainAgnosticBundlerV2.sol`](morpho-blue-bundlers/src/chain-agnostic/ChainAgnosticBundlerV2.sol) | 39 | contract | Chain agnostic bundler contract. |
| [`morpho-blue-bundlers/src/ethereum/EthereumBundlerV2.sol`](morpho-blue-bundlers/src/ethereum/EthereumBundlerV2.sol) | 43 | contract | Bundler contract specific to Ethereum. |
| [`morpho-blue-bundlers/src/ethereum/EthereumPermitBundler.sol`](morpho-blue-bundlers/src/ethereum/EthereumPermitBundler.sol) | 35 | abstract | PermitBundler contract specific to Ethereum, handling permit to DAI. |
| [`morpho-blue-bundlers/src/ethereum/EthereumStEthBundler.sol`](morpho-blue-bundlers/src/ethereum/EthereumStEthBundler.sol) | 17 | abstract | StEthBundler contract specific to Ethereum. |
| [`morpho-blue-bundlers/src/ethereum/interfaces/IDaiPermit.sol`](morpho-blue-bundlers/src/ethereum/interfaces/IDaiPermit.sol) | 27 | interface |  |
| [`morpho-blue-bundlers/src/ethereum/libraries/MainnetLib.sol`](morpho-blue-bundlers/src/ethereum/libraries/MainnetLib.sol) | 14 | library |  |
| [`morpho-blue-bundlers/src/goerli/GoerliBundlerV2.sol`](morpho-blue-bundlers/src/goerli/GoerliBundlerV2.sol) | 43 | contract | Bundler contract specific to the Goerli testnet. |
| [`morpho-blue-bundlers/src/goerli/libraries/GoerliLib.sol`](morpho-blue-bundlers/src/goerli/libraries/GoerliLib.sol) | 11 | library |  |
| [`morpho-blue-bundlers/src/interfaces/IMorphoBundler.sol`](morpho-blue-bundlers/src/interfaces/IMorphoBundler.sol) | 21 | interface | Interface of MorphoBundler. |
| [`morpho-blue-bundlers/src/interfaces/IMulticall.sol`](morpho-blue-bundlers/src/interfaces/IMulticall.sol) | 13 | interface | Interface of Multicall. |
| [`morpho-blue-bundlers/src/interfaces/IPublicAllocator.sol`](morpho-blue-bundlers/src/interfaces/IPublicAllocator.sol) | 37 | interface |  |
| [`morpho-blue-bundlers/src/interfaces/IStEth.sol`](morpho-blue-bundlers/src/interfaces/IStEth.sol) | 17 | interface |  |
| [`morpho-blue-bundlers/src/interfaces/IWNative.sol`](morpho-blue-bundlers/src/interfaces/IWNative.sol) | 10 | interface |  |
| [`morpho-blue-bundlers/src/interfaces/IWstEth.sol`](morpho-blue-bundlers/src/interfaces/IWstEth.sol) | 29 | interface |  |
| [`morpho-blue-bundlers/src/libraries/ConstantsLib.sol`](morpho-blue-bundlers/src/libraries/ConstantsLib.sol) | 6 | contract |  |
| [`morpho-blue-bundlers/src/libraries/ErrorsLib.sol`](morpho-blue-bundlers/src/libraries/ErrorsLib.sol) | 55 | library | Library exposing error messages. |
| [`morpho-blue-bundlers/src/migration/AaveV2MigrationBundlerV2.sol`](morpho-blue-bundlers/src/migration/AaveV2MigrationBundlerV2.sol) | 69 | contract | Contract allowing to migrate a position from Aave V2 to Morpho Blue easily. |
| [`morpho-blue-bundlers/src/migration/AaveV3MigrationBundlerV2.sol`](morpho-blue-bundlers/src/migration/AaveV3MigrationBundlerV2.sol) | 59 | contract | Contract allowing to migrate a position from Aave V3 to Morpho Blue easily. |
| [`morpho-blue-bundlers/src/migration/AaveV3OptimizerMigrationBundlerV2.sol`](morpho-blue-bundlers/src/migration/AaveV3OptimizerMigrationBundlerV2.sol) | 94 | contract | Contract allowing to migrate a position from AaveV3 Optimizer to Morpho Blue easily. |
| [`morpho-blue-bundlers/src/migration/CompoundV2MigrationBundlerV2.sol`](morpho-blue-bundlers/src/migration/CompoundV2MigrationBundlerV2.sol) | 87 | contract | Contract allowing to migrate a position from Compound V2 to Morpho Blue easily. |
| [`morpho-blue-bundlers/src/migration/CompoundV3MigrationBundlerV2.sol`](morpho-blue-bundlers/src/migration/CompoundV3MigrationBundlerV2.sol) | 91 | contract | Contract allowing to migrate a position from Compound V3 to Morpho Blue easily. |
| [`morpho-blue-bundlers/src/migration/MigrationBundler.sol`](morpho-blue-bundlers/src/migration/MigrationBundler.sol) | 31 | abstract | Abstract contract allowing to migrate a position from one lending protocol to Morpho Blue easily |
| [`morpho-blue-bundlers/src/migration/interfaces/IAaveV2.sol`](morpho-blue-bundlers/src/migration/interfaces/IAaveV2.sol) | 262 | interface |  |
| [`morpho-blue-bundlers/src/migration/interfaces/IAaveV3.sol`](morpho-blue-bundlers/src/migration/interfaces/IAaveV3.sol) | 524 | interface |  |
| [`morpho-blue-bundlers/src/migration/interfaces/IAaveV3Optimizer.sol`](morpho-blue-bundlers/src/migration/interfaces/IAaveV3Optimizer.sol) | 88 | interface | Contains the `v`, `r` and `s` parameters of an ECDSA signature. |
| [`morpho-blue-bundlers/src/migration/interfaces/ICEth.sol`](morpho-blue-bundlers/src/migration/interfaces/ICEth.sol) | 21 | interface |  |
| [`morpho-blue-bundlers/src/migration/interfaces/ICToken.sol`](morpho-blue-bundlers/src/migration/interfaces/ICToken.sol) | 23 | interface |  |
| [`morpho-blue-bundlers/src/migration/interfaces/ICompoundV3.sol`](morpho-blue-bundlers/src/migration/interfaces/ICompoundV3.sol) | 59 | interface |  |
| [`morpho-blue-bundlers/src/migration/interfaces/IComptroller.sol`](morpho-blue-bundlers/src/migration/interfaces/IComptroller.sol) | 7 | interface |  |
| [`morpho-blue-bundlers/src/mocks/AdaptiveCurveIrmImport.sol`](morpho-blue-bundlers/src/mocks/AdaptiveCurveIrmImport.sol) | 7 | contract |  |
| [`morpho-blue-bundlers/src/mocks/ERC20Mock.sol`](morpho-blue-bundlers/src/mocks/ERC20Mock.sol) | 14 | contract |  |
| [`morpho-blue-bundlers/src/mocks/ERC20PermitMock.sol`](morpho-blue-bundlers/src/mocks/ERC20PermitMock.sol) | 15 | contract |  |
| [`morpho-blue-bundlers/src/mocks/ERC20WrapperMock.sol`](morpho-blue-bundlers/src/mocks/ERC20WrapperMock.sol) | 18 | contract |  |
| [`morpho-blue-bundlers/src/mocks/ERC4626Mock.sol`](morpho-blue-bundlers/src/mocks/ERC4626Mock.sol) | 11 | contract |  |
| [`morpho-blue-bundlers/src/mocks/IrmMock.sol`](morpho-blue-bundlers/src/mocks/IrmMock.sol) | 24 | contract |  |
| [`morpho-blue-bundlers/src/mocks/MetaMorphoImport.sol`](morpho-blue-bundlers/src/mocks/MetaMorphoImport.sol) | 7 | contract |  |
| [`morpho-blue-bundlers/src/mocks/MorphoImport.sol`](morpho-blue-bundlers/src/mocks/MorphoImport.sol) | 7 | contract |  |
| [`morpho-blue-bundlers/src/mocks/MorphoMock.sol`](morpho-blue-bundlers/src/mocks/MorphoMock.sol) | 9 | contract |  |
| [`morpho-blue-bundlers/src/mocks/OracleMock.sol`](morpho-blue-bundlers/src/mocks/OracleMock.sol) | 13 | contract |  |
| [`morpho-blue-bundlers/src/mocks/PublicAllocatorImport.sol`](morpho-blue-bundlers/src/mocks/PublicAllocatorImport.sol) | 7 | contract |  |
| [`morpho-blue-bundlers/src/mocks/UrdFactoryImport.sol`](morpho-blue-bundlers/src/mocks/UrdFactoryImport.sol) | 7 | contract |  |
| [`morpho-blue-bundlers/src/sepolia/SepoliaBundlerV2.sol`](morpho-blue-bundlers/src/sepolia/SepoliaBundlerV2.sol) | 47 | contract | Bundler contract specific to the Sepolia testnet. |
| [`morpho-blue-bundlers/src/sepolia/libraries/SepoliaLib.sol`](morpho-blue-bundlers/src/sepolia/libraries/SepoliaLib.sol) | 13 | library |  |

---

<a id="1-morpho-blue-the-data-model"></a>
## 1. Morpho Blue: the data model

Everything in Blue is derived from four declarations in
[`morpho-blue/src/interfaces/IMorpho.sol`](morpho-blue/src/interfaces/IMorpho.sol). Read these
first; the rest of the contract is bookkeeping over them.

### 1.1 `Id` and `MarketParams`

```solidity
type Id is bytes32;

struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}
```

[`morpho-blue/src/interfaces/IMorpho.sol:4-12`](morpho-blue/src/interfaces/IMorpho.sol#L4-L12)

A market **is** these five fields. There is no registry entry to look up, no market index, no
per-market contract. The identity of a market is the hash of its parameters, computed in
[`MarketParamsLib.id`](morpho-blue/src/libraries/MarketParamsLib.sol#L16-L20):

```solidity
uint256 internal constant MARKET_PARAMS_BYTES_LENGTH = 5 * 32;

function id(MarketParams memory marketParams) internal pure returns (Id marketParamsId) {
    assembly ("memory-safe") {
        marketParamsId := keccak256(marketParams, MARKET_PARAMS_BYTES_LENGTH)
    }
}
```

The assembly hashes the struct's 160 bytes of memory directly. This is safe only because
`MarketParams` is five 32-byte words with no dynamic types and no packing, which is what the
`5 * 32` comment at
[`MarketParamsLib.sol:13`](morpho-blue/src/libraries/MarketParamsLib.sol#L13) is asserting.
Add a sixth field or make one of them `uint128` and this silently breaks.

**Consequence worth internalising:** changing *any* parameter produces a different market. There
is no "update the oracle on market X". A market's oracle, IRM and LLTV are immutable for the
market's entire life, because they are its name.

### 1.2 `Position` — 2 slots per user per market

```solidity
struct Position {
    uint256 supplyShares;
    uint128 borrowShares;
    uint128 collateral;
}
```

[`morpho-blue/src/interfaces/IMorpho.sol:16-20`](morpho-blue/src/interfaces/IMorpho.sol#L16-L20)

`supplyShares` occupies a full word because share counts are inflated by `VIRTUAL_SHARES = 1e6`
(§2.1) and need the headroom. `borrowShares` and `collateral` share the second word as two
`uint128`s, which is why [`MorphoLib.collateral`](morpho-blue/src/libraries/periphery/MorphoLib.sol#L23-L26)
reads it with `>> 128` and
[`MorphoLib.borrowShares`](morpho-blue/src/libraries/periphery/MorphoLib.sol#L18-L21) with a
`uint128` truncation.

The docstring at
[`IMorpho.sol:14-15`](morpho-blue/src/interfaces/IMorpho.sol#L14-L15) carries a trap: for
`feeRecipient`, `supplyShares` does **not** include shares accrued since the last interest
accrual. `MorphoBalancesLib.expectedSupplyAssets` repeats the warning at
[`MorphoBalancesLib.sol:91`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L91).

### 1.3 `Market` — 3 slots per market

```solidity
struct Market {
    uint128 totalSupplyAssets;
    uint128 totalSupplyShares;
    uint128 totalBorrowAssets;
    uint128 totalBorrowShares;
    uint128 lastUpdate;
    uint128 fee;
}
```

[`morpho-blue/src/interfaces/IMorpho.sol:26-33`](morpho-blue/src/interfaces/IMorpho.sol#L26-L33)

Six `uint128` fields pack into exactly three words, which is the entire per-market state. Compare
that with Aave's `ReserveData`, which is a 300-line struct plus two configuration bitmaps plus a
separate aToken and debt token contract per reserve
(see [`../aave/V3-PROTOCOL-COMPLETE-REFERENCE.md`](../aave/V3-PROTOCOL-COMPLETE-REFERENCE.md)).

`lastUpdate != 0` is the market-exists predicate. It is set once in `createMarket` at
[`Morpho.sol:157`](morpho-blue/src/Morpho.sol#L157) and checked at the top of almost every
function. Because `block.timestamp` is never zero on a live chain, this doubles as both a
liveness flag and the interest-accrual clock with no extra storage.

`fee` is capped at `MAX_FEE = 0.25e18` by
[`Morpho.sol:127`](morpho-blue/src/Morpho.sol#L127) against
[`ConstantsLib.sol:5`](morpho-blue/src/libraries/ConstantsLib.sol#L5).

### 1.4 `Authorization` and `Signature`

```solidity
struct Authorization {
    address authorizer;
    address authorized;
    bool isAuthorized;
    uint256 nonce;
    uint256 deadline;
}

struct Signature { uint8 v; bytes32 r; bytes32 s; }
```

[`morpho-blue/src/interfaces/IMorpho.sol:35-47`](morpho-blue/src/interfaces/IMorpho.sol#L35-L47)

Used only by `setAuthorizationWithSig` (§3.16). The EIP-712 type hash is fixed at
[`ConstantsLib.sol:20-21`](morpho-blue/src/libraries/ConstantsLib.sol#L20-L21).

### 1.5 Storage layout

Nine slots, confirmed with `forge inspect src/Morpho.sol:Morpho storage`:

| Slot | Name | Type |
|---:|---|---|
| — | `DOMAIN_SEPARATOR` | `bytes32` immutable — in bytecode, not storage |
| 0 | `owner` | `address` |
| 1 | `feeRecipient` | `address` |
| 2 | `position` | `mapping(Id => mapping(address => Position))` |
| 3 | `market` | `mapping(Id => Market)` |
| 4 | `isIrmEnabled` | `mapping(address => bool)` |
| 5 | `isLltvEnabled` | `mapping(uint256 => bool)` |
| 6 | `isAuthorized` | `mapping(address => mapping(address => bool))` |
| 7 | `nonce` | `mapping(address => uint256)` |
| 8 | `idToMarketParams` | `mapping(Id => MarketParams)` |

Declared at [`Morpho.sol:49-70`](morpho-blue/src/Morpho.sol#L49-L70). These nine numbers are
mirrored as constants in
[`MorphoStorageLib.sol:14-22`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L14-L22),
and §5.1 shows how the library reconstructs every derived slot from them.

---

<a id="2-morpho-blue-the-math-derived"></a>
## 2. Morpho Blue: the math, derived

Four small libraries carry all of Blue's arithmetic. Each is derived here rather than restated.

### 2.1 `SharesMathLib` — virtual shares and the inflation attack

[`morpho-blue/src/libraries/SharesMathLib.sol`](morpho-blue/src/libraries/SharesMathLib.sol), 45 lines.

```solidity
uint256 internal constant VIRTUAL_SHARES = 1e6;
uint256 internal constant VIRTUAL_ASSETS = 1;
```

[`SharesMathLib.sol:20`](morpho-blue/src/libraries/SharesMathLib.sol#L20) and
[`:24`](morpho-blue/src/libraries/SharesMathLib.sol#L24).

Every conversion adds these offsets to both sides of the ratio:

| Function | Formula | Rounding | Line |
|---|---|---|---|
| `toSharesDown` | `assets · (S + 1e6) / (A + 1)` | down | [`:27-29`](morpho-blue/src/libraries/SharesMathLib.sol#L27-L29) |
| `toAssetsDown` | `shares · (A + 1) / (S + 1e6)` | down | [`:32-34`](morpho-blue/src/libraries/SharesMathLib.sol#L32-L34) |
| `toSharesUp` | `assets · (S + 1e6) / (A + 1)` | up | [`:37-39`](morpho-blue/src/libraries/SharesMathLib.sol#L37-L39) |
| `toAssetsUp` | `shares · (A + 1) / (S + 1e6)` | up | [`:42-44`](morpho-blue/src/libraries/SharesMathLib.sol#L42-L44) |

**Why the offset works.** The classic ERC-4626 inflation attack is: be the first depositor with
1 wei, donate a large amount to inflate the share price, then the victim's deposit rounds down to
zero shares. With the offset, an empty market prices 1 wei of assets at `1 · 1e6 / 1 = 1e6`
shares, so the attacker cannot own a share supply small enough to make the victim's division
truncate to zero.

Simulated against the real integer arithmetic, with the attacker seeding 1 wei and the victim
depositing 1e18:

| Attacker inflation | Victim shares | Victim redeems | Loss |
|---:|---:|---:|---:|
| 1e6 | 1999996000007999984 | 999999999999999999 | 1 wei |
| 1e12 | 1999999999996 | 999999999999999999 | 1 wei |
| 1e18 | 1999999 | 999999749999937500 | 0.000025% |
| 1e24 | 1 | 500000249999875000 | 49.999975% |

Without the offset the same victim deposit yields **0 shares** and loses everything.

**But the offset is defence in depth, not the primary defence.** Blue tracks
`market[id].totalSupplyAssets` as internal accounting, incremented only inside `supply`
([`Morpho.sol:188`](morpho-blue/src/Morpho.sol#L188)) and `_accrueInterest`
([`:491`](morpho-blue/src/Morpho.sol#L491)). It never reads `balanceOf(address(this))`. A raw
token transfer to the Morpho contract therefore inflates nothing — it is simply lost. To move the
share price an attacker must actually `supply`, which mints them shares at the same price. The
1e24 row above requires genuinely supplying 1e24 assets, not donating them.

The docstring at
[`SharesMathLib.sol:17-19`](morpho-blue/src/libraries/SharesMathLib.sol#L17-L19) flags the mirror
image: virtual *borrow* shares are entitled to assets nobody will ever repay, so they behave like
a dust-sized permanent bad debt.

**Rounding discipline.** Every call site picks the direction that favours the protocol:

| Call site | Function | Direction | Line |
|---|---|---|---|
| `supply` (assets given) | `toSharesDown` | user gets fewer shares | [`Morpho.sol:183`](morpho-blue/src/Morpho.sol#L183) |
| `supply` (shares given) | `toAssetsUp` | user pays more assets | [`:184`](morpho-blue/src/Morpho.sol#L184) |
| `withdraw` (assets given) | `toSharesUp` | user burns more shares | [`:216`](morpho-blue/src/Morpho.sol#L216) |
| `withdraw` (shares given) | `toAssetsDown` | user gets fewer assets | [`:217`](morpho-blue/src/Morpho.sol#L217) |
| `borrow` (assets given) | `toSharesUp` | user owes more shares | [`:251`](morpho-blue/src/Morpho.sol#L251) |
| `borrow` (shares given) | `toAssetsDown` | user receives fewer assets | [`:252`](morpho-blue/src/Morpho.sol#L252) |
| `repay` (assets given) | `toSharesDown` | user clears fewer shares | [`:283`](morpho-blue/src/Morpho.sol#L283) |
| `repay` (shares given) | `toAssetsUp` | user pays more assets | [`:284`](morpho-blue/src/Morpho.sol#L284) |

The pattern is mechanical: supply and repay round *down* on shares out and *up* on assets in;
withdraw and borrow round *up* on shares out and *down* on assets out.

### 2.2 `MathLib.wTaylorCompounded` — truncated continuous compounding

[`morpho-blue/src/libraries/MathLib.sol:38-44`](morpho-blue/src/libraries/MathLib.sol#L38-L44):

```solidity
function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
    uint256 firstTerm = x * n;
    uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
    uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);

    return firstTerm + secondTerm + thirdTerm;
}
```

Let `z = x·n` (rate per second times elapsed seconds). The exact continuous factor is

```
e^z − 1 = z + z²/2! + z³/3! + z⁴/4! + …
```

The code computes `z + z²/2 + z³/6`, i.e. the first three non-zero terms. The third term is built
as `secondTerm · firstTerm / (3·WAD)` = `(z²/2)·z/3` = `z³/6`, which is `3!` as required.

**Error is always an underestimate**, since every omitted term is positive. Measured against
`e^z − 1`:

| APR | Elapsed | Taylor | Exact | Shortfall |
|---:|---:|---:|---:|---:|
| 5% | 1 day | 0.00013700 | 0.00013700 | 0.0000% |
| 10% | 1 year | 0.10516667 | 0.10517092 | 0.0040% |
| 25% | 1 year | 0.28385417 | 0.28402542 | 0.0603% |
| 50% | 1 year | 0.64583333 | 0.64872127 | 0.4452% |
| 100% | 1 year | 1.66666667 | 1.71828183 | 3.0039% |

The error only becomes visible at a year of untouched accrual, and it favours borrowers. In
practice any market with activity accrues on every interaction
([`Morpho.sol:181`](morpho-blue/src/Morpho.sol#L181), and the same call at the top of every other
state-changing function), so `z` stays tiny and the approximation is exact to the wei.

There is no overflow guard on `x * n`. A malicious IRM returning an enormous rate would revert on
overflow rather than mint infinite interest, which is the safe failure direction, but it is one
more reason the IRM is a trusted component gated by `enableIrm`.

The rest of `MathLib` is unremarkable fixed-point plumbing:

| Function | Meaning | Line |
|---|---|---|
| `wMulDown(x,y)` | `x·y/1e18`, down | [`:12-14`](morpho-blue/src/libraries/MathLib.sol#L12-L14) |
| `wDivDown(x,y)` | `x·1e18/y`, down | [`:17-19`](morpho-blue/src/libraries/MathLib.sol#L17-L19) |
| `wDivUp(x,y)` | `x·1e18/y`, up | [`:22-24`](morpho-blue/src/libraries/MathLib.sol#L22-L24) |
| `mulDivDown(x,y,d)` | `x·y/d`, down | [`:27-29`](morpho-blue/src/libraries/MathLib.sol#L27-L29) |
| `mulDivUp(x,y,d)` | `(x·y + d−1)/d` | [`:32-34`](morpho-blue/src/libraries/MathLib.sol#L32-L34) |

`WAD = 1e18` is declared as a file-level constant at
[`MathLib.sol:4`](morpho-blue/src/libraries/MathLib.sol#L4).

### 2.3 The liquidation incentive factor

Computed inline in `liquidate` at
[`Morpho.sol:366-369`](morpho-blue/src/Morpho.sol#L366-L369):

```solidity
uint256 liquidationIncentiveFactor = UtilsLib.min(
    MAX_LIQUIDATION_INCENTIVE_FACTOR,
    WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - marketParams.lltv))
);
```

With `LIQUIDATION_CURSOR = 0.3e18`
([`ConstantsLib.sol:11`](morpho-blue/src/libraries/ConstantsLib.sol#L11)) and
`MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18`
([`:14`](morpho-blue/src/libraries/ConstantsLib.sol#L14)):

```
LIF = min( 1.15 ,  1 / (1 − 0.3·(1 − LLTV)) )
```

The bonus is a pure function of LLTV, with no governance parameter per market — the opposite of
Aave, where each reserve carries its own configured liquidation bonus. Riskier markets (low LLTV)
get a bigger bonus, capped at 15%:

| LLTV | Raw factor | LIF | Liquidator bonus | Capped? |
|---:|---:|---:|---:|---|
| 0.25 | 1.290323 | 1.150000 | 15.000% | yes |
| 0.50 | 1.176471 | 1.150000 | 15.000% | yes |
| 0.625 | 1.126761 | 1.126761 | 12.676% | no |
| 0.77 | 1.074114 | 1.074114 | 7.411% | no |
| 0.80 | 1.063830 | 1.063830 | 6.383% | no |
| 0.86 | 1.043841 | 1.043841 | 4.384% | no |
| 0.915 | 1.026167 | 1.026167 | 2.617% | no |
| 0.945 | 1.016777 | 1.016777 | 1.678% | no |
| 0.965 | 1.010611 | 1.010611 | 1.061% | no |

The cap binds exactly when `1/(1 − 0.3(1 − L)) > 1.15`, i.e. for

```
LLTV < 13/23 = 0.565217391304…
```

Every LLTV at or below ~56.52% therefore receives an identical flat 15% bonus.

### 2.4 `UtilsLib` — four assembly one-liners

[`morpho-blue/src/libraries/UtilsLib.sol`](morpho-blue/src/libraries/UtilsLib.sol), 38 lines.

| Function | Implementation | Purpose | Line |
|---|---|---|---|
| `exactlyOneZero(x,y)` | `xor(iszero(x), iszero(y))` | enforces the assets-XOR-shares input convention | [`:13-17`](morpho-blue/src/libraries/UtilsLib.sol#L13-L17) |
| `min(x,y)` | `xor(x, mul(xor(x,y), lt(y,x)))` | branchless min | [`:20-24`](morpho-blue/src/libraries/UtilsLib.sol#L20-L24) |
| `toUint128(x)` | `require(x <= type(uint128).max)` | checked narrowing | [`:27-30`](morpho-blue/src/libraries/UtilsLib.sol#L27-L30) |
| `zeroFloorSub(x,y)` | `mul(gt(x,y), sub(x,y))` | saturating subtraction, `max(0, x−y)` | [`:33-37`](morpho-blue/src/libraries/UtilsLib.sol#L33-L37) |

`exactlyOneZero` is the gate that makes Blue's dual-input API unambiguous: every amount-taking
function accepts *either* `assets` or `shares`, never both and never neither. It is asserted at
[`Morpho.sol:178`](morpho-blue/src/Morpho.sol#L178),
[`:209`](morpho-blue/src/Morpho.sol#L209),
[`:244`](morpho-blue/src/Morpho.sol#L244),
[`:278`](morpho-blue/src/Morpho.sol#L278) and
[`:356`](morpho-blue/src/Morpho.sol#L356), always with `ErrorsLib.INCONSISTENT_INPUT`.

`zeroFloorSub` is what lets `repay` and `liquidate` tolerate the documented one-wei overshoot:
`totalBorrowAssets` is reduced with a saturating subtract at
[`Morpho.sol:288`](morpho-blue/src/Morpho.sol#L288) and
[`:386`](morpho-blue/src/Morpho.sol#L386), and both sites carry the comment that `assets` may
exceed `totalBorrowAssets` by 1 because of `toAssetsUp` rounding.

### 2.5 `SafeTransferLib` — no-return-value tolerance

[`morpho-blue/src/libraries/SafeTransferLib.sol`](morpho-blue/src/libraries/SafeTransferLib.sol), 36 lines.

```solidity
require(address(token).code.length > 0, ErrorsLib.NO_CODE);

(bool success, bytes memory returndata) =
    address(token).call(abi.encodeCall(IERC20Internal.transfer, (to, value)));
require(success, ErrorsLib.TRANSFER_REVERTED);
require(returndata.length == 0 || abi.decode(returndata, (bool)), ErrorsLib.TRANSFER_RETURNED_FALSE);
```

[`SafeTransferLib.sol:19-26`](morpho-blue/src/libraries/SafeTransferLib.sol#L19-L26); the
`transferFrom` twin is [`:28-35`](morpho-blue/src/libraries/SafeTransferLib.sol#L28-L35).

Three things happen here. The `code.length` check stops a transfer to a non-contract silently
succeeding. The raw `call` tolerates USDT-style tokens that return nothing. And the returndata
check accepts either an empty return or an explicit `true`.

Note the local `IERC20Internal` interface declared at
[`:8-11`](morpho-blue/src/libraries/SafeTransferLib.sol#L8-L11) — the project-wide
[`IERC20`](morpho-blue/src/interfaces/IERC20.sol#L9) is deliberately **empty** so that no caller
can accidentally invoke the raw `transfer` instead of `safeTransfer`. The comment at
[`IERC20.sol:7-8`](morpho-blue/src/interfaces/IERC20.sol#L7-L8) states this outright. It is a
small, elegant use of the type system to make a footgun unrepresentable.

---

<a id="3-morphosol--every-function"></a>
## 3. `Morpho.sol` — every function

[`morpho-blue/src/Morpho.sol`](morpho-blue/src/Morpho.sol), 557 lines, `pragma solidity 0.8.19`,
declared `contract Morpho is IMorphoStaticTyping` at
[`:24`](morpho-blue/src/Morpho.sol#L24). No inheritance beyond the interface, no proxy, no
initializer, no upgrade path. What is deployed is what runs, forever.

Twenty-one functions total: 1 constructor, 1 modifier, 5 owner-only, 1 market creation,
8 user actions, 2 authorization, 2 interest, 2 internal health checks, 1 view helper.

### 3.1 `constructor(address newOwner)`

[`:75-82`](morpho-blue/src/Morpho.sol#L75-L82) · sets `DOMAIN_SEPARATOR` and `owner`.

| | |
|---|---|
| **Checks** | `newOwner != address(0)` → `ZERO_ADDRESS` |
| **Writes** | `DOMAIN_SEPARATOR` (immutable), `owner` |
| **Emits** | `SetOwner(newOwner)` |

```solidity
DOMAIN_SEPARATOR = keccak256(abi.encode(DOMAIN_TYPEHASH, block.chainid, address(this)));
```

The separator binds `chainid` and `address(this)` but **not** a name or version string. Because
it is `immutable`, the chain id is frozen at deploy time: after a hard fork, signatures made for
the old chain id remain valid on the fork. Most protocols recompute the separator when
`block.chainid` changes; Blue deliberately does not, trading fork safety for a cold-storage read
saved on every `setAuthorizationWithSig`.

### 3.2 `modifier onlyOwner()`

[`:87-90`](morpho-blue/src/Morpho.sol#L87-L90) · `msg.sender == owner` else `NOT_OWNER`.

The *entire* access-control system. There are no roles, no `ACLManager`, no pausers, no
guardians, no timelock. Compare Aave's six-role `ACLManager`
([`../aave/V3-PROTOCOL-COMPLETE-REFERENCE.md`](../aave/V3-PROTOCOL-COMPLETE-REFERENCE.md), §19).

### 3.3 `setOwner(address newOwner)`

[`:95-101`](morpho-blue/src/Morpho.sol#L95-L101) · `onlyOwner`.

| | |
|---|---|
| **Checks** | `newOwner != owner` → `ALREADY_SET` |
| **Writes** | `owner = newOwner` |
| **Emits** | `SetOwner` |

Single-step transfer. No two-step `acceptOwnership` handshake, so a typo permanently hands the
contract to an unreachable address. MetaMorpho, by contrast, uses OpenZeppelin's `Ownable2Step`
([`metamorpho/src/MetaMorpho.sol:43`](metamorpho/src/MetaMorpho.sol#L43)). The asymmetry is
deliberate: what the Blue owner can actually *do* is so limited (§3.4–3.7) that a lost owner is
survivable, because it cannot touch existing markets or user funds.

### 3.4 `enableIrm(address irm)`

[`:104-110`](morpho-blue/src/Morpho.sol#L104-L110) · `onlyOwner`.

| | |
|---|---|
| **Checks** | `!isIrmEnabled[irm]` → `ALREADY_SET` |
| **Writes** | `isIrmEnabled[irm] = true` |
| **Emits** | `EnableIrm(irm)` |

**One-way only.** There is no `disableIrm`. Once an interest-rate model is whitelisted it can
never be removed, so markets already using it can never be rug-pulled by governance revoking
their IRM. This is the single most important governance-minimisation decision in the contract.

### 3.5 `enableLltv(uint256 lltv)`

[`:113-120`](morpho-blue/src/Morpho.sol#L113-L120) · `onlyOwner`.

| | |
|---|---|
| **Checks** | `!isLltvEnabled[lltv]` → `ALREADY_SET`; `lltv < WAD` → `MAX_LLTV_EXCEEDED` |
| **Writes** | `isLltvEnabled[lltv] = true` |
| **Emits** | `EnableLltv(lltv)` |

Also one-way. `lltv < WAD` is strict, so 100% LLTV is impossible. Note there is no *lower* bound:
`enableLltv(0)` is legal and creates markets where any borrow is instantly liquidatable.

### 3.6 `setFee(MarketParams marketParams, uint256 newFee)`

[`:123-136`](morpho-blue/src/Morpho.sol#L123-L136) · `onlyOwner`.

| | |
|---|---|
| **Checks** | market exists → `MARKET_NOT_CREATED`; `newFee != market[id].fee` → `ALREADY_SET`; `newFee <= MAX_FEE` (0.25e18) → `MAX_FEE_EXCEEDED` |
| **Calls** | `_accrueInterest(marketParams, id)` **before** writing |
| **Writes** | `market[id].fee` |
| **Emits** | `SetFee(id, newFee)` |

The accrual at [`:130`](morpho-blue/src/Morpho.sol#L130) is load-bearing and the comment says so:
interest earned under the old fee must be settled at the old fee before the new one applies.
Omitting it would retroactively re-price all pending interest.

This is the **only** owner function that touches an existing market, and all it can do is move a
number between 0 and 25% of the interest. It cannot pause the market, change its oracle, change
its LLTV, seize collateral, or stop a withdrawal.

### 3.7 `setFeeRecipient(address newFeeRecipient)`

[`:139-145`](morpho-blue/src/Morpho.sol#L139-L145) · `onlyOwner`. Checks `ALREADY_SET`, writes
`feeRecipient`, emits `SetFeeRecipient`. Global, not per-market. Setting it to `address(0)` burns
protocol fees rather than reverting.

### 3.8 `createMarket(MarketParams marketParams)`

[`:150-164`](morpho-blue/src/Morpho.sol#L150-L164) · **permissionless**, no modifier.

| | |
|---|---|
| **Checks** | `isIrmEnabled[irm]` → `IRM_NOT_ENABLED`; `isLltvEnabled[lltv]` → `LLTV_NOT_ENABLED`; `market[id].lastUpdate == 0` → `MARKET_ALREADY_CREATED` |
| **Writes** | `market[id].lastUpdate = block.timestamp`; `idToMarketParams[id] = marketParams` |
| **Emits** | `CreateMarket(id, marketParams)` |
| **Calls** | `IIrm(irm).borrowRate(marketParams, market[id])` if `irm != address(0)` |

Anyone can list a market. The owner controls only the *menu* of IRMs and LLTVs, never the
combinations drawn from it. `loanToken`, `collateralToken` and `oracle` are entirely unvalidated
— you may create a market whose oracle is your own contract returning any number you like. That
is safe for everyone else because such a market is a distinct `Id` that nobody else has supplied
to.

Two subtleties:

- The trailing IRM call at [`:163`](morpho-blue/src/Morpho.sol#L163) exists to initialise
  stateful IRMs (Morpho's own `AdaptiveCurveIrm` stores per-market rate state). It is an
  **untrusted external call at the end of market creation**, but reentering `createMarket` for the
  same id is blocked by the `lastUpdate` write that already happened at
  [`:157`](morpho-blue/src/Morpho.sol#L157).
- `irm == address(0)` is explicitly permitted and produces a **zero-interest market**, since
  `_accrueInterest` short-circuits on the same condition at
  [`:487`](morpho-blue/src/Morpho.sol#L487).

### 3.9 `supply(marketParams, assets, shares, onBehalf, data)`

[`:169-197`](morpho-blue/src/Morpho.sol#L169-L197) · returns `(assets, shares)`.

| | |
|---|---|
| **Checks** | market exists; `exactlyOneZero(assets, shares)`; `onBehalf != address(0)` |
| **Accrues** | `_accrueInterest` at [`:181`](morpho-blue/src/Morpho.sol#L181) |
| **Converts** | `toSharesDown` if assets given, `toAssetsUp` if shares given ([`:183-184`](morpho-blue/src/Morpho.sol#L183-L184)) |
| **Writes** | `position[id][onBehalf].supplyShares +=`, `totalSupplyShares +=`, `totalSupplyAssets +=` |
| **Emits** | `Supply(id, msg.sender, onBehalf, assets, shares)` |
| **Callback** | `IMorphoSupplyCallback(msg.sender).onMorphoSupply(assets, data)` if `data.length > 0` |
| **Transfer** | `safeTransferFrom(msg.sender, address(this), assets)` **last** |

**No authorization check.** Anyone may supply on anyone's behalf, because doing so is a gift.
Contrast `withdraw`, which requires it.

**Ordering is the security property.** State is fully updated ([`:186-188`](morpho-blue/src/Morpho.sol#L186-L188)),
then the event fires, then the untrusted callback runs, then the token is pulled. A reentrant
call from `onMorphoSupply` sees consistent, already-written state — it cannot mint shares twice —
and if the final `transferFrom` fails the whole transaction reverts. This is
checks-effects-interactions with a deliberate callback slot, and it is what makes flash-supply
patterns possible without a reentrancy guard anywhere in the contract.

### 3.10 `withdraw(marketParams, assets, shares, onBehalf, receiver)`

[`:200-230`](morpho-blue/src/Morpho.sol#L200-L230) · returns `(assets, shares)`.

| | |
|---|---|
| **Checks** | market exists; `exactlyOneZero`; `receiver != address(0)`; `_isSenderAuthorized(onBehalf)` → `UNAUTHORIZED` |
| **Accrues** | yes |
| **Converts** | `toSharesUp` / `toAssetsDown` ([`:216-217`](morpho-blue/src/Morpho.sol#L216-L217)) |
| **Writes** | subtracts from `supplyShares`, `totalSupplyShares`, `totalSupplyAssets` |
| **Post-check** | `totalBorrowAssets <= totalSupplyAssets` → `INSUFFICIENT_LIQUIDITY` ([`:223`](morpho-blue/src/Morpho.sol#L223)) |
| **Emits** | `Withdraw` |
| **Transfer** | `safeTransfer(receiver, assets)` last |

The comment at [`:211`](morpho-blue/src/Morpho.sol#L211) explains why `onBehalf != address(0)` is
not checked: `_isSenderAuthorized(address(0))` can only pass if `msg.sender == address(0)`, which
is unreachable.

The liquidity check is a single comparison of two accumulators — no per-user available-liquidity
computation, no interest-bearing receipt token to burn. Note it uses **internal accounting**, not
`balanceOf`, so a market whose loan token has been drained by a broken token still reports
consistent state.

`supplyShares -=` will underflow-revert (Solidity 0.8 checked arithmetic) if the user asks for
more than they own. There is no explicit error for that case; the revert is a panic, not
`ErrorsLib`.

### 3.11 `borrow(marketParams, assets, shares, onBehalf, receiver)`

[`:235-266`](morpho-blue/src/Morpho.sol#L235-L266) · returns `(assets, shares)`.

| | |
|---|---|
| **Checks** | market exists; `exactlyOneZero`; `receiver != address(0)`; `_isSenderAuthorized(onBehalf)` |
| **Accrues** | yes |
| **Converts** | `toSharesUp` / `toAssetsDown` ([`:251-252`](morpho-blue/src/Morpho.sol#L251-L252)) |
| **Writes** | adds to `borrowShares`, `totalBorrowShares`, `totalBorrowAssets` |
| **Post-checks** | `_isHealthy(marketParams, id, onBehalf)` → `INSUFFICIENT_COLLATERAL` ([`:258`](morpho-blue/src/Morpho.sol#L258)); `totalBorrowAssets <= totalSupplyAssets` → `INSUFFICIENT_LIQUIDITY` ([`:259`](morpho-blue/src/Morpho.sol#L259)) |
| **Emits** | `Borrow` |
| **Transfer** | `safeTransfer(receiver, assets)` last |
| **Callback** | **none** |

The health check is *after* the state write, so it validates the post-borrow position. This is the
only place a price is read during a borrow, via `_isHealthy` → `IOracle.price()` (§3.19).

`borrow` has no callback, unlike `supply`, `repay` and `supplyCollateral`. It does not need one:
the caller receives assets, so any follow-up logic can simply run after the call returns. The
callbacks exist only where Blue *pulls* tokens from the caller.

### 3.12 `repay(marketParams, assets, shares, onBehalf, data)`

[`:269-298`](morpho-blue/src/Morpho.sol#L269-L298) · returns `(assets, shares)`.

| | |
|---|---|
| **Checks** | market exists; `exactlyOneZero`; `onBehalf != address(0)` |
| **Accrues** | yes |
| **Converts** | `toSharesDown` / `toAssetsUp` ([`:283-284`](morpho-blue/src/Morpho.sol#L283-L284)) |
| **Writes** | subtracts `borrowShares`, `totalBorrowShares`; `totalBorrowAssets = zeroFloorSub(totalBorrowAssets, assets)` |
| **Emits** | `Repay` |
| **Callback** | `IMorphoRepayCallback(msg.sender).onMorphoRepay(assets, data)` if `data.length > 0` |
| **Transfer** | `safeTransferFrom(msg.sender, address(this), assets)` last |

No authorization check — repaying someone's debt is a gift, like supplying.

The `zeroFloorSub` at [`:288`](morpho-blue/src/Morpho.sol#L288) with its comment at
[`:290`](morpho-blue/src/Morpho.sol#L290) handles the documented one-wei overshoot: when the
caller passes `shares`, `toAssetsUp` can round `assets` one wei above `totalBorrowAssets`. A
plain subtraction would revert on the final repayment of a market; saturating to zero is correct
and lets the last borrower actually close their position.

The repay callback is what makes **collateral-swap and deleverage** atomic: repay with
`data`, and inside `onMorphoRepay` withdraw the freed collateral, swap it, and end up holding the
loan token that the trailing `transferFrom` then pulls. The bundler's `morphoRepay` at
[`morpho-blue-bundlers/src/MorphoBundler.sol:171`](morpho-blue-bundlers/src/MorphoBundler.sol#L171)
is built on exactly this.

### 3.13 `supplyCollateral(marketParams, assets, onBehalf, data)`

[`:303-320`](morpho-blue/src/Morpho.sol#L303-L320) · returns nothing.

| | |
|---|---|
| **Checks** | market exists; `assets != 0` → `ZERO_ASSETS`; `onBehalf != address(0)` |
| **Accrues** | **no** — see below |
| **Writes** | `position[id][onBehalf].collateral += assets` |
| **Emits** | `SupplyCollateral` |
| **Callback** | `onMorphoSupplyCollateral(assets, data)` if `data.length > 0` |
| **Transfer** | `safeTransferFrom(msg.sender, address(this), assets)` last |

The comment at [`:311`](morpho-blue/src/Morpho.sol#L311) — *"Don't accrue interest because it's
not required and it saves gas"* — is a precise claim, not laziness. Collateral earns no interest
and is not part of any share pool, so adding collateral cannot change any index. Skipping accrual
is observably equivalent and cheaper.

There is no assets-or-shares duality here: collateral is tracked as a raw token amount in a
`uint128`, never as shares. Collateral does not earn yield in Blue, full stop.

This callback plus `borrow` is the leverage primitive: supply collateral you do not yet own,
and inside `onMorphoSupplyCollateral` borrow the loan token, swap it for the collateral, and let
the trailing `transferFrom` collect it. That is a one-transaction leveraged position with no
flash loan. `LeverageWETHZapper` in Liquity does the same trick with a real flash loan; Blue does
not need one.

### 3.14 `withdrawCollateral(marketParams, assets, onBehalf, receiver)`

[`:323-342`](morpho-blue/src/Morpho.sol#L323-L342) · returns nothing.

| | |
|---|---|
| **Checks** | market exists; `assets != 0`; `receiver != address(0)`; `_isSenderAuthorized(onBehalf)` |
| **Accrues** | **yes** ([`:333`](morpho-blue/src/Morpho.sol#L333)) |
| **Writes** | `collateral -= assets` |
| **Post-check** | `_isHealthy` → `INSUFFICIENT_COLLATERAL` ([`:337`](morpho-blue/src/Morpho.sol#L337)) |
| **Emits** | `WithdrawCollateral` |
| **Transfer** | `safeTransfer(receiver, assets)` last |

The asymmetry with `supplyCollateral` is deliberate and correct: *withdrawing* collateral must
accrue first, because the health check compares collateral against debt, and debt grows with
interest. Skipping accrual here would let a borrower withdraw against a stale, understated debt.

### 3.15 `liquidate(marketParams, borrower, seizedAssets, repaidShares, data)`

[`:347-417`](morpho-blue/src/Morpho.sol#L347-L417) · returns `(seizedAssets, repaidAssets)`.
The densest function in the contract, and the one that differs most from Aave.

| | |
|---|---|
| **Checks** | market exists; `exactlyOneZero(seizedAssets, repaidShares)` |
| **Accrues** | yes |
| **Price** | `IOracle(marketParams.oracle).price()` once, at [`:361`](morpho-blue/src/Morpho.sol#L361) |
| **Guard** | `!_isHealthy(..., collateralPrice)` → `HEALTHY_POSITION` ([`:363`](morpho-blue/src/Morpho.sol#L363)) |
| **Writes** | `borrowShares`, `totalBorrowShares`, `totalBorrowAssets`, `collateral`, and on bad debt also `totalSupplyAssets` |
| **Emits** | `Liquidate(id, caller, borrower, repaidAssets, repaidShares, seizedAssets, badDebtAssets, badDebtShares)` |
| **Order** | seize → callback → pull repayment |

**No close factor.** Aave caps a single liquidation at 50% of debt (or 100% below a health-factor
threshold); Blue has no such cap at all. A liquidator may repay the entire position in one call.
The only limit is the borrower's collateral. This removes an entire class of parameter and an
entire class of griefing, at the cost of giving liquidators more discretion.

**Two entry modes**, mirroring the assets-or-shares convention:

*Given `seizedAssets`* ([`:372-375`](morpho-blue/src/Morpho.sol#L372-L375)) — "I want exactly this
much collateral":

```
seizedAssetsQuoted = ceil(seizedAssets · price / 1e36)
repaidShares       = toSharesUp( ceil(seizedAssetsQuoted / LIF) )
```

*Given `repaidShares`* ([`:377-379`](morpho-blue/src/Morpho.sol#L377-L379)) — "I want to clear
exactly this much debt":

```
seizedAssets = floor( floor(toAssetsDown(repaidShares) · LIF) · 1e36 / price )
```

Both round against the liquidator. `ORACLE_PRICE_SCALE = 1e36`
([`ConstantsLib.sol:17`](morpho-blue/src/libraries/ConstantsLib.sol#L17)).

**Bad-debt socialisation** ([`:392-403`](morpho-blue/src/Morpho.sol#L392-L403)) is the part with
no Aave equivalent. If the seize leaves `collateral == 0` while `borrowShares > 0`, the remaining
debt is written off **in the same transaction**:

```solidity
if (position[id][borrower].collateral == 0) {
    badDebtShares = position[id][borrower].borrowShares;
    badDebtAssets = UtilsLib.min(
        market[id].totalBorrowAssets,
        badDebtShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares)
    );

    market[id].totalBorrowAssets -= badDebtAssets.toUint128();
    market[id].totalSupplyAssets -= badDebtAssets.toUint128();
    market[id].totalBorrowShares -= badDebtShares.toUint128();
    position[id][borrower].borrowShares = 0;
}
```

Reducing `totalSupplyAssets` immediately lowers the value of every supply share in that market,
pro rata. Suppliers eat the loss at once, transparently, rather than the protocol carrying a
deficit that governance must later decide how to clear (Aave's `eliminateReserveDeficit`, added
in 3.4). Because Blue markets are isolated, the loss cannot spread beyond the one market. This is
the clearest expression of Blue's whole design thesis: push risk to the edges and price it there.

The `UtilsLib.min` guard at [`:394`](morpho-blue/src/Morpho.sol#L394) prevents the rounding-up
conversion from subtracting more than `totalBorrowAssets` holds.

**Ordering.** Collateral goes out at [`:410`](morpho-blue/src/Morpho.sol#L410) *before* the
callback at [`:412`](morpho-blue/src/Morpho.sol#L412), and repayment is pulled at
[`:414`](morpho-blue/src/Morpho.sol#L414) *after* it. So a liquidator needs no capital: receive
collateral, sell it inside `onMorphoLiquidate`, and repay from the proceeds. Blue makes the
flash-liquidation pattern native rather than requiring a separate adapter, which is what Aave v2
needed `FlashLiquidationAdapter` for.

### 3.16 `flashLoan(address token, uint256 assets, bytes data)`

[`:422-432`](morpho-blue/src/Morpho.sol#L422-L432) · returns nothing. **Eleven lines.**

| | |
|---|---|
| **Checks** | `assets != 0` → `ZERO_ASSETS` |
| **Writes** | none |
| **Emits** | `FlashLoan(msg.sender, token, assets)` |
| **Order** | transfer out → `onMorphoFlashLoan(assets, data)` → `transferFrom` back |

**Zero fee.** There is no premium, no fee parameter, no fee accrual. Aave's `FlashLoanLogic` is
253 lines with a two-part premium split between LPs and treasury; Blue's is eleven lines with
none.

**No market required.** `flashLoan` takes a bare `token`, not a `MarketParams`. It lends whatever
balance the singleton happens to hold of that token, aggregated across every market. There is no
per-market liquidity check because the repayment is enforced by the trailing `transferFrom`: if
the borrower does not return the full amount, that call reverts and the whole transaction unwinds.

**No accounting to corrupt.** Because Blue never reads `balanceOf(address(this))` for its
internal state (§2.1), draining the contract mid-transaction cannot desynchronise anything.
`totalSupplyAssets` is unchanged throughout. The one visible consequence is that a *withdrawal*
attempted inside a flash-loan callback may fail on the token transfer even though internal
accounting says liquidity exists — which is exactly the case MetaMorpho's `_withdrawable` guards
against by taking `min(totalSupply − totalBorrow, loanToken.balanceOf(MORPHO))` at
[`metamorpho/src/MetaMorpho.sol:869-871`](metamorpho/src/MetaMorpho.sol#L869-L871).

**No reentrancy guard**, deliberately. Reentering `flashLoan` simply nests another
transfer-out/transfer-back pair, each of which must independently balance.

### 3.17 `setAuthorization(address authorized, bool newIsAuthorized)`

[`:437-443`](morpho-blue/src/Morpho.sol#L437-L443).

| | |
|---|---|
| **Checks** | `newIsAuthorized != isAuthorized[msg.sender][authorized]` → `ALREADY_SET` |
| **Writes** | `isAuthorized[msg.sender][authorized]` |
| **Emits** | `SetAuthorization(msg.sender, msg.sender, authorized, newIsAuthorized)` |

An all-or-nothing delegation: an authorized address can `withdraw`, `borrow` and
`withdrawCollateral` on your behalf, across **every market**, without limit. Contrast Aave's
credit delegation, which is per-reserve and per-amount
(`DebtTokenBase.approveDelegation`). Blue's is a blunt instrument, appropriate because the
intended holder is a bundler contract used within a single transaction.

### 3.18 `setAuthorizationWithSig(Authorization authorization, Signature signature)`

[`:446-464`](morpho-blue/src/Morpho.sol#L446-L464) · EIP-712, callable by anyone.

| | |
|---|---|
| **Checks** | `block.timestamp <= deadline` → `SIGNATURE_EXPIRED`; `nonce == nonce[authorizer]++` → `INVALID_NONCE`; `signatory != address(0) && authorizer == signatory` → `INVALID_SIGNATURE` |
| **Writes** | `nonce[authorizer]++`, `isAuthorized[authorizer][authorized]` |
| **Emits** | `IncrementNonce`, then `SetAuthorization` |

The comment at [`:447`](morpho-blue/src/Morpho.sol#L447) notes the missing `ALREADY_SET` check is
intentional: re-signing the same value still burns a nonce, which is how a signer cancels a
signature they have leaked.

`ecrecover` is used raw, with the `signatory != address(0)` check catching malformed signatures.
There is **no EIP-2098 or malleability guard** on `s`, but replay is prevented by the nonce, so
a flipped-`s` variant of a signature merely consumes the same nonce.

Note this is *not* ERC-1271 compatible: a smart-contract wallet cannot authorize by signature, only
by calling `setAuthorization` directly.

### 3.19 `_isSenderAuthorized(address onBehalf)`

[`:467-469`](morpho-blue/src/Morpho.sol#L467-L469): `msg.sender == onBehalf || isAuthorized[onBehalf][msg.sender]`.
Called by `withdraw`, `borrow` and `withdrawCollateral` — the three functions that remove value.

### 3.20 `accrueInterest` and `_accrueInterest`

Public wrapper at [`:474-479`](morpho-blue/src/Morpho.sol#L474-L479) checks the market exists and
delegates. The real work is
[`:483-509`](morpho-blue/src/Morpho.sol#L483-L509):

```solidity
uint256 elapsed = block.timestamp - market[id].lastUpdate;
if (elapsed == 0) return;

if (marketParams.irm != address(0)) {
    uint256 borrowRate = IIrm(marketParams.irm).borrowRate(marketParams, market[id]);
    uint256 interest = market[id].totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
    market[id].totalBorrowAssets += interest.toUint128();
    market[id].totalSupplyAssets += interest.toUint128();
    ...
}
market[id].lastUpdate = uint128(block.timestamp);
```

| | |
|---|---|
| **Early exit** | `elapsed == 0`, so multiple calls in one block cost almost nothing |
| **External call** | `IIrm.borrowRate` — **state-changing**, not a view; stateful IRMs update here |
| **Writes** | `totalBorrowAssets`, `totalSupplyAssets`, optionally `feeShares` and `totalSupplyShares`, always `lastUpdate` |
| **Emits** | `AccrueInterest(id, borrowRate, interest, feeShares)` — only inside the IRM branch |

**One index, two totals.** There is no `liquidityIndex` and no `variableBorrowIndex`. Interest is
added to `totalBorrowAssets` and to `totalSupplyAssets` by the *same absolute amount*, so the
supply-share price rises mechanically as `totalSupplyAssets / totalSupplyShares`. Aave needs two
ray indexes and a linear-vs-compound distinction; Blue needs neither, because suppliers hold
shares of a pot that simply grew.

**The fee subtlety** at [`:496-499`](morpho-blue/src/Morpho.sol#L496-L499) is worth reading twice.
`totalSupplyAssets` has *already* been increased by the full `interest`, including the part
destined for the fee recipient. Minting fee shares against that inflated total would under-issue
them. So the conversion uses `totalSupplyAssets - feeAmount` as the denominator, pricing the fee
shares as if the fee had not yet been added. MetaMorpho repeats this exact compensation at
[`metamorpho/src/MetaMorpho.sol:905-908`](metamorpho/src/MetaMorpho.sol#L905-L908).

`lastUpdate` is written **outside** the IRM branch, so a zero-IRM market still advances its clock.

**Trust boundary:** `borrowRate` is an arbitrary external call made before any reentrancy-relevant
state settles. A malicious IRM could reenter. It cannot mint value — every path it could reenter
re-reads storage — but this is precisely why `enableIrm` is owner-gated and one-way (§3.4).

### 3.21 `_isHealthy` — both overloads

Three-arg version, [`:515-521`](morpho-blue/src/Morpho.sol#L515-L521): returns `true` immediately
if `borrowShares == 0`, **so no oracle call happens for a debt-free position**. That is why
`withdrawCollateral` costs no oracle read when you have no debt.

Four-arg version, [`:527-539`](morpho-blue/src/Morpho.sol#L527-L539):

```solidity
uint256 borrowed = borrowShares.toAssetsUp(totalBorrowAssets, totalBorrowShares);
uint256 maxBorrow = collateral.mulDivDown(collateralPrice, ORACLE_PRICE_SCALE).wMulDown(lltv);
return maxBorrow >= borrowed;
```

Debt rounds **up**, collateral value rounds **down**, LLTV multiplication rounds **down**. Three
roundings, all against the borrower, which the docstring at
[`:526`](morpho-blue/src/Morpho.sol#L526) acknowledges: you may be unable to borrow the exact
maximum, only one unit less.

**There is no health factor number.** Aave computes a ratio and compares it to 1e18; Blue compares
two absolute quantities and returns a bool. Cheaper, and it removes a whole class of
precision-loss questions.

`ORACLE_PRICE_SCALE = 1e36` ([`ConstantsLib.sol:17`](morpho-blue/src/libraries/ConstantsLib.sol#L17))
is large enough that a price fits regardless of the decimal difference between collateral and
loan token — the oracle is responsible for pre-scaling, which is what makes
`MorphoChainlinkOracleV2`'s `SCALE_FACTOR` derivation (§10.1) so intricate.

### 3.22 `extSloads(bytes32[] slots)`

[`:544-556`](morpho-blue/src/Morpho.sol#L544-L556) · arbitrary storage reads in a loop.

```solidity
assembly ("memory-safe") {
    mstore(add(res, mul(i, 32)), sload(slot))
}
```

`i` is incremented at `slots[i++]` *before* the `mstore`, so `mul(i, 32)` lands one word past the
array length prefix — correct, and the reason the loop reads slightly oddly.

This is the same idea as Uniswap v4's `Extsload`
([`../uni/V4-COMPLETE-REFERENCE.md`](../uni/V4-COMPLETE-REFERENCE.md)): expose raw storage and let
an off-chain or periphery library decode it, rather than shipping dozens of getters. §5.1 covers
the decoding side.

---

<a id="4-morpho-blue-libraries"></a>
## 4. Morpho Blue libraries

The six core libraries are derived in §2. This section covers what remains.

### 4.1 `ConstantsLib`

[`morpho-blue/src/libraries/ConstantsLib.sol`](morpho-blue/src/libraries/ConstantsLib.sol), 21 lines.
Every magic number in the protocol, in one place:

| Constant | Value | Meaning | Line |
|---|---|---|---|
| `MAX_FEE` | `0.25e18` | ceiling on a market's protocol fee | [`:5`](morpho-blue/src/libraries/ConstantsLib.sol#L5) |
| `ORACLE_PRICE_SCALE` | `1e36` | fixed-point scale for `IOracle.price()` | [`:17`](morpho-blue/src/libraries/ConstantsLib.sol#L17) |
| `LIQUIDATION_CURSOR` | `0.3e18` | steepness of the LIF curve | [`:11`](morpho-blue/src/libraries/ConstantsLib.sol#L11) |
| `MAX_LIQUIDATION_INCENTIVE_FACTOR` | `1.15e18` | 15% cap on liquidator bonus | [`:14`](morpho-blue/src/libraries/ConstantsLib.sol#L14) |
| `DOMAIN_TYPEHASH` | keccak of `EIP712Domain(uint256 chainId,address verifyingContract)` | EIP-712 domain | [`:8`](morpho-blue/src/libraries/ConstantsLib.sol#L8) |
| `AUTHORIZATION_TYPEHASH` | keccak of the `Authorization` struct | EIP-712 struct | [`:20-21`](morpho-blue/src/libraries/ConstantsLib.sol#L20-L21) |

Nine constants govern the entire protocol. There is no per-market risk parameter beyond LLTV and
fee, and no governance-settable global other than the fee recipient.

### 4.2 `ErrorsLib`

[`morpho-blue/src/libraries/ErrorsLib.sol`](morpho-blue/src/libraries/ErrorsLib.sol), 80 lines,
**22 string constants** rather than custom errors. Full table in §15.

Blue predates widespread custom-error adoption in Morpho's own style guide, and strings cost more
gas and more bytecode. MetaMorpho, written later, uses proper `error` declarations
([`metamorpho/src/libraries/ErrorsLib.sol`](metamorpho/src/libraries/ErrorsLib.sol)). The
inconsistency between the two repos is a genuine wart.

### 4.3 `EventsLib`

[`morpho-blue/src/libraries/EventsLib.sol`](morpho-blue/src/libraries/EventsLib.sol), 150 lines,
**16 events**. Full table in §14. Every one is `emit EventsLib.X(...)` from `Morpho.sol`, keeping
the main contract free of event declarations.

### 4.4 `MarketParamsLib`

Covered in §1.1. Twenty-one lines, one function, one assembly block.

---

<a id="5-morpho-blue-periphery-libraries"></a>
## 5. Morpho Blue periphery libraries

Three libraries in [`morpho-blue/src/libraries/periphery/`](morpho-blue/src/libraries/periphery/)
that are **not used by `Morpho.sol` at all**. They exist for integrators, and they are the reason
Blue can ship with almost no view functions.

### 5.1 `MorphoStorageLib` — reconstructing every slot

[`morpho-blue/src/libraries/periphery/MorphoStorageLib.sol`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol),
110 lines, 11 pure functions.

It mirrors the nine base slots (§1.5) plus per-struct offsets
([`:26-37`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L26-L37)), then derives any
slot with the standard Solidity mapping rule `keccak256(key . slot)`:

```solidity
function positionSupplySharesSlot(Id id, address user) internal pure returns (bytes32) {
    return bytes32(
        uint256(keccak256(abi.encode(user, keccak256(abi.encode(id, POSITION_SLOT))))) + SUPPLY_SHARES_OFFSET
    );
}
```

[`:49-54`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L49-L54). The nested
`keccak256` is the two-level mapping `position[id][user]`; the trailing `+ OFFSET` selects the
word within the struct.

| Function | Returns slot of | Line |
|---|---|---|
| `ownerSlot()` | `owner` | [`:41-43`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L41-L43) |
| `feeRecipientSlot()` | `feeRecipient` | [`:45-47`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L45-L47) |
| `positionSupplySharesSlot(id, user)` | `position[id][user].supplyShares` | [`:49-54`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L49-L54) |
| `positionBorrowSharesAndCollateralSlot(id, user)` | packed `borrowShares`+`collateral` | [`:56-61`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L56-L61) |
| `marketTotalSupplyAssetsAndSharesSlot(id)` | packed supply totals | [`:63-65`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L63-L65) |
| `marketTotalBorrowAssetsAndSharesSlot(id)` | packed borrow totals | [`:67-69`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L67-L69) |
| `marketLastUpdateAndFeeSlot(id)` | packed `lastUpdate`+`fee` | [`:71-73`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L71-L73) |
| `isIrmEnabledSlot(irm)` | `isIrmEnabled[irm]` | [`:75-77`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L75-L77) |
| `isLltvEnabledSlot(lltv)` | `isLltvEnabled[lltv]` | [`:79-81`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L79-L81) |
| `isAuthorizedSlot(a, b)` | `isAuthorized[a][b]` | [`:83-85`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L83-L85) |
| `nonceSlot(authorizer)` | `nonce[authorizer]` | [`:87-89`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L87-L89) |
| `idToMarketParamsSlot(id)` | `idToMarketParams[id]` | [`:91-93`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol#L91-L93) |

**This is a hard dependency on storage layout.** Reordering a single state variable in
`Morpho.sol` silently breaks every consumer. It is safe here only because Blue is immutable and
will never be redeployed with a different layout — the same bargain Uniswap v4's `StateLibrary`
makes.

### 5.2 `MorphoLib` — batched single-value reads

[`morpho-blue/src/libraries/periphery/MorphoLib.sol`](morpho-blue/src/libraries/periphery/MorphoLib.sol),
63 lines, 9 getters plus a private helper.

Each getter is one `extSloads` call with one slot, then a decode. The three that unpack are:

```solidity
function borrowShares(IMorpho morpho, Id id, address user) internal view returns (uint256) {
    bytes32 slot = MorphoStorageLib.positionBorrowSharesAndCollateralSlot(id, user);
    return uint128(uint256(morpho.extSloads(_array(slot))[0]));
}

function collateral(IMorpho morpho, Id id, address user) internal view returns (uint256) {
    bytes32 slot = MorphoStorageLib.positionBorrowSharesAndCollateralSlot(id, user);
    return uint256(morpho.extSloads(_array(slot))[0] >> 128);
}
```

[`:18-26`](morpho-blue/src/libraries/periphery/MorphoLib.sol#L18-L26). `borrowShares` truncates to
the low 128 bits, `collateral` shifts down from the high 128 — confirming the packing described in
§1.2. The same low/high split applies to `totalSupplyAssets`/`totalSupplyShares`
([`:28-36`](morpho-blue/src/libraries/periphery/MorphoLib.sol#L28-L36)),
`totalBorrowAssets`/`totalBorrowShares`
([`:38-46`](morpho-blue/src/libraries/periphery/MorphoLib.sol#L38-L46)) and
`lastUpdate`/`fee` ([`:48-56`](morpho-blue/src/libraries/periphery/MorphoLib.sol#L48-L56)).

`_array(bytes32)` at [`:58-62`](morpho-blue/src/libraries/periphery/MorphoLib.sol#L58-L62) just
wraps a single slot into the one-element array `extSloads` expects.

### 5.3 `MorphoBalancesLib` — accrual-aware views

[`morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol),
118 lines, 6 functions. The most useful library for integrators, because raw storage is *stale*
between accruals.

`expectedMarketBalances` [`:33-61`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L33-L61)
replays `_accrueInterest` in memory:

```solidity
if (elapsed != 0 && market.totalBorrowAssets != 0 && marketParams.irm != address(0)) {
    uint256 borrowRate = IIrm(marketParams.irm).borrowRateView(marketParams, market);
    uint256 interest = market.totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
    market.totalBorrowAssets += interest.toUint128();
    market.totalSupplyAssets += interest.toUint128();
    ...
}
```

Two differences from the on-chain version worth noting. It calls **`borrowRateView`**, not
`borrowRate` — the view twin declared at
[`IIrm.sol:17`](morpho-blue/src/interfaces/IIrm.sol#L17), which a stateful IRM must implement
without writing. And it adds a `totalBorrowAssets != 0` short-circuit that `_accrueInterest`
omits, since zero debt produces zero interest anyway.

| Function | Returns | Line |
|---|---|---|
| `expectedMarketBalances` | all four totals, post-accrual | [`:33-61`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L33-L61) |
| `expectedTotalSupplyAssets` | one total | [`:64-70`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L64-L70) |
| `expectedTotalBorrowAssets` | one total | [`:73-79`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L73-L79) |
| `expectedTotalSupplyShares` | one total | [`:82-88`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L82-L88) |
| `expectedSupplyAssets(user)` | `toAssetsDown` of the user's shares | [`:92-104`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L92-L104) |
| `expectedBorrowAssets(user)` | `toAssetsUp` of the user's shares | [`:107-117`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L107-L117) |

The last two keep the protocol's rounding convention: a supplier's balance rounds down, a
borrower's rounds up. The docstring at
[`:91`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L91) repeats the `feeRecipient`
warning from §1.2.

MetaMorpho depends on this library directly — `totalAssets()` sums
`expectedSupplyAssets` across its withdraw queue
([`metamorpho/src/MetaMorpho.sol:589-593`](metamorpho/src/MetaMorpho.sol#L589-L593)).

---

<a id="6-morpho-blue-interfaces-and-mocks"></a>
## 6. Morpho Blue interfaces and mocks

Five interfaces, five mocks. All ten are listed here; none is skipped.

### 6.1 `IMorpho.sol` — the full surface

[`morpho-blue/src/interfaces/IMorpho.sol`](morpho-blue/src/interfaces/IMorpho.sol), 355 lines,
the largest file in the repo — larger than half of `Morpho.sol` itself, because it carries all
the NatSpec.

Three interfaces in a deliberate hierarchy:

| Interface | Line | Purpose |
|---|---|---|
| `IMorphoBase` | [`:51`](morpho-blue/src/interfaces/IMorpho.sol#L51) | everything except the two struct getters |
| `IMorphoStaticTyping` | [`:277`](morpho-blue/src/interfaces/IMorpho.sol#L277) | adds `position`/`market`/`idToMarketParams` returning **flattened tuples** |
| `IMorpho` | [`:322`](morpho-blue/src/interfaces/IMorpho.sol#L322) | adds the same three returning **structs** |

`Morpho.sol` implements `IMorphoStaticTyping`
([`Morpho.sol:24`](morpho-blue/src/Morpho.sol#L24)) because Solidity's auto-generated public
mapping getters return tuples, not structs. `IMorpho` exists purely for integrator ergonomics: it
is ABI-compatible with the same deployed bytecode, but lets callers write
`morpho.market(id).totalSupplyAssets` instead of destructuring six values. The comment at
[`:271-276`](morpho-blue/src/interfaces/IMorpho.sol#L271-L276) explains the split.

### 6.2 `IIrm.sol`

[`morpho-blue/src/interfaces/IIrm.sol`](morpho-blue/src/interfaces/IIrm.sol), 19 lines, two
functions:

| Function | Mutability | Called from |
|---|---|---|
| `borrowRate(MarketParams, Market)` | **non-view** | `_accrueInterest` [`Morpho.sol:488`](morpho-blue/src/Morpho.sol#L488), `createMarket` [`:163`](morpho-blue/src/Morpho.sol#L163) |
| `borrowRateView(MarketParams, Market)` | `view` | `MorphoBalancesLib` [`:44`](morpho-blue/src/libraries/periphery/MorphoBalancesLib.sol#L44) |

The dual signature is the whole reason a stateful IRM is possible. Morpho's production
`AdaptiveCurveIrm` (a separate repo, not cloned here) keeps per-market rate state that drifts
toward a target utilisation, updating it in `borrowRate` and simulating it in `borrowRateView`.
The rate is returned as **per-second, WAD-scaled**, which is what `wTaylorCompounded` expects.

Nothing in Blue validates the returned rate. An IRM returning `type(uint256).max` would overflow
`x * n` in `wTaylorCompounded` and revert, which fails safe.

### 6.3 `IOracle.sol`

[`morpho-blue/src/interfaces/IOracle.sol`](morpho-blue/src/interfaces/IOracle.sol), 15 lines, one
function:

```solidity
function price() external view returns (uint256);
```

The docstring at [`:11-13`](morpho-blue/src/interfaces/IOracle.sol#L11-L13) specifies the
contract: the price of 1 asset of collateral quoted in loan token, scaled by
`1e36 + loanDecimals - collateralDecimals`. All decimal handling is pushed into the oracle, which
is why `_isHealthy` can divide by a single constant.

**The entire oracle interface is one view function.** No round id, no timestamp, no staleness
data, no min/max bounds. Blue cannot check staleness because the interface gives it nothing to
check. This is a deliberate transfer of responsibility to the market creator and, transitively,
to the suppliers who choose that market.

### 6.4 `IMorphoCallbacks.sol`

[`morpho-blue/src/interfaces/IMorphoCallbacks.sol`](morpho-blue/src/interfaces/IMorphoCallbacks.sol),
52 lines, five single-function interfaces:

| Interface | Callback | Invoked from |
|---|---|---|
| `IMorphoLiquidateCallback` | `onMorphoLiquidate(repaidAssets, data)` | [`Morpho.sol:412`](morpho-blue/src/Morpho.sol#L412) |
| `IMorphoRepayCallback` | `onMorphoRepay(assets, data)` | [`:293`](morpho-blue/src/Morpho.sol#L293) |
| `IMorphoSupplyCallback` | `onMorphoSupply(assets, data)` | [`:192`](morpho-blue/src/Morpho.sol#L192) |
| `IMorphoSupplyCollateralCallback` | `onMorphoSupplyCollateral(assets, data)` | [`:317`](morpho-blue/src/Morpho.sol#L317) |
| `IMorphoFlashLoanCallback` | `onMorphoFlashLoan(assets, data)` | [`:429`](morpho-blue/src/Morpho.sol#L429) |

Note the pattern: callbacks exist on exactly the four operations where Blue **pulls** tokens from
the caller, plus the flash loan. `borrow`, `withdraw` and `withdrawCollateral` push tokens out and
need no callback.

None returns a value or a magic selector, unlike ERC-3156's
`keccak256("ERC3156FlashBorrower.onFlashLoan")` handshake. Blue does not need one, because the
trailing `transferFrom` is the real enforcement.

### 6.5 `IERC20.sol` — the empty interface

[`morpho-blue/src/interfaces/IERC20.sol`](morpho-blue/src/interfaces/IERC20.sol), 9 lines:

```solidity
/// @dev Empty because we only call functions in assembly. It prevents calling
/// transfer (transferFrom) instead of safeTransfer (safeTransferFrom).
interface IERC20 {}
```

Discussed in §2.5. A deliberately empty type used to make a mistake uncompilable.

### 6.6 Mocks

| File | Lines | What it is |
|---|---|---|
| [`ERC20Mock.sol`](morpho-blue/src/mocks/ERC20Mock.sol) | 52 | minimal ERC-20 with a `setBalance` cheat |
| [`OracleMock.sol`](morpho-blue/src/mocks/OracleMock.sol) | 12 | `setPrice` / `price` |
| [`IrmMock.sol`](morpho-blue/src/mocks/IrmMock.sol) | 25 | utilisation-proportional rate, for tests |
| [`FlashBorrowerMock.sol`](morpho-blue/src/mocks/FlashBorrowerMock.sol) | 24 | round-trips a flash loan |
| [`mocks/interfaces/IERC20.sol`](morpho-blue/src/mocks/interfaces/IERC20.sol) | 24 | a *real* ERC-20 interface, usable because mocks are not called through `SafeTransferLib` |

`IrmMock.borrowRate` at
[`IrmMock.sol:22-24`](morpho-blue/src/mocks/IrmMock.sol#L22-L24) is `pure` despite the interface
declaring it non-view, which is legal (a `pure` function satisfies a non-view signature) and
confirms that stateless IRMs are supported.

---

<a id="7-metamorpho-roles-timelocks-queues"></a>
## 7. MetaMorpho: roles, timelocks, queues

Blue markets are isolated and permissionless, which means a supplier must pick markets and manage
exposure. MetaMorpho is the answer: an ERC-4626 vault that spreads one asset across many Blue
markets under a role-separated, timelocked policy.

[`metamorpho/src/MetaMorpho.sol`](metamorpho/src/MetaMorpho.sol), 911 lines — **63% larger than
Blue itself**. The curation and safety machinery costs more code than the lending primitive.

```solidity
contract MetaMorpho is ERC4626, ERC20Permit, Ownable2Step, Multicall, IMetaMorphoStaticTyping
```

[`:43`](metamorpho/src/MetaMorpho.sol#L43). All four base contracts are OpenZeppelin.

### 7.1 The four roles

Defined by four modifiers at
[`:139-170`](metamorpho/src/MetaMorpho.sol#L139-L170), each strictly nested:

| Role | May do | Modifier |
|---|---|---|
| **Owner** | everything; set curator, allocators, fee, fee recipient, skim recipient; submit timelock and guardian | `onlyOwner` (OZ) |
| **Curator** | submit caps, submit market removals; also holds allocator powers | [`onlyCuratorRole`](metamorpho/src/MetaMorpho.sol#L139-L144) |
| **Allocator** | set the supply queue, reorder the withdraw queue, `reallocate` | [`onlyAllocatorRole`](metamorpho/src/MetaMorpho.sol#L147-L154) |
| **Guardian** | *revoke* pending changes only; never enact | [`onlyGuardianRole`](metamorpho/src/MetaMorpho.sol#L157-L161) |

The nesting is explicit in the code: `onlyAllocatorRole` passes for allocators, the curator, *and*
the owner ([`:149`](metamorpho/src/MetaMorpho.sol#L149)); `onlyCuratorRole` passes for curator and
owner ([`:141`](metamorpho/src/MetaMorpho.sol#L141)).

The guardian is a pure veto. It has no positive power at all — it cannot set a cap, move funds, or
pause. That asymmetry is the design: the guardian can only ever make the vault *less* able to
change.

### 7.2 The timelock

Bounded by [`ConstantsLib`](metamorpho/src/libraries/ConstantsLib.sol):
`MIN_TIMELOCK = 1 days` ([`:13`](metamorpho/src/libraries/ConstantsLib.sol#L13)),
`MAX_TIMELOCK = 2 weeks` ([`:10`](metamorpho/src/libraries/ConstantsLib.sol#L10)), enforced by
`_checkTimelockBounds` ([`:720-724`](metamorpho/src/MetaMorpho.sol#L720-L724)).

`PendingLib` ([`metamorpho/src/libraries/PendingLib.sol`](metamorpho/src/libraries/PendingLib.sol),
48 lines) holds the three pending structs and two `update` overloads that stamp
`validAt = block.timestamp + timelock`
([`:35-47`](metamorpho/src/libraries/PendingLib.sol#L35-L47)).

The `afterTimelock(validAt)` modifier
([`:176-181`](metamorpho/src/MetaMorpho.sol#L176-L181)) gates every `accept*`:

```solidity
if (validAt == 0) revert ErrorsLib.NoPendingValue();
if (block.timestamp < validAt) revert ErrorsLib.TimelockNotElapsed();
```

**The direction rule is the elegant part.** Changes that reduce risk take effect immediately;
changes that increase it must wait. In `submitTimelock`
([`:213-227`](metamorpho/src/MetaMorpho.sol#L213-L227)), a *longer* timelock applies at once
([`:218-219`](metamorpho/src/MetaMorpho.sol#L218-L219)) while a shorter one is queued. In
`submitCap` ([`:273-289`](metamorpho/src/MetaMorpho.sol#L273-L289)), *lowering* a cap calls
`_setCap` directly ([`:282-283`](metamorpho/src/MetaMorpho.sol#L282-L283)) while raising it is
queued ([`:285`](metamorpho/src/MetaMorpho.sol#L285)).

`submitCap` also refuses a market whose loan token is not the vault's asset
([`:275`](metamorpho/src/MetaMorpho.sol#L275), `InconsistentAsset`) and one that does not exist on
Blue ([`:276`](metamorpho/src/MetaMorpho.sol#L276)).

### 7.3 The two queues

| Queue | Purpose | Set by | Line |
|---|---|---|---|
| `supplyQueue` | order markets are filled on deposit | `setSupplyQueue` | [`:100`](metamorpho/src/MetaMorpho.sol#L100) |
| `withdrawQueue` | order markets are drained on withdrawal | `updateWithdrawQueue` | [`:103`](metamorpho/src/MetaMorpho.sol#L103) |

Both capped at `MAX_QUEUE_LENGTH = 30`
([`ConstantsLib.sol:16`](metamorpho/src/libraries/ConstantsLib.sol#L16)) to bound gas, since
`totalAssets()` iterates the whole withdraw queue on **every** conversion.

`setSupplyQueue` ([`:308-320`](metamorpho/src/MetaMorpho.sol#L308-L320)) is a full replacement and
only checks that every entry has a non-zero cap. An allocator can therefore reorder deposit
priority freely — a real power, since it decides which market receives new money first.

`updateWithdrawQueue` ([`:323-363`](metamorpho/src/MetaMorpho.sol#L323-L363)) is a *permutation*
API: it takes indexes into the current queue rather than ids, uses a `seen` bitmap to reject
duplicates ([`:335`](metamorpho/src/MetaMorpho.sol#L335)), and then subjects every dropped market
to three checks ([`:341-357`](metamorpho/src/MetaMorpho.sol#L341-L357)):

```solidity
if (config[id].cap != 0) revert ErrorsLib.InvalidMarketRemovalNonZeroCap(id);
if (pendingCap[id].validAt != 0) revert ErrorsLib.PendingCap(id);

if (MORPHO.supplyShares(id, address(this)) != 0) {
    if (config[id].removableAt == 0) revert ErrorsLib.InvalidMarketRemovalNonZeroSupply(id);
    if (block.timestamp < config[id].removableAt) revert ErrorsLib.InvalidMarketRemovalTimelockNotElapsed(id);
}
```

So a market holding vault funds can be dropped from the withdraw queue only after the curator has
called `submitMarketRemoval` and its timelock has elapsed. This closes the obvious attack: an
allocator silently removing a market from the withdraw queue would strand depositor funds there
permanently, since `totalAssets()` only sums the withdraw queue.

`submitMarketRemoval` ([`:292-303`](metamorpho/src/MetaMorpho.sol#L292-L303)) requires the cap to
already be zero ([`:295`](metamorpho/src/MetaMorpho.sol#L295)), forcing a two-step
lower-cap-then-remove sequence.

---

<a id="8-metamorphosol--every-function"></a>
## 8. `MetaMorpho.sol` — every function

### 8.1 Constructor

[`:117-134`](metamorpho/src/MetaMorpho.sol#L117-L134). Sets `MORPHO`, computes `DECIMALS_OFFSET`,
checks and sets the initial timelock, then:

```solidity
IERC20(_asset).forceApprove(morpho, type(uint256).max);
```

[`:133`](metamorpho/src/MetaMorpho.sol#L133) — an **infinite, permanent approval to Blue**, granted
once at construction. Acceptable only because Blue is immutable and cannot be upgraded to abuse it.

```solidity
DECIMALS_OFFSET = uint8(uint256(18).zeroFloorSub(IERC20Metadata(_asset).decimals()));
```

[`:128`](metamorpho/src/MetaMorpho.sol#L128). For USDC (6 decimals) the offset is 12, so shares
carry 12 extra decimals of precision. For an 18-decimal asset the offset is **0**, which is why the
`deposit` NatSpec at [`:532-534`](metamorpho/src/MetaMorpho.sol#L532-L534) warns that inflation
protection is weak for 18-decimal assets and tells deployers to seed the vault. Blue's own virtual
shares (§2.1) do not help here, because this is the *vault's* share price, not a market's.

### 8.2 Owner functions

| Function | Line | Effect |
|---|---|---|
| `setCurator` | [`:186-193`](metamorpho/src/MetaMorpho.sol#L186-L193) | immediate |
| `setIsAllocator` | [`:195-202`](metamorpho/src/MetaMorpho.sol#L195-L202) | immediate |
| `setSkimRecipient` | [`:204-211`](metamorpho/src/MetaMorpho.sol#L204-L211) | immediate |
| `submitTimelock` | [`:213-227`](metamorpho/src/MetaMorpho.sol#L213-L227) | immediate if longer, queued if shorter |
| `setFee` | [`:229-242`](metamorpho/src/MetaMorpho.sol#L229-L242) | immediate, accrues first |
| `setFeeRecipient` | [`:244-255`](metamorpho/src/MetaMorpho.sol#L244-L255) | immediate, accrues first |
| `submitGuardian` | [`:257-271`](metamorpho/src/MetaMorpho.sol#L257-L271) | immediate if unset, queued if replacing |

`setFee` refuses a non-zero fee with no recipient
([`:232`](metamorpho/src/MetaMorpho.sol#L232), `ZeroFeeRecipient`) and accrues under the old fee
first ([`:235`](metamorpho/src/MetaMorpho.sol#L235)) — the same discipline as Blue's `setFee`
(§3.6). `MAX_FEE` here is `0.5e18`
([`ConstantsLib.sol:19`](metamorpho/src/libraries/ConstantsLib.sol#L19)), double Blue's 25%.

`submitGuardian` applies immediately when there is no guardian yet
([`:265-266`](metamorpho/src/MetaMorpho.sol#L265-L266)) — adding a veto-holder reduces risk — but
queues a *replacement*, since swapping guardians could neutralise the veto.

### 8.3 `reallocate(MarketAllocation[] allocations)`

[`:366-415`](metamorpho/src/MetaMorpho.sol#L366-L415) · `onlyAllocatorRole`. The vault's core
rebalancing operation.

It walks the allocations, treating each as a **target** absolute position. For each market it
computes `withdrawn = supplyAssets.zeroFloorSub(allocation.assets)`
([`:374`](metamorpho/src/MetaMorpho.sol#L374)) and branches:

- **Withdraw branch** ([`:376-391`](metamorpho/src/MetaMorpho.sol#L376-L391)): requires the market
  be enabled. `allocation.assets == 0` is special-cased to withdraw by **shares** rather than
  assets ([`:381-384`](metamorpho/src/MetaMorpho.sol#L381-L384)), with the comment *"Guarantees
  that unknown frontrunning donations can be withdrawn, in order to disable a market."* Withdrawing
  a computed asset amount could leave dust behind if someone donated shares; withdrawing the full
  share balance cannot.
- **Supply branch** ([`:392-411`](metamorpho/src/MetaMorpho.sol#L392-L411)): `type(uint256).max`
  means "absorb everything withdrawn so far"
  ([`:393-394`](metamorpho/src/MetaMorpho.sol#L393-L394)). Enforces a non-zero cap
  ([`:400`](metamorpho/src/MetaMorpho.sol#L400)) and the cap itself
  ([`:402`](metamorpho/src/MetaMorpho.sol#L402)).

The closing invariant is the safety property:

```solidity
if (totalWithdrawn != totalSupplied) revert ErrorsLib.InconsistentReallocation();
```

[`:414`](metamorpho/src/MetaMorpho.sol#L414). **A reallocation must be asset-neutral.** An
allocator can move funds between approved markets but can never move funds *out* of the vault.
Combined with caps being curator-controlled, this bounds what a compromised allocator can do to
"shuffle within the approved set" — real damage is possible (moving everything into the riskiest
approved market) but outright theft is not.

### 8.4 Guardian revocations

Four functions, all trivially short, all `onlyGuardianRole` or `onlyCuratorOrGuardianRole`:
`revokePendingTimelock` [`:420-425`](metamorpho/src/MetaMorpho.sol#L420-L425),
`revokePendingGuardian` [`:427-432`](metamorpho/src/MetaMorpho.sol#L427-L432),
`revokePendingCap` [`:434-439`](metamorpho/src/MetaMorpho.sol#L434-L439),
`revokePendingMarketRemoval` [`:441-447`](metamorpho/src/MetaMorpho.sol#L441-L447).
Each `delete`s the pending struct and emits.

### 8.5 Accept functions

`acceptTimelock` [`:460-463`](metamorpho/src/MetaMorpho.sol#L460-L463),
`acceptGuardian` [`:465-468`](metamorpho/src/MetaMorpho.sol#L465-L468),
`acceptCap` [`:470-476`](metamorpho/src/MetaMorpho.sol#L470-L476) — all gated by
`afterTimelock(...)` and **callable by anyone**. Enacting an already-vetted, already-waited change
needs no privilege.

### 8.6 `skim(address token)`

[`:478-488`](metamorpho/src/MetaMorpho.sol#L478-L488). Sweeps stray tokens to `skimRecipient`.
Cannot be used on the vault asset in a harmful way because vault assets live on Blue, not in the
vault contract.

### 8.7 ERC-4626 entry points

All four accrue the fee first and update `lastTotalAssets`:

| Function | Line | Conversion | Rounding |
|---|---|---|---|
| `deposit` | [`:535-545`](metamorpho/src/MetaMorpho.sol#L535-L545) | assets → shares | Floor |
| `mint` | [`:548-558`](metamorpho/src/MetaMorpho.sol#L548-L558) | shares → assets | Ceil |
| `withdraw` | [`:561-572`](metamorpho/src/MetaMorpho.sol#L561-L572) | assets → shares | Ceil |
| `redeem` | [`:575-586`](metamorpho/src/MetaMorpho.sol#L575-L586) | shares → assets | Floor |

Every rounding favours the vault, matching Blue's discipline (§2.1).

The comment at [`:538-539`](metamorpho/src/MetaMorpho.sol#L538-L539) — *"Update `lastTotalAssets`
to avoid an inconsistent state in a re-entrant context"* — marks a real hazard. `_deposit` calls
into Blue, which may call an ERC-777-style token, which may reenter the vault. Writing
`lastTotalAssets` eagerly at [`:540`](metamorpho/src/MetaMorpho.sol#L540) means a reentrant call
sees a consistent value rather than one that would mint phantom fee shares. The repo ships an
[`ERC777Mock`](metamorpho/src/mocks/ERC777Mock.sol) and an
[`ERC1820Registry`](metamorpho/src/mocks/ERC1820Registry.sol) specifically to test this.

`withdraw` and `redeem` deliberately skip the expensive `maxWithdraw` precheck
([`:564`](metamorpho/src/MetaMorpho.sol#L564), [`:578`](metamorpho/src/MetaMorpho.sol#L578)) and
let `_withdrawMorpho` revert instead.

### 8.8 `totalAssets()` and the max-* views

```solidity
function totalAssets() public view override returns (uint256 assets) {
    for (uint256 i; i < withdrawQueue.length; ++i) {
        assets += MORPHO.expectedSupplyAssets(_marketParams(withdrawQueue[i]), address(this));
    }
}
```

[`:589-593`](metamorpho/src/MetaMorpho.sol#L589-L593). Up to 30 markets, each doing a full
accrual simulation including an external `borrowRateView` call. **This is not a cheap view**, and
every `convertToShares`/`convertToAssets` pays it.

Only the **withdraw** queue is summed, never the supply queue. That is why dropping a funded market
from the withdraw queue is so tightly guarded (§7.3): it would erase those assets from the vault's
own accounting.

`maxDeposit`/`maxMint` ([`:497-507`](metamorpho/src/MetaMorpho.sol#L497-L507)) sum remaining cap
headroom via `_maxDeposit` ([`:618-632`](metamorpho/src/MetaMorpho.sol#L618-L632)). The NatSpec at
[`:502`](metamorpho/src/MetaMorpho.sol#L502) admits it over-reports if the supply queue contains
duplicates — which `setSupplyQueue` does not forbid.

`maxWithdraw`/`maxRedeem` ([`:515-529`](metamorpho/src/MetaMorpho.sol#L515-L529)) carry an honest
two-part warning at [`:510-514`](metamorpho/src/MetaMorpho.sol#L510-L514): they may over-report
inside a Blue callback, because `_simulateWithdrawMorpho` counts Blue's loan-token balance once
per market rather than once globally.

### 8.9 Internal machinery

| Function | Line | Notes |
|---|---|---|
| `_supplyMorpho` | [`:775-804`](metamorpho/src/MetaMorpho.sol#L775-L804) | walks supply queue, `try/catch` per market, reverts `AllCapsReached` if anything is left |
| `_withdrawMorpho` | [`:807-828`](metamorpho/src/MetaMorpho.sol#L807-L828) | walks withdraw queue, `try/catch`, reverts `NotEnoughLiquidity` |
| `_simulateWithdrawMorpho` | [`:832-858`](metamorpho/src/MetaMorpho.sol#L832-L858) | view twin of the above |
| `_withdrawable` | [`:862-874`](metamorpho/src/MetaMorpho.sol#L862-L874) | `min(supplyAssets, min(totalSupply − totalBorrow, loanToken.balanceOf(MORPHO)))` |
| `_setCap` | [`:745-770`](metamorpho/src/MetaMorpho.sol#L745-L770) | pushes to withdraw queue on first enable |
| `_accrueFee` / `_accruedFeeShares` | [`:887-910`](metamorpho/src/MetaMorpho.sol#L887-L910) | performance fee on interest only |

The `try/catch` in both loops
([`:795`](metamorpho/src/MetaMorpho.sol#L795), [`:819`](metamorpho/src/MetaMorpho.sol#L819)) is
important: one broken Blue market — a reverting oracle, say — must not brick the entire vault. The
loop skips it and continues.

`_withdrawable` includes `ERC20(marketParams.loanToken).balanceOf(address(MORPHO))` in its `min`
([`:869-871`](metamorpho/src/MetaMorpho.sol#L869-L871)) with the comment *"Inside a flashloan
callback, liquidity on Morpho Blue may be limited to the singleton's balance."* This is the
MetaMorpho-side consequence of Blue's fee-free flash loan (§3.16), and a good example of a
composability edge that only appears when you read both contracts together.

`_accruedFeeShares` ([`:898-910`](metamorpho/src/MetaMorpho.sol#L898-L910)) charges the fee on
`totalAssets() − lastTotalAssets`, i.e. **interest only, never principal**, and applies the same
`newTotalAssets - feeAssets` denominator compensation as Blue
([`:908`](metamorpho/src/MetaMorpho.sol#L908), cf. §3.20). The comment at
[`:903`](metamorpho/src/MetaMorpho.sol#L903) acknowledges the fee rounds to zero when
`totalInterest * fee < WAD`.

---

<a id="9-metamorpho-factory-libraries-interfaces-mocks"></a>
## 9. MetaMorpho factory, libraries, interfaces, mocks

All 15 files in the repo are accounted for here and in §7–8.

### 9.1 `MetaMorphoFactory`

[`metamorpho/src/MetaMorphoFactory.sol`](metamorpho/src/MetaMorphoFactory.sol), 58 lines.

```solidity
metaMorpho = IMetaMorpho(
    address(new MetaMorpho{salt: salt}(initialOwner, MORPHO, initialTimelock, asset, name, symbol))
);
isMetaMorpho[address(metaMorpho)] = true;
```

[`:48-52`](metamorpho/src/MetaMorphoFactory.sol#L48-L52).

**Full deployment, not a proxy.** `new MetaMorpho{salt:}` deploys a complete 911-line contract via
CREATE2 — no clone, no delegatecall, no upgradeability. Each vault is independent bytecode, which
means a vault's owner cannot be upgraded into something else, and it costs real gas to deploy.
The `salt` gives deterministic addresses.

`isMetaMorpho` is the only registry: a boolean map that integrators use to distinguish a genuine
factory-deployed vault from an impostor with the same interface. `MORPHO` is immutable
([`:20`](metamorpho/src/MetaMorphoFactory.sol#L20)), so a factory is pinned to one Blue deployment.

### 9.2 Libraries

| File | Lines | Contents |
|---|---|---|
| [`ConstantsLib.sol`](metamorpho/src/libraries/ConstantsLib.sol) | 20 | `MAX_TIMELOCK` 2 weeks, `MIN_TIMELOCK` 1 day, `MAX_QUEUE_LENGTH` 30, `MAX_FEE` 0.5e18 |
| [`PendingLib.sol`](metamorpho/src/libraries/PendingLib.sol) | 48 | `MarketConfig`, `PendingUint192`, `PendingAddress` + two `update` overloads |
| [`ErrorsLib.sol`](metamorpho/src/libraries/ErrorsLib.sol) | 98 | **custom errors**, unlike Blue's strings |
| [`EventsLib.sol`](metamorpho/src/libraries/EventsLib.sol) | 109 | every vault event |

`MarketConfig` packs `uint184 cap` + `bool enabled` + `uint64 removableAt` into one slot
([`PendingLib.sol:4-12`](metamorpho/src/libraries/PendingLib.sol#L4-L12)), which is why
`submitCap` casts through `toUint184`
([`MetaMorpho.sol:283`](metamorpho/src/MetaMorpho.sol#L283)). The comment at
[`PendingLib.sol:6`](metamorpho/src/libraries/PendingLib.sol#L6) is worth noting: *"The exposure
to a given market can go beyond the cap in case of interest or donations."* Caps bound new
allocation, not accrued position size.

### 9.3 Interfaces

[`IMetaMorpho.sol`](metamorpho/src/interfaces/IMetaMorpho.sol), 222 lines, splits into
`IMetaMorphoBase`, `IMetaMorphoStaticTyping` and `IMetaMorpho` — the identical
tuple-versus-struct pattern Blue uses (§6.1).
[`IMetaMorphoFactory.sol`](metamorpho/src/interfaces/IMetaMorphoFactory.sol), 32 lines.

### 9.4 Mocks

| File | Lines | Purpose |
|---|---|---|
| [`ERC777Mock.sol`](metamorpho/src/mocks/ERC777Mock.sol) | 531 | full ERC-777 with transfer hooks — for reentrancy tests |
| [`ERC1820Registry.sol`](metamorpho/src/mocks/ERC1820Registry.sol) | 221 | the registry ERC-777 requires |
| [`ERC20Mock.sol`](metamorpho/src/mocks/ERC20Mock.sol) | — | plain token |
| [`OracleMock.sol`](metamorpho/src/mocks/OracleMock.sol) | — | settable price |
| [`IrmMock.sol`](metamorpho/src/mocks/IrmMock.sol) | 25 | test IRM |
| [`MetaMorphoMock.sol`](metamorpho/src/mocks/MetaMorphoMock.sol) | 27 | minimal vault stub |
| [`MorphoImport.sol`](metamorpho/src/mocks/MorphoImport.sol) | — | pulls Blue into the build so tests can deploy it |

That two mocks totalling **752 lines** exist purely to model ERC-777 reentrancy tells you how
seriously the reentrancy path through `_deposit` (§8.7) is taken.

---

<a id="10-oracles"></a>
## 10. Oracles

[`morpho-blue-oracles/`](morpho-blue-oracles/), 12 files. Blue's `IOracle` is a single `price()`
view (§6.3), so all the difficulty lives here: composing feeds and getting the scale exactly right.

### 10.1 `MorphoChainlinkOracleV2` — the `SCALE_FACTOR` derivation

[`morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol),
157 lines. Ten immutables, one constructor, one function.

The whole contract exists to answer: *how many loan-token units is one collateral-token unit
worth, scaled by 1e36?* It supports up to **two feeds on each side** plus an optional ERC-4626
vault on each side, which covers chains of the form wstETH → stETH → ETH → USD.

The constructor's comment block at
[`:113-137`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol#L113-L137) is
the best piece of documentation in either repo. Reproducing the derivation:

Let `B1, B2, Q1, Q2, C` be assets with `dB1, dB2, dQ1, dQ2, dC` decimals, and let the feeds report

- `pB1` = units of `1e(dB2)` of B2 per `1e(dB1)` of B1
- `pB2` = units of `1e(dC)` of C per `1e(dB2)` of B2
- `pQ1`, `pQ2` symmetrically on the quote side

Blue wants `price()` = quantity of 1 asset Q1 exchangeable for 1 asset B1, times 1e36:

```
1e36 · (pB1 · 1e(dB2−dB1)) · (pB2 · 1e(dC−dB2)) / ((pQ1 · 1e(dQ2−dQ1)) · (pQ2 · 1e(dC−dQ2)))
  = 1e36 · (pB1 · 1e(−dB1) · pB2) / (pQ1 · 1e(−dQ1) · pQ2)
```

The `dB2` and `dC` terms cancel, which is why intermediate decimals never appear in the final
formula. Feeds actually return `p · 1e(fp)` for feed precision `fp`, so solving for the constant
that makes the runtime expression come out right:

```
SCALE_FACTOR = 1e(36 + dQ1 + fpQ1 + fpQ2 − dB1 − fpB1 − fpB2)
```

which is exactly the code at
[`:138-145`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol#L138-L145),
with the vault conversion samples folded in:

```solidity
SCALE_FACTOR = 10
    ** (36
        + quoteTokenDecimals
        + quoteFeed1.getDecimals()
        + quoteFeed2.getDecimals()
        - baseTokenDecimals
        - baseFeed1.getDecimals()
        - baseFeed2.getDecimals()) * quoteVaultConversionSample / baseVaultConversionSample;
```

`price()` is then a single `mulDiv`
([`:151-156`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol#L151-L156)):

```solidity
return SCALE_FACTOR.mulDiv(
    BASE_VAULT.getAssets(BASE_VAULT_CONVERSION_SAMPLE) * BASE_FEED_1.getPrice() * BASE_FEED_2.getPrice(),
    QUOTE_VAULT.getAssets(QUOTE_VAULT_CONVERSION_SAMPLE) * QUOTE_FEED_1.getPrice() * QUOTE_FEED_2.getPrice()
);
```

**The absent-component trick.** Every optional piece returns a multiplicative identity rather than
branching. `VaultLib.getAssets` returns `1` for a zero-address vault
([`VaultLib.sol:13-17`](morpho-blue-oracles/src/morpho-chainlink/libraries/VaultLib.sol#L13-L17));
`ChainlinkDataFeedLib.getPrice` returns `1` for a zero-address feed
([`ChainlinkDataFeedLib.sol:38-45`](morpho-blue-oracles/src/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol#L38-L45));
and `getDecimals` returns **`0`** so the exponent is unaffected
([`:49-53`](morpho-blue-oracles/src/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol#L49-L53)).
Four optional components, zero conditionals in `price()`.

Constructor validation is thin: only that a conversion sample is `1` when its vault is unset, and
non-zero otherwise
([`:93-102`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol#L93-L102)).
Nothing checks that the feeds actually describe the assets in the market — a misconfigured oracle
is a valid oracle.

The warning at
[`:70-72`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol#L70-L72) is
important and easy to miss: a vault that can receive donations must not be used as the loan/quote
asset, because an instantaneous price *drop* larger than `LLTV·LIF` would create bad debt faster
than liquidators can act.

### 10.2 `ChainlinkDataFeedLib` — what is deliberately *not* checked

[`ChainlinkDataFeedLib.sol:31-37`](morpho-blue-oracles/src/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol#L31-L37)
states the position outright:

```
- Using oracles on L2s assumes that the liveness risks are acceptable, there is no additional safety check.
- Staleness is not checked because it's assumed that the Chainlink feed keeps its promises on this.
- The price is not checked to be in the min/max bounds because it's assumed that the Chainlink feed keeps its promises.
```

The only validation is `answer >= 0`
([`:42`](morpho-blue-oracles/src/morpho-chainlink/libraries/ChainlinkDataFeedLib.sol#L42),
`NEGATIVE_ANSWER`). No `updatedAt` check, no L2 sequencer-uptime feed, no round-completeness check.

This is the same gap I flagged in Aave v2's `AaveOracle`
([`../aave/V1-V2-COMPLETE-REFERENCE.md`](../aave/V1-V2-COMPLETE-REFERENCE.md)) — but the posture
differs. Aave v2 has one oracle for the whole protocol and no alternative; Morpho documents the
omission and pushes the choice to the market creator, who is free to deploy a stricter `IOracle`.
Whether that is principled minimalism or passing the buck is a fair question, and it is the single
largest risk surface in the Morpho stack.

### 10.3 `MorphoChainlinkOracleV2Factory`

[`MorphoChainlinkOracleV2Factory.sol`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2Factory.sol),
54 lines. CREATE2 deploy plus an `isMorphoChainlinkOracleV2` registry
([`:37-52`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2Factory.sol#L37-L52)),
mirroring `MetaMorphoFactory` (§9.1). The registry lets a front-end say "this oracle came from the
canonical factory", which is weak assurance but better than none.

### 10.4 `WstEthStEthExchangeRateChainlinkAdapter`

[`WstEthStEthExchangeRateChainlinkAdapter.sol`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol),
30 lines — an adapter that makes a Lido call *look* like a Chainlink feed:

```solidity
function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (0, int256(ST_ETH.getPooledEthByShares(1 ether)), 0, 0, 0);
}
```

[`:26-29`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L26-L29).

`decimals` is a hardcoded constant 18
([`:15`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L15))
and stETH is a hardcoded mainnet address
([`:21`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L21)),
which is why the NatSpec restricts it to Ethereum
([`:11`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L11)).

Two honest caveats in the source. It returns **zero for `roundId`, `startedAt`, `updatedAt` and
`answeredInRound`** ([`:24`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L24)),
so any consumer that *did* check staleness would see a permanently stale feed — harmless here only
because §10.2 never checks. And it *"silently overflows if `getPooledEthByShares`'s return value is
greater than `type(int256).max`"*
([`:25`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L25)),
unreachable in practice.

Using an exchange rate rather than a market price is the correct choice for wstETH/stETH: it cannot
be manipulated by trading, and it ignores any temporary depeg. The trade-off is that a genuine
Lido slashing event would not show up until the rate itself moved.

### 10.5 The remaining oracle files

| File | Lines | What it is |
|---|---|---|
| [`interfaces/AggregatorV3Interface.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/AggregatorV3Interface.sol) | 22 | trimmed Chainlink interface |
| [`interfaces/IERC4626.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/IERC4626.sol) | — | only `convertToAssets` |
| [`interfaces/IMorphoChainlinkOracleV2.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2.sol) | 39 | the ten immutables as getters |
| [`interfaces/IMorphoChainlinkOracleV2Factory.sol`](morpho-blue-oracles/src/morpho-chainlink/interfaces/IMorphoChainlinkOracleV2Factory.sol) | 56 | factory surface |
| [`libraries/ErrorsLib.sol`](morpho-blue-oracles/src/morpho-chainlink/libraries/ErrorsLib.sol) | — | three string constants |
| [`wsteth-exchange-rate-adapter/interfaces/IStEth.sol`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/interfaces/IStEth.sol) | — | just `getPooledEthByShares` |
| [`wsteth-exchange-rate-adapter/interfaces/MinimalAggregatorV3Interface.sol`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/interfaces/MinimalAggregatorV3Interface.sol) | — | `decimals` + `latestRoundData` only |

---

<a id="11-bundlers"></a>
## 11. Bundlers

[`morpho-blue-bundlers/`](morpho-blue-bundlers/), 53 files — the largest of the four repos, and
the one that exists purely because Blue's core is so small. Every convenience Aave builds into its
`Pool` (permit variants, ETH wrapping, migration adapters) lives out here instead.

### 11.1 `BaseBundler` — `delegatecall` multicall

[`morpho-blue-bundlers/src/BaseBundler.sol`](morpho-blue-bundlers/src/BaseBundler.sol), 98 lines.
Everything else inherits it.

```solidity
function multicall(bytes[] memory data) external payable {
    require(_initiator == UNSET_INITIATOR, ErrorsLib.ALREADY_INITIATED);
    _initiator = msg.sender;
    _multicall(data);
    _initiator = UNSET_INITIATOR;
}
```

[`:51-59`](morpho-blue-bundlers/src/BaseBundler.sol#L51-L59), with `_multicall`
`delegatecall`ing into `address(this)` for each element
([`:65-72`](morpho-blue-bundlers/src/BaseBundler.sol#L65-L72)).

**`_initiator` is the whole security model.** It does two jobs at once, as its comment at
[`:23-24`](morpho-blue-bundlers/src/BaseBundler.sol#L23-L24) says: it records who started the
bundle, *and* it prevents any bundler function being called outside a bundle. The `protected`
modifier ([`:31-36`](morpho-blue-bundlers/src/BaseBundler.sol#L31-L36)) enforces both:

```solidity
require(_initiator != UNSET_INITIATOR, ErrorsLib.UNINITIATED);
require(_isSenderAuthorized(), ErrorsLib.UNAUTHORIZED_SENDER);
```

This matters because the bundler holds token approvals from users. Without `protected`, anyone
could call `erc20TransferFrom` directly and drain another user's approval. It is the same class of
risk LI.FI manages with its allowlist
([`../lifi/LIBRARIES-PERIPHERY-COMPLETE-REFERENCE.md`](../lifi/LIBRARIES-PERIPHERY-COMPLETE-REFERENCE.md)),
solved differently: LI.FI restricts *what you may call*, Morpho restricts *when you may be called*.

`_revert` ([`:76-83`](morpho-blue-bundlers/src/BaseBundler.sol#L76-L83)) bubbles the inner revert
reason with assembly so a failed step reports its real error, not a generic one.

The warning at [`:15-17`](morpho-blue-bundlers/src/BaseBundler.sol#L15-L17) is a genuine footgun:
every external bundler function must be `payable`, and **`msg.value` is the same for every
delegatecalled step**, so a bundler function must never treat `msg.value` as "the value for this
step".

### 11.2 `MorphoBundler` — reentering the bundle from a Blue callback

[`morpho-blue-bundlers/src/MorphoBundler.sol`](morpho-blue-bundlers/src/MorphoBundler.sol), 271 lines.
The bridge between Blue's callbacks (§6.4) and the multicall.

```solidity
function _callback(bytes calldata data) internal {
    require(msg.sender == address(MORPHO), ErrorsLib.UNAUTHORIZED_SENDER);
    _multicall(abi.decode(data, (bytes[])));
}

function _isSenderAuthorized() internal view virtual override returns (bool) {
    return super._isSenderAuthorized() || msg.sender == address(MORPHO);
}
```

[`:261-270`](morpho-blue-bundlers/src/MorphoBundler.sol#L261-L270).

This is the clever part of the whole repo. The `data` you pass to `morphoSupply` is itself an
encoded `bytes[]` of further bundler calls. Blue invokes `onMorphoSupply`, which invokes
`_callback`, which runs a **nested multicall** — inside Blue's execution, before Blue pulls your
tokens. The `_isSenderAuthorized` override is what lets Blue be a legitimate `msg.sender` for
`protected` functions during that window.

All five callbacks are thin wrappers over `_callback`:
`onMorphoSupply` [`:35-38`](morpho-blue-bundlers/src/MorphoBundler.sol#L35-L38),
`onMorphoSupplyCollateral` [`:40-43`](morpho-blue-bundlers/src/MorphoBundler.sol#L40-L43),
`onMorphoRepay` [`:45-48`](morpho-blue-bundlers/src/MorphoBundler.sol#L45-L48),
`onMorphoFlashLoan` [`:50-53`](morpho-blue-bundlers/src/MorphoBundler.sol#L50-L53).

| Function | Line | Wraps |
|---|---|---|
| `morphoSetAuthorizationWithSig` | [`:62`](morpho-blue-bundlers/src/MorphoBundler.sol#L62) | §3.18 |
| `morphoSupply` | [`:87`](morpho-blue-bundlers/src/MorphoBundler.sol#L87) | §3.9 |
| `morphoSupplyCollateral` | [`:117`](morpho-blue-bundlers/src/MorphoBundler.sol#L117) | §3.13 |
| `morphoBorrow` | [`:146`](morpho-blue-bundlers/src/MorphoBundler.sol#L146) | §3.11 |
| `morphoRepay` | [`:171`](morpho-blue-bundlers/src/MorphoBundler.sol#L171) | §3.12 |
| `morphoWithdraw` | [`:205`](morpho-blue-bundlers/src/MorphoBundler.sol#L205) | §3.10 |
| `morphoWithdrawCollateral` | [`:224`](morpho-blue-bundlers/src/MorphoBundler.sol#L224) | §3.14 |
| `morphoFlashLoan` | [`:236`](morpho-blue-bundlers/src/MorphoBundler.sol#L236) | §3.16 |
| `reallocateTo` | [`:248`](morpho-blue-bundlers/src/MorphoBundler.sol#L248) | public allocator |

### 11.3 The bundler mixins

Each is a self-contained capability, combined by inheritance:

| Mixin | Lines | Provides |
|---|---|---|
| [`TransferBundler`](morpho-blue-bundlers/src/TransferBundler.sol) | — | `nativeTransfer` [`:25`](morpho-blue-bundlers/src/TransferBundler.sol#L25), `erc20Transfer` [`:42`](morpho-blue-bundlers/src/TransferBundler.sol#L42), `erc20TransferFrom` [`:57`](morpho-blue-bundlers/src/TransferBundler.sol#L57) |
| [`PermitBundler`](morpho-blue-bundlers/src/PermitBundler.sol) | — | EIP-2612 `permit` |
| [`Permit2Bundler`](morpho-blue-bundlers/src/Permit2Bundler.sol) | — | Uniswap Permit2 signature transfers |
| [`ERC4626Bundler`](morpho-blue-bundlers/src/ERC4626Bundler.sol) | 122 | `erc4626Mint/Deposit/Withdraw/Redeem` — how MetaMorpho is reached |
| [`WNativeBundler`](morpho-blue-bundlers/src/WNativeBundler.sol) | — | `wrapNative` / `unwrapNative` |
| [`StEthBundler`](morpho-blue-bundlers/src/StEthBundler.sol) | — | stETH ↔ wstETH |
| [`UrdBundler`](morpho-blue-bundlers/src/UrdBundler.sol) | — | claims from the Universal Rewards Distributor |
| [`ERC20WrapperBundler`](morpho-blue-bundlers/src/ERC20WrapperBundler.sol) | — | permissioned-token wrappers |

`erc20TransferFrom` at
[`TransferBundler.sol:57`](morpho-blue-bundlers/src/TransferBundler.sol#L57) pulls from
`initiator()`, not `msg.sender` — which is exactly why `protected` must be airtight.

### 11.4 The deployed bundlers

Only two matter in production, and both are pure composition with no new logic:

```solidity
contract ChainAgnosticBundlerV2 is
    TransferBundler, PermitBundler, Permit2Bundler, ERC4626Bundler,
    WNativeBundler, UrdBundler, MorphoBundler, ERC20WrapperBundler
```

[`chain-agnostic/ChainAgnosticBundlerV2.sol:18-26`](morpho-blue-bundlers/src/chain-agnostic/ChainAgnosticBundlerV2.sol#L18-L26)

```solidity
contract EthereumBundlerV2 is
    TransferBundler, EthereumPermitBundler, Permit2Bundler, ERC4626Bundler,
    WNativeBundler, EthereumStEthBundler, UrdBundler, MorphoBundler, ERC20WrapperBundler
```

[`ethereum/EthereumBundlerV2.sol:21-30`](morpho-blue-bundlers/src/ethereum/EthereumBundlerV2.sol#L21-L30)

The mainnet variant swaps in `EthereumPermitBundler` (which adds DAI's non-standard permit, via
[`IDaiPermit`](morpho-blue-bundlers/src/ethereum/interfaces/IDaiPermit.sol)) and
`EthereumStEthBundler`, and hardcodes WETH from
[`MainnetLib`](morpho-blue-bundlers/src/ethereum/libraries/MainnetLib.sol). Both must override
`_isSenderAuthorized` explicitly to resolve the diamond between `BaseBundler` and `MorphoBundler`
([`EthereumBundlerV2.sol:39-41`](morpho-blue-bundlers/src/ethereum/EthereumBundlerV2.sol#L39-L41)).

Testnet twins: [`GoerliBundlerV2`](morpho-blue-bundlers/src/goerli/GoerliBundlerV2.sol) and
[`SepoliaBundlerV2`](morpho-blue-bundlers/src/sepolia/SepoliaBundlerV2.sol) with their own address
libraries.

### 11.5 Migration bundlers

Six contracts that move a position from a competitor into Blue **atomically**, all inheriting
[`MigrationBundler`](morpho-blue-bundlers/src/migration/MigrationBundler.sol):

| Bundler | Migrates from |
|---|---|
| [`AaveV2MigrationBundlerV2`](morpho-blue-bundlers/src/migration/AaveV2MigrationBundlerV2.sol) | Aave v2 |
| [`AaveV3MigrationBundlerV2`](morpho-blue-bundlers/src/migration/AaveV3MigrationBundlerV2.sol) | Aave v3 |
| [`AaveV3OptimizerMigrationBundlerV2`](morpho-blue-bundlers/src/migration/AaveV3OptimizerMigrationBundlerV2.sol) | Morpho's own Aave v3 Optimizer |
| [`CompoundV2MigrationBundlerV2`](morpho-blue-bundlers/src/migration/CompoundV2MigrationBundlerV2.sol) | Compound v2 |
| [`CompoundV3MigrationBundlerV2`](morpho-blue-bundlers/src/migration/CompoundV3MigrationBundlerV2.sol) | Compound v3 |

The recipe is always the same, and it is a good exercise to trace: flash loan the debt asset from
Blue (free, §3.16) → repay the old protocol → withdraw the old collateral → `supplyCollateral` to
Blue → `borrow` from Blue → repay the flash loan. One transaction, no capital.

The interface files are large because they vendor competitor ABIs:
[`IAaveV3.sol`](morpho-blue-bundlers/src/migration/interfaces/IAaveV3.sol) is 523 lines and
[`IAaveV2.sol`](morpho-blue-bundlers/src/migration/interfaces/IAaveV2.sol) is 261, alongside
[`ICToken`](morpho-blue-bundlers/src/migration/interfaces/ICToken.sol),
[`ICEth`](morpho-blue-bundlers/src/migration/interfaces/ICEth.sol),
[`IComptroller`](morpho-blue-bundlers/src/migration/interfaces/IComptroller.sol),
[`ICompoundV3`](morpho-blue-bundlers/src/migration/interfaces/ICompoundV3.sol) and
[`IAaveV3Optimizer`](morpho-blue-bundlers/src/migration/interfaces/IAaveV3Optimizer.sol).

### 11.6 Remaining bundler files

Interfaces: [`IMulticall`](morpho-blue-bundlers/src/interfaces/IMulticall.sol),
[`IMorphoBundler`](morpho-blue-bundlers/src/interfaces/IMorphoBundler.sol),
[`IPublicAllocator`](morpho-blue-bundlers/src/interfaces/IPublicAllocator.sol),
[`IStEth`](morpho-blue-bundlers/src/interfaces/IStEth.sol),
[`IWstEth`](morpho-blue-bundlers/src/interfaces/IWstEth.sol),
[`IWNative`](morpho-blue-bundlers/src/interfaces/IWNative.sol).
Libraries: [`ConstantsLib`](morpho-blue-bundlers/src/libraries/ConstantsLib.sol) (holds
`UNSET_INITIATOR`), [`ErrorsLib`](morpho-blue-bundlers/src/libraries/ErrorsLib.sol).
Twelve mocks including several `*Import.sol` files whose only job is to pull external bytecode
into the test build.

---

<a id="12-storage-layouts"></a>
## 12. Storage layouts

### 12.1 `Morpho`

Nine slots. Full table in §1.5. `DOMAIN_SEPARATOR` is `immutable`
([`Morpho.sol:33`](morpho-blue/src/Morpho.sol#L33)) so it lives in bytecode, not storage.

Packing within the mapped structs:

| Struct | Word | Bits 0–127 | Bits 128–255 |
|---|---|---|---|
| `Position` | 0 | `supplyShares` (full `uint256`) | — |
| `Position` | 1 | `borrowShares` | `collateral` |
| `Market` | 0 | `totalSupplyAssets` | `totalSupplyShares` |
| `Market` | 1 | `totalBorrowAssets` | `totalBorrowShares` |
| `Market` | 2 | `lastUpdate` | `fee` |

Verified against the shifts in `MorphoLib` (§5.2): low half by truncation, high half by `>> 128`.

**Two words per user per market, three per market.** That is the entire footprint of a lending
market.

### 12.2 `MetaMorpho`

Inherits OZ `ERC20`, `ERC20Permit`, `ERC4626` and `Ownable2Step`, so vault-specific storage begins
after those. Own declarations at
[`:59-106`](metamorpho/src/MetaMorpho.sol#L59-L106):

| Variable | Type | Notes |
|---|---|---|
| `MORPHO` | `IMorpho` immutable | bytecode |
| `DECIMALS_OFFSET` | `uint8` immutable | bytecode |
| `curator` | `address` | |
| `isAllocator` | `mapping(address => bool)` | |
| `guardian` | `address` | |
| `config` | `mapping(Id => MarketConfig)` | one packed slot per market |
| `timelock` | `uint256` | |
| `pendingGuardian` | `PendingAddress` | `address` + `uint64` in one slot |
| `pendingCap` | `mapping(Id => PendingUint192)` | `uint192` + `uint64` in one slot |
| `pendingTimelock` | `PendingUint192` | one slot |
| `fee` | `uint96` | |
| `feeRecipient` | `address` | packs with `fee` |
| `skimRecipient` | `address` | |
| `supplyQueue` | `Id[]` | ≤ 30 |
| `withdrawQueue` | `Id[]` | ≤ 30 |
| `lastTotalAssets` | `uint256` | fee high-water mark |

`fee` is `uint96` specifically so it shares a slot with `feeRecipient`
([`:91-94`](metamorpho/src/MetaMorpho.sol#L91-L94)), and every pending struct is sized to fit one
word with its `uint64 validAt`.

---

<a id="13-selector--abi-tables"></a>
## 13. Selector / ABI tables

Every selector below was computed with `cast sig` against the fully-expanded tuple signature, not
transcribed. `MarketParams` expands to `(address,address,address,address,uint256)`.

### 13.1 `Morpho`

| Selector | Signature |
|---|---|
| `0xa99aad89` | `supply((address,address,address,address,uint256),uint256,uint256,address,bytes)` |
| `0x5c2bea49` | `withdraw((address,address,address,address,uint256),uint256,uint256,address,address)` |
| `0x50d8cd4b` | `borrow((address,address,address,address,uint256),uint256,uint256,address,address)` |
| `0x20b76e81` | `repay((address,address,address,address,uint256),uint256,uint256,address,bytes)` |
| `0x238d6579` | `supplyCollateral((address,address,address,address,uint256),uint256,address,bytes)` |
| `0x8720316d` | `withdrawCollateral((address,address,address,address,uint256),uint256,address,address)` |
| `0xd8eabcb8` | `liquidate((address,address,address,address,uint256),address,uint256,uint256,bytes)` |
| `0xe0232b42` | `flashLoan(address,uint256,bytes)` |
| `0x8c1358a2` | `createMarket((address,address,address,address,uint256))` |
| `0x151c1ade` | `accrueInterest((address,address,address,address,uint256))` |
| `0xeecea000` | `setAuthorization(address,bool)` |
| `0x8069218f` | `setAuthorizationWithSig((address,address,bool,uint256,uint256),(uint8,bytes32,bytes32))` |
| `0x2b4f013c` | `setFee((address,address,address,address,uint256),uint256)` |
| `0x5a64f51e` | `enableIrm(address)` |
| `0x4d98a93b` | `enableLltv(uint256)` |
| `0x13af4035` | `setOwner(address)` |
| `0xe74b981b` | `setFeeRecipient(address)` |
| `0x7784c685` | `extSloads(bytes32[])` |
| `0x8da5cb5b` | `owner()` |
| `0x46904840` | `feeRecipient()` |
| `0x3644e515` | `DOMAIN_SEPARATOR()` |
| `0x93c52062` | `position(bytes32,address)` |
| `0x5c60e39a` | `market(bytes32)` |
| `0x2c3c9157` | `idToMarketParams(bytes32)` |
| `0xf2b863ce` | `isIrmEnabled(address)` |
| `0xb485f3b8` | `isLltvEnabled(uint256)` |
| `0x65e4ad9e` | `isAuthorized(address,address)` |
| `0x70ae92d2` | `nonce(address)` |

Twenty-eight entries, and that is the complete external surface of the protocol.

### 13.2 `MetaMorpho`

| Selector | Signature |
|---|---|
| `0x6e553f65` | `deposit(uint256,address)` |
| `0x94bf804d` | `mint(uint256,address)` |
| `0xb460af94` | `withdraw(uint256,address,address)` |
| `0xba087652` | `redeem(uint256,address,address)` |
| `0x01e1d114` | `totalAssets()` |
| `0x7299aa31` | `reallocate(((address,address,address,address,uint256),uint256)[])` |
| `0x3b24c2bf` | `submitCap((address,address,address,address,uint256),uint256)` |
| `0x6fda3868` | `acceptCap((address,address,address,address,uint256))` |
| `0x84755b5f` | `submitMarketRemoval((address,address,address,address,uint256))` |
| `0x2acc56f9` | `setSupplyQueue(bytes32[])` |
| `0x41b67833` | `updateWithdrawQueue(uint256[])` |
| `0x7224a512` | `submitTimelock(uint256)` |
| `0x8a2c7b39` | `acceptTimelock()` |
| `0x69fe0e2d` | `setFee(uint256)` |
| `0xe90956cf` | `setCurator(address)` |
| `0xb192a84a` | `setIsAllocator(address,bool)` |
| `0x9d6b4a45` | `submitGuardian(address)` |
| `0xa5f31d61` | `acceptGuardian()` |
| `0xbc25cf77` | `skim(address)` |

Note `deposit`, `mint`, `withdraw` and `redeem` carry the standard ERC-4626 selectors, so any
4626-aware integration works against a MetaMorpho vault unmodified.

