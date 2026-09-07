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
## 5. `Lido.sol` — every function

[`core/contracts/0.4.24/Lido.sol`](core/contracts/0.4.24/Lido.sol) — 1,572 lines, solc 0.4.24.

`Lido is StETHPermit is StETH is AragonApp`. It supplies the total pooled ether
that `StETH` divides by, holds the buffered ETH, and is the only contract that
may mint or burn shares.

### 5.1 Roles

All four are precomputed keccaks, declared at
[`:97-102`](core/contracts/0.4.24/Lido.sol#L97-L102). These are **Aragon ACL**
roles, checked through `_auth`, not OpenZeppelin roles.

| Role | Gates |
|---|---|
| `PAUSE_ROLE` | `stop()` |
| `RESUME_ROLE` | `resume()` |
| `STAKING_PAUSE_ROLE` | `pauseStaking()` |
| `STAKING_CONTROL_ROLE` | `resumeStaking()`, `setStakingLimit()`, `removeStakingLimit()` |
| `BUFFER_RESERVE_MANAGER_ROLE` | `setDepositsReserveTarget()` |

`_auth(bytes32)` at [`:1389`](core/contracts/0.4.24/Lido.sol#L1389) is the role
check; the overload `_auth(address)` at
[`:1394`](core/contracts/0.4.24/Lido.sol#L1394) is a plain caller check used for
the contract-to-contract entry points.

### 5.2 Storage, all packed, all verified

Nine unstructured slots. Every one of the eight below was confirmed with
`cast keccak` against its declared constant; all eight match.

| Slot name | Preimage | Layout |
|---|---|---|
| `TOTAL_AND_EXTERNAL_SHARES_POSITION` [`:113`](core/contracts/0.4.24/Lido.sol#L113) | `lido.StETH.totalAndExternalShares` | Aliased to `StETH`'s slot. Low 128 total shares, high 128 external shares. |
| `LOCATOR_AND_MAX_EXTERNAL_RATIO_POSITION` [`:120`](core/contracts/0.4.24/Lido.sol#L120) | `lido.Lido.lidoLocatorAndMaxExternalRatio` | 160-bit locator address plus the max external ratio in bp. |
| `BUFFERED_ETHER_AND_DEPOSITED_POST_REPORT_POSITION` [`:131`](core/contracts/0.4.24/Lido.sol#L131) | `lido.Lido.bufferedEtherAndDepositedPostReport` | Low 128 buffered ether, high 128 deposited since the report. |
| `DEPOSITED_NEXT_REPORT_AND_LAST_DEPOSIT_NONCE_POSITION` [`:137`](core/contracts/0.4.24/Lido.sol#L137) | `lido.Lido.depositedNextReportAndLastDepositNonce` | Accrues deposits for the *next* frame plus the frame's refSlot as a nonce. |
| `CL_VALIDATORS_BALANCE_AND_CL_PENDING_BALANCE_POSITION` [`:144`](core/contracts/0.4.24/Lido.sol#L144) | `lido.Lido.clValidatorsBalanceAndClPendingBalance` | Low 128 CL validators balance, high 128 CL pending balance. |
| `SEED_DEPOSITS_COUNT_POSITION` [`:149`](core/contracts/0.4.24/Lido.sol#L149) | `lido.Lido.seedDepositsCount` | Count of initial seed deposits. |
| `STAKING_STATE_POSITION` [`:154`](core/contracts/0.4.24/Lido.sol#L154) | `lido.Lido.stakeLimit` | Packed `StakeLimitState.Data`; see [§12.3](#123-stakelimitutils). |
| `TOTAL_EL_REWARDS_COLLECTED_POSITION` [`:159`](core/contracts/0.4.24/Lido.sol#L159) | `lido.Lido.totalELRewardsCollected` | Lifetime EL rewards. |
| `DEPOSITS_RESERVE_POSITION` [`:169`](core/contracts/0.4.24/Lido.sol#L169) | `lido.Lido.depositsReserve` | Buffered ether kept depositable despite withdrawal demand. |
| `DEPOSITS_RESERVE_TARGET_POSITION` [`:176`](core/contracts/0.4.24/Lido.sol#L176) | `lido.Lido.depositsReserveTarget` | Governance target the reserve is restored to each report. |

**The v3 accounting change.** v2 tracked `beaconValidators` and `beaconBalance`.
v3 replaced that with **balance-based** accounting: `clValidatorsBalance` plus
`clPendingBalance`, so in-flight deposits are represented directly rather than
inferred. `_migrateStorage_v3_to_v4`
([`:311`](core/contracts/0.4.24/Lido.sol#L311)) rewrites the old slots, and you
can see the previous constants named inline at
[`:314-317`](core/contracts/0.4.24/Lido.sol#L314-L317).

### 5.3 The share rate, and why it excludes vault shares

This is the most consequential piece of v3 and it is easy to miss.

```solidity
function _getShareRateNumerator() internal view returns (uint256) {
    return _getInternalEther();
}
function _getShareRateDenominator() internal view returns (uint256) {
    (uint256 totalShares, uint256 externalShares) = _getTotalAndExternalShares();
    uint256 internalShares = totalShares - externalShares;
    return internalShares;
}
```

[`:1298-1306`](core/contracts/0.4.24/Lido.sol#L1298-L1306). Both overrides
replace `StETH`'s defaults ([§2.3](#23-the-conversion-functions)).

The rate is **internal ether over internal shares**, not total over total. The
reason, given in the comment at
[`:1293-1297`](core/contracts/0.4.24/Lido.sol#L1293-L1297), is to avoid a second
rounding step: external ether is itself derived from the ratio, so dividing by
totals would apply the same division twice and lose precision. The two are
mathematically equal but not equal in integer arithmetic.

The supporting functions:

- **`_getInternalEther()`** [`:1271`](core/contracts/0.4.24/Lido.sol#L1271) —
  `bufferedEther + clValidatorsBalance + clPendingBalance + depositedPostReport`.
  The comment notes pending deposits are already inside `clPendingBalance`, so
  the v2 "transient ether" term is gone.
- **`_getExternalEther(uint256 _internalEther)`** [`:1281`](core/contracts/0.4.24/Lido.sol#L1281) —
  `externalShares * internalEther / internalShares`.
- **`_getTotalPooledEther()`** [`:1289`](core/contracts/0.4.24/Lido.sol#L1289) —
  the sum, and the implementation of `StETH`'s abstract hook.

`internalShares` can never be zero because of the "stone in the elevator", the
initial holder seeded by `_bootstrapInitialHolder`
([`:1459`](core/contracts/0.4.24/Lido.sol#L1459)). The comment at
[`:1305`](core/contracts/0.4.24/Lido.sol#L1305) says so explicitly. This is Lido's
answer to the first-depositor inflation attack, the same problem Morpho solves by
never reading `balanceOf` and Uniswap V2 solves by burning `MINIMUM_LIQUIDITY`.

### 5.4 The external-shares cap

**`_getMaxMintableExternalShares() internal view`** —
[`:1321`](core/contracts/0.4.24/Lido.sol#L1321). Solves

```
(externalShares + x) / (totalShares + x) <= maxRatioBP / totalBP
x <= (totalShares * maxRatioBP - externalShares * totalBP) / (totalBP - maxRatioBP)
```

with the derivation written out in the docstring at
[`:1313-1320`](core/contracts/0.4.24/Lido.sol#L1313-L1320). Returns 0 when the
ratio is 0 or already breached, and `2^256-1` at 100%. This is the ceiling on how
much of stETH's supply may be backed by stVaults rather than by pooled ETH.

### 5.5 Staking: user entry points

| Function | Line | Behaviour |
|---|---|---|
| `submit(address _referral) payable` | [`:508`](core/contracts/0.4.24/Lido.sol#L508) | The way ETH enters. Delegates to `_submit`. |
| `_submit(address) internal` | [`:1253`](core/contracts/0.4.24/Lido.sol#L1253) | `"ZERO_DEPOSIT"` on zero value, `_decreaseStakingLimit(msg.value)`, mint `getSharesByPooledEth(msg.value)` shares, add to buffered ether, emit `Submitted` then the synthetic `Transfer`. |
| `receiveELRewards() payable` | [`:517`](core/contracts/0.4.24/Lido.sol#L517) | Only the EL rewards vault. Adds to buffer and to the lifetime counter, emits `ELRewardsReceived`. |
| `receiveWithdrawals() payable` | [`:530`](core/contracts/0.4.24/Lido.sol#L530) | Only the withdrawal vault. Emits `WithdrawalsReceived`. |

There is no `receive()`; ETH sent bare reverts. That is deliberate, because
untracked ETH would silently change the share rate.

### 5.6 Staking limits

A leaky-bucket rate limit, so a whale cannot dilute the deposit queue in one
block. State lives packed in `STAKING_STATE_POSITION`; the arithmetic is in
[`StakeLimitUtils`](#123-stakelimitutils).

| Function | Line | Access |
|---|---|---|
| `pauseStaking()` | [`:349`](core/contracts/0.4.24/Lido.sol#L349) | `STAKING_PAUSE_ROLE` |
| `resumeStaking()` | [`:363`](core/contracts/0.4.24/Lido.sol#L363) | `STAKING_CONTROL_ROLE` |
| `setStakingLimit(uint256 _maxStakeLimit, uint256 _stakeLimitIncreasePerBlock)` | [`:392`](core/contracts/0.4.24/Lido.sol#L392) | `STAKING_CONTROL_ROLE`. Emits `StakingLimitSet`. |
| `removeStakingLimit()` | [`:408`](core/contracts/0.4.24/Lido.sol#L408) | `STAKING_CONTROL_ROLE`. Emits `StakingLimitRemoved`. |
| `isStakingPaused()` | [`:421`](core/contracts/0.4.24/Lido.sol#L421) | view |
| `getCurrentStakeLimit()` | [`:431`](core/contracts/0.4.24/Lido.sol#L431) | view, regenerated to the current block |
| `getStakeLimitFullInfo()` | [`:446`](core/contracts/0.4.24/Lido.sol#L446) | view, the whole packed struct decoded |
| `_decreaseStakingLimit` / `_increaseStakingLimit` | [`:1361`](core/contracts/0.4.24/Lido.sol#L1361), [`:1377`](core/contracts/0.4.24/Lido.sol#L1377) | internal |

### 5.7 Buffered ether and the deposits reserve

New in v3: buffered ETH is no longer a single pot. It is split between what may
be deposited to the beacon chain and what is held back for withdrawals.

| Function | Line | Notes |
|---|---|---|
| `getBufferedEther()` | [`:562`](core/contracts/0.4.24/Lido.sol#L562) | Total buffer. |
| `_getBufferedEtherAllocation()` | [`:605`](core/contracts/0.4.24/Lido.sol#L605) | Splits the buffer into its parts. |
| `getDepositsReserve()` | [`:623`](core/contracts/0.4.24/Lido.sol#L623) | Reserve kept depositable regardless of withdrawal demand. |
| `getWithdrawalsReserve()` | [`:640`](core/contracts/0.4.24/Lido.sol#L640) | The complement. |
| `getDepositsReserveTarget()` | [`:648`](core/contracts/0.4.24/Lido.sol#L648) | Governance target. |
| `setDepositsReserveTarget(uint256)` | [`:656`](core/contracts/0.4.24/Lido.sol#L656) | `BUFFER_RESERVE_MANAGER_ROLE`. Emits `DepositsReserveTargetSet`. |
| `canDeposit()` | [`:815`](core/contracts/0.4.24/Lido.sol#L815) | Not stopped, not bunker mode. |
| `getDepositableEther()` | [`:823`](core/contracts/0.4.24/Lido.sol#L823) | How much may go to the beacon chain now. |
| `_spendDepositableEther(uint256)` | [`:839`](core/contracts/0.4.24/Lido.sol#L839) | Debits buffer and reserve together. |
| `withdrawDepositableEther(uint256 _amount, uint256 _seedDepositsCount)` | [`:869`](core/contracts/0.4.24/Lido.sol#L869) | Called by the staking router to pull ETH for deposits. |
| `_updateBufferedEtherAllocation()` | [`:1125`](core/contracts/0.4.24/Lido.sol#L1125) | Restores the reserve to target at each report. |

### 5.8 Minting and burning

| Function | Line | Caller | Notes |
|---|---|---|---|
| `mintShares(address,uint256)` | [`:894`](core/contracts/0.4.24/Lido.sol#L894) | `Accounting` | Protocol fee minting during a report. |
| `burnShares(uint256)` | [`:907`](core/contracts/0.4.24/Lido.sol#L907) | `Burner` | Burns from the burner's own balance. |
| `mintExternalShares(address,uint256)` | [`:927`](core/contracts/0.4.24/Lido.sol#L927) | `VaultHub` | Mints stETH backed by a stVault. Checks the cap from §5.4. Emits `ExternalSharesMinted`. |
| `burnExternalShares(uint256)` | [`:949`](core/contracts/0.4.24/Lido.sol#L949) | `VaultHub` | The inverse. Emits `ExternalSharesBurnt`. |
| `rebalanceExternalEtherToInternal(uint256) payable` | [`:978`](core/contracts/0.4.24/Lido.sol#L978) | `VaultHub` | Converts vault-backed shares into pool-backed by paying ETH in. Emits `ExternalEtherTransferredToBuffer`. |
| `internalizeExternalBadDebt(uint256)` | [`:1037`](core/contracts/0.4.24/Lido.sol#L1037) | `VaultHub` | Socialises an unrecoverable vault deficit onto stETH holders. Emits `ExternalBadDebtInternalized`. |

That last one is the sharp edge of the vaults design: a vault that goes bad
dilutes every stETH holder. It is the analogue of Aave's `deficit` and Liquity's
redistribution, and it is worth reading next to both.

### 5.9 The report path

Two functions, both callable only by `Accounting`.

**`processClStateUpdate(uint256 _reportTimestamp, uint256 _clValidatorsBalance, uint256 _clPendingBalance) external`** —
[`:1012`](core/contracts/0.4.24/Lido.sol#L1012). Writes the packed CL slot and
emits `CLBalancesUpdated`.

**`collectRewardsAndProcessWithdrawals(...) external`** —
[`:1072`](core/contracts/0.4.24/Lido.sol#L1072). Eight parameters. In order it:

1. `_whenNotStopped()`, then `_auth(_accounting(locator))`.
2. Pulls EL rewards from the vault if any ([`:1088`](core/contracts/0.4.24/Lido.sol#L1088)).
3. Pulls withdrawn ETH from the withdrawal vault if any ([`:1093`](core/contracts/0.4.24/Lido.sol#L1093)).
4. Finalises withdrawal requests, forwarding ETH with the call ([`:1098-1101`](core/contracts/0.4.24/Lido.sol#L1098-L1101)).
5. Recomputes the buffer as `buffered + elRewards + withdrawals − lockedOnQueue` ([`:1104-1107`](core/contracts/0.4.24/Lido.sol#L1104-L1107)).
6. `_updateBufferedEtherAllocation()`, then emits `ETHDistributed`.

**`emitTokenRebase(...)`** at [`:1154`](core/contracts/0.4.24/Lido.sol#L1154)
emits `TokenRebased`, the event any indexer should watch, since a rebase produces
no ERC-20 `Transfer`.

### 5.10 Views and plumbing

| Function | Line | Returns |
|---|---|---|
| `getExternalEther()` / `getExternalShares()` | [`:685`](core/contracts/0.4.24/Lido.sol#L685), [`:692`](core/contracts/0.4.24/Lido.sol#L692) | Vault-backed portions. |
| `getMaxMintableExternalShares()` | [`:699`](core/contracts/0.4.24/Lido.sol#L699) | The §5.4 cap. |
| `getMaxExternalRatioBP()` / `setMaxExternalRatioBP(uint256)` | [`:475`](core/contracts/0.4.24/Lido.sol#L475), [`:483`](core/contracts/0.4.24/Lido.sol#L483) | Governance-set ceiling; emits `MaxExternalRatioBPSet`. |
| `getTotalELRewardsCollected()` | [`:708`](core/contracts/0.4.24/Lido.sol#L708) | Lifetime EL rewards. |
| `getLidoLocator()` | [`:715`](core/contracts/0.4.24/Lido.sol#L715) | The address book. |
| `getBeaconStat()` | [`:726`](core/contracts/0.4.24/Lido.sol#L726) | Legacy-shaped CL stats. |
| `getBalanceStats()` | [`:746`](core/contracts/0.4.24/Lido.sol#L746) | The v3 balance-based view. |
| `getWithdrawalCredentials()` | [`:1199`](core/contracts/0.4.24/Lido.sol#L1199) | Forwarded from the staking router. |
| `getTreasury()` | [`:1207`](core/contracts/0.4.24/Lido.sol#L1207) | From the locator. |
| `getFee()` / `getFeeDistribution()` | [`:1218`](core/contracts/0.4.24/Lido.sol#L1218), [`:1234`](core/contracts/0.4.24/Lido.sol#L1234) | Aggregate fee and its split, both from the staking router. |
| `transferToVault(...)` | [`:1183`](core/contracts/0.4.24/Lido.sol#L1183) | Legacy; reverts in v3. |
| `stop()` / `resume()` | [`:539`](core/contracts/0.4.24/Lido.sol#L539), [`:550`](core/contracts/0.4.24/Lido.sol#L550) | `PAUSE_ROLE` / `RESUME_ROLE`. |

Initialisation is `initialize(address _lidoLocator, address _eip712StETH, uint256 _depositsReserveTarget) payable onlyInit`
at [`:276`](core/contracts/0.4.24/Lido.sol#L276), with
`finalizeUpgrade_v4(uint256)` at
[`:296`](core/contracts/0.4.24/Lido.sol#L296) for the migration. The latter
refuses to run if the last oracle report is missing, so deposits cannot resume
against stale accounting.

The remaining internals from [`:1473`](core/contracts/0.4.24/Lido.sol#L1473) to
[`:1569`](core/contracts/0.4.24/Lido.sol#L1569) are getter/setter pairs for each
packed slot, plus the locator shortcuts `_stakingRouter`, `_withdrawalQueue`,
`_vaultHub`, `_burner`, `_accounting`, `_accountingOracle`, `_elRewardsVault` and
`_withdrawalVault` at [`:1398-1446`](core/contracts/0.4.24/Lido.sol#L1398-L1446).

---
## 6. `Accounting.sol` — the rebase engine

[`core/contracts/0.8.9/Accounting.sol`](core/contracts/0.8.9/Accounting.sol) — 536 lines, solc 0.8.9.

New in v3. In v2, `Lido.handleOracleReport` did all of this itself in Solidity
0.4.24. v3 lifts the arithmetic into a 0.8.9 contract that computes the entire
rebase in memory, sanity-checks it, and only then calls back into `Lido` to apply
it. `Lido` is left holding state and permissions; `Accounting` holds the maths.

### 6.1 Structures

**`Contracts`** [`:39`](core/contracts/0.8.9/Accounting.sol#L39) — the locator
addresses needed for one report, loaded once by `_loadOracleReportContracts`
([`:510`](core/contracts/0.8.9/Accounting.sol#L510)) so the report path makes no
repeated locator calls.

**`PreReportState`** [`:50`](core/contracts/0.8.9/Accounting.sol#L50) — the
protocol as it stands before the report: `clValidatorsBalance`,
`clPendingBalance`, `depositedBalance`, `totalPooledEther`, `totalShares`,
`externalShares`, `externalEther`, `badDebtToInternalize`.

**`CalculatedValues`** [`:62`](core/contracts/0.8.9/Accounting.sol#L62) — the
fourteen numbers a report produces, including the pre/post pairs for both shares
and ether and, crucially, the **internal** post values that feed the share rate
from [§5.3](#53-the-share-rate-and-why-it-excludes-vault-shares):
`postInternalShares` and `postInternalEther`.

**`FeeDistribution`** [`:98`](core/contracts/0.8.9/Accounting.sol#L98) — recipients,
module ids, per-module shares and the treasury remainder.

### 6.2 Entry points

**`handleOracleReport(ReportValues calldata _report) external`** —
[`:137`](core/contracts/0.8.9/Accounting.sol#L137). The only mutating entry.
Callable solely by the accounting oracle; reverts
`NotAuthorized(string,address)` otherwise. It snapshots, simulates, then applies.

**`simulateOracleReport(...)`** — [`:125`](core/contracts/0.8.9/Accounting.sol#L125).
The same computation with no writes, used off-chain to derive
`simulatedShareRate` before submitting.

**`_snapshotPreReportState(Contracts memory, bool isSimulation)`** —
[`:147`](core/contracts/0.8.9/Accounting.sol#L147). Reads the pre-state. The
`isSimulation` flag is what lets one code path serve both.

**`_simulateOracleReport(...)`** — [`:179`](core/contracts/0.8.9/Accounting.sol#L179).
Orchestrates: withdrawals, then fees, then the post totals.

### 6.3 The fee formula, derived

This is the piece worth working through by hand.

`_calculateTotalProtocolFeeShares` — [`:306`](core/contracts/0.8.9/Accounting.sol#L306):

```solidity
uint256 unifiedClBalance = _report.clValidatorsBalance + _report.clPendingBalance
                         + _update.withdrawalsVaultTransfer;
if (unifiedClBalance > _update.principalClBalance) {
    uint256 totalRewards = unifiedClBalance - _update.principalClBalance
                         + _update.elRewardsVaultTransfer;
    uint256 feeEther = (totalRewards * _totalFee) / _feePrecisionPoints;
    sharesToMintAsFees = (feeEther * _internalSharesBeforeFees)
                       / (_update.postInternalEther - feeEther);
}
```

**The guard first.** The `if` implements LIP-12: no fee is taken when the
consensus-layer delta is zero or negative. A loss-making report mints nothing, so
the protocol never charges for going backwards. The source cites the proposal at
[`:355-357`](core/contracts/0.8.9/Accounting.sol#L355-L357).

**Now the formula.** The protocol wants `feeEther` of value, but it cannot pay
itself in ether without removing ether from the pool, so it mints shares instead
and dilutes. How many shares is that?

If the fee *were* taken as an ether deduction, existing holders would end up at
the rate

```
r_target = (postInternalEther − feeEther) / sharesBefore
```

Instead the ether stays and `x` new shares are minted, giving

```
r_actual = postInternalEther / (sharesBefore + x)
```

Set them equal, since the whole point is that holders are left exactly as they
would have been:

```
postInternalEther / (sharesBefore + x) = (postInternalEther − feeEther) / sharesBefore
postInternalEther · sharesBefore = (postInternalEther − feeEther)(sharesBefore + x)
postInternalEther · sharesBefore = postInternalEther · sharesBefore
                                 + postInternalEther · x
                                 − feeEther · sharesBefore
                                 − feeEther · x
feeEther · sharesBefore = x · (postInternalEther − feeEther)
x = feeEther · sharesBefore / (postInternalEther − feeEther)
```

which is the line of code exactly. The comment at
[`:359-364`](core/contracts/0.8.9/Accounting.sol#L359-L364) describes this in
prose; the algebra above is the same statement.

Note `_internalSharesBeforeFees`, not total shares. Vault-backed external shares
are excluded, consistent with [§5.3](#53-the-share-rate-and-why-it-excludes-vault-shares).

### 6.4 Splitting the fee

`_calculateProtocolFees` — [`:265`](core/contracts/0.8.9/Accounting.sol#L265).
Asks `StakingRouter.getStakingRewardsDistribution()` for recipients, module ids,
per-module fees in `uint96`, the aggregate `totalFee`, and `precisionPoints`. Two
`assert`s confirm the three arrays are the same length.

`_calculateFeeDistribution` — [`:335`](core/contracts/0.8.9/Accounting.sol#L335):

```solidity
uint256 moduleFeeShares = (_totalSharesToMintAsFees * moduleFee) / _totalFee;
...
treasurySharesToMint = _totalSharesToMintAsFees - totalModuleFeeShares;
```

Each module gets its pro-rata slice rounded down, and **the treasury takes the
remainder**. That is a deliberate choice: all truncation dust accrues to the DAO
rather than being lost or over-paid to a module. Note `assert(_totalFee > 0)` at
[`:341`](core/contracts/0.8.9/Accounting.sol#L341) — a zero total fee with a
non-zero mint would divide by zero, and the assert makes that a panic rather than
a silent wrap.

### 6.5 Applying the report

`_applyOracleReportContext` — [`:360`](core/contracts/0.8.9/Accounting.sol#L360).
The order matters and is worth reading as a sequence:

1. `_sanityChecks(...)` ([`:432`](core/contracts/0.8.9/Accounting.sol#L432)) — everything in [§7](#7-oraclereportsanitychecker-and-the-limiters). Nothing has been written yet, so a failed check reverts the whole report cleanly.
2. If finalising withdrawals, request the burn of the queue's shares and note the last request id ([`:369-375`](core/contracts/0.8.9/Accounting.sol#L369-L375)).
3. `LIDO.processClStateUpdate(...)` — write the new CL balances ([`:377`](core/contracts/0.8.9/Accounting.sol#L377)).
4. If a vault has bad debt, `vaultHub.decreaseInternalizedBadDebt(...)` then `LIDO.internalizeExternalBadDebt(...)` ([`:383-386`](core/contracts/0.8.9/Accounting.sol#L383-L386)).
5. `burner.commitSharesToBurn(...)` ([`:388-390`](core/contracts/0.8.9/Accounting.sol#L388-L390)).
6. `LIDO.collectRewardsAndProcessWithdrawals(...)` — the eight-argument call from [§5.9](#59-the-report-path) ([`:392`](core/contracts/0.8.9/Accounting.sol#L392)).
7. If fees are due: `LIDO.mintShares(address(this), ...)`, `_distributeFee(...)`, then `stakingRouter.reportRewardsMinted(...)` ([`:403-411`](core/contracts/0.8.9/Accounting.sol#L403-L411)).
8. `_notifyRebaseObserver(...)` ([`:490`](core/contracts/0.8.9/Accounting.sol#L490)).
9. `LIDO.emitTokenRebase(...)` last, so the event carries final numbers.

`_distributeFee` — [`:471`](core/contracts/0.8.9/Accounting.sol#L471). `Accounting`
mints the whole fee to **itself** first, then transfers shares out to each module
recipient and the treasury. That keeps the mint a single operation and makes the
distribution a set of ordinary share transfers.

`_calculateWithdrawals` — [`:251`](core/contracts/0.8.9/Accounting.sol#L251).
Works out how much ether to lock and how many shares to burn for the finalised
batch.

### 6.6 Errors

Three, all at [`:533-535`](core/contracts/0.8.9/Accounting.sol#L533-L535):

| Error | Cause |
|---|---|
| `NotAuthorized(string operation, address addr)` | Caller is not the accounting oracle. |
| `IncorrectReportTimestamp(uint256 reportTimestamp, uint256 upperBoundTimestamp)` | Report timestamp is in the future. |
| `InternalSharesCantBeZero()` | Internal shares reached zero, which would make the share rate undefined. The "stone in the elevator" exists to make this unreachable. |

---
## 7. `OracleReportSanityChecker` and the limiters

[`core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol) — 1,588 lines, solc 0.8.9.

The oracle is a quorum of off-chain actors. This contract is the assumption that
they might be wrong or captured, expressed as code: every number in a report must
fall inside a governance-set band, or the report reverts.

### 7.1 `LimitsList`

The struct at [`:59-103`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L59-L103).
Each field is separately settable and separately role-gated.

| Field | Units | Meaning |
|---|---|---|
| `exitedEthAmountPerDayLimit` | ETH, fits `uint32` | Max exited ETH reportable per day. |
| `appearedEthAmountPerDayLimit` | ETH, fits `uint32` | Max newly appeared ETH per day. |
| `annualBalanceIncreaseBPLimit` | bp | Max annualised CL balance growth, excluding fresh deposits and withdrawals. Catches an impossibly good report. |
| `simulatedShareRateDeviationBPLimit` | bp | How far the submitted `simulatedShareRate` may differ from the recomputed one. |
| `maxBalanceExitRequestedPerReportInEth` | ETH | Cap on exit requests in one report. |
| `maxEffectiveBalanceWeightWCType01` | ETH, `uint16`, non-zero | Effective-balance weight for 0x01 credentials. |
| `maxEffectiveBalanceWeightWCType02` | ETH, `uint16`, non-zero | Same for 0x02 (EIP-7251 compounding). |
| `maxItemsPerExtraDataTransaction` | count, `uint16` | Gas bound on extra data. |
| `maxNodeOperatorsPerExtraDataItem` | count, `uint16` | Gas bound per item. |
| `requestTimestampMargin` | seconds | Minimum age of a withdrawal request before it may be finalised. |
| `maxPositiveTokenRebase` | 1e9 precision | Max positive rebase per report. `1e6` is 0.1%, `1e9` is 100%. |
| `maxCLBalanceDecreaseBP` | bp, `uint16` | Max CL balance decrease over the window, as a fraction of adjusted balance. |

The two `maxEffectiveBalanceWeight*` fields are v3 additions and exist because
EIP-7251 lets a validator hold up to 2048 ETH instead of 32, so "one validator"
is no longer a fixed quantity of ETH.

### 7.2 Roles

Sixteen, at [`:191-219`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L191-L219).
`ALL_LIMITS_MANAGER_ROLE` sets everything at once via `setOracleReportLimits`
([`:330`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L330));
each remaining role sets exactly one field. The granularity is the point: the DAO
can hand out the authority to tune one bound without handing over the rest.

| Role | Setter |
|---|---|
| `ALL_LIMITS_MANAGER_ROLE` | `setOracleReportLimits` [`:330`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L330) |
| `EXITED_ETH_AMOUNT_PER_DAY_LIMIT_MANAGER_ROLE` | `setExitedEthAmountPerDayLimit` [`:343`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L343) |
| `APPEARED_ETH_AMOUNT_PER_DAY_LIMIT_MANAGER_ROLE` | `setAppearedEthAmountPerDayLimit` [`:354`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L354) |
| `CONSOLIDATION_ETH_AMOUNT_PER_DAY_LIMIT_MANAGER_ROLE` | `setConsolidationEthAmountPerDayLimit` [`:365`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L365) |
| `EXITED_VALIDATOR_ETH_AMOUNT_LIMIT_MANAGER_ROLE` | `setExitedValidatorEthAmountLimit` [`:375`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L375) |
| `EXTERNAL_PENDING_BALANCE_CAP_MANAGER_ROLE` | `setExternalPendingBalanceCapEth` [`:386`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L386) |
| `ANNUAL_BALANCE_INCREASE_LIMIT_MANAGER_ROLE` | `setAnnualBalanceIncreaseBPLimit` [`:397`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L397) |
| `SHARE_RATE_DEVIATION_LIMIT_MANAGER_ROLE` | `setSimulatedShareRateDeviationBPLimit` [`:408`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L408) |
| `MAX_BALANCE_EXIT_REQUESTED_PER_REPORT_IN_ETH_ROLE` | `setMaxBalanceExitRequestedPerReportInEth` [`:420`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L420) |
| `MAX_EFFECTIVE_BALANCE_WEIGHTS_MANAGER_ROLE` | `setMaxEffectiveBalanceWeightWCType01` [`:431`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L431), `...Type02` [`:442`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L442) |
| `MAX_ITEMS_PER_EXTRA_DATA_TRANSACTION_ROLE` | `setMaxItemsPerExtraDataTransaction` [`:481`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L481) |
| `MAX_NODE_OPERATORS_PER_EXTRA_DATA_ITEM_ROLE` | `setMaxNodeOperatorsPerExtraDataItem` [`:492`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L492) |
| `REQUEST_TIMESTAMP_MARGIN_MANAGER_ROLE` | `setRequestTimestampMargin` [`:454`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L454) |
| `MAX_POSITIVE_TOKEN_REBASE_MANAGER_ROLE` | `setMaxPositiveTokenRebase` [`:470`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L470) |
| `SECOND_OPINION_MANAGER_ROLE` | `setSecondOpinionOracleAndCLBalanceUpperMargin` [`:506`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L506) |
| `MAX_CL_BALANCE_DECREASE_MANAGER_ROLE` | `setMaxCLBalanceDecreaseBP` [`:522`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L522) |

### 7.3 The checks

| Function | Line | Called by |
|---|---|---|
| `checkAccountingOracleReport(...)` | [`:645`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L645) | `Accounting._sanityChecks`. The main gate. |
| `checkModuleAndCLBalancesChangeRates(...)` | [`:719`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L719) | `AccountingOracle`, per-module rate bounds. |
| `checkExitBusOracleReport(uint256)` | [`:763`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L763) | `ValidatorsExitBus`. |
| `checkExitedValidatorsCount(...)` | [`:780`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L780) | Exit accounting. |
| `checkNodeOperatorsPerExtraDataItemCount(uint256,uint256)` | [`:804`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L804) | Extra-data bound. |
| `checkExtraDataItemsCountPerTransaction(uint256)` | [`:813`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L813) | Extra-data bound. |
| `checkWithdrawalQueueOracleReport(...)` | [`:823`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L823) | Enforces `requestTimestampMargin`. |

**The second-opinion oracle.** `setSecondOpinionOracleAndCLBalanceUpperMargin`
wires an independent oracle (LIP-23,
[`ISecondOpinionOracle`](core/contracts/0.8.9/interfaces/ISecondOpinionOracle.sol)).
When the CL balance falls by more than `maxCLBalanceDecreaseBP`, the report is
not simply rejected; a second source must corroborate the loss. This is the
protocol's answer to a mass-slashing report that might be either real or forged.

### 7.4 `PositiveTokenRebaseLimiter`

[`core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol) — 178 lines.

A memory-only accumulator that caps how good a single report may be. Rewards
beyond the cap are not lost; they are deferred by leaving ether unclaimed from
the vaults this round.

| Function | Line | Purpose |
|---|---|---|
| `initLimiterState(...)` | [`:83`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol#L83) | Builds `TokenRebaseLimiterData` from the cap and current totals. |
| `isLimitReached(...)` | [`:109`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol#L109) | Whether the budget is exhausted. |
| `decreaseEther(...)` | [`:118`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol#L118) | Consumes budget for ether leaving. |
| `increaseEther(...)` | [`:134`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol#L134) | Consumes budget for ether arriving; returns the amount actually allowed. |
| `getSharesToBurnLimit(...)` | [`:159`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol#L159) | How many shares may be burnt without breaching the cap. |

---

## 8. The oracle stack

Three layers: `HashConsensus` decides *what* the committee agreed, `BaseOracle`
handles the handoff, and the two concrete oracles interpret the payload.

### 8.1 `HashConsensus`

[`core/contracts/0.8.9/oracle/HashConsensus.sol`](core/contracts/0.8.9/oracle/HashConsensus.sol) — 1,096 lines, solc 0.8.9.

Members submit a **hash** of a report for a reference slot. When a quorum agrees
on the same hash, that hash is forwarded to the processor. The data itself is
submitted separately and checked against the hash, which keeps consensus cheap.

**Structures.** `FrameConfig` [`:123`](core/contracts/0.8.9/oracle/HashConsensus.sol#L123),
`ConsensusFrame` [`:137`](core/contracts/0.8.9/oracle/HashConsensus.sol#L137),
`ReportingState` [`:147`](core/contracts/0.8.9/oracle/HashConsensus.sol#L147),
`MemberState` [`:156`](core/contracts/0.8.9/oracle/HashConsensus.sol#L156),
`ReportVariant` [`:163`](core/contracts/0.8.9/oracle/HashConsensus.sol#L163),
`MemberConsensusState` [`:531`](core/contracts/0.8.9/oracle/HashConsensus.sol#L531).

**Roles** at [`:172-190`](core/contracts/0.8.9/oracle/HashConsensus.sol#L172-L190):
`MANAGE_MEMBERS_AND_QUORUM_ROLE`, `DISABLE_CONSENSUS_ROLE`,
`MANAGE_FRAME_CONFIG_ROLE`, `MANAGE_FAST_LANE_CONFIG_ROLE`,
`MANAGE_REPORT_PROCESSOR_ROLE`.

**Frame arithmetic**, [`:672-700`](core/contracts/0.8.9/oracle/HashConsensus.sol#L672-L700):

```
epoch      = (timestamp − GENESIS_TIME) / SECONDS_PER_SLOT / SLOTS_PER_EPOCH
frameIndex = (epoch − initialEpoch) / epochsPerFrame
frameStart = initialEpoch + frameIndex · epochsPerFrame
```

`_computeFrameIndex` reverts `InitialEpochIsYetToArrive()` below `initialEpoch`.
`_computeTimestampAtSlot` is `GENESIS_TIME + slot · SECONDS_PER_SLOT`, matching
the consensus spec, which the comment cites at
[`:694`](core/contracts/0.8.9/oracle/HashConsensus.sol#L694).

**The fast lane.** `fastLaneLengthSlots` gives a rotating subset of members an
exclusive window at the start of each frame
(`getIsFastLaneMember` [`:398`](core/contracts/0.8.9/oracle/HashConsensus.sol#L398),
`getFastLaneMembers` [`:420`](core/contracts/0.8.9/oracle/HashConsensus.sol#L420)).
It spreads gas costs across the committee instead of rewarding whoever submits
first every time.

| Function | Line |
|---|---|
| `getChainConfig()` | [`:274`](core/contracts/0.8.9/oracle/HashConsensus.sol#L274) |
| `getFrameConfig()` / `setFrameConfig(uint256,uint256)` | [`:288`](core/contracts/0.8.9/oracle/HashConsensus.sol#L288), [`:350`](core/contracts/0.8.9/oracle/HashConsensus.sol#L350) |
| `getCurrentFrame()` / `getInitialRefSlot()` | [`:307`](core/contracts/0.8.9/oracle/HashConsensus.sol#L307), [`:318`](core/contracts/0.8.9/oracle/HashConsensus.sol#L318) |
| `updateInitialEpoch(uint256)` | [`:326`](core/contracts/0.8.9/oracle/HashConsensus.sol#L326) — `DEFAULT_ADMIN_ROLE` |
| `getIsMember` / `getMembers` | [`:366`](core/contracts/0.8.9/oracle/HashConsensus.sol#L366), [`:408`](core/contracts/0.8.9/oracle/HashConsensus.sol#L408) |
| `addMember` / `removeMember` | [`:441`](core/contracts/0.8.9/oracle/HashConsensus.sol#L441), [`:448`](core/contracts/0.8.9/oracle/HashConsensus.sol#L448) |
| `getQuorum` / `setQuorum` / `disableConsensus` | [`:455`](core/contracts/0.8.9/oracle/HashConsensus.sol#L455), [`:459`](core/contracts/0.8.9/oracle/HashConsensus.sol#L459), [`:466`](core/contracts/0.8.9/oracle/HashConsensus.sol#L466) |
| `getReportProcessor` / `setReportProcessor` | [`:475`](core/contracts/0.8.9/oracle/HashConsensus.sol#L475), [`:479`](core/contracts/0.8.9/oracle/HashConsensus.sol#L479) |
| `getConsensusState` / `getReportVariants` / `getConsensusStateForMember` | [`:500`](core/contracts/0.8.9/oracle/HashConsensus.sol#L500), [`:512`](core/contracts/0.8.9/oracle/HashConsensus.sol#L512), [`:564`](core/contracts/0.8.9/oracle/HashConsensus.sol#L564) |
| `submitReport(uint256 slot, bytes32 report, uint256 consensusVersion)` | [`:609`](core/contracts/0.8.9/oracle/HashConsensus.sol#L609) — members only |

`disableConsensus` sets quorum beyond the member count, halting reports without
removing anyone. It is the emergency brake.

### 8.2 `BaseOracle`

[`core/contracts/0.8.9/oracle/BaseOracle.sol`](core/contracts/0.8.9/oracle/BaseOracle.sol) — 416 lines.

Shared plumbing. Roles `MANAGE_CONSENSUS_CONTRACT_ROLE`
[`:74`](core/contracts/0.8.9/oracle/BaseOracle.sol#L74) and
`MANAGE_CONSENSUS_VERSION_ROLE` [`:79`](core/contracts/0.8.9/oracle/BaseOracle.sol#L79).

| Function | Line | Notes |
|---|---|---|
| `submitConsensusReport(bytes32,uint256,uint256)` | [`:174`](core/contracts/0.8.9/oracle/BaseOracle.sol#L174) | Only the consensus contract. Stores hash and deadline. |
| `discardConsensusReport(uint256 refSlot)` | [`:225`](core/contracts/0.8.9/oracle/BaseOracle.sol#L225) | Drops a report if consensus is lost before processing. |
| `getConsensusReport()` | [`:146`](core/contracts/0.8.9/oracle/BaseOracle.sol#L146) | Hash, refSlot, deadline, processing flag. |
| `getLastProcessingRefSlot()` | [`:248`](core/contracts/0.8.9/oracle/BaseOracle.sol#L248) | Monotonic; blocks replay. |
| `_checkConsensusData(uint256,uint256,bytes32)` | [`:300`](core/contracts/0.8.9/oracle/BaseOracle.sol#L300) | Data must hash to the agreed hash for the right slot and version. |
| `_startProcessing()` | [`:326`](core/contracts/0.8.9/oracle/BaseOracle.sol#L326) | Marks processing begun, returns the previous refSlot. |
| `_checkProcessingDeadline()` | [`:347`](core/contracts/0.8.9/oracle/BaseOracle.sol#L347) | Late data is refused. |
| `_handleConsensusReport(...)` | [`:285`](core/contracts/0.8.9/oracle/BaseOracle.sol#L285) | `virtual` hook the concrete oracles override. |

### 8.3 `AccountingOracle`

[`core/contracts/0.8.9/oracle/AccountingOracle.sol`](core/contracts/0.8.9/oracle/AccountingOracle.sol) — 916 lines.

Carries the report that drives the rebase. `SUBMIT_DATA_ROLE` at
[`:105`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L105).

`ReportData` [`:152`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L152) is the
main payload; `ExtraDataProcessingState`
[`:94`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L94) tracks the
second-phase upload; `ProcessingState`
[`:384`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L384) is the public view.

**Two-phase submission.** The main report arrives via `submitReportData`
([`:360`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L360)). Per-operator
exit counts can be far too large for one transaction, so they come afterwards
through `submitReportExtraDataList(bytes)`
([`:380`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L380)), or
`submitReportExtraDataEmpty()`
([`:371`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L371)) when there is
none. The `maxItemsPerExtraDataTransaction` and
`maxNodeOperatorsPerExtraDataItem` limits from [§7.1](#71-limitslist) bound each
chunk.

`_handleConsensusReportData` ([`:477`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L477))
validates then calls `Accounting.handleOracleReport`.
`_processStakingRouterExitedValidatorsByModule`
([`:565`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L565)) and
`_processStakingRouterValidatorBalancesByModule`
([`:609`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L609)) push per-module
results onward. `getProcessingState()`
([`:414`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L414)) is what a
monitoring bot polls.

### 8.4 `ValidatorsExitBus` and `ValidatorsExitBusOracle`

[`ValidatorsExitBus.sol`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol) — 1,148 lines;
[`ValidatorsExitBusOracle.sol`](core/contracts/0.8.9/oracle/ValidatorsExitBusOracle.sol) — 285 lines.

Lido cannot force a validator to exit from the execution layer alone, so
historically it *published a request* and relied on operators to act. EIP-7002
changed that, and v3 reflects it: the bus both publishes requests and can trigger
withdrawals directly.

Roles at [`:228-235`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L228-L235):
`SUBMIT_REPORT_HASH_ROLE`, `EXIT_REQUEST_LIMIT_MANAGER_ROLE`, `PAUSE_ROLE`,
`RESUME_ROLE`.

| Function | Line | Purpose |
|---|---|---|
| `submitExitRequestsHash(bytes32)` | [`:324`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L324) | Commit to a request set. |
| `submitExitRequestsData(ExitRequestsData)` | [`:346`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L346) | Reveal it; must match the hash. |
| `triggerExits(...)` | [`:391`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L391) | EIP-7002 triggerable withdrawals, via the gateway. |
| `setExitRequestLimit(...)` / `getExitRequestLimitFullInfo()` | [`:451`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L451), [`:467`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L467) | Rate limit, backed by [`ExitLimitUtils`](core/contracts/0.8.9/lib/ExitLimitUtils.sol). |
| `setMaxValidatorsPerReport(uint256)` | [`:493`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L493) | Per-report cap. |
| `getDeliveryTimestamp(bytes32)` | [`:514`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L514) | When a request set was delivered; feeds the delay verifier. |
| `unpackExitRequest(...)` | [`:534`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L534) | Decodes the packed request format. |
| `pauseFor` / `pauseUntil` / `resume` | [`:572`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L572), [`:581`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L581), [`:561`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L561) | Via `PausableUntil`. |
| `MAX_EFFECTIVE_BALANCE_WEIGHT_WC_TYPE_01/02()` | [`:302`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L302), [`:307`](core/contracts/0.8.9/oracle/ValidatorsExitBus.sol#L307) | Read through to the sanity checker. |

---
## 9. Withdrawals

Unstaking is asynchronous: ETH has to come off the beacon chain first. The queue
makes the wait explicit and, importantly, makes each position transferable.

### 9.1 `WithdrawalQueueBase`

[`core/contracts/0.8.9/WithdrawalQueueBase.sol`](core/contracts/0.8.9/WithdrawalQueueBase.sol) — 596 lines.

**Storage**, all unstructured, at
[`:28-44`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L28-L44): `QUEUE_POSITION`,
`LAST_REQUEST_ID_POSITION`, `LAST_FINALIZED_REQUEST_ID_POSITION`,
`CHECKPOINTS_POSITION`, `LAST_CHECKPOINT_INDEX_POSITION`,
`LOCKED_ETHER_AMOUNT_POSITION`, `REQUEST_BY_OWNER_POSITION`,
`LAST_REPORT_TIMESTAMP_POSITION`. These use inline `keccak256("...")` rather than
precomputed literals.

**`WithdrawalRequest`** [`:46`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L46)
stores *cumulative* stETH and shares, not per-request amounts. A single request's
size is the difference between it and its predecessor, which is what
`_calcBatch` ([`:534`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L534))
computes. That is why index 0 is a zero-filled sentinel, created by
`_initializeQueue` ([`:517`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L517))
so that `_requestId - 1` never underflows.

**`Checkpoint`** [`:62`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L62) records
`fromRequestId` and `maxShareRate`. Finalisation appends a checkpoint rather than
writing to every request, so finalising a million requests is O(1).

### 9.2 The discount mechanism

This is the part worth understanding. A request is created at today's share rate,
but if the protocol loses value before it is finalised, paying out at the
original rate would let exiting users escape the loss at the expense of everyone
who stayed.

`_calculateClaimableEther` — [`:484`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L484):

```solidity
(uint256 batchShareRate, uint256 eth, uint256 shares) = _calcBatch(prevRequest, _request);

if (batchShareRate > checkpoint.maxShareRate) {
    eth = shares * checkpoint.maxShareRate / E27_PRECISION_BASE;
}
return eth;
```

If the request's own rate exceeds the rate the batch was finalised at, the payout
is recomputed at the **checkpoint's** rate. Requests are never paid *more* than
the protocol could afford at finalisation, and never less than their own rate
either. The loss lands on whoever was in the queue when it happened, which is the
correct place for it.

The hint machinery exists because finding the right checkpoint by binary search
on chain would be expensive. `_findCheckpointHint`
([`:418`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L418)) does the search;
callers normally precompute it off chain via `findCheckpointHints` and pass it
in. A wrong hint reverts `InvalidHint(_hint)`, and the range check at
[`:497-505`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L497-L505) is what makes
passing a hint safe rather than trusting.

| Function | Line | Purpose |
|---|---|---|
| `getLastRequestId` / `getLastFinalizedRequestId` | [`:116`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L116), [`:122`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L122) | Queue head and finalisation frontier. |
| `getLockedEtherAmount` | [`:127`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L127) | ETH reserved for finalised requests. |
| `unfinalizedRequestNumber` / `unfinalizedStETH` | [`:138`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L138), [`:143`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L143) | Outstanding demand; read by `Accounting`. |
| `calculateFinalizationBatches(...)` | [`:215`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L215) | Off-chain helper producing the batch split, using `BatchesCalculationState` [`:179`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L179). |
| `prefinalize(uint256[],uint256)` | [`:293`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L293) | Prices a proposed finalisation without executing it. |
| `_finalize(...)` | [`:332`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L332) | Appends the checkpoint, moves the frontier, locks ETH. |
| `_enqueue(uint128,uint128,address)` | [`:364`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L364) | Appends a request with cumulative sums. |
| `_getStatus(uint256)` | [`:393`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L393) | Returns `WithdrawalRequestStatus` [`:68`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L68). |
| `_claim(uint256,uint256,address)` | [`:460`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L460) | Marks claimed and sends ETH. |
| `_sendValue(address,uint256)` | [`:525`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L525) | Raw call with full gas, so contract recipients work. |

### 9.3 `WithdrawalQueue`

[`core/contracts/0.8.9/WithdrawalQueue.sol`](core/contracts/0.8.9/WithdrawalQueue.sol) — 415 lines.

Roles at [`:46-49`](core/contracts/0.8.9/WithdrawalQueue.sol#L46-L49): `PAUSE_ROLE`,
`RESUME_ROLE`, `FINALIZE_ROLE` (held by `Lido`), `ORACLE_ROLE`.

| Function | Line | Notes |
|---|---|---|
| `requestWithdrawals(uint256[],address)` | [`:125`](core/contracts/0.8.9/WithdrawalQueue.sol#L125) | Batch request in stETH. |
| `requestWithdrawalsWstETH(uint256[],address)` | [`:144`](core/contracts/0.8.9/WithdrawalQueue.sol#L144) | Unwraps first. |
| `requestWithdrawalsWithPermit(...)` | [`:171`](core/contracts/0.8.9/WithdrawalQueue.sol#L171) | Permit plus request in one transaction. |
| `requestWithdrawalsWstETHWithPermit(...)` | [`:186`](core/contracts/0.8.9/WithdrawalQueue.sol#L186) | Same for wstETH. |
| `getWithdrawalRequests(address)` | [`:201`](core/contracts/0.8.9/WithdrawalQueue.sol#L201) | Ids owned by an address. |
| `getWithdrawalStatus(uint256[])` | [`:207`](core/contracts/0.8.9/WithdrawalQueue.sol#L207) | Statuses in bulk. |
| `getClaimableEther(uint256[],uint256[])` | [`:223`](core/contracts/0.8.9/WithdrawalQueue.sol#L223) | Payouts, given hints. |
| `claimWithdrawals` / `claimWithdrawalsTo` / `claimWithdrawal` | [`:266`](core/contracts/0.8.9/WithdrawalQueue.sol#L266), [`:244`](core/contracts/0.8.9/WithdrawalQueue.sol#L244), [`:284`](core/contracts/0.8.9/WithdrawalQueue.sol#L284) | The single-id form searches for its own hint, so it costs more gas. |
| `findCheckpointHints(uint256[],uint256,uint256)` | [`:298`](core/contracts/0.8.9/WithdrawalQueue.sol#L298) | The off-chain helper. |
| `onOracleReport(bool,uint256,uint256)` | [`:319`](core/contracts/0.8.9/WithdrawalQueue.sol#L319) | Sets bunker mode. |
| `isBunkerModeActive` / `bunkerModeSinceTimestamp` | [`:346`](core/contracts/0.8.9/WithdrawalQueue.sol#L346), [`:352`](core/contracts/0.8.9/WithdrawalQueue.sol#L352) | Bunker mode halts new deposits and changes finalisation, so a mass-slashing event cannot be exited around. |

### 9.4 `WithdrawalQueueERC721`

[`core/contracts/0.8.9/WithdrawalQueueERC721.sol`](core/contracts/0.8.9/WithdrawalQueueERC721.sol) — 394 lines.

Makes each request an NFT, so a queue position can be sold rather than waited
out. Implements ERC-721 plus ERC-4906 metadata updates
([`IERC4906`](core/contracts/0.8.9/interfaces/IERC4906.sol)) and supplies the
`_emitTransfer` hook that `WithdrawalQueue` declares abstract at
[`:357`](core/contracts/0.8.9/WithdrawalQueue.sol#L357). `tokenURI` is delegated
to a swappable descriptor contract.

### 9.5 `WithdrawalVault`

[`core/contracts/0.8.9/WithdrawalVault.sol`](core/contracts/0.8.9/WithdrawalVault.sol) — 225 lines,
plus [`WithdrawalVaultEIP7685.sol`](core/contracts/0.8.9/WithdrawalVaultEIP7685.sol) — 132 lines.

Holds ETH arriving from beacon-chain withdrawals until a report moves it. Only
`Lido` may call `withdrawWithdrawals`. The EIP-7685 half encodes execution-layer
withdrawal and consolidation requests, which is how v3 triggers exits without
operator cooperation.

Related: [`LidoExecutionLayerRewardsVault`](core/contracts/0.8.9/LidoExecutionLayerRewardsVault.sol)
— 123 lines, the same pattern for MEV and priority fees, drained by
`withdrawRewards`.

---

## 10. `Burner`, vaults and reward sinks

[`core/contracts/0.8.9/Burner.sol`](core/contracts/0.8.9/Burner.sol) — 468 lines.

Burning shares raises the share rate for everyone else, so it is how Lido applies
a *negative* correction. Two categories are tracked separately: **cover** burns,
which offset a loss such as slashing, and **non-cover** burns, mainly withdrawal
finalisation.

Roles: `REQUEST_BURN_MY_STETH_ROLE` and `REQUEST_BURN_SHARES_ROLE` at
[`:91-92`](core/contracts/0.8.9/Burner.sol#L91-L92).

| Function | Line | Notes |
|---|---|---|
| `requestBurnMyStETHForCover(uint256)` | [`:209`](core/contracts/0.8.9/Burner.sol#L209) | Caller's own stETH, cover. |
| `requestBurnSharesForCover(address,uint256)` | [`:226`](core/contracts/0.8.9/Burner.sol#L226) | Pulls from another holder, cover. |
| `requestBurnMyShares(uint256)` | [`:244`](core/contracts/0.8.9/Burner.sol#L244) | Own shares, non-cover. |
| `requestBurnMyStETH(uint256)` | [`:261`](core/contracts/0.8.9/Burner.sol#L261) | Own stETH, non-cover. |
| `requestBurnShares(address,uint256)` | [`:278`](core/contracts/0.8.9/Burner.sol#L278) | The one `Accounting` uses for the withdrawal queue. |
| `commitSharesToBurn(uint256)` | [`:349`](core/contracts/0.8.9/Burner.sol#L349) | Only `Accounting`. Executes the burn during a report so it lands atomically with the rebase. |
| `getSharesRequestedToBurn()` | [`:398`](core/contracts/0.8.9/Burner.sol#L398) | Pending cover and non-cover. |
| `getCoverSharesBurnt` / `getNonCoverSharesBurnt` | [`:413`](core/contracts/0.8.9/Burner.sol#L413), [`:420`](core/contracts/0.8.9/Burner.sol#L420) | Lifetime totals. |
| `getExcessStETH()` | [`:427`](core/contracts/0.8.9/Burner.sol#L427) | stETH beyond what is requested; recoverable. |
| `recoverExcessStETH` / `recoverERC20` / `recoverERC721` | [`:288`](core/contracts/0.8.9/Burner.sol#L288), [`:314`](core/contracts/0.8.9/Burner.sol#L314), [`:330`](core/contracts/0.8.9/Burner.sol#L330) | Rescue paths for tokens sent by mistake. |
| `migrate(address _oldBurner)` | [`:174`](core/contracts/0.8.9/Burner.sol#L174) | One-shot import of the v2 burner's counters, guarded by `isMigrationAllowed`. |

**Separating the two counters matters.** Cover burns are funded by insurance or
the DAO to absorb a loss; non-cover burns are the ordinary consequence of
withdrawals. Collapsing them would make it impossible to tell, after the fact,
whether the share rate rose because users left or because a loss was covered.

Also here: [`TokenRateNotifier`](core/contracts/0.8.9/TokenRateNotifier.sol) (202
lines) fans rebase notifications out to registered observers such as L2 bridges,
via [`ITokenRatePusher`](core/contracts/0.8.9/interfaces/ITokenRatePusher.sol) and
[`ITokenRatePusherWithArgs`](core/contracts/0.8.9/interfaces/ITokenRatePusherWithArgs.sol).
[`OracleDaemonConfig`](core/contracts/0.8.9/OracleDaemonConfig.sol) (85 lines) is
a role-gated key-value store the off-chain daemon reads for its parameters.

---

## 11. `DepositSecurityModule` and depositing

[`core/contracts/0.8.9/DepositSecurityModule.sol`](core/contracts/0.8.9/DepositSecurityModule.sol) — 598 lines.

**The attack this exists to stop.** Lido deposits 32 ETH batches against
operator-supplied keys. If an operator front-runs the deposit and registers the
same public key with *their own* withdrawal credentials first, the 32 ETH is
theirs. The deposit contract cannot distinguish the two. So Lido will not deposit
unless a quorum of guardians signs off that the deposit root has not changed.

Two immutable prefixes bind signatures to purpose, built in the constructor at
[`:119-131`](core/contracts/0.8.9/DepositSecurityModule.sol#L119-L131):
`ATTEST_MESSAGE_PREFIX` [`:78`](core/contracts/0.8.9/DepositSecurityModule.sol#L78)
and `PAUSE_MESSAGE_PREFIX` [`:80`](core/contracts/0.8.9/DepositSecurityModule.sol#L80).
Each is a keccak over a domain string plus the chain id, so a signature cannot be
replayed onto another network or repurposed between the two flows.

| Function | Line | Access |
|---|---|---|
| `getOwner` / `setOwner(address)` | [`:156`](core/contracts/0.8.9/DepositSecurityModule.sol#L156), [`:170`](core/contracts/0.8.9/DepositSecurityModule.sol#L170) | owner |
| `getPauseIntentValidityPeriodBlocks` / setter | [`:184`](core/contracts/0.8.9/DepositSecurityModule.sol#L184), [`:193`](core/contracts/0.8.9/DepositSecurityModule.sol#L193) | owner. Bounds how stale a pause signature may be. |
| `getMaxOperatorsPerUnvetting` / setter | [`:207`](core/contracts/0.8.9/DepositSecurityModule.sol#L207), [`:216`](core/contracts/0.8.9/DepositSecurityModule.sol#L216) | owner |
| `getGuardianQuorum` / `setGuardianQuorum` | [`:230`](core/contracts/0.8.9/DepositSecurityModule.sol#L230), [`:239`](core/contracts/0.8.9/DepositSecurityModule.sol#L239) | owner |
| `getGuardians` / `isGuardian` / `getGuardianIndex` | [`:256`](core/contracts/0.8.9/DepositSecurityModule.sol#L256), [`:265`](core/contracts/0.8.9/DepositSecurityModule.sol#L265), [`:279`](core/contracts/0.8.9/DepositSecurityModule.sol#L279) | view |
| `addGuardian` / `addGuardians` / `removeGuardian` | [`:294`](core/contracts/0.8.9/DepositSecurityModule.sol#L294), [`:306`](core/contracts/0.8.9/DepositSecurityModule.sol#L306), [`:332`](core/contracts/0.8.9/DepositSecurityModule.sol#L332) | owner |
| `pauseDeposits(uint256 blockNumber, Signature)` | [`:368`](core/contracts/0.8.9/DepositSecurityModule.sol#L368) | **any single guardian**. Hashes `PAUSE_MESSAGE_PREFIX ‖ blockNumber` ([`:379`](core/contracts/0.8.9/DepositSecurityModule.sol#L379)) and pauses on one valid signature. |
| `unpauseDeposits()` | [`:396`](core/contracts/0.8.9/DepositSecurityModule.sol#L396) | owner only |

**The asymmetry is deliberate.** One guardian can halt deposits; only the owner
can resume them. Stopping is cheap and reversible, so it is made easy; restarting
is a decision, so it is made hard. Pausing is also bounded by
`pauseIntentValidityPeriodBlocks`, which stops an old signature being replayed
later to cause a denial of service.

Depositing itself runs through
[`BeaconChainDepositor`](core/contracts/0.8.25/lib/BeaconChainDepositor.sol) (160
lines), which builds the call to the vendored
[`deposit_contract.sol`](core/contracts/0.6.11/deposit_contract.sol) (178 lines).
On Sepolia the deposit contract differs, hence
[`SepoliaDepositAdapter`](core/contracts/tooling/sepolia/SepoliaDepositAdapter.sol).

---
## 12. `NodeOperatorsRegistry` and its libraries

[`core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol) — 1,496 lines, solc 0.4.24.

The **curated** staking module: a permissioned set of professional operators. It
implements [`IStakingModule`](core/contracts/common/interfaces/IStakingModule.sol)
so the router can treat it interchangeably with Community Staking or Simple DVT.

### 12.1 Roles

Precomputed keccaks at [`:81-88`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L81-L88),
each with the preimage in the comment above it. Aragon ACL roles.

| Role | Gates |
|---|---|
| `MANAGE_SIGNING_KEYS` | Adding and removing operator keys. |
| `SET_NODE_OPERATOR_LIMIT_ROLE` | `setNodeOperatorStakingLimit` (vetting). |
| `MANAGE_NODE_OPERATOR_ROLE` | Add, activate, deactivate, rename, change reward address. |
| `STAKING_ROUTER_ROLE` | Held by the router: `obtainDepositData`, exited-count updates, `onRewardsMinted`. |

### 12.2 Key lifecycle

A key moves through four counters, held in `NodeOperator`
([`:171`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L171)) and
summarised by `NodeOperatorSummary`
([`:201`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L201)):

```
 added  ──vetted──>  vetted  ──deposited──>  deposited  ──exited──>  exited
```

Only **vetted** keys may be deposited against. Vetting is a manual DAO act
because a key is a promise about withdrawal credentials that cannot be verified
on chain.

| Function | Line | Purpose |
|---|---|---|
| `addNodeOperator(string,address)` | [`:283`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L283) | Registers an operator, returns its id. |
| `activateNodeOperator` / `deactivateNodeOperator` | [`:307`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L307), [`:323`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L323) | Toggles participation. |
| `setNodeOperatorName` / `setNodeOperatorRewardAddress` | [`:355`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L355), [`:368`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L368) | Metadata. |
| `setNodeOperatorStakingLimit(uint256,uint64)` | [`:384`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L384) | Sets the vetted count. |
| `decreaseVettedSigningKeysCount(...)` | [`:396`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L396) | Unvetting, driven by the deposit security module. |
| `addSigningKeys(...)` / `addSigningKeysOperatorBH(...)` | [`:964`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L964), [`:978`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L978) | DAO-added versus operator-added ("BH" is behalf). |
| `removeSigningKey(uint256,uint256)` | [`:1010`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L1010) | Removes an undeposited key. |
| `invalidateReadyToDepositKeysRange(uint256,uint256)` | [`:651`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L651) | Bulk unvet. |
| `onWithdrawalCredentialsChanged()` | [`:640`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L640) | Invalidates every undeposited key, since signatures were made against the old credentials. |
| `obtainDepositData(...)` | [`:697`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L697) | Router-only. Allocates and returns keys to deposit. |
| `updateExitedValidatorsCount(...)` | [`:478`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L478) | From the oracle's extra data. |
| `unsafeUpdateValidatorsCount(...)` | [`:547`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L547) | Governance override; the name is the warning. |
| `updateTargetValidatorsLimits(...)` | [`:595`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L595), [`:603`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L603) | Soft or hard cap per operator; two overloads, the second taking a mode. |
| `onRewardsMinted(uint256)` | [`:463`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L463) | Hook after fee minting. |
| `distributeReward()` | [`:526`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L526) | Splits the module's shares among operators. |
| `getRewardsDistribution(uint256)` | [`:903`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L903) | The split, pro rata to active validators. |
| `getNodeOperator(uint256,bool)` | [`:871`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L871) | Full or summary view. |
| `_getSigningKeysAllocationData(uint256)` | [`:774`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L774) | Runs the min-first allocator over operators. |
| `_loadAllocatedSigningKeys(...)` | [`:821`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L821) | Materialises keys and signatures. |
| `_applyNodeOperatorLimits(uint256)` | [`:737`](core/contracts/0.4.24/nos/NodeOperatorsRegistry.sol#L737) | Applies target limits to the depositable count. |

**`onWithdrawalCredentialsChanged` deserves emphasis.** A deposit signature commits
to the withdrawal credentials in force when it was made. Change them and every
unused signature becomes worthless, so the registry throws them all away. It is a
blunt but correct response.

### 12.3 `StakeLimitUtils`

[`core/contracts/0.4.24/lib/StakeLimitUtils.sol`](core/contracts/0.4.24/lib/StakeLimitUtils.sol) — 261 lines.

Packs the whole rate-limit state into one slot (`Data`,
[`:42`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L42)) and provides the
leaky-bucket arithmetic.

| Function | Line | Purpose |
|---|---|---|
| `getStorageStakeLimitStruct` / `setStorageStakeLimitStruct` | [`:66`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L66), [`:80`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L80) | Pack and unpack the slot. |
| `calculateCurrentStakeLimit(Data)` | [`:99`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L99) | `min(maxLimit, prevLimit + blocksPassed · increasePerBlock)`. |
| `isStakingPaused` / `isStakingLimitSet` | [`:116`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L116), [`:123`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L123) | Flags encoded in the same word. |
| `setStakingLimit` / `removeStakingLimit` | [`:134`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L134), [`:176`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L176) | Configuration. |
| `updatePrevStakeLimit` / `setStakeLimitPauseState` | [`:190`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L190), [`:209`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L209) | State transitions. |
| `_constGasLt` / `_constGasMin` / `_constGasMax` / `_saturatingSub` | [`:224`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L224)–[`:257`](core/contracts/0.4.24/lib/StakeLimitUtils.sol#L257) | Branch-free comparisons. |

Those last four are branchless on purpose: constant gas regardless of input, so
the cost of `submit` does not leak information about the limit state and cannot
be gamed by choosing an amount that takes a cheaper path.

### 12.4 `Packed64x4` and `SigningKeys`

[`Packed64x4.sol`](core/contracts/0.4.24/lib/Packed64x4.sol) — 49 lines. Four
`uint64` counters in one word, with `get`
([`:25`](core/contracts/0.4.24/lib/Packed64x4.sol#L25)), `set`
([`:33`](core/contracts/0.4.24/lib/Packed64x4.sol#L33)), `add`
([`:40`](core/contracts/0.4.24/lib/Packed64x4.sol#L40)), `sub`
([`:46`](core/contracts/0.4.24/lib/Packed64x4.sol#L46)). This is why an operator's
four key counters cost one `SSTORE` rather than four.

[`SigningKeys.sol`](core/contracts/0.4.24/lib/SigningKeys.sol) — 179 lines. Keys
are 48 bytes and signatures 96, neither a clean multiple of 32, so storage is
hand-rolled: `getKeyOffset`
([`:24`](core/contracts/0.4.24/lib/SigningKeys.sol#L24)) computes the slot,
`saveKeysSigs` ([`:36`](core/contracts/0.4.24/lib/SigningKeys.sol#L36)),
`removeKeysSigs` ([`:90`](core/contracts/0.4.24/lib/SigningKeys.sol#L90)),
`loadKeysSigs` ([`:149`](core/contracts/0.4.24/lib/SigningKeys.sol#L149)) and
`initKeysSigsBuf` ([`:176`](core/contracts/0.4.24/lib/SigningKeys.sol#L176)) do
the packing with assembly.

### 12.5 `MinFirstAllocationStrategy`

[`core/contracts/common/lib/MinFirstAllocationStrategy.sol`](core/contracts/common/lib/MinFirstAllocationStrategy.sol) — 108 lines.

The allocator used both across modules and across operators within a module. It
fills the **least-full** bucket first, equalising fill factors rather than
distributing proportionally.

`allocate(uint256[] buckets, uint256[] capacities, uint256 allocationSize)`
([`:26`](core/contracts/common/lib/MinFirstAllocationStrategy.sol#L26)) loops
`allocateToBestCandidate` until the budget is spent or nothing more fits. The
docstring works a full example at
[`:14-20`](core/contracts/common/lib/MinFirstAllocationStrategy.sol#L14-L20): with
buckets `[9998, 70, 0]`, capacities `[10000, 101, 100]` and 101 to allocate, it
tops up index 2 by 70, then alternates between 1 and 2 to keep them level,
ending at `[9998, 86, 85]`.

The effect is that a new operator receives deposits until it catches up with the
others, rather than receiving a proportional trickle forever. Note the method
**mutates `buckets` in place** to avoid a second memory allocation, which the
docstring flags at [`:21`](core/contracts/common/lib/MinFirstAllocationStrategy.sol#L21).

---

## 13. `StakingRouter`

[`core/contracts/0.8.25/sr/StakingRouter.sol`](core/contracts/0.8.25/sr/StakingRouter.sol) — 1,191 lines, solc 0.8.25,
with most logic in [`SRLib.sol`](core/contracts/0.8.25/sr/SRLib.sol) — 932 lines,
types in [`SRTypes.sol`](core/contracts/0.8.25/sr/SRTypes.sol) — 281 lines,
storage in [`SRStorage.sol`](core/contracts/0.8.25/sr/SRStorage.sol) — 79 lines,
helpers in [`SRUtils.sol`](core/contracts/0.8.25/sr/SRUtils.sol) — 96 lines,
events and errors in [`ISRBase.sol`](core/contracts/0.8.25/sr/ISRBase.sol) — 101 lines.

The router turns "Lido has N ETH to stake" into "module M deposits it against
these keys". Splitting the implementation into an external library is a
deployed-bytecode-size measure; the router alone would exceed the 24 KB limit.

### 13.1 Roles

Nine, at [`:46-54`](core/contracts/0.8.25/sr/StakingRouter.sol#L46-L54):
`MANAGE_WITHDRAWAL_CREDENTIALS_ROLE`, `STAKING_MODULE_MANAGE_ROLE`,
`STAKING_MODULE_SHARE_MANAGE_ROLE`, `STAKING_MODULE_UNVETTING_ROLE`,
`REPORT_EXITED_VALIDATORS_ROLE`, `REPORT_VALIDATOR_EXITING_STATUS_ROLE`,
`REPORT_VALIDATOR_EXIT_TRIGGERED_ROLE`, `UNSAFE_SET_EXITED_VALIDATORS_ROLE`,
`REPORT_REWARDS_MINTED_ROLE`. These are OpenZeppelin `AccessControl`, unlike the
Aragon roles in `Lido` and the registry.

### 13.2 Module management

| Function | Line | Access |
|---|---|---|
| `addStakingModule(...)` | [`:180`](core/contracts/0.8.25/sr/StakingRouter.sol#L180) | `STAKING_MODULE_MANAGE_ROLE` |
| `updateStakingModule(...)` | [`:201`](core/contracts/0.8.25/sr/StakingRouter.sol#L201) | `STAKING_MODULE_MANAGE_ROLE` |
| `updateAllStakingModulesFees(...)` | [`:226`](core/contracts/0.8.25/sr/StakingRouter.sol#L226) | `STAKING_MODULE_MANAGE_ROLE` |
| `updateModuleShares(uint256,uint16,uint16)` | [`:238`](core/contracts/0.8.25/sr/StakingRouter.sol#L238) | `STAKING_MODULE_SHARE_MANAGE_ROLE`. Sets the stake-share limit and the priority exit threshold. |
| `updateTargetValidatorsLimits(...)` | [`:252`](core/contracts/0.8.25/sr/StakingRouter.sol#L252) | Per-operator caps. |
| `setWithdrawalCredentials(bytes32)` | [`:1003`](core/contracts/0.8.25/sr/StakingRouter.sol#L1003) | `MANAGE_WITHDRAWAL_CREDENTIALS_ROLE`. Cascades `onWithdrawalCredentialsChanged` to every module. |
| `setMaxTopUpPerBlockGwei(uint256)` | [`:1019`](core/contracts/0.8.25/sr/StakingRouter.sol#L1019) | `STAKING_MODULE_MANAGE_ROLE`. New in v3, bounds EIP-7251 top-ups. |

Constants: `MAX_STAKING_MODULES_COUNT`
([`:79`](core/contracts/0.8.25/sr/StakingRouter.sol#L79)),
`MAX_STAKING_MODULE_NAME_LENGTH`
([`:84`](core/contracts/0.8.25/sr/StakingRouter.sol#L84)),
`INITIAL_DEPOSIT_SIZE` ([`:69`](core/contracts/0.8.25/sr/StakingRouter.sol#L69)),
`TOTAL_BASIS_POINTS` ([`:74`](core/contracts/0.8.25/sr/StakingRouter.sol#L74)).

### 13.3 Depositing and allocation

**`deposit(uint256 _stakingModuleId, bytes calldata _depositCalldata)`** —
[`:942`](core/contracts/0.8.25/sr/StakingRouter.sol#L942). Only the deposit
security module. Pulls depositable ether from `Lido`, asks the module for keys,
and submits to the beacon deposit contract.

**`getDepositAllocations(uint256 _depositAmount, bool _isTopUp)`** —
[`:929`](core/contracts/0.8.25/sr/StakingRouter.sol#L929). Runs
`MinFirstAllocationStrategy` across modules, bounded by each module's
`stakeShareLimit`. `_getModuleDepositAllocation`
([`:1064`](core/contracts/0.8.25/sr/StakingRouter.sol#L1064)) is the per-module
step and `getStakingModuleMaxDepositsCount`
([`:649`](core/contracts/0.8.25/sr/StakingRouter.sol#L649)) the cap.

**`topUp(...)`** — [`:679`](core/contracts/0.8.25/sr/StakingRouter.sol#L679), with
`_validateTopUpInputs` at [`:761`](core/contracts/0.8.25/sr/StakingRouter.sol#L761).
New in v3. EIP-7251 raised the maximum effective balance to 2048 ETH, so ETH can
now be added to an existing validator instead of creating a new one. That is
strictly cheaper: no activation queue wait. `maxTopUpPerBlockGwei` rate-limits it.

`receiveDepositableEther()` at [`:665`](core/contracts/0.8.25/sr/StakingRouter.sol#L665)
is the payable entry from `Lido`.

**Deposit pacing.** `getStakingModuleMinDepositBlockDistance`
([`:608`](core/contracts/0.8.25/sr/StakingRouter.sol#L608)) and
`getStakingModuleLastDepositBlock`
([`:600`](core/contracts/0.8.25/sr/StakingRouter.sol#L600)) enforce a gap between
deposits per module. Combined with the guardian attestation in
[§11](#11-depositsecuritymodule-and-depositing), this bounds how much can be lost
to a front-run before guardians can react.

### 13.4 Fees

**`getStakingRewardsDistribution()`** —
[`:808`](core/contracts/0.8.25/sr/StakingRouter.sol#L808). The function
`Accounting` calls in [§6.4](#64-splitting-the-fee). Returns recipients, module
ids, per-module fees, the aggregate, and the precision base.

Supporting: `getStakingFeeAggregateDistribution`
([`:788`](core/contracts/0.8.25/sr/StakingRouter.sol#L788)), its E4-precision
variant ([`:910`](core/contracts/0.8.25/sr/StakingRouter.sol#L910)),
`getTotalFeeE4Precision` ([`:899`](core/contracts/0.8.25/sr/StakingRouter.sol#L899))
and `_computeModuleFee` ([`:885`](core/contracts/0.8.25/sr/StakingRouter.sol#L885)).
The E4 variants exist because `Lido` at 0.4.24 expects `uint16` basis points.

**`reportRewardsMinted(uint256[],uint256[])`** —
[`:266`](core/contracts/0.8.25/sr/StakingRouter.sol#L266). Tells each module how
many shares it received so it can run its own internal split.

### 13.5 Exit and balance reporting

| Function | Line | Role |
|---|---|---|
| `updateExitedValidatorsCountByStakingModule(...)` | [`:276`](core/contracts/0.8.25/sr/StakingRouter.sol#L276) | `REPORT_EXITED_VALIDATORS_ROLE` |
| `reportValidatorBalancesByStakingModule(...)` | [`:285`](core/contracts/0.8.25/sr/StakingRouter.sol#L285) | v3 balance-based accounting |
| `validateReportValidatorBalancesByStakingModule(...)` | [`:293`](core/contracts/0.8.25/sr/StakingRouter.sol#L293) | Dry run |
| `reportStakingModuleExitedValidatorsCountByNodeOperator(...)` | [`:303`](core/contracts/0.8.25/sr/StakingRouter.sol#L303) | Extra-data path |
| `unsafeSetExitedValidatorsCount(...)` | [`:313`](core/contracts/0.8.25/sr/StakingRouter.sol#L313) | `UNSAFE_SET_EXITED_VALIDATORS_ROLE` |
| `onValidatorsCountsByNodeOperatorReportingFinished()` | [`:325`](core/contracts/0.8.25/sr/StakingRouter.sol#L325) | End-of-extra-data hook |
| `decreaseStakingModuleVettedKeysCountByNodeOperator(...)` | [`:332`](core/contracts/0.8.25/sr/StakingRouter.sol#L332) | `STAKING_MODULE_UNVETTING_ROLE`, from the DSM |
| `reportValidatorExitDelay(...)` | [`:343`](core/contracts/0.8.25/sr/StakingRouter.sol#L343) | `REPORT_VALIDATOR_EXITING_STATUS_ROLE` |
| `onValidatorExitTriggered(...)` | [`:356`](core/contracts/0.8.25/sr/StakingRouter.sol#L356) | `REPORT_VALIDATOR_EXIT_TRIGGERED_ROLE` |

### 13.6 Views

`getStakingModules` [`:366`](core/contracts/0.8.25/sr/StakingRouter.sol#L366),
`getStakingModuleIds` [`:408`](core/contracts/0.8.25/sr/StakingRouter.sol#L408),
`getStakingModule` [`:415`](core/contracts/0.8.25/sr/StakingRouter.sol#L415),
`getStakingModulesCount` [`:422`](core/contracts/0.8.25/sr/StakingRouter.sol#L422),
`hasStakingModule` [`:429`](core/contracts/0.8.25/sr/StakingRouter.sol#L429),
`getStakingModuleStatus` [`:436`](core/contracts/0.8.25/sr/StakingRouter.sol#L436),
and the three split state getters `getStakingModuleStateConfig`
[`:379`](core/contracts/0.8.25/sr/StakingRouter.sol#L379),
`getStakingModuleStateDeposits`
[`:387`](core/contracts/0.8.25/sr/StakingRouter.sol#L387) and
`getStakingModuleStateAccounting`
[`:396`](core/contracts/0.8.25/sr/StakingRouter.sol#L396). Digests for UIs:
`getAllStakingModuleDigests` [`:474`](core/contracts/0.8.25/sr/StakingRouter.sol#L474),
`getStakingModuleDigests` [`:483`](core/contracts/0.8.25/sr/StakingRouter.sol#L483).
Balances: `getModuleValidatorsBalance`
[`:876`](core/contracts/0.8.25/sr/StakingRouter.sol#L876) and
`getTotalModulesValidatorsBalance`
[`:881`](core/contracts/0.8.25/sr/StakingRouter.sol#L881).

Withdrawal credentials: `getWithdrawalCredentials`
[`:1012`](core/contracts/0.8.25/sr/StakingRouter.sol#L1012),
`getStakingModuleWithdrawalCredentials`
[`:639`](core/contracts/0.8.25/sr/StakingRouter.sol#L639), and
`_getWithdrawalCredentialsWithType`
[`:1046`](core/contracts/0.8.25/sr/StakingRouter.sol#L1046), which selects between
0x01 and 0x02 forms.

---
