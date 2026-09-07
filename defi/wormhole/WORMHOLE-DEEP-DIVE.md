# Wormhole Deep Dive

You have already read [`lifi/LIFI-DEEP-DIVE.md`](../lifi/LIFI-DEEP-DIVE.md) and
[`lifi/FACETS-COMPLETE-REFERENCE.md`](../lifi/FACETS-COMPLETE-REFERENCE.md). Those
documents show how a router *calls* a bridge: it validates a `BridgeData`, pulls
the user's tokens, approves the bridge contract, and fires one external call.
What happens after that call was, in those documents, a black box.

This document opens the box.

Wormhole is also the best cross-language case study available in this repository.
The same protocol is implemented in Solidity on EVM chains and in Rust on Solana,
against radically different execution models. Sections 1 through 4 teach the
protocol from the Solidity. Section 5 shows the same steps in Rust and explains
why the account model forces a different shape.

Source: `wormhole/` (wormhole-foundation/wormhole). Every citation below is a
verified link into that tree.

---

## 0. The problem: chains cannot read each other

A smart contract on Ethereum can read Ethereum state. It cannot read Solana
state. There is no opcode for it, and there is no cheap way to build one: to
verify a Solana block header on Ethereum you would have to run a Solana light
client inside the EVM, which means verifying Ed25519 signatures over a validator
set of ~1500 stakers, on every block, forever. The gas cost is prohibitive and
for some chain pairs the cryptography is not even available as a precompile.

So every cross-chain system answers the same question — *how does chain B learn
that something happened on chain A?* — and there are only three families of
answer.

**Light clients / native verification.** Chain B runs a real consensus client of
chain A on-chain and verifies headers cryptographically. This is the strongest
model, trusting nothing but chain A's consensus. It is also the most expensive
and must be built per chain pair. IBC works this way. Ethereum↔Ethereum-L2
canonical bridges approximate it.

**Optimistic / fraud proofs.** Anyone may assert "this happened on chain A",
and the assertion is accepted after a challenge window unless someone proves it
false. Cheap in the happy path, but it imposes a latency floor (the window) and
requires at least one honest, funded, liveness-having watcher.

**External attestation.** A known set of off-chain observers watches chain A,
and when they agree that something happened, they sign a statement to that
effect. Chain B verifies those signatures. Cheap, fast, works for any chain pair
including non-EVM, and trusts the observers.

**Wormhole is squarely in the third family, and you should be clear-eyed about
what that means.** A set of *Guardians* runs full nodes on every connected
chain. When a message is published, they observe it, and each signs the message
body with a secp256k1 key. Collect enough signatures and you have a VAA, which
any chain can verify cheaply because `ecrecover` is a precompile everywhere.

The trust assumption is a supermajority of the Guardian set. Quorum is computed
in one line, [`wormhole/ethereum/contracts/Messages.sol:216`](wormhole/ethereum/contracts/Messages.sol#L216):

```solidity
return ((numGuardians * 2) / 3) + 1;
```

With the mainnet set of 19 Guardians that is `(19*2)/3 + 1 = 12 + 1 = 13`. So
**13 of 19**. Thirteen colluding or compromised Guardian keys can mint arbitrary
messages on every connected chain, which in practice means draining every token
the bridge custodies. No amount of Solidity elsewhere in the system changes that.
This is a social and operational guarantee dressed in cryptography, and the
whitepaper is honest about it: the design exists because *"smart contract engines
on chains are often insufficiently powerful to independently verify expensive
state proofs from other chains"*, so the protocol trusts *"the oracle network as
an intermediary rather than trusting the remote chain"*
([`wormhole/whitepapers/0001_generic_message_passing.md`](wormhole/whitepapers/0001_generic_message_passing.md)).

What the design *does* buy is generality. The core protocol knows nothing about
tokens. It moves bytes. The token bridge in section 3 is an application built on
top, and it is deliberately separable — the whitepaper's stated goal was to
*"redesign the protocol such that it is fully decoupled from the application
logic"*, so that Wormhole *"will no longer hold assets in custody"* at the core
layer.

### The lifecycle, end to end

```
  CHAIN A (source)                                    CHAIN B (destination)
  ────────────────                                    ─────────────────────
  your contract
      │
      │ publishMessage(nonce, payload, consistencyLevel)
      ▼
  Core Bridge (Implementation.sol)
      │  - charge messageFee
      │  - sequence = useSequence(msg.sender)
      │  - emit LogMessagePublished
      ▼
   [ event in a block ]
      │
      │ ... wait for consistencyLevel confirmations ...
      ▼
  ┌─────────────────────────────────────┐
  │  19 GUARDIANS (off-chain)           │
  │  each runs a full node on chain A   │
  │  observes the event, signs          │
  │  keccak256(keccak256(body))         │
  └─────────────────────────────────────┘
      │
      │ gossip signatures, assemble ≥13
      ▼
   V A A  (bytes)  ──── carried by anyone: a relayer, a bot, or the user ────►
                                                          │
                                                          ▼
                                              Core Bridge (Messages.sol)
                                                 parseAndVerifyVM(encodedVM)
                                                   - parse header + body
                                                   - hash = keccak(keccak(body))
                                                   - guardian set live?
                                                   - signatures ≥ quorum?
                                                   - each sig recovers to the
                                                     right guardian key?
                                                          │
                                                          ▼
                                                   your contract acts
```

Note what is *not* in that diagram: there is no privileged relayer. A VAA is a
bearer credential. Anyone holding the bytes can submit them, and the protocol
does not care who does. That property is what lets LI.FI, Mayan, or a user's own
wallet all complete the same transfer.

---

## 1. The core primitive: a VAA

A **VAA** (Verifiable Action Approval) is a signed observation. It is the only
thing the protocol really produces, and every other feature is a consumer of it.

### 1.1 The struct

[`wormhole/ethereum/contracts/Structs.sol:25-39`](wormhole/ethereum/contracts/Structs.sol#L25-L39):

```solidity
struct VM {
	uint8 version;
	uint32 timestamp;
	uint32 nonce;
	uint16 emitterChainId;
	bytes32 emitterAddress;
	uint64 sequence;
	uint8 consistencyLevel;
	bytes payload;

	uint32 guardianSetIndex;
	Signature[] signatures;

	bytes32 hash;
}
```

The ordering in the struct is *not* the wire ordering. On the wire a VAA is a
**header** followed by a **body**, and the split matters enormously because only
the body is signed.

### 1.2 The wire format, byte by byte

Derived from the parser at
[`wormhole/ethereum/contracts/Messages.sol:147-208`](wormhole/ethereum/contracts/Messages.sol#L147-L208):

```
HEADER (not covered by the signature)
  offset  size  field
  ──────  ────  ─────────────────────────────────────────────
  0       1     version                 must equal 1
  1       4     guardianSetIndex        which set signed this
  5       1     signersLen (N)          number of signatures
  6       N×66  signatures              each 66 bytes:
                                          1  guardianIndex
                                          32 r
                                          32 s
                                          1  v   (stored as 0/1, +27 on parse)

BODY (this is what gets hashed and signed)
  +0      4     timestamp
  +4      4     nonce
  +8      2     emitterChainId          Wormhole chain id, not EIP-155
  +10     32    emitterAddress          left-zero-padded
  +42     8     sequence                per-emitter counter
  +50     1     consistencyLevel
  +51     ...   payload                 opaque to the core protocol
```

Two details in that table are load-bearing and both are called out in the source.

**`emitterChainId` is a Wormhole chain id, not an EIP-155 chain id.** Ethereum
is Wormhole chain 2, BSC is 4, Polygon is 5. The mapping is enumerated
explicitly at
[`wormhole/ethereum/contracts/Implementation.sol:40-55`](wormhole/ethereum/contracts/Implementation.sol#L40-L55).
Confusing the two namespaces is a classic integration bug.

**Addresses are `bytes32`, not `address`.** Wormhole must express a Solana
pubkey (32 bytes) and an Ethereum address (20 bytes) in the same field, so
everything is widened to 32 and EVM addresses are left-zero-padded. Truncating
back is a deliberate, separate step — see `_truncateAddress` in section 3.

### 1.3 `parseVM`: parsing, and the hash that matters

[`wormhole/ethereum/contracts/Messages.sol:147-208`](wormhole/ethereum/contracts/Messages.sol#L147-L208).

It takes `bytes memory encodedVM` and returns a populated `VM`. It performs
**no** validation beyond the version check — the doc comment says so explicitly:
*"it intentionally performs no validation functions, it simply parses raw into a
struct"*. Parsing and verifying are separate concerns, and conflating them is
how people write vulnerable integrations.

The version check is the one exception,
[`wormhole/ethereum/contracts/Messages.sol:157`](wormhole/ethereum/contracts/Messages.sol#L157):

```solidity
require(vm.version == 1, "VM version incompatible");
```

The comment immediately above it is one of the most interesting in the codebase
([`:152-156`](wormhole/ethereum/contracts/Messages.sol#L152-L156)): the version
byte lives in the header, so it is *not* part of the signed body, so *"this
field's integrity is not protected and cannot be trusted"*. It is safe today only
because exactly one version is accepted. If a version 2 were ever added, an
attacker could flip the byte on a legitimate VAA and change how it is
interpreted, without invalidating any signature.

Then the hash, [`:185-186`](wormhole/ethereum/contracts/Messages.sol#L185-L186):

```solidity
bytes memory body = encodedVM.slice(index, encodedVM.length - index);
vm.hash = keccak256(abi.encodePacked(keccak256(body)));
```

**Double keccak.** Not a typo, and not decoration. `keccak256(keccak256(body))`.
The Guardians sign this doubled digest. The reason it is doubled at all is
historical, but the reason it must never change is stated in the source
([`:181-183`](wormhole/ethereum/contracts/Messages.sol#L181-L183)): *"Do not
change the way the hash of a VM is computed! Changing it could result into two
different hashes for the same observation. But xDapps rely on the hash of an
observation for replay protection."*

That is the crux. `vm.hash` is the **identity** of a message across the entire
ecosystem. The token bridge uses it as a replay key
(`isTransferCompleted(vm.hash)`), governance uses it as a replay key
(`governanceActionIsConsumed(vm.hash)`), and every third-party integrator was
told to do the same. Change the derivation and every one of those replay-guard
tables silently stops protecting anything.

Note also that `index` at the moment of the slice points at the first byte after
the signatures. The body is *the rest of the buffer*. There is no length prefix
on the payload; the payload is simply "everything left". A VAA is therefore not
self-delimiting, and appending bytes to a VAA changes its hash — which is what
you want.

### 1.4 `verifySignatures`: recovery, ordering, bounds

[`wormhole/ethereum/contracts/Messages.sol:111-141`](wormhole/ethereum/contracts/Messages.sol#L111-L141).

Signature: `(bytes32 hash, Signature[] signatures, GuardianSet guardianSet) → (bool valid, string reason)`.
It is `public pure`, and the doc comment is emphatic that it is **not** safe on
its own: it *"intentionally does not solve for expectations within guardianSet"*,
*"intentionally does not solve for quorum"*, and *"intentionally returns true
when signatures is an empty set"*. It answers exactly one question: are these
signatures, whatever there are of them, valid signatures by the guardians at the
indices claimed?

The loop body, [`:116-136`](wormhole/ethereum/contracts/Messages.sol#L116-L136):

```solidity
address signatory = ecrecover(hash, sig.v, sig.r, sig.s);
require(signatory != address(0), "ecrecover failed with signature");

/// Ensure that provided signature indices are ascending only
require(i == 0 || sig.guardianIndex > lastIndex, "signature indices must be ascending");
lastIndex = sig.guardianIndex;

require(sig.guardianIndex < guardianCount, "guardian index out of bounds");

if(signatory != guardianSet.keys[sig.guardianIndex]){
    return (false, "VM signature invalid");
}
```

Four checks, and each exists for a distinct reason.

**`signatory != address(0)`.** `ecrecover` returns the zero address on malformed
input rather than reverting. The comment at
[`:117-118`](wormhole/ethereum/contracts/Messages.sol#L117-L118) explains the
real danger: *"the default storage slot value also being 0"*. An uninitialised
guardian key reads as `address(0)`, so without this check a garbage signature
that recovers to zero would match an empty slot.

**Strictly ascending indices.** This is the anti-duplication mechanism, and it is
subtle. Quorum is counted as `vm.signatures.length` — the *array length*, not the
number of distinct guardians. If you could submit guardian 3's valid signature
thirteen times, `signatures.length == 13` would pass quorum with one key.
Requiring `sig.guardianIndex > lastIndex` makes duplicates impossible and makes
array length a sound proxy for distinct-signer count. Note it must be strictly
greater, not `>=`.

**Bounds check.** The source admits at
[`:125-130`](wormhole/ethereum/contracts/Messages.sol#L125-L130) that this is
*"technically redundant"* because the array index on the next line would revert
anyway. It is kept as defence in depth against *"the nontrivial storage semantics
of solidity"* — a good instinct, since a future refactor to a mapping would
silently remove the implicit bound.

**Key match.** The recovered address must equal the guardian at that exact index.
Note this returns `(false, reason)` rather than reverting, so callers can
distinguish "not valid" from "malformed input".

### 1.5 `verifyVMInternal`: the five gates

[`wormhole/ethereum/contracts/Messages.sol:40-102`](wormhole/ethereum/contracts/Messages.sol#L40-L102).
This is where a VAA is actually judged. Five gates, in order.

**Gate 1 — hash integrity (conditional).**
[`:50-66`](wormhole/ethereum/contracts/Messages.sol#L50-L66). If `checkHash` is
set, recompute the body hash from the struct fields and compare against
`vm.hash`. The `WARNING` comment at
[`:46-48`](wormhole/ethereum/contracts/Messages.sol#L46-L48) is the important
part: without it, *"vm.hash can be a valid signed hash but the body of the vm
could be completely different from what was actually signed"*.

This is the single most dangerous foot-gun in the whole API, and it explains why
there are two public entry points:

| entry point | input | `checkHash` | why |
|---|---|---|---|
| [`parseAndVerifyVM`](wormhole/ethereum/contracts/Messages.sol#L16) | `bytes calldata` | `false` | `parseVM` computed the hash from the bytes itself, so it is trustworthy by construction |
| [`verifyVM`](wormhole/ethereum/contracts/Messages.sol#L30) | `VM memory` | `true` | the caller supplied the struct, including `hash`, so the hash must be re-derived and checked |

**If you are integrating, use `parseAndVerifyVM`.** `verifyVM` takes a
caller-constructed struct, and it is only safe because of gate 1. Note the
re-derivation at [`:51-61`](wormhole/ethereum/contracts/Messages.sol#L51-L61)
uses `abi.encodePacked` of the seven body fields in wire order — the struct field
order is different, which is exactly why this code has to exist rather than
hashing the struct directly.

**Gate 2 — guardian set is non-empty.**
[`:75-77`](wormhole/ethereum/contracts/Messages.sol#L75-L77). Reading an unknown
`guardianSetIndex` returns a zero-valued struct with `keys.length == 0`. The
`WARNING` at [`:70-73`](wormhole/ethereum/contracts/Messages.sol#L70-L73) spells
out the trap: with zero keys, `quorum(0)` returns `(0*2)/3 + 1 = 1`, and
`verifySignatures` returns `true` for an empty array. Without this gate, a VAA
citing a nonexistent guardian set with... actually, with one signature would
still fail the key comparison — but a VAA with *zero* signatures would pass
quorum-of-1? No: `0 < 1` fails quorum. The real hazard is subtler, which is why
the comment says it protects *"the integrity of both vm and signature
verification"* jointly. Treat it as belt-and-braces on a genuinely fragile
interaction.

**Gate 3 — guardian set not expired.**
[`:80-82`](wormhole/ethereum/contracts/Messages.sol#L80-L82):

```solidity
if(vm.guardianSetIndex != getCurrentGuardianSetIndex() && guardianSet.expirationTime < block.timestamp){
    return (false, "guardian set has expired");
}
```

Read the boolean carefully. The current set is **always** accepted, regardless of
`expirationTime`. Only a *non-current* set is subject to expiry. This is what
creates the grace window discussed in section 4.

**Gate 4 — quorum.** [`:90-92`](wormhole/ethereum/contracts/Messages.sol#L90-L92),
`vm.signatures.length < quorum(guardianSet.keys.length)`. Sound only because of
the ascending-index rule in gate 5's helper.

**Gate 5 — signatures valid.**
[`:95-98`](wormhole/ethereum/contracts/Messages.sol#L95-L98). Delegates to
`verifySignatures`.

### 1.6 `quorum`

[`wormhole/ethereum/contracts/Messages.sol:213-217`](wormhole/ethereum/contracts/Messages.sol#L213-L217):

```solidity
require(numGuardians < 256, "too many guardians");
return ((numGuardians * 2) / 3) + 1;
```

The `< 256` bound exists because `guardianIndex` is a `uint8`. The formula is
floor-based, so it is strictly more than two thirds:

| guardians | `(n*2)/3` | quorum | fraction |
|---|---|---|---|
| 1 | 0 | 1 | 100% |
| 4 | 2 | 3 | 75% |
| 13 | 8 | 9 | 69.2% |
| 19 | 12 | **13** | 68.4% |
| 100 | 66 | 67 | 67% |

Both `parseVM` and `quorum` are `virtual`, so a subclass can override the wire
format or the threshold. That is used by test harnesses and by forks.
