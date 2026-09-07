# Wormhole EVM — Complete Reference

Every Solidity contract and every function in `wormhole/ethereum/contracts`, walked
one at a time. 61 files, 6,477 lines.

The conceptual companion is [`WORMHOLE-DEEP-DIVE.md`](WORMHOLE-DEEP-DIVE.md), which
covers the Solana/Rust side and the guardian network. This document stays on EVM
and stays mechanical: signatures, checks, state writes, byte offsets.

Every `path:line` below was verified with `grep -n` against these exact files.

## Contents

- [0. File inventory](#0-file-inventory)
- [1. The shape of the system](#1-the-shape-of-the-system)
- [2. The VAA, byte by byte](#2-the-vaa-byte-by-byte)
- [3. Core: storage, setters, getters](#3-core-storage-setters-getters)
- [4. Core: `Messages.sol`](#4-core-messagessol)
- [5. Core: `GovernanceStructs.sol`](#5-core-governancestructssol)
- [6. Core: `Governance.sol`](#6-core-governancesol)
- [7. Core: `Implementation`, `Setup`, `Wormhole`, `Shutdown`](#7-core-implementation-setup-wormhole-shutdown)
- [8. Token bridge: storage and roles](#8-token-bridge-storage-and-roles)
- [9. Token bridge: `Bridge.sol` outbound](#9-token-bridge-bridgesol-outbound)
- [10. Token bridge: `Bridge.sol` inbound](#10-token-bridge-bridgesol-inbound)
- [11. Token bridge: payload codecs](#11-token-bridge-payload-codecs)
- [12. Token bridge: `BridgeGovernance.sol`](#12-token-bridge-bridgegovernancesol)
- [13. The wrapped token](#13-the-wrapped-token)
- [14. NFT bridge](#14-nft-bridge)
- [15. `BytesLib`](#15-byteslib)
- [16. Delegated guardians and manager set](#16-delegated-guardians-and-manager-set)
- [17. Custom consistency level](#17-custom-consistency-level)
- [18. Mocks and test contracts](#18-mocks-and-test-contracts)
- [19. Selector tables](#19-selector-tables)
- [20. Storage layouts](#20-storage-layouts)
- [21. Events reference](#21-events-reference)
- [22. Revert decoder](#22-revert-decoder)
- [23. Chain ID registry](#23-chain-id-registry)
- [24. Use-case index](#24-use-case-index)
- [25. Gotchas](#25-gotchas)

---

## 0. File inventory

All 61 `.sol` files. Nothing here is skipped later.

### Core messaging (12 files, 1,152 lines)

| File | Lines | Purpose |
|---|---|---|
| [`ethereum/contracts/Wormhole.sol`](wormhole/ethereum/contracts/Wormhole.sol) | 12 | The ERC-1967 proxy users actually call |
| [`ethereum/contracts/Setup.sol`](wormhole/ethereum/contracts/Setup.sol) | 43 | One-shot constructor-time initializer |
| [`ethereum/contracts/Implementation.sol`](wormhole/ethereum/contracts/Implementation.sol) | 80 | `publishMessage`, the whole outbound surface |
| [`ethereum/contracts/Governance.sol`](wormhole/ethereum/contracts/Governance.sol) | 220 | Five governance handlers |
| [`ethereum/contracts/GovernanceStructs.sol`](wormhole/ethereum/contracts/GovernanceStructs.sol) | 182 | Governance payload parsers |
| [`ethereum/contracts/Messages.sol`](wormhole/ethereum/contracts/Messages.sol) | 218 | VAA parsing, signature verification, quorum |
| [`ethereum/contracts/Getters.sol`](wormhole/ethereum/contracts/Getters.sol) | 55 | Read accessors over `_state` |
| [`ethereum/contracts/Setters.sol`](wormhole/ethereum/contracts/Setters.sol) | 56 | Internal write accessors over `_state` |
| [`ethereum/contracts/State.sol`](wormhole/ethereum/contracts/State.sol) | 52 | `WormholeState` struct + legacy events |
| [`ethereum/contracts/Structs.sol`](wormhole/ethereum/contracts/Structs.sol) | 40 | `Provider`, `GuardianSet`, `Signature`, `VM` |
| [`ethereum/contracts/Shutdown.sol`](wormhole/ethereum/contracts/Shutdown.sol) | 31 | Drop-in implementation that disables publishing |
| [`ethereum/contracts/Migrations.sol`](wormhole/ethereum/contracts/Migrations.sol) | 18 | Truffle migration bookkeeping, not protocol code |

### Core interfaces and libraries (2 files, 652 lines)

| File | Lines | Purpose |
|---|---|---|
| [`ethereum/contracts/interfaces/IWormhole.sol`](wormhole/ethereum/contracts/interfaces/IWormhole.sol) | 142 | The integrator-facing ABI |
| [`ethereum/contracts/libraries/external/BytesLib.sol`](wormhole/ethereum/contracts/libraries/external/BytesLib.sol) | 510 | GNU-LGPL byte slicing, all in assembly |

### Token bridge (22 files, 2,873 lines)

| File | Lines | Purpose |
|---|---|---|
| [`ethereum/contracts/bridge/Bridge.sol`](wormhole/ethereum/contracts/bridge/Bridge.sol) | 960 | Transfers, attestation, pausing, codecs |
| [`ethereum/contracts/bridge/BridgeGovernance.sol`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol) | 264 | Four governance handlers |
| [`ethereum/contracts/bridge/BridgeStructs.sol`](wormhole/ethereum/contracts/bridge/BridgeStructs.sol) | 112 | Seven payload structs |
| [`ethereum/contracts/bridge/BridgeGetters.sol`](wormhole/ethereum/contracts/bridge/BridgeGetters.sol) | 98 | Read accessors |
| [`ethereum/contracts/bridge/BridgeSetters.sol`](wormhole/ethereum/contracts/bridge/BridgeSetters.sol) | 91 | Internal write accessors |
| [`ethereum/contracts/bridge/BridgeState.sol`](wormhole/ethereum/contracts/bridge/BridgeState.sol) | 62 | `BridgeStorage.State` struct |
| [`ethereum/contracts/bridge/BridgePauserStorage.sol`](wormhole/ethereum/contracts/bridge/BridgePauserStorage.sol) | 47 | ERC-7201 namespaced pauser roles |
| [`ethereum/contracts/bridge/BridgeSetup.sol`](wormhole/ethereum/contracts/bridge/BridgeSetup.sol) | 44 | One-shot initializer |
| [`ethereum/contracts/bridge/BridgeImplementation.sol`](wormhole/ethereum/contracts/bridge/BridgeImplementation.sol) | 37 | Upgrade entry point + token beacon |
| [`ethereum/contracts/bridge/BridgeShutdown.sol`](wormhole/ethereum/contracts/bridge/BridgeShutdown.sol) | 36 | Drop-in implementation that disables transfers |
| [`ethereum/contracts/bridge/TokenBridge.sol`](wormhole/ethereum/contracts/bridge/TokenBridge.sol) | 14 | The ERC-1967 proxy |
| [`ethereum/contracts/bridge/token/TokenImplementation.sol`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol) | 351 | The wrapped ERC-20 logic |
| [`ethereum/contracts/bridge/token/TokenState.sol`](wormhole/ethereum/contracts/bridge/token/TokenState.sol) | 63 | Wrapped token storage struct |
| [`ethereum/contracts/bridge/token/Token.sol`](wormhole/ethereum/contracts/bridge/token/Token.sol) | 11 | `BridgeToken`, the beacon proxy |
| [`ethereum/contracts/bridge/utils/Migrator.sol`](wormhole/ethereum/contracts/bridge/utils/Migrator.sol) | 68 | One-off asset migration helper |
| [`ethereum/contracts/bridge/interfaces/ITokenBridge.sol`](wormhole/ethereum/contracts/bridge/interfaces/ITokenBridge.sol) | 233 | Integrator-facing ABI |
| [`ethereum/contracts/bridge/interfaces/IWETH.sol`](wormhole/ethereum/contracts/bridge/interfaces/IWETH.sol) | 10 | `deposit` / `withdraw` |
| [`ethereum/contracts/bridge/mock/MockBridgeImplementation.sol`](wormhole/ethereum/contracts/bridge/mock/MockBridgeImplementation.sol) | 25 | Upgrade test double |
| [`ethereum/contracts/bridge/mock/MockFeeToken.sol`](wormhole/ethereum/contracts/bridge/mock/MockFeeToken.sol) | 177 | Fee-on-transfer ERC-20 for tests |
| [`ethereum/contracts/bridge/mock/MockTokenBridgeIntegration.sol`](wormhole/ethereum/contracts/bridge/mock/MockTokenBridgeIntegration.sol) | 48 | Payload-3 recipient double |
| [`ethereum/contracts/bridge/mock/MockTokenImplementation.sol`](wormhole/ethereum/contracts/bridge/mock/MockTokenImplementation.sol) | 12 | Wrapped-token upgrade double |
| [`ethereum/contracts/bridge/mock/MockWETH9.sol`](wormhole/ethereum/contracts/bridge/mock/MockWETH9.sol) | 81 | WETH double |

### NFT bridge (14 files, 1,261 lines)

| File | Lines | Purpose |
|---|---|---|
| [`ethereum/contracts/nft/NFTBridge.sol`](wormhole/ethereum/contracts/nft/NFTBridge.sol) | 282 | ERC-721 transfer logic |
| [`ethereum/contracts/nft/NFTBridgeGovernance.sol`](wormhole/ethereum/contracts/nft/NFTBridgeGovernance.sol) | 183 | Governance handlers |
| [`ethereum/contracts/nft/NFTBridgeStructs.sol`](wormhole/ethereum/contracts/nft/NFTBridgeStructs.sol) | 67 | Transfer + governance structs |
| [`ethereum/contracts/nft/NFTBridgeGetters.sol`](wormhole/ethereum/contracts/nft/NFTBridgeGetters.sol) | 72 | Read accessors |
| [`ethereum/contracts/nft/NFTBridgeSetters.sol`](wormhole/ethereum/contracts/nft/NFTBridgeSetters.sol) | 67 | Write accessors |
| [`ethereum/contracts/nft/NFTBridgeState.sol`](wormhole/ethereum/contracts/nft/NFTBridgeState.sol) | 61 | Storage struct |
| [`ethereum/contracts/nft/NFTBridgeImplementation.sol`](wormhole/ethereum/contracts/nft/NFTBridgeImplementation.sol) | 61 | Upgrade entry point |
| [`ethereum/contracts/nft/NFTBridgeSetup.sol`](wormhole/ethereum/contracts/nft/NFTBridgeSetup.sol) | 41 | One-shot initializer |
| [`ethereum/contracts/nft/NFTBridgeShutdown.sol`](wormhole/ethereum/contracts/nft/NFTBridgeShutdown.sol) | 30 | Disabled drop-in |
| [`ethereum/contracts/nft/NFTBridgeEntrypoint.sol`](wormhole/ethereum/contracts/nft/NFTBridgeEntrypoint.sol) | 14 | The ERC-1967 proxy |
| [`ethereum/contracts/nft/token/NFTImplementation.sol`](wormhole/ethereum/contracts/nft/token/NFTImplementation.sol) | 254 | Wrapped ERC-721 logic |
| [`ethereum/contracts/nft/token/NFTState.sol`](wormhole/ethereum/contracts/nft/token/NFTState.sol) | 40 | Wrapped NFT storage |
| [`ethereum/contracts/nft/token/NFT.sol`](wormhole/ethereum/contracts/nft/token/NFT.sol) | 10 | `BridgeNFT`, the beacon proxy |
| [`ethereum/contracts/nft/interfaces/INFTBridge.sol`](wormhole/ethereum/contracts/nft/interfaces/INFTBridge.sol) | 107 | Integrator ABI |

Plus two NFT mocks: [`nft/mock/MockNFTBridgeImplementation.sol`](wormhole/ethereum/contracts/nft/mock/MockNFTBridgeImplementation.sol) (21) and [`nft/mock/MockNFTImplementation.sol`](wormhole/ethereum/contracts/nft/mock/MockNFTImplementation.sol) (12).

### Newer modules (7 files, 582 lines)

| File | Lines | Purpose |
|---|---|---|
| [`ethereum/contracts/delegated_guardians/WormholeDelegatedGuardians.sol`](wormhole/ethereum/contracts/delegated_guardians/WormholeDelegatedGuardians.sol) | 248 | Guardians delegating signing authority |
| [`ethereum/contracts/delegated_manager_set/DelegatedManagerSet.sol`](wormhole/ethereum/contracts/delegated_manager_set/DelegatedManagerSet.sol) | 166 | Manager-set delegation registry |
| [`ethereum/contracts/delegated_manager_set/interfaces/IDelegatedManagerSet.sol`](wormhole/ethereum/contracts/delegated_manager_set/interfaces/IDelegatedManagerSet.sol) | 42 | Its ABI |
| [`ethereum/contracts/custom_consistency_level/CustomConsistencyLevel.sol`](wormhole/ethereum/contracts/custom_consistency_level/CustomConsistencyLevel.sol) | 32 | Per-emitter finality config registry |
| [`ethereum/contracts/custom_consistency_level/interfaces/ICustomConsistencyLevel.sol`](wormhole/ethereum/contracts/custom_consistency_level/interfaces/ICustomConsistencyLevel.sol) | 24 | Its ABI |
| [`ethereum/contracts/custom_consistency_level/libraries/ConfigMakers.sol`](wormhole/ethereum/contracts/custom_consistency_level/libraries/ConfigMakers.sol) | 23 | Config word packing |
| [`ethereum/contracts/custom_consistency_level/TestCustomConsistencyLevel.sol`](wormhole/ethereum/contracts/custom_consistency_level/TestCustomConsistencyLevel.sol) | 47 | Example integrator |

### Core mocks (2 files, 70 lines)

[`ethereum/contracts/mock/MockBatchedVAASender.sol`](wormhole/ethereum/contracts/mock/MockBatchedVAASender.sol) (53) publishes several messages in one transaction; [`ethereum/contracts/mock/MockImplementation.sol`](wormhole/ethereum/contracts/mock/MockImplementation.sol) (17) is an upgrade double.

### Audits on file

`wormhole/audits/` holds four PDFs: Neodyme (2022-01), Kudelski (2022-07) and Trail of Bits (2022-09) on the node plus the Solana/Terra/CosmWasm bridges, and Trail of Bits (2023-04) on the node. **None of them covers the EVM contracts in this directory.** The `audits/evm/` subdirectory exists but the EVM-specific reports are not in this tree.

Authoritative naming throughout comes from `wormhole/whitepapers/`, particularly `0001_generic_message_passing.md`, `0002_governance_messaging.md`, `0003_token_bridge.md` and `0004_message_publishing.md`.

---

## 1. The shape of the system

Two independent proxied contracts, deployed once per chain.

```
                    ┌──────────────────────────────────────┐
   integrator  ───► │ TokenBridge (ERC1967Proxy)           │
                    │   └─ delegatecall ─► BridgeImplementation
                    │                        └─ Bridge
                    │                             └─ BridgeGovernance
                    │                                  └─ BridgeGetters/Setters
                    └───────────────┬──────────────────────┘
                                    │ publishMessage()
                                    ▼
                    ┌──────────────────────────────────────┐
   integrator  ───► │ Wormhole (ERC1967Proxy)              │
                    │   └─ delegatecall ─► Implementation  │
                    │                        └─ Governance │
                    │                             └─ Messages (parse/verify)
                    │                                  └─ Getters/Setters/State
                    └──────────────────────────────────────┘
                                    │
                              LogMessagePublished
                                    │
                              (guardians observe off-chain,
                               sign, produce a VAA)
                                    │
                                    ▼
                          verifyVM on the destination chain
```

The core contract does exactly two things on chain: it emits an event with a
per-emitter sequence number, and it verifies signatures on VAAs coming back. It
never moves value. Everything else — the guardian network, the VAA assembly, the
relaying — happens off chain.

The inheritance linearization matters because storage layout depends on it.

| Contract | Linearization (most-base first) |
|---|---|
| `Implementation` | `State` → `Setters`/`Getters` → `Messages` → `GovernanceStructs` → `Governance` → `Implementation` |
| `Bridge` | `BridgeState` → `BridgeGetters`/`BridgeSetters` → `BridgeGovernance` → `Bridge` → `ReentrancyGuard` |
| `BridgeImplementation` | everything in `Bridge`, plus its own `initializer` |

`Bridge` inherits `ReentrancyGuard` **last**, which is why
[`BridgeShutdown.sol:25`](wormhole/ethereum/contracts/bridge/BridgeShutdown.sol#L25)
also inherits it despite never using it. The comment at
[`:19-23`](wormhole/ethereum/contracts/bridge/BridgeShutdown.sol#L19-L23) says so
outright: the guard adds a storage variable, and a drop-in replacement
implementation must not shift the layout.

---
