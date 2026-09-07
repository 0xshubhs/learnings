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

## 2. The VAA, byte by byte

A VAA (Verifiable Action Approval) is the only thing that crosses chains. It is a
guardian-signed attestation that some emitter published some payload. The layout
is not declared anywhere as a struct — it exists only as the sequence of reads in
[`Messages.parseVM`](wormhole/ethereum/contracts/Messages.sol#L147-L208), so that
function *is* the specification.

### Envelope

| Offset | Size | Field | Parsed at |
|---|---|---|---|
| `0` | 1 | `version`, must equal 1 | [`:150`](wormhole/ethereum/contracts/Messages.sol#L150) |
| `1` | 4 | `guardianSetIndex` | [`:159`](wormhole/ethereum/contracts/Messages.sol#L159) |
| `5` | 1 | `signersLen` (n) | [`:163`](wormhole/ethereum/contracts/Messages.sol#L163) |
| `6` | 66·n | signature array | [`:166-176`](wormhole/ethereum/contracts/Messages.sol#L166-L176) |

Each signature is 66 bytes:

| Rel. offset | Size | Field |
|---|---|---|
| `+0` | 1 | `guardianIndex` |
| `+1` | 32 | `r` |
| `+33` | 32 | `s` |
| `+65` | 1 | `v`, **stored as `v + 27`** ([`:174`](wormhole/ethereum/contracts/Messages.sol#L174)) |

### Body

The body begins at `6 + 66n`. Call that `B`.

| Offset | Size | Field | Parsed at |
|---|---|---|---|
| `B+0` | 4 | `timestamp` | [`:189`](wormhole/ethereum/contracts/Messages.sol#L189) |
| `B+4` | 4 | `nonce` | [`:192`](wormhole/ethereum/contracts/Messages.sol#L192) |
| `B+8` | 2 | `emitterChainId` | [`:195`](wormhole/ethereum/contracts/Messages.sol#L195) |
| `B+10` | 32 | `emitterAddress` | [`:198`](wormhole/ethereum/contracts/Messages.sol#L198) |
| `B+42` | 8 | `sequence` | [`:201`](wormhole/ethereum/contracts/Messages.sol#L201) |
| `B+50` | 1 | `consistencyLevel` | [`:204`](wormhole/ethereum/contracts/Messages.sol#L204) |
| `B+51` | rest | `payload` | [`:207`](wormhole/ethereum/contracts/Messages.sol#L207) |

So the body header is exactly **51 bytes**, and a minimal VAA with one signature
is `6 + 66 + 51 = 123` bytes plus payload.

### The hash is doubled

```solidity
bytes memory body = encodedVM.slice(index, encodedVM.length - index);
vm.hash = keccak256(abi.encodePacked(keccak256(body)));
```

[`Messages.sol:185-186`](wormhole/ethereum/contracts/Messages.sol#L185-L186). The
double `keccak256` is what guardians sign, and it is what integrators use for
replay protection. The comment at
[`:181-183`](wormhole/ethereum/contracts/Messages.sol#L181-L183) forbids changing
it for exactly that reason.

**`version` is outside the hash.** The comment at
[`:152-156`](wormhole/ethereum/contracts/Messages.sol#L152-L156) is unusually
candid: the version byte's integrity is not protected and cannot be trusted. It
is harmless today because only version 1 is accepted at
[`:157`](wormhole/ethereum/contracts/Messages.sol#L157), but it would become a
problem the moment a second version is allowed.

---

## 3. Core: storage, setters, getters

### `Structs.sol` — [4 structs](wormhole/ethereum/contracts/Structs.sol#L6-L39)

An `interface` used purely as a type namespace.

| Struct | Fields |
|---|---|
| `Provider` ([`:7-11`](wormhole/ethereum/contracts/Structs.sol#L7-L11)) | `chainId`, `governanceChainId`, `governanceContract` |
| `GuardianSet` ([`:13-16`](wormhole/ethereum/contracts/Structs.sol#L13-L16)) | `address[] keys`, `uint32 expirationTime` |
| `Signature` ([`:18-23`](wormhole/ethereum/contracts/Structs.sol#L18-L23)) | `r`, `s`, `v`, `guardianIndex` |
| `VM` ([`:25-39`](wormhole/ethereum/contracts/Structs.sol#L25-L39)) | the parsed VAA, including the computed `hash` |

### `State.sol` — [`WormholeState`](wormhole/ethereum/contracts/State.sol#L22-L47)

| Slot | Field | Notes |
|---|---|---|
| 0–2 | `provider` | `chainId`+`governanceChainId` pack into slot 0; `governanceContract` takes slot 1 |
| 3 | `guardianSets` mapping | `uint32 => GuardianSet` |
| 4 | `guardianSetIndex` + `guardianSetExpiry` | both `uint32`, packed |
| 5 | `sequences` mapping | `address => uint64` |
| 6 | `consumedGovernanceActions` mapping | `bytes32 => bool` |
| 7 | `initializedImplementations` mapping | `address => bool` |
| 8 | `messageFee` | |
| 9 | `evmChainId` | EIP-155 id, used for fork detection |

`State` itself ([`:50-52`](wormhole/ethereum/contracts/State.sol#L50-L52)) is one
contract holding one `WormholeState _state`. The `Events` contract at
[`:8-19`](wormhole/ethereum/contracts/State.sol#L8-L19) declares
`LogGuardianSetChanged` and a legacy `LogMessagePublished` that **nothing emits** —
the live event is redeclared in `Implementation`.

### `Setters.sol` — 11 internal writers

All `internal`. Two carry checks worth naming.

| Function | Line | Note |
|---|---|---|
| `updateGuardianSetIndex(uint32)` | [`:9`](wormhole/ethereum/contracts/Setters.sol#L9) | |
| `expireGuardianSet(uint32)` | [`:13`](wormhole/ethereum/contracts/Setters.sol#L13) | Sets expiry to `block.timestamp + 86400`, a fixed 24-hour grace |
| `storeGuardianSet(GuardianSet,uint32)` | [`:17`](wormhole/ethereum/contracts/Setters.sol#L17) | Loops every key rejecting `address(0)` with `"Invalid key"` ([`:20`](wormhole/ethereum/contracts/Setters.sol#L20)). Critical: `ecrecover` returns `address(0)` on failure, so a zero key would validate garbage |
| `setInitialized(address)` | [`:25`](wormhole/ethereum/contracts/Setters.sol#L25) | Parameter is misspelled `implementatiom` in the source |
| `setGovernanceActionConsumed(bytes32)` | [`:29`](wormhole/ethereum/contracts/Setters.sol#L29) | |
| `setChainId(uint16)` | [`:33`](wormhole/ethereum/contracts/Setters.sol#L33) | |
| `setGovernanceChainId(uint16)` | [`:37`](wormhole/ethereum/contracts/Setters.sol#L37) | |
| `setGovernanceContract(bytes32)` | [`:41`](wormhole/ethereum/contracts/Setters.sol#L41) | |
| `setMessageFee(uint256)` | [`:45`](wormhole/ethereum/contracts/Setters.sol#L45) | |
| `setNextSequence(address,uint64)` | [`:49`](wormhole/ethereum/contracts/Setters.sol#L49) | |
| `setEvmChainId(uint256)` | [`:53`](wormhole/ethereum/contracts/Setters.sol#L53) | `require(evmChainId == block.chainid, "invalid evmChainId")` — you cannot set it to a lie |

### `Getters.sol` — 11 public readers

Plain accessors over `_state`, except one piece of real logic:

```solidity
function isFork() public view returns (bool) {
    return evmChainId() != block.chainid;
}
```

[`Getters.sol:37-39`](wormhole/ethereum/contracts/Getters.sol#L37-L39). This is
the whole fork-detection mechanism. If the chain hard-forks, the stored
`evmChainId` no longer matches `block.chainid`, and every governance path that
checks `isFork()` shuts itself off. It is the reason a replayed governance VAA
cannot be used to drain a forked chain.

The rest: `getGuardianSet` [`:9`](wormhole/ethereum/contracts/Getters.sol#L9),
`getCurrentGuardianSetIndex` [`:13`](wormhole/ethereum/contracts/Getters.sol#L13),
`getGuardianSetExpiry` [`:17`](wormhole/ethereum/contracts/Getters.sol#L17),
`governanceActionIsConsumed` [`:21`](wormhole/ethereum/contracts/Getters.sol#L21),
`isInitialized` [`:25`](wormhole/ethereum/contracts/Getters.sol#L25),
`chainId` [`:29`](wormhole/ethereum/contracts/Getters.sol#L29),
`evmChainId` [`:33`](wormhole/ethereum/contracts/Getters.sol#L33),
`governanceChainId` [`:41`](wormhole/ethereum/contracts/Getters.sol#L41),
`governanceContract` [`:45`](wormhole/ethereum/contracts/Getters.sol#L45),
`messageFee` [`:49`](wormhole/ethereum/contracts/Getters.sol#L49),
`nextSequence` [`:53`](wormhole/ethereum/contracts/Getters.sol#L53).

---

## 4. Core: `Messages.sol`

Five functions. This contract is the security boundary of the entire protocol.

### `parseAndVerifyVM(bytes calldata) public view` — [`:16`](wormhole/ethereum/contracts/Messages.sol#L16)

Returns `(VM vm, bool valid, string reason)`. Parses, then verifies with
`checkHash = false`.

The `false` is safe and deliberate: `parseVM` computed `vm.hash` itself from the
raw bytes at [`:186`](wormhole/ethereum/contracts/Messages.sol#L186), so
re-deriving it would be redundant. The comment at
[`:18`](wormhole/ethereum/contracts/Messages.sol#L18) says exactly that.

**This is the function integrators should call.** It never reverts on an invalid
VAA; it returns `valid = false` and a reason string.

### `verifyVM(VM memory) public view` — [`:30`](wormhole/ethereum/contracts/Messages.sol#L30)

Delegates to `verifyVMInternal(vm, true)`. The `true` is load-bearing: a caller
who hands over a hand-built `VM` struct could otherwise supply a legitimately
signed `hash` alongside a completely different body. The warning at
[`:46-48`](wormhole/ethereum/contracts/Messages.sol#L46-L48) spells out that
attack.

### `verifyVMInternal(VM memory, bool) internal view` — [`:40`](wormhole/ethereum/contracts/Messages.sol#L40)

Five checks, in order. Each returns `(false, reason)` rather than reverting.

| # | Check | Line | Reason string |
|---|---|---|---|
| 1 | If `checkHash`, recompute `keccak256(keccak256(body))` from the struct fields and compare | [`:50-66`](wormhole/ethereum/contracts/Messages.sol#L50-L66) | `"vm.hash doesn't match body"` |
| 2 | Guardian set is non-empty | [`:75-77`](wormhole/ethereum/contracts/Messages.sol#L75-L77) | `"invalid guardian set"` |
| 3 | Set is current, or not yet expired | [`:80-82`](wormhole/ethereum/contracts/Messages.sol#L80-L82) | `"guardian set has expired"` |
| 4 | `signatures.length >= quorum(keys.length)` | [`:90-92`](wormhole/ethereum/contracts/Messages.sol#L90-L92) | `"no quorum"` |
| 5 | Every signature recovers to the right guardian | [`:95-98`](wormhole/ethereum/contracts/Messages.sol#L95-L98) | forwarded from `verifySignatures` |

Check 2 exists specifically to stop the degenerate case the comment at
[`:69-73`](wormhole/ethereum/contracts/Messages.sol#L69-L73) describes: an empty
key set with an empty signature set would sail through quorum arithmetic.

The body reconstruction in check 1 uses `abi.encodePacked` over seven fields at
[`:51-59`](wormhole/ethereum/contracts/Messages.sol#L51-L59), matching the wire
layout in §2 exactly.

### `verifySignatures(bytes32, Signature[], GuardianSet) public pure` — [`:111`](wormhole/ethereum/contracts/Messages.sol#L111)

The docblock at [`:106-110`](wormhole/ethereum/contracts/Messages.sol#L106-L110)
is a warning label: this function does **not** check quorum, does **not** check
expiry, and **returns true for an empty signature set**. Calling it directly
instead of `verifyVM` is a way to accept anything.

Per signature:

1. `ecrecover` the hash, and `require(signatory != address(0), "ecrecover failed with signature")` at [`:119`](wormhole/ethereum/contracts/Messages.sol#L119). Required because `ecrecover` signals failure by returning zero, which is also the default storage value.
2. `require(i == 0 || sig.guardianIndex > lastIndex, "signature indices must be ascending")` at [`:122`](wormhole/ethereum/contracts/Messages.sol#L122). **Strictly** ascending, which is what makes duplicate-signature attacks impossible: you cannot present the same guardian twice to fake quorum.
3. `require(sig.guardianIndex < guardianCount, "guardian index out of bounds")` at [`:131`](wormhole/ethereum/contracts/Messages.sol#L131). The comment at [`:125-130`](wormhole/ethereum/contracts/Messages.sol#L125-L130) concedes this is redundant with the array bounds check that follows, and keeps it anyway as defence against future refactoring.
4. Compare against `guardianSet.keys[sig.guardianIndex]`; mismatch returns `"VM signature invalid"` at [`:135`](wormhole/ethereum/contracts/Messages.sol#L135).

### `parseVM(bytes memory) public pure virtual` — [`:147`](wormhole/ethereum/contracts/Messages.sol#L147)

Pure decoding, no validation beyond `version == 1`. Layout in §2. Marked `virtual`
so `Shutdown` and mocks can override.

### `quorum(uint) public pure virtual` — [`:213`](wormhole/ethereum/contracts/Messages.sol#L213)

```solidity
require(numGuardians < 256, "too many guardians");
return ((numGuardians * 2) / 3) + 1;
```

Integer arithmetic gives the ceiling of two-thirds plus one. For the mainnet set
of 19 guardians: `(19*2)/3 + 1 = 12 + 1 = 13`. The `< 256` bound exists because
`guardianIndex` is a `uint8`.

| Guardians | Quorum |
|---|---|
| 1 | 1 |
| 3 | 3 |
| 7 | 5 |
| 13 | 9 |
| 19 | 13 |
| 255 | 171 |

---

## 5. Core: `GovernanceStructs.sol`

Five payload parsers, one per governance action. Every one follows the same
shape: read fields sequentially, assert the action byte, and finish with
`require(encoded.length == index, ...)` so trailing bytes are rejected.

The governance header is `module(32) | action(1) | chain(2)` for actions 1–4.
**Action 5 has no `chain` field** — see below.

### Payload layouts

**`ContractUpgrade`, action 1** — parser [`:64`](wormhole/ethereum/contracts/GovernanceStructs.sol#L64), total 67 bytes

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 1, asserted [`:73`](wormhole/ethereum/contracts/GovernanceStructs.sol#L73) |
| `33` | 2 | `chain` |
| `35` | 32 | `newContract`, truncated to `address` at [`:78`](wormhole/ethereum/contracts/GovernanceStructs.sol#L78) |

The truncation at `:78` is `address(uint160(uint256(...)))` — a **silent** truncation.
Unlike the token bridge's `_truncateAddress`, it does not reject non-zero high
bytes. A malformed governance VAA would upgrade to a wrong address rather than
revert. That is tolerable only because the payload is guardian-signed.

**`GuardianSetUpgrade`, action 2** — parser [`:85`](wormhole/ethereum/contracts/GovernanceStructs.sol#L85), total `40 + 20n` bytes

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 2, asserted [`:94`](wormhole/ethereum/contracts/GovernanceStructs.sol#L94) |
| `33` | 2 | `chain` |
| `35` | 4 | `newGuardianSetIndex` |
| `39` | 1 | `guardianLength` (n) |
| `40` | 20·n | guardian addresses, read via `toAddress` [`:111`](wormhole/ethereum/contracts/GovernanceStructs.sol#L111) |

Note guardians are **20 bytes each**, not 32. `expirationTime` is hardcoded to 0
at [`:107`](wormhole/ethereum/contracts/GovernanceStructs.sol#L107); expiry is set
later by `expireGuardianSet` on the *outgoing* set.

**`SetMessageFee`, action 3** — parser [`:119`](wormhole/ethereum/contracts/GovernanceStructs.sol#L119), total 67 bytes

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 3 |
| `33` | 2 | `chain` |
| `35` | 32 | `messageFee` |

**`TransferFees`, action 4** — parser [`:140`](wormhole/ethereum/contracts/GovernanceStructs.sol#L140), total 99 bytes

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 4 |
| `33` | 2 | `chain` |
| `35` | 32 | `amount` |
| `67` | 32 | `recipient` |

**`RecoverChainId`, action 5** — parser [`:164`](wormhole/ethereum/contracts/GovernanceStructs.sol#L164), total 67 bytes

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 5 |
| `33` | 32 | `evmChainId` |
| `65` | 2 | `newChainId` |

**This one breaks the header pattern**: there is no `chain` field, because the
whole point is that the contract's stored `chainId` is currently wrong. The
struct at [`:55-61`](wormhole/ethereum/contracts/GovernanceStructs.sol#L55-L61)
declares only `module` and `action` in its header. Targeting is done instead by
matching `evmChainId` against `block.chainid`.

The `GovernanceAction` enum at
[`:16-19`](wormhole/ethereum/contracts/GovernanceStructs.sol#L16-L19) lists only
two of the five actions and is not used by any parser. Dead code.

---

## 6. Core: `Governance.sol`

Abstract, inherits `GovernanceStructs`, `Messages`, `Setters`, `ERC1967Upgrade`.

Module constant at [`:22`](wormhole/ethereum/contracts/Governance.sol#L22):

```solidity
bytes32 constant module = 0x00000000000000000000000000000000000000000000000000000000436f7265;
```

`0x436f7265` is ASCII `"Core"`, left-padded to 32 bytes.

### `verifyGovernanceVM(VM memory) internal view` — [`:190`](wormhole/ethereum/contracts/Governance.sol#L190)

The gate every handler passes through. Four checks after `verifyVM`:

| Check | Line | Reason |
|---|---|---|
| VAA is valid | [`:192-195`](wormhole/ethereum/contracts/Governance.sol#L192-L195) | forwarded |
| Signed by the **current** guardian set, not merely an unexpired one | [`:198-200`](wormhole/ethereum/contracts/Governance.sol#L198-L200) | `"not signed by current guardian set"` |
| `emitterChainId == governanceChainId()` | [`:203-205`](wormhole/ethereum/contracts/Governance.sol#L203-L205) | `"wrong governance chain"` |
| `emitterAddress == governanceContract()` | [`:208-210`](wormhole/ethereum/contracts/Governance.sol#L208-L210) | `"wrong governance contract"` |
| Not already consumed | [`:214-216`](wormhole/ethereum/contracts/Governance.sol#L214-L216) | `"governance action already consumed"` |

The stricter current-set requirement is deliberate. A normal transfer VAA stays
valid for 24 hours after a guardian rotation; a governance VAA does not.

### The five handlers

All are `public` and permissionless — anyone may submit a validly signed VAA.

| Function | Line | Fork guard | Chain check |
|---|---|---|---|
| `submitContractUpgrade` | [`:27`](wormhole/ethereum/contracts/Governance.sol#L27) | `require(!isFork(), "invalid fork")` [`:28`](wormhole/ethereum/contracts/Governance.sol#L28) | `chain == chainId()` |
| `submitSetMessageFee` | [`:54`](wormhole/ethereum/contracts/Governance.sol#L54) | inline `&& !isFork()` [`:67`](wormhole/ethereum/contracts/Governance.sol#L67) | `chain == chainId()` |
| `submitNewGuardianSet` | [`:79`](wormhole/ethereum/contracts/Governance.sol#L79) | inline [`:92`](wormhole/ethereum/contracts/Governance.sol#L92) | `chain == chainId()` **or `chain == 0`** |
| `submitTransferFees` | [`:117`](wormhole/ethereum/contracts/Governance.sol#L117) | inline [`:131`](wormhole/ethereum/contracts/Governance.sol#L131) | `chain == chainId()` **or `chain == 0`** |
| `submitRecoverChainId` | [`:146`](wormhole/ethereum/contracts/Governance.sol#L146) | `require(isFork(), "not a fork")` [`:147`](wormhole/ethereum/contracts/Governance.sol#L147) — **inverted** | `evmChainId == block.chainid` |

`chain == 0` means "all chains", used for guardian rotations and fee sweeps that
should apply everywhere from one signed payload.

Each handler sets `setGovernanceActionConsumed(vm.hash)` **before** acting, which
is the replay and reentrancy guard. In `submitTransferFees` that ordering matters
concretely: [`:134`](wormhole/ethereum/contracts/Governance.sol#L134) marks
consumed, then [`:140`](wormhole/ethereum/contracts/Governance.sol#L140) does
`recipient.transfer(transfer.amount)`. The `.transfer` caps gas at 2300, and the
consumed flag is already written, so a reentrant recipient gains nothing.

`submitNewGuardianSet` carries two extra invariants:

```solidity
require(upgrade.newGuardianSet.keys.length > 0, "new guardian set is empty");
require(upgrade.newGuardianSetIndex == getCurrentGuardianSetIndex() + 1,
        "index must increase in steps of 1");
```

[`:96`](wormhole/ethereum/contracts/Governance.sol#L96) and
[`:99`](wormhole/ethereum/contracts/Governance.sol#L99). The strict `+1` prevents
gaps in the index space, so an old VAA referencing an unset index can never
resolve. The order of operations then matters: expire the outgoing set
[`:105`](wormhole/ethereum/contracts/Governance.sol#L105), store the new one
[`:108`](wormhole/ethereum/contracts/Governance.sol#L108), and only then make it
current [`:111`](wormhole/ethereum/contracts/Governance.sol#L111).

### `upgradeImplementation(address) internal` — [`:174`](wormhole/ethereum/contracts/Governance.sol#L174)

`_upgradeTo`, then `delegatecall` into `initialize()` on the new implementation,
`require(success, string(reason))`, then emit `ContractUpgraded`. The delegatecall
is why every implementation must expose an `initialize()` even when it does
nothing — see `Shutdown` below.

---

## 7. Core: `Implementation`, `Setup`, `Wormhole`, `Shutdown`

### `Implementation.sol` — the outbound surface

`publishMessage(uint32 nonce, bytes payload, uint8 consistencyLevel) public payable`
at [`:15`](wormhole/ethereum/contracts/Implementation.sol#L15) is the entire
sending API of Wormhole.

1. `require(msg.value == messageFee(), "invalid fee")` — [`:21`](wormhole/ethereum/contracts/Implementation.sol#L21). Exact equality, not `>=`. Overpaying reverts.
2. `sequence = useSequence(msg.sender)` — reads then increments the per-emitter counter, [`:28-31`](wormhole/ethereum/contracts/Implementation.sol#L28-L31).
3. Emit `LogMessagePublished(msg.sender, sequence, nonce, payload, consistencyLevel)` — [`:25`](wormhole/ethereum/contracts/Implementation.sol#L25).

That is all. No storage of the message, no verification, no callback. The
guardians watch the log. Note that `sequence` is returned *before* increment, so
the first message from any emitter is sequence 0.

`initialize()` at [`:33`](wormhole/ethereum/contracts/Implementation.sol#L33) is a
one-time backfill that maps Wormhole chain ids to EIP-155 ids for 16 chains
([`:40-58`](wormhole/ethereum/contracts/Implementation.sol#L40-L58)), reverting
`"Unknown chain id."` otherwise. It only runs when `evmChainId() == 0`.

The `initializer` modifier at
[`:64-75`](wormhole/ethereum/contracts/Implementation.sol#L64-L75) keys off
`isInitialized(_getImplementation())`, so each implementation address can
initialize exactly once.

Both `fallback` and `receive` revert:
[`:77`](wormhole/ethereum/contracts/Implementation.sol#L77) with `"unsupported"`,
[`:79`](wormhole/ethereum/contracts/Implementation.sol#L79) with
`"the Wormhole contract does not accept assets"`. The core contract holds ETH only
from message fees, and there is no way to send it any other way.

### `Setup.sol` — [`setup(...)`](wormhole/ethereum/contracts/Setup.sol#L12)

Called once through the proxy constructor. Stores the initial guardian set at
index 0, the chain ids, the governance emitter, then `_upgradeTo(implementation)`
and `setInitialized`.

`require(initialGuardians.length > 0, "no guardians specified")` at
[`:20`](wormhole/ethereum/contracts/Setup.sol#L20). **`setup` is otherwise
unprotected** — it has no access control at all. It is safe only because it runs
inside `ERC1967Proxy`'s constructor with the setup contract as the initial
implementation, and afterwards the proxy points elsewhere. Calling `setup` on the
bare Setup contract affects only that contract's own useless storage.

### `Wormhole.sol` — [`ERC1967Proxy`](wormhole/ethereum/contracts/Wormhole.sol#L8-L12)

Twelve lines. Constructor takes `(address setup, bytes initData)` and hands both
to OpenZeppelin. This is the address integrators hold.

### `Shutdown.sol` — the kill switch

Inherits `Governance` but adds nothing. Because it does not inherit
`Implementation`, `publishMessage` **does not exist** on it — calls hit the
`fallback` and revert. Governance still works, so the DAO can upgrade back out.

`initialize()` at [`:22-30`](wormhole/ethereum/contracts/Shutdown.sol#L22-L30)
deliberately omits the `initializer` modifier. The comment at
[`:27-29`](wormhole/ethereum/contracts/Shutdown.sol#L27-L29) explains: the chain
may need to be shut down more than once, and each upgrade calls `initialize`.

### `Migrations.sol`

Truffle scaffolding: an `owner`, a `last_completed_migration`, and a `restricted`
modifier. Not part of the protocol.

---

## 8. Token bridge: storage and roles

### `BridgeState.sol` — [`BridgeStorage.State`](wormhole/ethereum/contracts/bridge/BridgeState.sol#L28-L57)

| Slot | Field | Notes |
|---|---|---|
| 0 | `wormhole` | `address payable` |
| 1 | `tokenImplementation` | beacon target for wrapped tokens |
| 2–4 | `provider` | see below |
| 5 | `consumedGovernanceActions` | `bytes32 => bool` |
| 6 | `completedTransfers` | `bytes32 => bool`, keyed by VAA hash |
| 7 | `initializedImplementations` | |
| 8 | `wrappedAssets` | `uint16 => bytes32 => address` |
| 9 | `isWrappedAsset` | `address => bool` |
| 10 | `outstandingBridged` | `address => uint256` |
| 11 | `bridgeImplementations` | `uint16 => bytes32`, the peer registry |
| 12 | `evmChainId` | |
| 13 | `_status` | inherited from `ReentrancyGuard` |

The `Provider` struct at
[`:9-21`](wormhole/ethereum/contracts/bridge/BridgeState.sol#L9-L21) packs
`chainId(16) | governanceChainId(16) | finality(8) | paused(bool)` into one slot,
then `governanceContract(32)` and `WETH(address)`. The comment at
[`:14-17`](wormhole/ethereum/contracts/bridge/BridgeState.sol#L14-L17) explains
why `paused` lives here rather than with the other pause fields: the
`notPaused` check then rides along on the `SLOAD` that already fetches `chainId`
on every entry point.

### `BridgePauserStorage.sol` — ERC-7201 namespaced

The pauser roles live in their own namespace rather than in `State`, so adding
them did not shift `_status` at slot 13 on an in-place upgrade. That reasoning is
written out at
[`:5-12`](wormhole/ethereum/contracts/bridge/BridgePauserStorage.sol#L5-L12).

```solidity
bytes32 internal constant LAYOUT_SLOT =
    0x685f7dd8ace9c4fb94a4997fcd733e0d769273ee87b95731641e14d0cc4a6700;
```

[`:38-39`](wormhole/ethereum/contracts/bridge/BridgePauserStorage.sol#L38-L39),
derived per ERC-7201 from `"wormhole.tokenbridge.pauser.storage"`.

Layout: `pauser`, `unpauser`, `freezer`, `uint64 pauseExpiry`. The comment at
[`:22-25`](wormhole/ethereum/contracts/bridge/BridgePauserStorage.sol#L22-L25)
flags that `freezer` and `pauseExpiry` were **appended**, so the struct field
order deliberately differs from the wire order in the governance payload
(`pauser, freezer, unpauser`).

### The three-role pause system

| Role | Function | Effect | Idempotent |
|---|---|---|---|
| `pauser` | [`pause()`](wormhole/ethereum/contracts/bridge/Bridge.sol#L156) | `pauseExpiry = now + 5 days` | No — each call extends |
| `freezer` | [`freeze()`](wormhole/ethereum/contracts/bridge/Bridge.sol#L176) | `pauseExpiry = type(uint64).max` | Yes |
| `unpauser` | [`unpause()`](wormhole/ethereum/contracts/bridge/Bridge.sol#L191) | clears, sets expiry to now | — |
| anyone | [`unpauseExpired()`](wormhole/ethereum/contracts/bridge/Bridge.sol#L212) | clears, only after expiry | — |

`PAUSE_DURATION` is 5 days at
[`:127`](wormhole/ethereum/contracts/bridge/Bridge.sol#L127). The design is a
dead-man's switch: a `pause` lapses on its own unless the pauser keeps renewing
it, and anyone can then call `unpauseExpired`. A `freeze` sets expiry to the
`uint64` maximum, so in practice only the unpauser can lift it.

`_requireRole(address role, bytes4 err)` at
[`:134-141`](wormhole/ethereum/contracts/bridge/Bridge.sol#L134-L141) checks
`role == address(0) || msg.sender != role` and reverts via raw assembly. The
zero-check comes **first** so an unassigned role is never authorized — otherwise
a caller from `address(0)` would pass, which matters more than it sounds given
how many chains have odd precompile behaviour.

`pause()` also refuses to *shorten* an existing hold:

```solidity
if (newExpiry <= pauseExpiry()) revert PauseNotExtended();
```

[`:162`](wormhole/ethereum/contracts/bridge/Bridge.sol#L162). A lower-trust pauser
cannot curtail a freezer's hold, and a no-op call fails loudly instead of
emitting a misleading `Paused` event.

Both `pause` and `freeze` intentionally skip the `isFork()` check. The rationale
at [`:152-155`](wormhole/ethereum/contracts/bridge/Bridge.sol#L152-L155): on a
forked chain you want the key-holder to be able to shut the bridge immediately,
without first waiting for a chain-id recovery VAA.

### Getters and setters

`BridgeGetters` ([98 lines](wormhole/ethereum/contracts/bridge/BridgeGetters.sol))
exposes 18 readers, including the four pause readers at
[`:79-97`](wormhole/ethereum/contracts/bridge/BridgeGetters.sol#L79-L97) which
reach into the namespaced storage. `isFork()` at
[`:39-41`](wormhole/ethereum/contracts/bridge/BridgeGetters.sol#L39-L41) mirrors
the core.

`BridgeSetters` ([91 lines](wormhole/ethereum/contracts/bridge/BridgeSetters.sol))
has 16 writers. Two carry checks: `setTokenImplementation` rejects the zero
address with `InvalidImplementationAddress` at
[`:42`](wormhole/ethereum/contracts/bridge/BridgeSetters.sol#L42), and
`setEvmChainId` requires equality with `block.chainid` at
[`:68`](wormhole/ethereum/contracts/bridge/BridgeSetters.sol#L68).

`setWrappedAsset` at
[`:54-57`](wormhole/ethereum/contracts/bridge/BridgeSetters.sol#L54-L57) writes
**both** the forward mapping and the `isWrappedAsset` flag, which is what lets
`_transferTokens` distinguish burn-side from lock-side tokens in one `SLOAD`.

---

## 9. Token bridge: `Bridge.sol` outbound

### `attestToken(address, uint32) public payable notPaused` — [`:222`](wormhole/ethereum/contracts/bridge/Bridge.sol#L222)

Publishes an `AssetMeta` (payload 2) so other chains can create a wrapper.

Reads `decimals()`, `symbol()` and `name()` by `staticcall` at
[`:224-226`](wormhole/ethereum/contracts/bridge/Bridge.sol#L224-L226) rather than
by interface call, because none of the three is in the core ERC-20 standard. It
then grabs the first 32 bytes of each string via assembly at
[`:235-239`](wormhole/ethereum/contracts/bridge/Bridge.sol#L235-L239):

```solidity
assembly {
    // first 32 bytes hold string length
    symbol := mload(add(symbolString, 32))
    name := mload(add(nameString, 32))
}
```

**Names and symbols longer than 32 bytes are silently truncated.** There is no
check. A token called something long crosses the bridge with a clipped name.

Note the return values of the three staticcalls are discarded — only the data is
kept. A token without `decimals()` produces empty returndata and the
`abi.decode` at [`:228`](wormhole/ethereum/contracts/bridge/Bridge.sol#L228)
reverts, which is the intended outcome but arrives as a decode failure rather than
a clear error.

### `normalizeAmount` / `deNormalizeAmount` — [`:472`](wormhole/ethereum/contracts/bridge/Bridge.sol#L472), [`:479`](wormhole/ethereum/contracts/bridge/Bridge.sol#L479)

```solidity
function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
    if (decimals > 8) { amount /= 10 ** (decimals - 8); }
    return amount;
}
```

Every amount on the wire is capped at **8 decimals**. The reason is that Wormhole
must interoperate with chains whose native token amounts are `u64` — Solana in
particular — and 8 decimals keeps values inside that range.

The consequence is dust. For an 18-decimal token the last 10 digits are
unrepresentable. Two places handle it:

- **`_transferTokens`** [`:432`](wormhole/ethereum/contracts/bridge/Bridge.sol#L432) does `amount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals)` *before* pulling funds. The round trip floors the amount, so dust is never taken from the user in the first place.
- **`_wrapAndTransferETH`** [`:325-328`](wormhole/ethereum/contracts/bridge/Bridge.sol#L325-L328) computes `dust = amount - deNormalizeAmount(normalizedAmount, 18)` and refunds it with `payable(msg.sender).transfer(dust)`, because ETH already arrived as `msg.value` and cannot be un-sent.

The asymmetry is worth noting: ERC-20 dust is *avoided*, ETH dust is *refunded*.

### `_transferTokens(address, uint256, uint256) internal` — [`:415`](wormhole/ethereum/contracts/bridge/Bridge.sol#L415)

The core outbound path.

1. Classify the token at [`:419-425`](wormhole/ethereum/contracts/bridge/Bridge.sol#L419-L425). If `isWrappedAsset(token)`, read origin chain and address off the wrapper; otherwise it is native here.
2. Query decimals, floor the amount to 8-decimal precision.
3. **Native branch** [`:434-447`](wormhole/ethereum/contracts/bridge/Bridge.sol#L434-L447): snapshot `balanceOf(this)`, `safeTransferFrom`, snapshot again, and set `amount = balanceAfter - balanceBefore`. This is explicit fee-on-transfer support — the amount bridged is what actually arrived, not what was requested.
4. **Wrapped branch** [`:448-452`](wormhole/ethereum/contracts/bridge/Bridge.sol#L448-L452): `safeTransferFrom` into the bridge, then `burn`. Two steps rather than a direct burn-from, so the wrapper needs no special allowance semantics.
5. Normalize amount and arbiter fee.
6. Native tokens only: `bridgeOut(token, normalizedAmount)`.

`bridgeOut` at [`:764-768`](wormhole/ethereum/contracts/bridge/Bridge.sol#L764-L768)
enforces `outstanding + normalizedAmount <= type(uint64).max`, reverting
`OutstandingExceedsMax`. That is the `u64` ceiling showing up again: the protocol
refuses to let more of a token leave than a 64-bit counter can track.

### The four public senders

| Function | Line | Guards | Payload |
|---|---|---|---|
| `transferTokens` | [`:350`](wormhole/ethereum/contracts/bridge/Bridge.sol#L350) | `nonReentrant notPaused` | 1 |
| `transferTokensWithPayload` | [`:387`](wormhole/ethereum/contracts/bridge/Bridge.sol#L387) | `nonReentrant notPaused` | 3 |
| `wrapAndTransferETH` | [`:260`](wormhole/ethereum/contracts/bridge/Bridge.sol#L260) | `notPaused` only | 1 |
| `wrapAndTransferETHWithPayload` | [`:292`](wormhole/ethereum/contracts/bridge/Bridge.sol#L292) | `notPaused` only | 3 |

**The ETH paths are not `nonReentrant`.** They are safe because
`_wrapAndTransferETH` only interacts with WETH and refunds dust via a
2300-gas `.transfer`, but the asymmetry is a real difference worth knowing when
auditing an integration.

Both payload-3 variants pass `arbiterFee = 0` — see
[`:299`](wormhole/ethereum/contracts/bridge/Bridge.sol#L299) and
[`:398`](wormhole/ethereum/contracts/bridge/Bridge.sol#L398) — because contract-
controlled transfers have no relayer fee field at all.

`_wrapAndTransferETH` requires `wormholeFee < msg.value` strictly at
[`:315`](wormhole/ethereum/contracts/bridge/Bridge.sol#L315), so a zero-value
bridge of ETH is impossible even when the message fee is zero.

### `logTransfer` / `logTransferWithPayload` — [`:486`](wormhole/ethereum/contracts/bridge/Bridge.sol#L486), [`:520`](wormhole/ethereum/contracts/bridge/Bridge.sol#L520)

Build the struct, encode, and call `wormhole().publishMessage{value: callValue}`.
`logTransfer` re-checks `fee > amount` at
[`:496`](wormhole/ethereum/contracts/bridge/Bridge.sol#L496) — a second time,
after `_transferTokens` already checked, because the normalization in between
could in principle change the relationship.

`logTransferWithPayload` stamps `fromAddress = bytes32(uint256(uint160(msg.sender)))`
at [`:538`](wormhole/ethereum/contracts/bridge/Bridge.sol#L538). That is the
sender identity a destination contract can trust, and it is why payload-3 is the
basis for cross-chain composability.

---

## 10. Token bridge: `Bridge.sol` inbound

### The four public redeemers

All four funnel into `_completeTransfer`.

| Function | Line | `unwrapWETH` | Payload |
|---|---|---|---|
| `completeTransfer` | [`:652`](wormhole/ethereum/contracts/bridge/Bridge.sol#L652) | false | 1 |
| `completeTransferAndUnwrapETH` | [`:663`](wormhole/ethereum/contracts/bridge/Bridge.sol#L663) | true | 1 |
| `completeTransferWithPayload` | [`:627`](wormhole/ethereum/contracts/bridge/Bridge.sol#L627) | false | 3, returns payload |
| `completeTransferAndUnwrapETHWithPayload` | [`:641`](wormhole/ethereum/contracts/bridge/Bridge.sol#L641) | true | 3, returns payload |

None of them is `nonReentrant`. The protection is the replay flag instead, set
before any external call.

### `_completeTransfer(bytes, bool) internal` — [`:679`](wormhole/ethereum/contracts/bridge/Bridge.sol#L679)

Order of operations, which is the whole security argument:

1. `parseAndVerifyVM` on the core contract, `require(valid, reason)` — [`:680-682`](wormhole/ethereum/contracts/bridge/Bridge.sol#L680-L682).
2. `verifyBridgeVM(vm)` — the emitter must be the registered token bridge on the source chain. Reverts `InvalidEmitter` at [`:683`](wormhole/ethereum/contracts/bridge/Bridge.sol#L683).
3. Parse as payload 1 or 3 via `_parseTransferCommon`.
4. **Payload-3 gate**: `if (transfer.payloadID == 3) { if (msg.sender != transferRecipient) revert InvalidSender(); }` — [`:689-691`](wormhole/ethereum/contracts/bridge/Bridge.sol#L689-L691). Only the designated recipient may redeem a contract-controlled transfer. This is what makes payload 3 safe to build protocols on: nobody can front-run the redemption and hand your contract tokens out of context.
5. **Replay check and set**, [`:693-694`](wormhole/ethereum/contracts/bridge/Bridge.sol#L693-L694). `isTransferCompleted(vm.hash)` then `setTransferCompleted(vm.hash)`, both before any token movement.
6. Emit `TransferRedeemed` — [`:697`](wormhole/ethereum/contracts/bridge/Bridge.sol#L697).
7. `if (transfer.toChain != chainId()) revert InvalidTargetChain()` — [`:699`](wormhole/ethereum/contracts/bridge/Bridge.sol#L699).
8. Resolve the token: native side unlocks and calls `bridgedIn`; foreign side looks up the wrapper and reverts `WrappedAssetNotFound` if absent — [`:701-712`](wormhole/ethereum/contracts/bridge/Bridge.sol#L701-L712).
9. `if (unwrapWETH && address(transferToken) != address(WETH())) revert OnlyWETH()` — [`:714`](wormhole/ethereum/contracts/bridge/Bridge.sol#L714).
10. De-normalize amount and fee back to native decimals — [`:721-722`](wormhole/ethereum/contracts/bridge/Bridge.sol#L721-L722).
11. Pay the relayer fee, then the recipient.

Steps 5 and 6 land before every transfer, so a reentrant token cannot replay the
same VAA.

### `_truncateAddress(bytes32) internal pure` — [`:673`](wormhole/ethereum/contracts/bridge/Bridge.sol#L673)

```solidity
if (bytes12(b) != 0) revert InvalidEVMAddress();
return address(uint160(uint256(b)));
```

Rejects a 32-byte value whose top 12 bytes are non-zero. Contrast this with the
core's `submitContractUpgrade`, which truncates silently. Here it matters: a
Solana address is a full 32 bytes, and quietly folding one into 20 bytes would
send funds to an address nobody controls.

### The relayer fee

[`:725-743`](wormhole/ethereum/contracts/bridge/Bridge.sol#L725-L743). Paid only
when `nativeFee > 0 && transferRecipient != msg.sender`. If the recipient redeems
their own transfer, the fee is zeroed at
[`:742`](wormhole/ethereum/contracts/bridge/Bridge.sol#L742) and they receive the
whole amount — so self-redeeming is always strictly better for the user, and the
fee is genuinely a payment for someone else's gas.

The mint-versus-transfer split appears twice, once for the fee and once for the
principal: foreign tokens are minted on the wrapper
([`:735`](wormhole/ethereum/contracts/bridge/Bridge.sol#L735),
[`:755`](wormhole/ethereum/contracts/bridge/Bridge.sol#L755)), native tokens are
released from the bridge's own balance
([`:737`](wormhole/ethereum/contracts/bridge/Bridge.sol#L737),
[`:757`](wormhole/ethereum/contracts/bridge/Bridge.sol#L757)).

### `bridgedIn` — [`:770`](wormhole/ethereum/contracts/bridge/Bridge.sol#L770)

```solidity
setOutstandingBridged(token, outstandingBridged(token) - normalizedAmount);
```

Unchecked subtraction in the sense that there is no explicit guard — it relies on
Solidity 0.8 overflow reverting. If accounting ever desynchronized, redemption of
a native token would revert rather than silently underflow.

### `verifyBridgeVM(IWormhole.VM memory) internal view` — [`:774`](wormhole/ethereum/contracts/bridge/Bridge.sol#L774)

```solidity
if (isFork()) revert InvalidFork();
return bridgeContracts(vm.emitterChainId) == vm.emitterAddress;
```

Two jobs in four lines: refuse to process anything at all on a forked chain, and
confirm the message came from the registered peer. `InvalidFork` is declared in
`BridgeGovernance` at
[`:35`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L35).

### `createWrapped` / `updateWrapped`

`createWrapped(bytes) external notPaused` at
[`:569`](wormhole/ethereum/contracts/bridge/Bridge.sol#L569) verifies an
`AssetMeta` VAA and calls `_createWrapped`
([`:580`](wormhole/ethereum/contracts/bridge/Bridge.sol#L580)), which:

- rejects tokens native to this chain, `OnlyForeignTokens` [`:581`](wormhole/ethereum/contracts/bridge/Bridge.sol#L581)
- rejects duplicates, `WrappedAssetAlreadyExists` [`:582`](wormhole/ethereum/contracts/bridge/Bridge.sol#L582)
- deploys a `BridgeToken` beacon proxy by `CREATE2` with

```solidity
bytes32 salt = keccak256(abi.encodePacked(meta.tokenChain, meta.tokenAddress));
```

[`:604`](wormhole/ethereum/contracts/bridge/Bridge.sol#L604). The salt is the
origin `(chain, address)` pair, so **the wrapper address is deterministic across
every EVM chain** running the same bridge bytecode. That is how integrators can
precompute a wrapped-token address before it exists.

The assembly at [`:606-612`](wormhole/ethereum/contracts/bridge/Bridge.sol#L606-L612)
checks `extcodesize(token)` and reverts with no data on failure.

`updateWrapped` at [`:549`](wormhole/ethereum/contracts/bridge/Bridge.sol#L549)
handles a later re-attestation, calling `updateDetails` with the VAA's `sequence`
so stale attestations can be ordered and rejected by the token itself.

`receive() external payable {}` at
[`:959`](wormhole/ethereum/contracts/bridge/Bridge.sol#L959) accepts ETH with no
checks, because WETH sends ETH here during `withdraw`. Any ETH sent directly is
stuck.

---

## 11. Token bridge: payload codecs

### On-the-wire layouts

**`Transfer`, payload 1** — 133 bytes exactly. Encoder [`:790`](wormhole/ethereum/contracts/bridge/Bridge.sol#L790), parser [`:854`](wormhole/ethereum/contracts/bridge/Bridge.sol#L854).

| Offset | Size | Field |
|---|---|---|
| `0` | 1 | `payloadID` = 1 |
| `1` | 32 | `amount` (normalized, ≤ 8 decimals) |
| `33` | 32 | `tokenAddress` |
| `65` | 2 | `tokenChain` |
| `67` | 32 | `to` |
| `99` | 2 | `toChain` |
| `101` | 32 | `fee` |

**`AssetMeta`, payload 2** — 100 bytes exactly. Encoder [`:779`](wormhole/ethereum/contracts/bridge/Bridge.sol#L779), parser [`:822`](wormhole/ethereum/contracts/bridge/Bridge.sol#L822).

| Offset | Size | Field |
|---|---|---|
| `0` | 1 | `payloadID` = 2 |
| `1` | 32 | `tokenAddress` |
| `33` | 2 | `tokenChain` |
| `35` | 1 | `decimals` |
| `36` | 32 | `symbol` |
| `68` | 32 | `name` |

**`TransferWithPayload`, payload 3** — 133-byte header plus arbitrary tail. Encoder [`:802`](wormhole/ethereum/contracts/bridge/Bridge.sol#L802), parser [`:889`](wormhole/ethereum/contracts/bridge/Bridge.sol#L889).

| Offset | Size | Field |
|---|---|---|
| `0` | 1 | `payloadID` = 3 |
| `1` | 32 | `amount` |
| `33` | 32 | `tokenAddress` |
| `65` | 2 | `tokenChain` |
| `67` | 32 | `to` |
| `99` | 2 | `toChain` |
| `101` | 32 | `fromAddress` |
| `133` | rest | `payload` |

Payload 3 replaces payload 1's `fee` field with `fromAddress`. Same offset, same
width, different meaning — which is exactly why `_parseTransferCommon` must
dispatch on the payload id rather than reinterpreting bytes.

### Length discipline

`parseTransfer` [`:880`](wormhole/ethereum/contracts/bridge/Bridge.sol#L880) and
`parseAssetMeta` [`:845`](wormhole/ethereum/contracts/bridge/Bridge.sol#L845) both
end with `if (encoded.length != index) revert Invalid...`, rejecting trailing
bytes. **`parseTransferWithPayload` does not** — it cannot, since its tail is
variable-length. It ends by slicing the remainder at
[`:915`](wormhole/ethereum/contracts/bridge/Bridge.sol#L915).

### `_parseTransferCommon(bytes) public pure` — [`:926`](wormhole/ethereum/contracts/bridge/Bridge.sol#L926)

Normalizes payload 1 and 3 into one `Transfer` struct, forcing `fee = 0` for
payload 3 at [`:940`](wormhole/ethereum/contracts/bridge/Bridge.sol#L940).
Anything else reverts `InvalidPayloadId`. The docblock at
[`:922-924`](wormhole/ethereum/contracts/bridge/Bridge.sol#L922-L924) admits its
real motivation: getting under the local-variable limit in `_completeTransfer`.

It is declared `public` despite the leading underscore, so it is callable
externally and useful for off-chain decoding.

### `bytes32ToString(bytes32) internal pure` — [`:946`](wormhole/ethereum/contracts/bridge/Bridge.sol#L946)

Walks until the first zero byte, then copies. Converts the fixed-width name and
symbol back into a Solidity `string` for the wrapper.

---

## 12. Token bridge: `BridgeGovernance.sol`

Module constant at
[`:25`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L25):
`0x...546f6b656e427269646765`, ASCII `"TokenBridge"` left-padded.

Fourteen custom errors are declared at
[`:29-44`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L29-L44). The
comment at [`:27-28`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L27-L28)
gives the reason: revert strings would push `BridgeImplementation` past the
24,576-byte EIP-170 limit. That constraint explains several odd shapes in this
codebase, including the shared `_requireRole` and `_clearPauseToNow` helpers.

### `verifyGovernanceVM(bytes) internal view` — [`:166`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L166)

Differs from the core's version in two ways: it takes raw bytes and reverts rather
than returning a flag, and it does **not** require the current guardian set — only
that the emitter matches governance. Checks: valid VAA (forwarding the core's
dynamic reason string, [`:169`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L169)),
`WrongGovernanceChain`, `WrongGovernanceContract`, `GovernanceActionConsumed`.

### The four handlers

| Action | Function | Line | Payload size |
|---|---|---|---|
| 1 `RegisterChain` | `registerChain` | [`:47`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L47) | 69 bytes |
| 2 `UpgradeContract` | `upgrade` | [`:61`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L61) | 67 bytes |
| 3 `RecoverChainId` | `submitRecoverChainId` | [`:148`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L148) | 67 bytes |
| 4 `SetPauserAddresses` | `submitSetPauserAddresses` | [`:98`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L98) | variable |

**`RegisterChain`** — parser [`:193`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L193)

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 1 |
| `33` | 2 | `chainId` (this chain or 0) |
| `35` | 2 | `emitterChainID` |
| `37` | 32 | `emitterAddress` |

`if (bridgeContracts(chain.emitterChainID) != bytes32(0)) revert ChainAlreadyRegistered();`
at [`:55`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L55). **A peer
registration is permanent.** There is no way to change a registered peer, only to
upgrade the whole implementation. That is a deliberate immutability guarantee: the
set of trusted source bridges cannot be quietly swapped.

**`UpgradeContract`** — parser [`:220`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L220)

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 2 |
| `33` | 2 | `chainId` |
| `35` | 32 | `newContract` |

Guarded by `if (isFork()) revert InvalidFork()` at
[`:62`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L62) and requires
an exact chain match at
[`:70`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L70) — no `0`
wildcard, unlike `registerChain`.

**`RecoverChainId`** — parser [`:245`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L245). Same shape as the core's action 5: no `chain` field, targeted by `evmChainId` instead. Inverted guard `if (!isFork()) revert NotAFork()` at [`:149`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L149).

**`SetPauserAddresses`** — parsed inline at
[`:103-116`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L103-L116),
with no struct and no separate parser, again for bytecode size.

| Offset | Size | Field |
|---|---|---|
| `0` | 32 | `module` |
| `32` | 1 | `action` = 4 |
| `33` | 2 | `chainId` |
| `35` | 1 | `pauserLen` (0 or 20) |
| `36` | 0 or 20 | `pauser` |
| … | 1 | `freezerLen` |
| … | 0 or 20 | `freezer` |
| … | 1 | `unpauserLen` |
| … | 0 or 20 | `unpauser` |

`_parsePauserAddress` at
[`:129-143`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L129-L143)
accepts only length 20 or 0, reverting `InvalidAddressLength` otherwise. Length 0
means "leave unassigned", which resolves to `address(0)` and therefore to a role
nobody can invoke.

Wire order is `pauser, freezer, unpauser`; the storage struct order is
`pauser, unpauser, freezer`. They do not match, and the comment at
[`:23-25`](wormhole/ethereum/contracts/bridge/BridgePauserStorage.sol#L23-L25)
flags it explicitly. Anyone hand-building one of these payloads should read that
note first.

### `upgradeImplementation(address) internal` — [`:180`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L180)

Same as the core's, except failure surfaces as `InitializeFailed(bytes reason)`
at [`:188`](wormhole/ethereum/contracts/bridge/BridgeGovernance.sol#L188) rather
than a string revert — a parameterized custom error, which is how the reason is
preserved without the string-literal bytecode cost.

---

## 13. The wrapped token

### `Token.sol` — [`BridgeToken`](wormhole/ethereum/contracts/bridge/token/Token.sol#L6-L9)

An OpenZeppelin `BeaconProxy`. The beacon is the token bridge itself, which is why
`BridgeImplementation` exposes `implementation()` at
[`:16-18`](wormhole/ethereum/contracts/bridge/BridgeImplementation.sol#L16-L18)
returning `tokenImplementation()`. **Upgrading the bridge's token implementation
upgrades every wrapped token on that chain at once.**

### `TokenState.sol` — [`TokenStorage.State`](wormhole/ethereum/contracts/bridge/token/TokenState.sol#L9-L41)

Standard ERC-20 fields plus five EIP-712 cache slots and the origin identity:

| Field | Purpose |
|---|---|
| `metaLastUpdatedSequence` | VAA sequence of the last `updateDetails`, for ordering |
| `owner` | the token bridge; gates `mint`/`burn`/`updateDetails` |
| `initialized` | one-shot guard |
| `chainId`, `nativeContract` | the origin `(chain, address)` pair |
| `cachedDomainSeparator`, `cachedChainId`, `cachedThis`, `cachedSalt`, `cachedHashedName` | EIP-712 memoization |

`TokenState` also carries `nonces(address)` at
[`:52`](wormhole/ethereum/contracts/bridge/token/TokenState.sol#L52) and
`_useNonce` at
[`:59`](wormhole/ethereum/contracts/bridge/token/TokenState.sol#L59) for permit.

### `TokenImplementation.sol` — the ERC-20

Standard OpenZeppelin-derived ERC-20 with three protocol additions.

**`initialize(...)` `initializer public`** — [`:17`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L17). Sets name, symbol, decimals, the attestation sequence, the owner (the bridge), and the origin pair, then builds the EIP-712 cache. The `initializer` modifier at [`:213-222`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L213-L222) uses a plain `_state.initialized` bool.

**`mint` / `burn`, both `onlyOwner`** — [`:161`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L161) and [`:173`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L173). Only the bridge may call them, enforced at [`:208-211`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L208-L211). Note this is a **local** `onlyOwner` reading `_state.owner`, not OpenZeppelin's `Ownable`, despite the import at [`:7`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L7) — that import is unused.

**`updateDetails(string,string,uint64) onlyOwner`** — [`:196`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L196):

```solidity
require(_state.metaLastUpdatedSequence < sequence_, "current metadata is up to date");
```

[`:197`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L197).
Strictly increasing sequence, so an old attestation VAA cannot roll a token's name
backwards. Since the name feeds the EIP-712 domain separator, it recaches at
[`:205`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L205).

**A quirk in `transferFrom`** — [`:126-134`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L126-L134):

```solidity
function transferFrom(address sender_, address recipient_, uint256 amount_) public returns (bool) {
    _transfer(sender_, recipient_, amount_);

    uint256 currentAllowance = _state.allowances[sender_][_msgSender()];
    require(currentAllowance >= amount_, "ERC20: transfer amount exceeds allowance");
    _approve(sender_, _msgSender(), currentAllowance - amount_);

    return true;
}
```

The transfer happens **before** the allowance check. It is still safe because the
whole call reverts atomically, but the event ordering differs from every standard
ERC-20: a `Transfer` is emitted before the `Approval`, and a failing call emits
neither. Anything simulating state mid-call, or a hook-bearing recipient, sees an
order no other token produces. There is no reentrancy risk here because this token
has no hooks.

**EIP-712 / permit.** `permit` at
[`:274`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L274)
follows the standard shape with one addition: it calls
`_initializePermitStateIfNeeded()` first at
[`:285`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L285),
because tokens deployed before permit existed have empty caches.

The domain separator at
[`:237-250`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L237-L250)
includes a **salt**, which most tokens omit:

```solidity
function _eip712DomainSalt() internal view returns (bytes32) {
    return keccak256(abi.encodePacked(_state.chainId, _state.nativeContract));
}
```

[`:348-350`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L348-L350).
The salt is the origin pair. This matters precisely because wrapper addresses are
deterministic via `CREATE2`: the same origin token gets the *same address* on
every EVM chain. `block.chainid` already separates them, and the salt adds a
second, independent discriminator.

`_domainSeparatorV4` at
[`:227-235`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L227-L235)
invalidates the cache if either `address(this)` or `block.chainid` changed, which
covers both chain forks and the proxy being read through a different address.

`eip712Domain()` at
[`:320`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol#L320)
implements ERC-5267, returning `hex"1F"` (binary `11111`) to signal that all five
domain fields are in use.

### `utils/Migrator.sol` — [68 lines](wormhole/ethereum/contracts/bridge/utils/Migrator.sol)

A standalone one-off helper for swapping one wrapped asset for another, used
during historical asset migrations. Not part of the transfer path and not
referenced by the bridge.

### `interfaces/IWETH.sol` — [10 lines](wormhole/ethereum/contracts/bridge/interfaces/IWETH.sol)

`deposit()` and `withdraw(uint)`. That is the entire surface the bridge needs.

### `interfaces/ITokenBridge.sol` — [233 lines](wormhole/ethereum/contracts/bridge/interfaces/ITokenBridge.sol)

The integrator-facing ABI, re-declaring the structs and every public function.
This is the file to import when writing a contract that talks to the bridge.

---

## 14. NFT bridge

A parallel stack with the same shape as the token bridge — proxy, setup,
implementation, governance, getters, setters, state, shutdown, wrapped token — but
a different payload and one genuinely strange parser.

Module constant at
[`nft/NFTBridgeGovernance.sol:24`](wormhole/ethereum/contracts/nft/NFTBridgeGovernance.sol#L24):
`0x...4e4654427269646765`, ASCII `"NFTBridge"`. Governance actions are the same
three as the token bridge (`RegisterChain` 1, `UpgradeContract` 2,
`RecoverChainId` 3) with parsers at
[`:117`](wormhole/ethereum/contracts/nft/NFTBridgeGovernance.sol#L117),
[`:144`](wormhole/ethereum/contracts/nft/NFTBridgeGovernance.sol#L144) and
[`:167`](wormhole/ethereum/contracts/nft/NFTBridgeGovernance.sol#L167). There is
no pauser system here.

### `transferNFT(address, uint256, uint16, bytes32, uint32) public payable` — [`:23`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L23)

Unlike the token bridge, it validates interfaces up front for native tokens:

```solidity
require(ERC165(token).supportsInterface(type(IERC721).interfaceId), "must support the ERC721 interface");
require(ERC165(token).supportsInterface(type(IERC721Metadata).interfaceId), "must support the ERC721-Metadata extension");
```

[`:34-35`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L34-L35).

### The Solana special case

Chain id 1 is Solana, and the code branches on it in three places.

Solana SPL NFTs share unified name and symbol values across a collection, so
those fields would be lost on a round trip. The bridge caches them. On the way
out ([`:55-60`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L55-L60)) it reads
`splCache(tokenID)` and clears it; on the way in
([`:136-142`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L136-L142)) it writes
the cache before minting. The `SPLCache` struct is at
[`nft/NFTBridgeState.sol:22`](wormhole/ethereum/contracts/nft/NFTBridgeState.sol#L22),
keyed by `tokenID` alone at
[`:52`](wormhole/ethereum/contracts/nft/NFTBridgeState.sol#L52) — not by
`(chain, address, tokenID)`.

Note the guard at [`:42`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L42) skips
the `symbol()` and `name()` staticcalls entirely when `tokenChain == 1`.

### Auto-creating wrappers

`_completeTransfer` creates the wrapper on demand if it does not exist:

```solidity
if (wrapped == address(0)) {
    wrapped = _createWrapped(transfer.tokenChain, transfer.tokenAddress, transfer.name, transfer.symbol);
}
```

[`:125-127`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L125-L127). The token
bridge deliberately does **not** do this — it requires a separate `attestToken`
and `createWrapped`, because an ERC-20 needs `decimals` that only an attestation
carries. An NFT needs nothing beyond name and symbol, which ride along in the
transfer payload itself.

### The payload, and its broken parser

Encoder at [`:204`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L204):

| Offset | Size | Field |
|---|---|---|
| `0` | 1 | `payloadID` = 1 |
| `1` | 32 | `tokenAddress` |
| `33` | 2 | `tokenChain` |
| `35` | 32 | `symbol` |
| `67` | 32 | `name` |
| `99` | 32 | `tokenID` |
| `131` | 1 | `uriLength` |
| `132` | `uriLength` | `uri` |
| … | 32 | `to` |
| … | 2 | `toChain` |

The URI is capped at 200 bytes:

```solidity
require(bytes(transfer.uri).length <= 200, "tokenURI must not exceed 200 bytes");
```

[`:206`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L206), and the comment at
[`:205`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L205) attributes the limit
to Solana.

**`parseTransfer` does not trust its own length prefix.** At
[`:245-247`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L245-L247):

```solidity
// Ignore length due to malformatted payload
index += 1;
transfer.uri = string(encoded.slice(index, encoded.length - index - 34));
```

It skips the length byte and instead derives the URI length from the total payload
size minus the trailing 34 bytes (`to` 32 + `toChain` 2). Then it reads those two
fields **backwards from the end** at
[`:250-256`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L250-L256), and the
final length assertion is commented out at
[`:258`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L258):

```solidity
//require(encoded.length == index, "invalid Transfer");
```

This is the only parser in the codebase that abandons its own framing. Some
historical emitter produced payloads whose length byte disagreed with the actual
URI, and the fix was to stop reading it. The practical consequence: the URI field
absorbs whatever sits between `tokenID` and the trailing 34 bytes, whatever the
length byte claims.

### `onERC721Received` — [`:261`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L261)

```solidity
require(operator == address(this), "can only bridge tokens via transferNFT method");
```

[`:267`](wormhole/ethereum/contracts/nft/NFTBridge.sol#L267). The bridge accepts
an NFT only when it initiated the transfer itself, so a `safeTransferFrom`
straight to the bridge address reverts instead of stranding the token.

### `nft/token/NFTImplementation.sol` — [254 lines](wormhole/ethereum/contracts/nft/token/NFTImplementation.sol)

A standard OpenZeppelin-derived ERC-721 with the same three additions as the
fungible wrapper: `chainId()` [`:72`](wormhole/ethereum/contracts/nft/token/NFTImplementation.sol#L72),
`nativeContract()` [`:76`](wormhole/ethereum/contracts/nft/token/NFTImplementation.sol#L76),
`owner()` [`:80`](wormhole/ethereum/contracts/nft/token/NFTImplementation.sol#L80),
plus owner-gated `mint`/`burn`. `tokenURI` is stored per token rather than
derived from a base URI, because each bridged token carries its own URI in the
payload.

### The rest of the NFT stack

| File | Role |
|---|---|
| [`NFTBridgeEntrypoint.sol`](wormhole/ethereum/contracts/nft/NFTBridgeEntrypoint.sol) | the ERC-1967 proxy |
| [`NFTBridgeSetup.sol`](wormhole/ethereum/contracts/nft/NFTBridgeSetup.sol) | one-shot initializer |
| [`NFTBridgeImplementation.sol`](wormhole/ethereum/contracts/nft/NFTBridgeImplementation.sol) | upgrade entry point + token beacon |
| [`NFTBridgeShutdown.sol`](wormhole/ethereum/contracts/nft/NFTBridgeShutdown.sol) | disabled drop-in, same pattern as `Shutdown` |
| [`NFTBridgeGetters.sol`](wormhole/ethereum/contracts/nft/NFTBridgeGetters.sol) / [`NFTBridgeSetters.sol`](wormhole/ethereum/contracts/nft/NFTBridgeSetters.sol) | accessors, including `splCache`/`setSplCache`/`clearSplCache` |
| [`NFTBridgeState.sol`](wormhole/ethereum/contracts/nft/NFTBridgeState.sol) | storage struct with the `splCache` mapping |
| [`nft/token/NFT.sol`](wormhole/ethereum/contracts/nft/token/NFT.sol) | `BridgeNFT`, the beacon proxy |
| [`nft/token/NFTState.sol`](wormhole/ethereum/contracts/nft/token/NFTState.sol) | wrapped NFT storage |
| [`nft/interfaces/INFTBridge.sol`](wormhole/ethereum/contracts/nft/interfaces/INFTBridge.sol) | integrator ABI |
| [`nft/mock/MockNFTBridgeImplementation.sol`](wormhole/ethereum/contracts/nft/mock/MockNFTBridgeImplementation.sol), [`nft/mock/MockNFTImplementation.sol`](wormhole/ethereum/contracts/nft/mock/MockNFTImplementation.sol) | upgrade doubles |

---
