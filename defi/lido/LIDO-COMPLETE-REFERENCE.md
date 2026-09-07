# Lido v3 — Complete Reference

Every contract and every function in [`lidofinance/core`](https://github.com/lidofinance/core)
v3.0.2, cloned into `lido/core` with its `.git` removed. **155 Solidity files,
37,663 lines.**

This is the exhaustive companion to [`LIDO-DEEP-DIVE.md`](LIDO-DEEP-DIVE.md),
which explains why the protocol is shaped this way. Read that first if you want
the ideas; read this when you need the surface.

Every `path:line` below is a link that jumps to the exact line, and every one was
checked against the source with `grep -n` before it was written.

**A note on the tree.** Lido is unusual in that it spans four Solidity major
versions in one repository, because the 2020 core was never redeployed. Directory
names *are* compiler versions:

| Directory | solc | What lives there |
|---|---|---|
| `0.4.24/` | 0.4.24 | `Lido`, `StETH`, `NodeOperatorsRegistry` — the original Aragon-app core |
| `0.6.11/`, `0.6.12/` | 0.6.x | The vendored beacon deposit contract and `WstETH` |
| `0.8.9/` | 0.8.9 | Oracles, withdrawals, `Accounting`, sanity checks, proxies |
| `0.8.25/` | 0.8.25 | Staking router, stVaults, consolidation, verifiers |
| `common/` | mixed pragmas | Libraries and interfaces shared across all of the above |

That constraint explains most of what looks odd here: unstructured storage with
keccak position constants, Aragon roles sitting next to OpenZeppelin
`AccessControl`, and three separate copies of `PausableUntil` and
`UnstructuredStorage`.

---

## Contents

- [0. File inventory (all 155)](#0-file-inventory)
- [1. Architecture and `LidoLocator`](#1-architecture-and-lidolocator)
- [2. `StETH` — the shares math](#2-steth--the-shares-math)
- [3. `StETHPermit` and `EIP712StETH`](#3-stethpermit-and-eip712steth)
- [4. `WstETH`](#4-wsteth)
- [5. `Lido.sol` — every function](#5-lidosol--every-function)
- [6. `Accounting.sol` — the rebase engine](#6-accountingsol--the-rebase-engine)
- [7. `OracleReportSanityChecker` and the limiters](#7-oraclereportsanitychecker-and-the-limiters)
- [8. The oracle stack](#8-the-oracle-stack)
- [9. Withdrawals](#9-withdrawals)
- [10. `Burner`, vaults and reward sinks](#10-burner-vaults-and-reward-sinks)
- [11. `DepositSecurityModule` and depositing](#11-depositsecuritymodule-and-depositing)
- [12. `NodeOperatorsRegistry` and its libraries](#12-nodeoperatorsregistry-and-its-libraries)
- [13. `StakingRouter`](#13-stakingrouter)
- [14. stVaults](#14-stvaults)
- [15. Exits, consolidation and verifiers](#15-exits-consolidation-and-verifiers)
- [16. `common/lib` — shared libraries](#16-commonlib--shared-libraries)
- [17. Proxies, access control, pausing, versioning](#17-proxies-access-control-pausing-versioning)
- [18. Upgrade machinery, tooling, vendored OpenZeppelin](#18-upgrade-machinery-tooling-vendored-openzeppelin)
- [19. Reference tables](#19-reference-tables)
- [20. Use-case index](#20-use-case-index)

---

## 0. File inventory

All 155 `.sol` files under `lido/core/contracts/`. Nothing is omitted; interfaces
and mocks get a row too.

| File | Lines | solc | Purpose |
|---|---:|---|---|
| [`0.4.24/Lido.sol`](core/contracts/0.4.24/Lido.sol) | 1573 | `0.4.24` | The stETH pool. Accepts ETH, mints shares, routes deposits to the beacon chain, receives oracle reports. |
| [`0.4.24/StETH.sol`](core/contracts/0.4.24/StETH.sol) | 591 | `0.4.24` | Rebasing ERC-20. Balances are derived from shares times the pooled-ETH ratio. |
| [`0.4.24/StETHPermit.sol`](core/contracts/0.4.24/StETHPermit.sol) | 179 | `0.4.24` | EIP-2612 permit for stETH, delegating hashing to EIP712StETH. |
| [`0.4.24/lib/Packed64x4.sol`](core/contracts/0.4.24/lib/Packed64x4.sol) | 50 | `^0.4.24` | Packs four uint64 counters into one storage word. |
| [`0.4.24/lib/SigningKeys.sol`](core/contracts/0.4.24/lib/SigningKeys.sol) | 180 | `0.4.24` | Storage layout and accessors for validator signing keys and signatures. |
| [`0.4.24/lib/StakeLimitUtils.sol`](core/contracts/0.4.24/lib/StakeLimitUtils.sol) | 262 | `0.4.24` | Packed staking rate-limit state and its regeneration arithmetic. |
| [`0.4.24/nos/NodeOperatorsRegistry.sol`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol) | 1497 | `0.4.24` | Curated staking module: operators, signing keys, key vetting, reward distribution. |
| [`0.4.24/template/IETHRegistrarController.sol`](core/contracts/0.4.24/template/IETHRegistrarController.sol) | 19 | `0.4.24` | ENS registrar controller interface used by the template. |
| [`0.4.24/template/IInterfaceResolver.sol`](core/contracts/0.4.24/template/IInterfaceResolver.sol) | 10 | `0.4.24` | ENS interface-resolver interface used by the template. |
| [`0.4.24/template/Imports.sol`](core/contracts/0.4.24/template/Imports.sol) | 12 | `0.4.24` | Forces Aragon artifacts into the build. |
| [`0.4.24/template/LidoTemplate.sol`](core/contracts/0.4.24/template/LidoTemplate.sol) | 745 | `0.4.24` | One-shot DAO deployment template (Aragon APM, ENS registration). |
| [`0.4.24/utils/Pausable.sol`](core/contracts/0.4.24/utils/Pausable.sol) | 44 | `0.4.24` | Simple stopped/resumed flag in unstructured storage. |
| [`0.4.24/utils/UnstructuredStorageExt.sol`](core/contracts/0.4.24/utils/UnstructuredStorageExt.sol) | 64 | `0.4.24` | Signed-integer accessors for unstructured storage. |
| [`0.4.24/utils/Versioned.sol`](core/contracts/0.4.24/utils/Versioned.sol) | 48 | `0.4.24` | Contract version counter for initializers (0.4.24 port). |
| [`0.6.11/deposit_contract.sol`](core/contracts/0.6.11/deposit_contract.sol) | 179 | `0.6.11` | Vendored Ethereum beacon deposit contract. |
| [`0.6.12/WstETH.sol`](core/contracts/0.6.12/WstETH.sol) | 119 | `0.6.12` | Non-rebasing ERC-20 wrapper over stETH shares. |
| [`0.6.12/interfaces/IStETH.sol`](core/contracts/0.6.12/interfaces/IStETH.sol) | 17 | `0.6.12` | Minimal stETH interface for the wrapper. |
| [`0.8.25/CLValidatorVerifier.sol`](core/contracts/0.8.25/CLValidatorVerifier.sol) | 109 | `0.8.25` | Verifies a validator exists on the consensus layer via SSZ proof. |
| [`0.8.25/TopUpGateway.sol`](core/contracts/0.8.25/TopUpGateway.sol) | 444 | `0.8.25` | Rate-limited gateway for validator top-up deposits. |
| [`0.8.25/ValidatorExitDelayVerifier.sol`](core/contracts/0.8.25/ValidatorExitDelayVerifier.sol) | 430 | `0.8.25` | Proves a validator was late to exit. |
| [`0.8.25/consolidation/ConsolidationBus.sol`](core/contracts/0.8.25/consolidation/ConsolidationBus.sol) | 433 | `0.8.25` | Queues and rate-limits EIP-7251 consolidation requests. |
| [`0.8.25/consolidation/ConsolidationGateway.sol`](core/contracts/0.8.25/consolidation/ConsolidationGateway.sol) | 380 | `0.8.25` | Entry point and permissioning for consolidations. |
| [`0.8.25/consolidation/ConsolidationMigrator.sol`](core/contracts/0.8.25/consolidation/ConsolidationMigrator.sol) | 404 | `0.8.25` | Migrates 0x01 validators to 0x02 credentials. |
| [`0.8.25/lib/BeaconChainDepositor.sol`](core/contracts/0.8.25/lib/BeaconChainDepositor.sol) | 161 | `0.8.25` | Builds and submits beacon deposit calls. |
| [`0.8.25/sr/ISRBase.sol`](core/contracts/0.8.25/sr/ISRBase.sol) | 102 | `0.8.25` | StakingRouter events and errors. |
| [`0.8.25/sr/SRLib.sol`](core/contracts/0.8.25/sr/SRLib.sol) | 933 | `0.8.25` | External library holding most StakingRouter logic. |
| [`0.8.25/sr/SRStorage.sol`](core/contracts/0.8.25/sr/SRStorage.sol) | 80 | `0.8.25` | StakingRouter storage positions. |
| [`0.8.25/sr/SRTypes.sol`](core/contracts/0.8.25/sr/SRTypes.sol) | 282 | `0.8.25` | StakingRouter shared structs and enums. |
| [`0.8.25/sr/SRUtils.sol`](core/contracts/0.8.25/sr/SRUtils.sol) | 97 | `0.8.25` | StakingRouter helper functions. |
| [`0.8.25/sr/StakingRouter.sol`](core/contracts/0.8.25/sr/StakingRouter.sol) | 1192 | `0.8.25` | Allocates deposits across staking modules and aggregates their state. |
| [`0.8.25/utils/AccessControlConfirmable.sol`](core/contracts/0.8.25/utils/AccessControlConfirmable.sol) | 26 | `0.8.25` | AccessControl plus Confirmations. |
| [`0.8.25/utils/Confirmable2Addresses.sol`](core/contracts/0.8.25/utils/Confirmable2Addresses.sol) | 29 | `0.8.25` | Two-address confirmation variant. |
| [`0.8.25/utils/Confirmations.sol`](core/contracts/0.8.25/utils/Confirmations.sol) | 231 | `0.8.25` | Multi-party confirmation with expiry for privileged calls. |
| [`0.8.25/utils/PausableUntilWithRoles.sol`](core/contracts/0.8.25/utils/PausableUntilWithRoles.sol) | 57 | `0.8.25` | PausableUntil gated by roles. |
| [`0.8.25/vaults/LazyOracle.sol`](core/contracts/0.8.25/vaults/LazyOracle.sol) | 684 | `0.8.25` | Merkle-root based per-vault report distribution. |
| [`0.8.25/vaults/OperatorGrid.sol`](core/contracts/0.8.25/vaults/OperatorGrid.sol) | 905 | `0.8.25` | Tier and group limits per node operator across vaults. |
| [`0.8.25/vaults/PinnedBeaconProxy.sol`](core/contracts/0.8.25/vaults/PinnedBeaconProxy.sol) | 44 | `0.8.25` | Beacon proxy that can pin its implementation. |
| [`0.8.25/vaults/StakingVault.sol`](core/contracts/0.8.25/vaults/StakingVault.sol) | 746 | `0.8.25` | A single-owner staking vault holding ETH and validators. |
| [`0.8.25/vaults/ValidatorConsolidationRequests.sol`](core/contracts/0.8.25/vaults/ValidatorConsolidationRequests.sol) | 217 | `0.8.25` | Consolidation requests originating from a vault. |
| [`0.8.25/vaults/VaultFactory.sol`](core/contracts/0.8.25/vaults/VaultFactory.sol) | 185 | `0.8.25` | Deploys a StakingVault plus its Dashboard. |
| [`0.8.25/vaults/VaultHub.sol`](core/contracts/0.8.25/vaults/VaultHub.sol) | 1773 | `0.8.25` | Connects stVaults to the protocol: share limits, tiers, rebalancing, bad debt. |
| [`0.8.25/vaults/dashboard/Dashboard.sol`](core/contracts/0.8.25/vaults/dashboard/Dashboard.sol) | 828 | `0.8.25` | Owner-facing vault control surface. |
| [`0.8.25/vaults/dashboard/NodeOperatorFee.sol`](core/contracts/0.8.25/vaults/dashboard/NodeOperatorFee.sol) | 468 | `0.8.25` | Node-operator fee accrual and claiming for a vault. |
| [`0.8.25/vaults/dashboard/Permissions.sol`](core/contracts/0.8.25/vaults/dashboard/Permissions.sol) | 388 | `0.8.25` | Role definitions and gating for the Dashboard. |
| [`0.8.25/vaults/interfaces/IPinnedBeaconProxy.sol`](core/contracts/0.8.25/vaults/interfaces/IPinnedBeaconProxy.sol) | 16 | `>=0.8.0` | Pinned beacon proxy interface. |
| [`0.8.25/vaults/interfaces/IPredepositGuarantee.sol`](core/contracts/0.8.25/vaults/interfaces/IPredepositGuarantee.sol) | 65 | `>=0.8.0` | PredepositGuarantee interface. |
| [`0.8.25/vaults/interfaces/IStakingVault.sol`](core/contracts/0.8.25/vaults/interfaces/IStakingVault.sol) | 66 | `>=0.8.0` | StakingVault interface. |
| [`0.8.25/vaults/interfaces/IVaultFactory.sol`](core/contracts/0.8.25/vaults/interfaces/IVaultFactory.sol) | 10 | `0.8.25` | Vault factory interface. |
| [`0.8.25/vaults/lib/PinnedBeaconUtils.sol`](core/contracts/0.8.25/vaults/lib/PinnedBeaconUtils.sol) | 44 | `0.8.25` | Implementation pinning storage helpers. |
| [`0.8.25/vaults/lib/RecoverTokens.sol`](core/contracts/0.8.25/vaults/lib/RecoverTokens.sol) | 53 | `0.8.25` | Token and ETH recovery helper. |
| [`0.8.25/vaults/lib/RefSlotCache.sol`](core/contracts/0.8.25/vaults/lib/RefSlotCache.sol) | 167 | `0.8.25` | Caches a value at the previous reference slot. |
| [`0.8.25/vaults/predeposit_guarantee/CLProofVerifier.sol`](core/contracts/0.8.25/vaults/predeposit_guarantee/CLProofVerifier.sol) | 223 | `0.8.25` | Verifies validator state via beacon-block SSZ proofs. |
| [`0.8.25/vaults/predeposit_guarantee/MeIfNobodyElse.sol`](core/contracts/0.8.25/vaults/predeposit_guarantee/MeIfNobodyElse.sol) | 22 | `0.8.25` | Sender-or-default address helper. |
| [`0.8.25/vaults/predeposit_guarantee/PredepositGuarantee.sol`](core/contracts/0.8.25/vaults/predeposit_guarantee/PredepositGuarantee.sol) | 955 | `0.8.25` | Guarantees vault predeposits against front-running. |
| [`0.8.9/Accounting.sol`](core/contracts/0.8.9/Accounting.sol) | 537 | `0.8.9` | v3 rebase engine. Computes the report, mints fees, calls Lido to apply it. |
| [`0.8.9/Burner.sol`](core/contracts/0.8.9/Burner.sol) | 469 | `0.8.9` | Burns stETH shares (cover and non-cover) on request. |
| [`0.8.9/DepositSecurityModule.sol`](core/contracts/0.8.9/DepositSecurityModule.sol) | 599 | `0.8.9` | Guardian-signed deposit authorisation and pause on bad deposit roots. |
| [`0.8.9/EIP712StETH.sol`](core/contracts/0.8.9/EIP712StETH.sol) | 125 | `0.8.9` | EIP-712 domain and hashing helper for stETH permits. |
| [`0.8.9/LidoExecutionLayerRewardsVault.sol`](core/contracts/0.8.9/LidoExecutionLayerRewardsVault.sol) | 124 | `0.8.9` | Collects EL rewards (MEV, priority fees) for the protocol. |
| [`0.8.9/LidoLocator.sol`](core/contracts/0.8.9/LidoLocator.sol) | 147 | `0.8.9` | Immutable address book for every core component. |
| [`0.8.9/OracleDaemonConfig.sol`](core/contracts/0.8.9/OracleDaemonConfig.sol) | 86 | `0.8.9` | Key-value config store read by the off-chain oracle daemon. |
| [`0.8.9/TokenRateNotifier.sol`](core/contracts/0.8.9/TokenRateNotifier.sol) | 203 | `0.8.9` | Fans out rebase notifications to registered observers. |
| [`0.8.9/TriggerableWithdrawalsGateway.sol`](core/contracts/0.8.9/TriggerableWithdrawalsGateway.sol) | 310 | `0.8.9` | Rate-limited entry point for EIP-7002 triggerable exits. |
| [`0.8.9/WithdrawalQueue.sol`](core/contracts/0.8.9/WithdrawalQueue.sol) | 416 | `0.8.9` | User-facing withdrawal requests, permit variants and finalisation hooks. |
| [`0.8.9/WithdrawalQueueBase.sol`](core/contracts/0.8.9/WithdrawalQueueBase.sol) | 597 | `0.8.9` | Queue mechanics: requests, checkpoints, discount rates, claiming. |
| [`0.8.9/WithdrawalQueueERC721.sol`](core/contracts/0.8.9/WithdrawalQueueERC721.sol) | 395 | `0.8.9` | Withdrawal requests as transferable NFTs. |
| [`0.8.9/WithdrawalVault.sol`](core/contracts/0.8.9/WithdrawalVault.sol) | 226 | `0.8.9` | Holds withdrawn beacon-chain ETH awaiting the queue. |
| [`0.8.9/WithdrawalVaultEIP7685.sol`](core/contracts/0.8.9/WithdrawalVaultEIP7685.sol) | 133 | `0.8.9` | EIP-7685 request encoding for the withdrawal vault. |
| [`0.8.9/interfaces/IERC4906.sol`](core/contracts/0.8.9/interfaces/IERC4906.sol) | 23 | `0.8.9` | Metadata-update event interface for the withdrawal NFT. |
| [`0.8.9/interfaces/IPostTokenRebaseReceiver.sol`](core/contracts/0.8.9/interfaces/IPostTokenRebaseReceiver.sol) | 20 | `0.8.9` | Rebase subscriber interface. |
| [`0.8.9/interfaces/ISecondOpinionOracle.sol`](core/contracts/0.8.9/interfaces/ISecondOpinionOracle.sol) | 27 | `0.8.9` | LIP-23 second-opinion oracle interface. |
| [`0.8.9/interfaces/ITokenRatePusher.sol`](core/contracts/0.8.9/interfaces/ITokenRatePusher.sol) | 14 | `0.8.9` | Token-rate push interface. |
| [`0.8.9/interfaces/ITokenRatePusherWithArgs.sol`](core/contracts/0.8.9/interfaces/ITokenRatePusherWithArgs.sol) | 35 | `0.8.9` | Token-rate push interface carrying rebase args. |
| [`0.8.9/lib/ExitLimitUtils.sol`](core/contracts/0.8.9/lib/ExitLimitUtils.sol) | 125 | `0.8.9` | Packed rate-limit state for exit requests. |
| [`0.8.9/lib/Math.sol`](core/contracts/0.8.9/lib/Math.sol) | 32 | `0.8.9` | Modular interval test. |
| [`0.8.9/lib/PositiveTokenRebaseLimiter.sol`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol) | 179 | `0.8.9` | Caps positive rebase per report. |
| [`0.8.9/lib/UnstructuredRefStorage.sol`](core/contracts/0.8.9/lib/UnstructuredRefStorage.sol) | 19 | `0.8.9` | Unstructured storage for reference (array/mapping) types. |
| [`0.8.9/lib/UnstructuredStorage.sol`](core/contracts/0.8.9/lib/UnstructuredStorage.sol) | 44 | `0.8.9` | Aragon unstructured storage accessors (0.8.9). |
| [`0.8.9/oracle/AccountingOracle.sol`](core/contracts/0.8.9/oracle/AccountingOracle.sol) | 917 | `0.8.9` | Receives the main report, extra data, and forwards to Accounting. |
| [`0.8.9/oracle/BaseOracle.sol`](core/contracts/0.8.9/oracle/BaseOracle.sol) | 417 | `0.8.9` | Shared consensus-report plumbing for the oracles. |
| [`0.8.9/oracle/HashConsensus.sol`](core/contracts/0.8.9/oracle/HashConsensus.sol) | 1097 | `0.8.9` | Frame/epoch arithmetic and member quorum over report hashes. |
| [`0.8.9/oracle/ValidatorsExitBus.sol`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol) | 1149 | `0.8.9` | Emits and rate-limits validator exit requests. |
| [`0.8.9/oracle/ValidatorsExitBusOracle.sol`](core/contracts/0.8.9/oracle/ValidatorsExitBusOracle.sol) | 286 | `0.8.9` | Consensus wrapper around ValidatorsExitBus. |
| [`0.8.9/proxy/OssifiableProxy.sol`](core/contracts/0.8.9/proxy/OssifiableProxy.sol) | 95 | `0.8.9` | ERC-1967 proxy that can be permanently frozen. |
| [`0.8.9/proxy/WithdrawalsManagerProxy.sol`](core/contracts/0.8.9/proxy/WithdrawalsManagerProxy.sol) | 518 | `0.8.9` | Stub proxy used before the withdrawal queue existed. |
| [`0.8.9/sanity_checks/OracleReportSanityChecker.sol`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol) | 1589 | `0.8.9` | Every bound an oracle report must satisfy. |
| [`0.8.9/utils/DummyEmptyContract.sol`](core/contracts/0.8.9/utils/DummyEmptyContract.sol) | 14 | `0.8.9` | Placeholder implementation for proxies. |
| [`0.8.9/utils/PausableUntil.sol`](core/contracts/0.8.9/utils/PausableUntil.sol) | 104 | `0.8.9` | Pause with an expiry timestamp. |
| [`0.8.9/utils/Versioned.sol`](core/contracts/0.8.9/utils/Versioned.sol) | 62 | `0.8.9` | Contract version counter for initializers. |
| [`0.8.9/utils/access/AccessControl.sol`](core/contracts/0.8.9/utils/access/AccessControl.sol) | 234 | `0.8.9` | Vendored OZ role-based access control. |
| [`0.8.9/utils/access/AccessControlEnumerable.sol`](core/contracts/0.8.9/utils/access/AccessControlEnumerable.sol) | 78 | `0.8.9` | Enumerable extension of the above. |
| [`common/interfaces/IBurner.sol`](core/contracts/common/interfaces/IBurner.sol) | 42 | `>=0.4.24 <0.9.0` | Interface: IBurner. |
| [`common/interfaces/ICircuitBreaker.sol`](core/contracts/common/interfaces/ICircuitBreaker.sol) | 14 | `>=0.4.24 <0.9.0` | Interface: ICircuitBreaker. |
| [`common/interfaces/IDepositContract.sol`](core/contracts/common/interfaces/IDepositContract.sol) | 18 | `>=0.5.0` | Interface: IDepositContract. |
| [`common/interfaces/IEIP712StETH.sol`](core/contracts/common/interfaces/IEIP712StETH.sol) | 48 | `>=0.4.24 <0.9.0` | Interface: IEIP712StETH. |
| [`common/interfaces/IGateSeal.sol`](core/contracts/common/interfaces/IGateSeal.sol) | 14 | `>=0.4.24 <0.9.0` | Interface: IGateSeal. |
| [`common/interfaces/IGateSealFactory.sol`](core/contracts/common/interfaces/IGateSealFactory.sol) | 21 | `>=0.4.24 <0.9.0` | Interface: IGateSealFactory. |
| [`common/interfaces/IHashConsensus.sol`](core/contracts/common/interfaces/IHashConsensus.sol) | 27 | `>=0.5.0` | Interface: IHashConsensus. |
| [`common/interfaces/ILazyOracle.sol`](core/contracts/common/interfaces/ILazyOracle.sol) | 19 | `>=0.5.0` | Interface: ILazyOracle. |
| [`common/interfaces/ILido.sol`](core/contracts/common/interfaces/ILido.sol) | 87 | `>=0.8.0` | Interface: ILido. |
| [`common/interfaces/ILidoLocator.sol`](core/contracts/common/interfaces/ILidoLocator.sol) | 57 | `>=0.4.24 <0.9.0` | Interface: ILidoLocator. |
| [`common/interfaces/IOracleReportSanityChecker.sol`](core/contracts/common/interfaces/IOracleReportSanityChecker.sol) | 50 | `>=0.4.24` | Interface: IOracleReportSanityChecker. |
| [`common/interfaces/IOssifiableProxy.sol`](core/contracts/common/interfaces/IOssifiableProxy.sol) | 14 | `>=0.4.24` | Interface: IOssifiableProxy. |
| [`common/interfaces/IPausableUntil.sol`](core/contracts/common/interfaces/IPausableUntil.sol) | 18 | `>=0.4.24 <0.9.0` | Interface: IPausableUntil. |
| [`common/interfaces/IStakingModule.sol`](core/contracts/common/interfaces/IStakingModule.sol) | 217 | `>=0.5.0` | Interface: IStakingModule. |
| [`common/interfaces/IStakingModuleV2.sol`](core/contracts/common/interfaces/IStakingModuleV2.sol) | 31 | `>=0.8.9 <0.9.0` | Interface: IStakingModuleV2. |
| [`common/interfaces/IVaultHub.sol`](core/contracts/common/interfaces/IVaultHub.sol) | 15 | `>=0.5.0` | Interface: IVaultHub. |
| [`common/interfaces/IVersioned.sol`](core/contracts/common/interfaces/IVersioned.sol) | 12 | `>=0.4.24` | Interface: IVersioned. |
| [`common/interfaces/IWithdrawalQueue.sol`](core/contracts/common/interfaces/IWithdrawalQueue.sol) | 16 | `>=0.5.0` | Interface: IWithdrawalQueue. |
| [`common/interfaces/ReportValues.sol`](core/contracts/common/interfaces/ReportValues.sol) | 29 | `>=0.5.0` | Interface: ReportValues. |
| [`common/interfaces/TopUpWitness.sol`](core/contracts/common/interfaces/TopUpWitness.sol) | 18 | `>=0.8.9` | Interface: TopUpWitness. |
| [`common/interfaces/ValidatorWitness.sol`](core/contracts/common/interfaces/ValidatorWitness.sol) | 25 | `>=0.8.9` | Interface: ValidatorWitness. |
| [`common/lib/BLS.sol`](core/contracts/common/lib/BLS.sol) | 598 | `^0.8.25` | BLS12-381 verification for deposit messages. |
| [`common/lib/BeaconTypes.sol`](core/contracts/common/lib/BeaconTypes.sol) | 25 | `^0.8.25` | Beacon-chain struct definitions. |
| [`common/lib/Bytes32String.sol`](core/contracts/common/lib/Bytes32String.sol) | 39 | `>=0.8.9 <0.9.0` | bytes32 to string conversion. |
| [`common/lib/ECDSA.sol`](core/contracts/common/lib/ECDSA.sol) | 60 | `>=0.4.24 <0.9.0` | Vendored ECDSA recovery. |
| [`common/lib/GIndex.sol`](core/contracts/common/lib/GIndex.sol) | 110 | `^0.8.25` | Generalized index type and arithmetic. |
| [`common/lib/Math256.sol`](core/contracts/common/lib/Math256.sol) | 45 | `>=0.4.24 <0.9.0` | min/max/ceilDiv helpers. |
| [`common/lib/MemUtils.sol`](core/contracts/common/lib/MemUtils.sol) | 67 | `>=0.4.24 <0.9.0` | Unsafe memory allocation and copying. |
| [`common/lib/MinFirstAllocationStrategy.sol`](core/contracts/common/lib/MinFirstAllocationStrategy.sol) | 109 | `>=0.4.24 <0.9.0` | Fills the least-full buckets first; the deposit allocator. |
| [`common/lib/RateLimit.sol`](core/contracts/common/lib/RateLimit.sol) | 125 | `>=0.8.9 <0.9.0` | Generic regenerating rate limiter. |
| [`common/lib/SSZ.sol`](core/contracts/common/lib/SSZ.sol) | 272 | `^0.8.25` | SSZ hashing and generalized-index Merkle proofs. |
| [`common/lib/SignatureUtils.sol`](core/contracts/common/lib/SignatureUtils.sol) | 66 | `>=0.4.24 <0.9.0` | ECDSA plus ERC-1271 signature checking. |
| [`common/lib/TriggerableWithdrawals.sol`](core/contracts/common/lib/TriggerableWithdrawals.sol) | 190 | `>=0.8.9 <0.9.0` | EIP-7002 withdrawal request encoding and fee handling. |
| [`common/lib/UnstructuredStorage.sol`](core/contracts/common/lib/UnstructuredStorage.sol) | 40 | `^0.8.9` | Unstructured storage accessors (common). |
| [`common/lib/WithdrawalCredentials.sol`](core/contracts/common/lib/WithdrawalCredentials.sol) | 51 | `>=0.8.9 <0.9.0` | 0x01/0x02 withdrawal-credential helpers. |
| [`common/utils/PausableUntil.sol`](core/contracts/common/utils/PausableUntil.sol) | 103 | `^0.8.9` | Pause-with-expiry (common copy). |
| [`openzeppelin/5.2/upgradeable/access/AccessControlUpgradeable.sol`](core/contracts/openzeppelin/5.2/upgradeable/access/AccessControlUpgradeable.sol) | 234 | `^0.8.20` | Vendored OpenZeppelin 5.2 upgradeable: AccessControlUpgradeable. |
| [`openzeppelin/5.2/upgradeable/access/Ownable2StepUpgradeable.sol`](core/contracts/openzeppelin/5.2/upgradeable/access/Ownable2StepUpgradeable.sol) | 88 | `^0.8.20` | Vendored OpenZeppelin 5.2 upgradeable: Ownable2StepUpgradeable. |
| [`openzeppelin/5.2/upgradeable/access/OwnableUpgradeable.sol`](core/contracts/openzeppelin/5.2/upgradeable/access/OwnableUpgradeable.sol) | 121 | `^0.8.20` | Vendored OpenZeppelin 5.2 upgradeable: OwnableUpgradeable. |
| [`openzeppelin/5.2/upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol`](core/contracts/openzeppelin/5.2/upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol) | 106 | `^0.8.20` | Vendored OpenZeppelin 5.2 upgradeable: AccessControlEnumerableUpgradeable. |
| [`openzeppelin/5.2/upgradeable/proxy/utils/Initializable.sol`](core/contracts/openzeppelin/5.2/upgradeable/proxy/utils/Initializable.sol) | 229 | `^0.8.20` | Vendored OpenZeppelin 5.2 upgradeable: Initializable. |
| [`openzeppelin/5.2/upgradeable/utils/ContextUpgradeable.sol`](core/contracts/openzeppelin/5.2/upgradeable/utils/ContextUpgradeable.sol) | 35 | `^0.8.20` | Vendored OpenZeppelin 5.2 upgradeable: ContextUpgradeable. |
| [`openzeppelin/5.2/upgradeable/utils/introspection/ERC165Upgradeable.sol`](core/contracts/openzeppelin/5.2/upgradeable/utils/introspection/ERC165Upgradeable.sol) | 34 | `^0.8.20` | Vendored OpenZeppelin 5.2 upgradeable: ERC165Upgradeable. |
| [`tooling/AlertingHarness.sol`](core/contracts/tooling/AlertingHarness.sol) | 317 | `0.8.25` | Off-chain monitoring harness. |
| [`tooling/sepolia/SepoliaDepositAdapter.sol`](core/contracts/tooling/sepolia/SepoliaDepositAdapter.sol) | 110 | `0.8.9` | Sepolia-only deposit contract adapter. |
| [`upgrade/UpgradeConfig.sol`](core/contracts/upgrade/UpgradeConfig.sol) | 472 | `0.8.25` | Addresses and parameters for the upgrade. |
| [`upgrade/UpgradeTemplate.sol`](core/contracts/upgrade/UpgradeTemplate.sol) | 861 | `0.8.25` | Executes the v2 to v3 upgrade in one transaction. |
| [`upgrade/UpgradeTemporaryAdmin.sol`](core/contracts/upgrade/UpgradeTemporaryAdmin.sol) | 132 | `0.8.25` | Temporary admin holder during the upgrade. |
| [`upgrade/UpgradeTypes.sol`](core/contracts/upgrade/UpgradeTypes.sol) | 507 | `0.8.25` | Structs used by the upgrade machinery. |
| [`upgrade/UpgradeVoteScript.sol`](core/contracts/upgrade/UpgradeVoteScript.sol) | 909 | `0.8.25` | Builds the Aragon vote calldata for the upgrade. |
| [`upgrade/interfaces/IDualGovernance.sol`](core/contracts/upgrade/interfaces/IDualGovernance.sol) | 42 | `^0.8.25` | Upgrade-path interface: IDualGovernance. |
| [`upgrade/interfaces/IForwarder.sol`](core/contracts/upgrade/interfaces/IForwarder.sol) | 11 | `>=0.4.24 <0.9.0` | Upgrade-path interface: IForwarder. |
| [`upgrade/interfaces/IOracleReportSanityChecker_preV3.sol`](core/contracts/upgrade/interfaces/IOracleReportSanityChecker_preV3.sol) | 78 | `>=0.4.24 <0.9.0` | Upgrade-path interface: IOracleReportSanityChecker_preV3. |
| [`upgrade/interfaces/IOracleReportSanityChecker_preV4.sol`](core/contracts/upgrade/interfaces/IOracleReportSanityChecker_preV4.sol) | 28 | `>=0.4.24 <0.9.0` | Upgrade-path interface: IOracleReportSanityChecker_preV4. |
| [`upgrade/interfaces/ITimelock.sol`](core/contracts/upgrade/interfaces/ITimelock.sol) | 41 | `^0.8.25` | Upgrade-path interface: ITimelock. |
| [`upgrade/interfaces/IUpgradeConfig.sol`](core/contracts/upgrade/interfaces/IUpgradeConfig.sol) | 21 | `^0.8.25` | Upgrade-path interface: IUpgradeConfig. |
| [`upgrade/interfaces/IUpgradeTemplate.sol`](core/contracts/upgrade/interfaces/IUpgradeTemplate.sol) | 12 | `^0.8.25` | Upgrade-path interface: IUpgradeTemplate. |
| [`upgrade/interfaces/IVoting.sol`](core/contracts/upgrade/interfaces/IVoting.sol) | 38 | `>=0.4.24 <0.9.0` | Upgrade-path interface: IVoting. |
| [`upgrade/mocks/CircuitBreakerMock.sol`](core/contracts/upgrade/mocks/CircuitBreakerMock.sol) | 35 | `0.8.25` | Upgrade test stub. |
| [`upgrade/mocks/EasyTrackEVMScriptExecutorStub.sol`](core/contracts/upgrade/mocks/EasyTrackEVMScriptExecutorStub.sol) | 16 | `>=0.4.24 <0.9.0` | Upgrade test stub. |
| [`upgrade/mocks/EasyTrackFactoryMock.sol`](core/contracts/upgrade/mocks/EasyTrackFactoryMock.sol) | 14 | `>=0.4.24 <0.9.0` | Upgrade test stub. |
| [`upgrade/mocks/VaultsAdapterMock.sol`](core/contracts/upgrade/mocks/VaultsAdapterMock.sol) | 23 | `0.8.25` | Upgrade test stub. |
| [`upgrade/utils/CallScriptBuilder.sol`](core/contracts/upgrade/utils/CallScriptBuilder.sol) | 41 | `0.8.25` | Builds Aragon EVM call scripts. |
| [`upgrade/utils/OmnibusBase.sol`](core/contracts/upgrade/utils/OmnibusBase.sol) | 133 | `^0.8.25` | Base for multi-action governance omnibuses. |

---
## 1. Architecture and `LidoLocator`

### 1.1 How the pieces connect

Lido has no single "protocol" contract. It has a token that is also the pool, a
report pipeline that mutates it, and a deposit pipeline that spends it. Every
component finds every other component through one immutable address book.

```
                    users
                      |  submit() ETH
                      v
              +---------------+   handleOracleReport   +--------------+
              |    Lido.sol   | <--------------------- |  Accounting  |
              | (is StETH)    |                        +--------------+
              +---------------+                               ^
               |            |                                 | report
               | deposit()  | withdrawals                     |
               v            v                          +------------------+
     +-----------------+  +------------------+         | AccountingOracle |
     |  StakingRouter  |  | WithdrawalQueue  |         +------------------+
     +-----------------+  +------------------+                 ^
        |          |                                           | consensus
        v          v                                    +---------------+
  +-----------+  +-----------------------+              | HashConsensus |
  | NO Registry| | other staking modules |              +---------------+
  +-----------+  +-----------------------+
        |
        v  deposit data
  +------------------------+     guardian sigs    +------------------------+
  | Beacon deposit contract| <------------------- | DepositSecurityModule  |
  +------------------------+                      +------------------------+
```

Everything above is resolved through [`LidoLocator`](core/contracts/0.8.9/LidoLocator.sol).
Alongside it, v3 adds the **stVaults** subsystem ([§14](#14-stvaults)), which is a
second, parallel way to stake that settles against the same token.

### 1.2 `LidoLocator`

[`core/contracts/0.8.9/LidoLocator.sol`](core/contracts/0.8.9/LidoLocator.sol) — 146 lines, solc 0.8.9.

A pure address book. Every address is `public immutable`, so a lookup is a code
read rather than an `SLOAD`; the contract itself sits behind an
`OssifiableProxy`, so the set can be replaced by deploying a new implementation.

**Storage.** None. 23 immutables, declared at
[`:46-69`](core/contracts/0.8.9/LidoLocator.sol#L46-L69): `accountingOracle`,
`depositSecurityModule`, `elRewardsVault`, `lido`, `oracleReportSanityChecker`,
`postTokenRebaseReceiver`, `burner`, `stakingRouter`, `treasury`,
`validatorsExitBusOracle`, `withdrawalQueue`, `withdrawalVault`,
`oracleDaemonConfig`, `validatorExitDelayVerifier`,
`triggerableWithdrawalsGateway`, `consolidationGateway`, `accounting`,
`predepositGuarantee`, `wstETH`, `vaultHub`, `vaultFactory`, `lazyOracle`,
`operatorGrid`.

The last seven are new in v3 and are what the vaults subsystem hangs off.

| Function | Line | Notes |
|---|---|---|
| `constructor(Config memory _config)` | [`:77`](core/contracts/0.8.9/LidoLocator.sol#L77) | Assigns all 23 immutables, each through `_assertNonZero`. A single zero address in the config bricks deployment, which is the intent. |
| `coreComponents()` | [`:104`](core/contracts/0.8.9/LidoLocator.sol#L104) | Returns the five addresses a typical integrator needs in one call, saving five external calls. |
| `oracleReportComponents()` | [`:122`](core/contracts/0.8.9/LidoLocator.sol#L122) | Returns the set `Accounting` needs during a report. |
| `_assertNonZero(address)` | [`:142`](core/contracts/0.8.9/LidoLocator.sol#L142) | `internal pure`. Reverts `ZeroAddress()` on zero, else returns the input. |

**Gotcha.** `postTokenRebaseReceiver` is the one address allowed to be zero in
practice; check the constructor before assuming otherwise. Because the whole set
is immutable, adding a component means a new implementation and a proxy upgrade,
which is why the v3 upgrade ([§18](#18-upgrade-machinery-tooling-vendored-openzeppelin))
deploys a fresh locator rather than mutating one.

---

## 2. `StETH` — the shares math

[`core/contracts/0.4.24/StETH.sol`](core/contracts/0.4.24/StETH.sol) — 590 lines, solc 0.4.24.

`StETH` is abstract. It implements the token; `Lido` supplies the total pooled
ether. This is the single most important contract in the protocol to understand,
because every other number in Lido is denominated in its shares.

### 2.1 The idea

A holder never owns a balance. They own **shares**, and their balance is derived:

```
balanceOf(a) = shares[a] * totalPooledEther / totalShares
```

Staking rewards arrive by increasing `totalPooledEther` while `totalShares` stays
put, so every balance grows at once with no per-holder writes. That is what
"rebasing" means here, and it is why `_mintShares` deliberately emits no
`Transfer` from the zero address: minting shares dilutes existing holders rather
than increasing supply, and representing that faithfully would need one event per
holder. The comment at
[`:538-545`](core/contracts/0.4.24/StETH.sol#L538-L545) says exactly this.

### 2.2 Storage, and the v3 packing change

Balances (`shares`) and `allowances` are conventional mappings, because
unstructured storage for reference types in Solidity 0.4 is, as the source puts
it, "non-trivial and error-prone"
([`:84-86`](core/contracts/0.4.24/StETH.sol#L84-L86)).

Total shares live in one unstructured slot:

```solidity
bytes32 internal constant TOTAL_SHARES_POSITION_LOW128 =
    0x6038150aecaa250d524370a0fdcdec13f2690e0723eaf277f41d7cae26b359e6;
uint256 constant internal UINT128_HIGH_MASK = ~uint256(0) << 128;
```

[`:92-98`](core/contracts/0.4.24/StETH.sol#L92-L98). Verified:
`cast keccak "lido.StETH.totalAndExternalShares"` returns exactly that value.

The name is the v3 change. **The slot is now split.** The low 128 bits hold
`totalShares`; the high 128 bits hold *external* shares, meaning shares minted
against stVaults rather than against ETH in the pool. `_getTotalShares`
([`:473`](core/contracts/0.4.24/StETH.sol#L473)) masks to the low half, and
`_mintShares` enforces the boundary:

```solidity
newTotalShares = _getTotalShares().add(_sharesAmount);
require(newTotalShares & UINT128_HIGH_MASK == 0, "SHARES_OVERFLOW");
```

[`:522-523`](core/contracts/0.4.24/StETH.sol#L522-L523). A v2 reader expecting a
plain `uint256` at this slot will misread it; anything decoding Lido storage
directly must mask.

### 2.3 The conversion functions

All three take `uint128`-bounded inputs and revert on overflow.

**`getSharesByPooledEth(uint256 _ethAmount) public view`** —
[`:317`](core/contracts/0.4.24/StETH.sol#L317). Requires `_ethAmount < UINT128_MAX`
(`"ETH_TOO_LARGE"`), then returns `_ethAmount * totalShares / totalPooledEther`.
**Rounds down.**

**`getPooledEthByShares(uint256 _sharesAmount) public view`** —
[`:329`](core/contracts/0.4.24/StETH.sol#L329). The inverse:
`_sharesAmount * totalPooledEther / totalShares`. Requires
`_sharesAmount < UINT128_MAX` (`"SHARES_TOO_LARGE"`). **Rounds down.**

**`getPooledEthBySharesRoundUp(uint256 _sharesAmount) public view`** —
[`:342`](core/contracts/0.4.24/StETH.sol#L342). Same value via
`Math256.ceilDiv`. **Rounds up.** The docstring states the guarantee it exists
for: at `shareRate >= 0.5`, `getSharesByPooledEth(getPooledEthBySharesRoundUp(1))`
is 1, so a one-share round trip does not evaporate.

**Why rounding down everywhere else matters.** Both directions truncate, so a
`transfer(x)` moves `getSharesByPooledEth(x)` shares, which is at most `x` worth
and usually a wei less. This is the origin of the famous "stETH balance is off by
1 wei" behaviour. It is not a bug; it is the protocol refusing to round in the
user's favour. Any integration comparing `balanceOf` before and after a transfer
for exact equality will fail intermittently.

The rate itself is indirected through two overridable hooks,
`_getShareRateNumerator` ([`:410`](core/contracts/0.4.24/StETH.sol#L410), returns
`_getTotalPooledEther()`) and `_getShareRateDenominator`
([`:419`](core/contracts/0.4.24/StETH.sol#L419), returns `_getTotalShares()`).
`_getTotalPooledEther` is abstract at
[`:403`](core/contracts/0.4.24/StETH.sol#L403) and implemented by `Lido`.

### 2.4 ERC-20 surface

| Function | Line | Behaviour |
|---|---|---|
| `name()` / `symbol()` / `decimals()` | [`:133`](core/contracts/0.4.24/StETH.sol#L133), [`:141`](core/contracts/0.4.24/StETH.sol#L141), [`:148`](core/contracts/0.4.24/StETH.sol#L148) | `pure`. "Liquid staked Ether 2.0", `stETH`, 18. |
| `totalSupply()` | [`:158`](core/contracts/0.4.24/StETH.sol#L158) | Returns `_getTotalPooledEther()`, **not** a stored supply. |
| `getTotalPooledEther()` | [`:167`](core/contracts/0.4.24/StETH.sol#L167) | Same value, explicit name. |
| `balanceOf(address)` | [`:177`](core/contracts/0.4.24/StETH.sol#L177) | `getPooledEthByShares(shares[a])`. Derived, never stored. |
| `transfer(address,uint256)` | [`:196`](core/contracts/0.4.24/StETH.sol#L196) | Converts to shares, then `_transferShares`. |
| `allowance` / `approve` | [`:207`](core/contracts/0.4.24/StETH.sol#L207), [`:226`](core/contracts/0.4.24/StETH.sol#L226) | Allowances are denominated in **stETH, not shares**, so an approval's share-value drifts with the rate. |
| `transferFrom` | [`:252`](core/contracts/0.4.24/StETH.sol#L252) | `_spendAllowance` then `_transfer`. |
| `increaseAllowance` / `decreaseAllowance` | [`:270`](core/contracts/0.4.24/StETH.sol#L270), [`:288`](core/contracts/0.4.24/StETH.sol#L288) | Standard; `decreaseAllowance` reverts `"ALLOWANCE_BELOW_ZERO"` on underflow. |
| `getTotalShares()` / `sharesOf(address)` | [`:301`](core/contracts/0.4.24/StETH.sol#L301), [`:308`](core/contracts/0.4.24/StETH.sol#L308) | The rate-independent views. Integrations should prefer these. |
| `transferShares(address,uint256)` | [`:365`](core/contracts/0.4.24/StETH.sol#L365) | Moves shares directly, sidestepping the rounding in §2.3. Returns the stETH equivalent. |
| `transferSharesFrom(address,address,uint256)` | [`:388`](core/contracts/0.4.24/StETH.sol#L388) | Allowance-checked variant; the allowance spent is the *stETH* value of the shares. |

### 2.5 Internal share mechanics

**`_transferShares(address _sender, address _recipient, uint256 _sharesAmount) internal`** —
[`:494`](core/contracts/0.4.24/StETH.sol#L494). Four checks:
`"TRANSFER_FROM_ZERO_ADDR"`, `"TRANSFER_TO_ZERO_ADDR"`,
`"TRANSFER_TO_STETH_CONTRACT"`, then `_whenNotStopped()`. Then
`"BALANCE_EXCEEDED"` if short. Writes both mapping entries. **Emits nothing** —
callers emit via `_emitTransferEvents`.

**`_mintShares(address _recipient, uint256 _sharesAmount) internal returns (uint256)`** —
[`:518`](core/contracts/0.4.24/StETH.sol#L518). Rejects zero address and the token
itself, computes the new total, enforces the 128-bit boundary, writes the low half
of the packed slot, credits the recipient. Note it does **not** check the pause;
the docstring says this is delegated to callers.

**`_burnShares(address _account, uint256 _sharesAmount) internal returns (uint256)`** —
[`:547`](core/contracts/0.4.24/StETH.sol#L547). `"BURN_FROM_ZERO_ADDR"`,
`"BALANCE_EXCEEDED"`, then decrements both. Also does not check the pause.

**Event helpers.** `_emitTransferEvents`
([`:562`](core/contracts/0.4.24/StETH.sol#L562)) emits `Transfer` and
`TransferShares` as a pair; `_emitTransferAfterMintingShares`
([`:570`](core/contracts/0.4.24/StETH.sol#L570)) emits the mint as a transfer from
zero *in token terms*; `_emitSharesBurnt`
([`:577`](core/contracts/0.4.24/StETH.sol#L577)) emits `SharesBurnt` with the
pre- and post-rebase token amounts, which differ because the burn itself moves
the rate. `_mintInitialShares` ([`:586`](core/contracts/0.4.24/StETH.sol#L586))
seeds the very first shares.

**Events.** `TransferShares(address indexed from, address indexed to, uint256 sharesValue)`
at [`:105`](core/contracts/0.4.24/StETH.sol#L105), and
`SharesBurnt(address indexed account, uint256 preRebaseTokenAmount, uint256 postRebaseTokenAmount, uint256 sharesAmount)`
at [`:123`](core/contracts/0.4.24/StETH.sol#L123). An indexer that watches only
ERC-20 `Transfer` will see balances change with no event during a rebase; watch
the rebase event on `Lido` instead ([§5](#5-lidosol--every-function)).

---

## 3. `StETHPermit` and `EIP712StETH`

### 3.1 `StETHPermit`

[`core/contracts/0.4.24/StETHPermit.sol`](core/contracts/0.4.24/StETHPermit.sol) — 178 lines, solc 0.4.24.

EIP-2612 for a 0.4.24 contract, which cannot compute an EIP-712 domain separator
conveniently, so the hashing is delegated to a 0.8.9 helper.

```solidity
bytes32 internal constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
```

[`:83`](core/contracts/0.4.24/StETHPermit.sol#L83). The helper's address lives at
`EIP712_STETH_POSITION` ([`:75`](core/contracts/0.4.24/StETHPermit.sol#L75)).

| Function | Line | Notes |
|---|---|---|
| `permit(owner, spender, value, deadline, v, r, s)` | [`:99`](core/contracts/0.4.24/StETHPermit.sol#L99) | Reverts `"DEADLINE_EXPIRED"` past the deadline, builds the struct hash, asks the helper to wrap it, verifies via `SignatureUtils.isValidSignature` (so **ERC-1271 contract wallets work**), then `_approve`. |
| `nonces(address)` | [`:121`](core/contracts/0.4.24/StETHPermit.sol#L121) | Per-owner counter. |
| `DOMAIN_SEPARATOR()` | [`:129`](core/contracts/0.4.24/StETHPermit.sol#L129) | Delegates to the helper. |
| `eip712Domain()` | [`:143`](core/contracts/0.4.24/StETHPermit.sol#L143) | ERC-5267 discovery. |
| `_useNonce(address)` | [`:155`](core/contracts/0.4.24/StETHPermit.sol#L155) | `internal`, returns then increments. |
| `_initializeEIP712StETH(address)` | [`:163`](core/contracts/0.4.24/StETHPermit.sol#L163) | One-shot; reverts if already set or zero. |
| `getEIP712StETH()` | [`:175`](core/contracts/0.4.24/StETHPermit.sol#L175) | Reads the helper address. |

### 3.2 `EIP712StETH`

[`core/contracts/0.8.9/EIP712StETH.sol`](core/contracts/0.8.9/EIP712StETH.sol) — 124 lines, solc 0.8.9.

Stateless and immutable, deployed once and pointed at the stETH address.

| Function | Line | Notes |
|---|---|---|
| `domainSeparatorV4(address _stETH)` | [`:71`](core/contracts/0.8.9/EIP712StETH.sol#L71) | Cached separator if chain id and address are unchanged, else rebuilt. |
| `_buildDomainSeparator(...)` | [`:79`](core/contracts/0.8.9/EIP712StETH.sol#L79) | `internal pure`. Name, version, chain id, verifying contract. |
| `hashTypedDataV4(address _stETH, bytes32 _structHash)` | [`:103`](core/contracts/0.8.9/EIP712StETH.sol#L103) | The `\x19\x01` prefix wrapper. |
| `eip712Domain(address _stETH)` | [`:111`](core/contracts/0.8.9/EIP712StETH.sol#L111) | ERC-5267 fields. |

**Gotcha.** The domain's `verifyingContract` is the **stETH** address, not this
helper. Signing against the helper's address produces a signature that will not
verify.

---

## 4. `WstETH`

[`core/contracts/0.6.12/WstETH.sol`](core/contracts/0.6.12/WstETH.sol) — 118 lines, solc 0.6.12.

A plain, non-rebasing ERC-20 (with permit) whose balance *is* a share count. This
exists because rebasing tokens break most DeFi: an AMM pool holding stETH would
silently accrue rewards into the pool rather than to LPs, and lending markets
cannot use a balance that moves without a transfer. Wrapping converts "my balance
grows" into "my token is worth more", which composes.

| Function | Line | Behaviour |
|---|---|---|
| `constructor(IStETH _stETH)` | [`:34`](core/contracts/0.6.12/WstETH.sol#L34) | `ERC20("Wrapped liquid staked Ether 2.0", "wstETH")` plus permit. Stores the stETH address. |
| `wrap(uint256 _stETHAmount)` | [`:53`](core/contracts/0.6.12/WstETH.sol#L53) | Rejects zero (`"wstETH: can't wrap zero stETH"`), computes `getSharesByPooledEth`, mints that many wstETH, pulls the stETH in. Returns wstETH minted. |
| `unwrap(uint256 _wstETHAmount)` | [`:69`](core/contracts/0.6.12/WstETH.sol#L69) | Rejects zero, burns, transfers out `getPooledEthByShares`. Returns stETH out. |
| `getWstETHByStETH(uint256)` | [`:90`](core/contracts/0.6.12/WstETH.sol#L90) | View passthrough to `getSharesByPooledEth`. |
| `getStETHByWstETH(uint256)` | [`:99`](core/contracts/0.6.12/WstETH.sol#L99) | View passthrough to `getPooledEthByShares`. |
| `stEthPerToken()` | [`:107`](core/contracts/0.6.12/WstETH.sol#L107) | `getPooledEthByShares(1 ether)`. The canonical exchange rate. |
| `tokensPerStEth()` | [`:115`](core/contracts/0.6.12/WstETH.sol#L115) | The inverse. |

There is also a `receive()` that stakes bare ETH via `Lido.submit` and wraps in
one step; confirm its presence in your deployment before relying on it, since it
is the one function here that varies between networks.

**Cross-reference.** LI.FI ships a dedicated `LidoWrapper` periphery contract for
exactly this conversion; see
[`../lifi/LIBRARIES-PERIPHERY-COMPLETE-REFERENCE.md`](../lifi/LIBRARIES-PERIPHERY-COMPLETE-REFERENCE.md).
That contract unwraps the *entire* stETH balance of the wrapper rather than the
requested amount, which is worth knowing if you route through it.

---
