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
out the trap it is guarding: *"if guardianSet key length is 0 and vm.signatures
length is 0, this could compromise the integrity of both vm and signature
verification"*. The concern is the interaction of two lenient primitives —
`quorum(0)` returns `(0*2)/3 + 1 = 1`, and `verifySignatures` returns `true`
unconditionally on an empty array — against a struct whose fields all read as
zero. Rather than reason about whether the arithmetic happens to save them, the
authors cut the whole class off at the root: an unknown guardian set index is
rejected outright, before quorum or signatures are considered at all. That is
the right instinct for a check whose failure mode is total.

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

---

## 2. Publishing a message

Verification is the hard half. Publishing is almost trivially simple, and that
simplicity is the design.

### 2.1 `publishMessage`

[`wormhole/ethereum/contracts/Implementation.sol:15-26`](wormhole/ethereum/contracts/Implementation.sol#L15-L26):

```solidity
function publishMessage(
    uint32 nonce,
    bytes memory payload,
    uint8 consistencyLevel
) public payable returns (uint64 sequence) {
    // check fee
    require(msg.value == messageFee(), "invalid fee");

    sequence = useSequence(msg.sender);
    // emit log
    emit LogMessagePublished(msg.sender, sequence, nonce, payload, consistencyLevel);
}
```

That is the entire on-chain publish path. Walked properly:

- **Inputs.** `nonce` is application-defined and opaque to the protocol.
  `payload` is arbitrary bytes. `consistencyLevel` tells Guardians how long to
  wait before signing.
- **Checks.** Exactly one: `msg.value == messageFee()`, at
  [`:21`](wormhole/ethereum/contracts/Implementation.sol#L21). Note it is
  equality, not `>=`. Overpaying reverts. Integrators must read
  [`messageFee()`](wormhole/ethereum/contracts/Getters.sol#L49) and forward
  precisely that amount, which is why every bridge contract in section 3 threads
  a `wormholeFee` through its accounting.
- **State writes.** One, via
  [`useSequence`](wormhole/ethereum/contracts/Implementation.sol#L28-L31):
  `_state.sequences[msg.sender] += 1`, returning the pre-increment value.
- **External calls.** None. This is important — publishing cannot reenter.
- **Emits.** `LogMessagePublished(sender, sequence, nonce, payload, consistencyLevel)`,
  declared at
  [`:12`](wormhole/ethereum/contracts/Implementation.sol#L12), with `sender`
  indexed.

**There is no storage of the message.** The payload is never written to state; it
exists only as event data. The contract does not know or care whether anyone
observed it. That is what "the core protocol is decoupled from application logic"
actually means in code: the core is a fee-metered, sequence-numbered event
emitter, and everything else is built by reading its logs.

**The emitter is `msg.sender`, always.** There is no way to publish on behalf of
another address on EVM. The whitepaper explains the general rule: the emitter *"is
either a parameter to the postMessage method if the chain allows proving that the
caller controls or is authorized by said address (i.e. Solana PDAs), or it is the
sender of the transaction"*
([`wormhole/whitepapers/0004_message_publishing.md`](wormhole/whitepapers/0004_message_publishing.md)).
EVM has no PDA equivalent, so it takes the second branch. Solana takes the
first — see section 5.

The consequence is that **`(emitterChainId, emitterAddress)` is the security
boundary for every application built on Wormhole.** A VAA proves only "this
address on this chain emitted these bytes". If your destination contract does not
check *who* emitted, anyone can publish a message with your payload format and
your contract will honour it. The token bridge's check is
[`verifyBridgeVM`](wormhole/ethereum/contracts/bridge/Bridge.sol#L774-L777), and
governance's is
[`verifyGovernanceVM`](wormhole/ethereum/contracts/Governance.sol#L190-L220).

Sequence numbers are per-emitter, read back through
[`nextSequence(address)`](wormhole/ethereum/contracts/Getters.sol#L53-L55). They
give each emitter a totally-ordered, gapless message stream. Combined with
`emitterChain` and `emitterAddress`, the triple
`(emitterChain, emitterAddress, sequence)` uniquely identifies a message across
the entire network — that triple is exactly the replay key used on Solana
([`wormhole/solana/bridge/program/src/accounts/claim.rs:108-112`](wormhole/solana/bridge/program/src/accounts/claim.rs#L108-L112)),
whereas EVM instead keys on `vm.hash`.

### 2.2 The contract is not payable, except here

[`wormhole/ethereum/contracts/Implementation.sol:77-79`](wormhole/ethereum/contracts/Implementation.sol#L77-L79):

```solidity
fallback() external payable {revert("unsupported");}
receive() external payable {revert("the Wormhole contract does not accept assets");}
```

Fees accumulate as the contract's ETH balance and are later swept by governance
via `submitTransferFees` (section 4). But you cannot simply send ETH to the core
bridge; the only way in is through `publishMessage`.

### 2.3 What the Guardians actually do

The on-chain half stops at the event. The rest is off-chain and is worth stating
plainly because it is where the trust lives:

1. Each Guardian runs a **full node** for every connected chain. Not a light
   client — a full node. They see `LogMessagePublished` as a normal log.
2. They wait for the requested `consistencyLevel`.
3. Each independently reconstructs the VAA **body** from the log plus block
   metadata, computes `keccak256(keccak256(body))`, and signs it with its
   secp256k1 guardian key.
4. Signatures are gossiped over a p2p network. Once ≥ quorum exist, anyone can
   concatenate header + signatures + body into a VAA.

Step 3 is the interesting one. The `timestamp` field is **not** supplied by the
publisher; it is derived by the Guardians from the block. The whitepaper: *"The
timestamp is derived by the guardian software using the finalized timestamp of
the block the message was published in."* So a VAA's timestamp is an attestation
about the source chain's clock, not a user input.

Step 4 explains why VAAs are bearer credentials and why "relayer" is an
unprivileged role in this protocol. A relayer is just someone willing to pay
destination gas.

### 2.4 `consistencyLevel`, and why finality is per-chain

`consistencyLevel` is one byte, opaque to the contract, and interpreted entirely
by Guardian software. It exists because **finality does not mean the same thing
on every chain**.

On Solana, "confirmed" and "finalized" are distinct states seconds apart. On
Ethereum post-merge there is a two-epoch (~13 minute) finality gap during which a
block can still be reorganised. On BSC or Polygon, deeper reorgs have happened in
production.

This creates a genuine and unavoidable tension. Guardians sign an observation of
a block. If that block is later reorganised away, the Guardians have signed an
attestation to an event that no longer exists — but the VAA is already valid
forever on every other chain, because signatures do not expire. **A reorg after
signing is unrecoverable**: tokens were locked in a transaction that got undone,
yet the mint on the far side is fully authorised.

So `consistencyLevel` is the application's dial between latency and safety. The
whitepaper frames it exactly that way: it *"allows latency sensitive applications
to make sacrifices on safety while critical applications can sacrifice latency
over safety"*, and *"chains with instant finality can omit the argument"*.

The token bridge does not expose the dial to users. It hardcodes a per-deployment
value read from storage,
[`finality()`](wormhole/ethereum/contracts/bridge/BridgeGetters.sol#L75), stored
as a `uint8` at
[`wormhole/ethereum/contracts/bridge/BridgeState.sol:13`](wormhole/ethereum/contracts/bridge/BridgeState.sol#L13),
and passes it on every publish — see `attestToken` at
[`Bridge.sol:253`](wormhole/ethereum/contracts/bridge/Bridge.sol#L253). Moving
money is the "sacrifice latency over safety" case.

### 2.5 The fee model

Fees exist for spam control, not revenue. The whitepaper: *"In order to
incentivize guardians and prevent spamming of the Wormhole network, publishing a
message will require a fee payment."* The fee is denominated in the chain's
native currency, set per chain by governance, and is frequently **zero** on
mainnet EVM deployments — which is why `require(msg.value == messageFee())` with
`msg.value == 0` is the common case and integrators often forget the fee exists
at all until they hit a chain where it does not.
