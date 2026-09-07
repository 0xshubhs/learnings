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
[`Bridge.sol:254`](wormhole/ethereum/contracts/bridge/Bridge.sol#L254). Moving
money is the "sacrifice latency over safety" case.

### 2.5 The fee model

Fees exist for spam control, not revenue. The whitepaper: *"In order to
incentivize guardians and prevent spamming of the Wormhole network, publishing a
message will require a fee payment."* The fee is denominated in the chain's
native currency, set per chain by governance, and is frequently **zero** on
mainnet EVM deployments — which is why `require(msg.value == messageFee())` with
`msg.value == 0` is the common case and integrators often forget the fee exists
at all until they hit a chain where it does not.

---

## 3. The token bridge

Everything so far has been the *core* protocol: publish bytes, verify bytes. The
token bridge (branded "Portal") is an **application** built on top, living in
[`wormhole/ethereum/contracts/bridge/Bridge.sol`](wormhole/ethereum/contracts/bridge/Bridge.sol)
(960 lines). It is a Wormhole *user*, not part of Wormhole.

Its job is to make a token on chain A spendable on chain B, and it does that with
two mechanisms depending on where the token is native.

### 3.1 Lock/mint versus burn/release

```
  Token native to chain A, moving A ──► B
  ────────────────────────────────────────
  A:  safeTransferFrom(user → Bridge)      LOCK   (bridge custodies real tokens)
      bridgeOut(token, normalizedAmount)          (accounting)
  B:  TokenImplementation.mint(recipient)  MINT   (wrapped asset created)

  Same token coming home B ──► A
  ────────────────────────────────────────
  B:  safeTransferFrom(user → Bridge)
      TokenImplementation.burn(...)        BURN   (wrapped supply destroyed)
  A:  safeTransfer(Bridge → recipient)     RELEASE
      bridgedIn(token, normalizedAmount)          (accounting)
```

The branch is decided by comparing the token's home chain to the local chain. On
the way out, [`_transferTokens:419-425`](wormhole/ethereum/contracts/bridge/Bridge.sol#L419-L425):

```solidity
if (isWrappedAsset(token)) {
    tokenChain = TokenImplementation(token).chainId();
    tokenAddress = TokenImplementation(token).nativeContract();
} else {
    tokenChain = chainId();
    tokenAddress = bytes32(uint256(uint160(token)));
}
```

A wrapped asset knows its own origin. Note the crucial consequence: `tokenChain`
and `tokenAddress` in the VAA always describe the **canonical origin** of the
asset, never the local representation. That is what allows a token to hop
A→B→C and still be recognised on C as "the asset from A".

The lock/burn decision itself, [`:434-451`](wormhole/ethereum/contracts/bridge/Bridge.sol#L434-L451):

```solidity
if (tokenChain == chainId()) {
    // ... balanceOf before ...
    SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
    // ... balanceOf after ...
    amount = balanceAfter - balanceBefore;
} else {
    SafeERC20.safeTransferFrom(IERC20(token), msg.sender, address(this), amount);
    TokenImplementation(token).burn(address(this), amount);
}
```

The native branch measures the balance delta rather than trusting `amount`,
which handles fee-on-transfer tokens correctly — the same defensive pattern
LI.FI uses in `LibSwap`. The wrapped branch does not need it, because the bridge
controls that token's implementation.

### 3.2 Normalization: the eight-decimal truncation

This is the detail that trips up every integrator, so derive it properly.

[`wormhole/ethereum/contracts/bridge/Bridge.sol:472-484`](wormhole/ethereum/contracts/bridge/Bridge.sol#L472-L484):

```solidity
function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
    if (decimals > 8) {
        amount /= 10 ** (decimals - 8);
    }
    return amount;
}

function deNormalizeAmount(uint256 amount, uint8 decimals) internal pure returns(uint256){
    if (decimals > 8) {
        amount *= 10 ** (decimals - 8);
    }
    return amount;
}
```

**Why 8?** Because the VAA must be interpretable on chains that cannot represent
18 decimals. Solana's SPL tokens are typically 6 or 9 decimals and amounts are
`u64`. The maximum `u64` is ~1.8×10¹⁹; an 18-decimal token amount of 100 tokens
is 10²⁰, which overflows. Capping the wire format at 8 decimals keeps every
transferable amount inside `u64` and makes the format chain-agnostic. The bridge
enforces that bound explicitly at
[`bridgeOut:765-768`](wormhole/ethereum/contracts/bridge/Bridge.sol#L765-L768):

```solidity
uint outstanding = outstandingBridged(token);
if (outstanding + normalizedAmount > type(uint64).max) revert OutstandingExceedsMax();
```

**The consequence is truncation, and it is lossy.** For an 18-decimal token,
`normalizeAmount` divides by 10¹⁰. Any value below 10¹⁰ wei — that is, below
0.00000001 tokens — normalizes to zero and would simply vanish.

The bridge refuses to let that happen silently. At
[`:432`](wormhole/ethereum/contracts/bridge/Bridge.sol#L432):

```solidity
amount = deNormalizeAmount(normalizeAmount(amount, decimals), decimals);
```

Round-tripping through normalize/denormalize **before** the transfer floors the
amount to the nearest representable value, and only that floored amount is
pulled from the user. Send `1.2345678901234` ETH and the bridge takes
`1.23456789` and leaves the rest in your wallet. The comment calls it exactly
that: *"don't deposit dust that can not be bridged due to the decimal shift"*.

The ETH path handles it differently, because there `msg.value` has already
arrived. [`_wrapAndTransferETH:321-328`](wormhole/ethereum/contracts/bridge/Bridge.sol#L321-L328):

```solidity
uint normalizedAmount = normalizeAmount(amount, 18);
uint normalizedArbiterFee = normalizeAmount(arbiterFee, 18);

// refund dust
uint dust = amount - deNormalizeAmount(normalizedAmount, 18);
if (dust > 0) {
    payable(msg.sender).transfer(dust);
}
```

It cannot decline the dust, so it **refunds** it. Note `.transfer` with its 2300
gas stipend — a contract with a non-trivial `receive()` cannot bridge ETH through
this path if there is any dust. That is a real integration hazard and the reason
sophisticated callers pre-floor their amounts.

Decimals are re-read on the destination side and denormalized back at
[`_completeTransfer:720-722`](wormhole/ethereum/contracts/bridge/Bridge.sol#L720-L722).
Because the wrapped token is created with the *origin* token's decimals (section
3.4), the round trip is faithful.

### 3.3 The three payload types

The core protocol treats payloads as opaque bytes; the token bridge imposes its
own tagging. From
[`BridgeStructs.sol`](wormhole/ethereum/contracts/bridge/BridgeStructs.sol) and
the parsers:

| ID | struct | meaning |
|---|---|---|
| 1 | [`Transfer`](wormhole/ethereum/contracts/bridge/BridgeStructs.sol#L7-L22) | plain token transfer, redeemable by anyone |
| 2 | [`AssetMeta`](wormhole/ethereum/contracts/bridge/BridgeStructs.sol#L56-L69) | token metadata attestation (name, symbol, decimals) |
| 3 | [`TransferWithPayload`](wormhole/ethereum/contracts/bridge/BridgeStructs.sol#L24-L41) | transfer plus arbitrary bytes, redeemable **only** by the recipient |

Payload 1 carries a `fee` field — the "arbiter fee", paid to whoever submits the
VAA. Payload 3 replaces it with `fromAddress` and `payload`, because a
contract-controlled transfer does not need to bribe a relayer; the recipient
contract is the relayer.

The distinction is enforced at
[`_completeTransfer:687-691`](wormhole/ethereum/contracts/bridge/Bridge.sol#L687-L691):

```solidity
address transferRecipient = _truncateAddress(transfer.to);
if (transfer.payloadID == 3) {
    if (msg.sender != transferRecipient) revert InvalidSender();
}
```

**This is the composability primitive.** Payload 3 lets a contract on chain B
receive tokens *and* instructions atomically, knowing that only it could have
redeemed them. That is what protocols like Mayan build on, and it is the direct
analogue of LI.FI's destination-call pattern.

Both parsers funnel into
[`_parseTransferCommon:926-944`](wormhole/ethereum/contracts/bridge/Bridge.sol#L926-L944),
which reads the shared prefix regardless of tag — the comment notes its *"sole
purpose ... is to get around the local variable limit"*, a very Solidity reason
for a function to exist.

### 3.4 `attestToken` and wrapped-asset creation

Before a token can move to a new chain, that chain must be told what it is.

[`attestToken:222-255`](wormhole/ethereum/contracts/bridge/Bridge.sol#L222-L255)
reads `decimals()`, `symbol()`, `name()` via `staticcall` — the comment notes
these *"are not part of the core ERC20 token standard"*, so failures must not
revert the whole call — packs them into an `AssetMeta` (payload 2), and publishes
it. The string→`bytes32` conversion is done in assembly at
[`:234-238`](wormhole/ethereum/contracts/bridge/Bridge.sol#L234-L238), which
**silently truncates** names longer than 32 bytes.

On the far side,
[`_createWrapped:580-615`](wormhole/ethereum/contracts/bridge/Bridge.sol#L580-L615)
consumes it. Two guards first,
[`:581-582`](wormhole/ethereum/contracts/bridge/Bridge.sol#L581-L582):

```solidity
if (meta.tokenChain == chainId()) revert OnlyForeignTokens();
if (wrappedAsset(meta.tokenChain, meta.tokenAddress) != address(0)) revert WrappedAssetAlreadyExists();
```

Then a CREATE2 deploy,
[`:604-613`](wormhole/ethereum/contracts/bridge/Bridge.sol#L604-L613):

```solidity
bytes32 salt = keccak256(abi.encodePacked(meta.tokenChain, meta.tokenAddress));

assembly {
    token := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
    if iszero(extcodesize(token)) { revert(0, 0) }
}
```

**The salt is the canonical origin, so the wrapped address is deterministic.**
Anyone can compute where wrapped-USDC-from-Ethereum will live on Polygon before
it is deployed — the same CREATE2 determinism you saw in Uniswap V2's `pairFor`.

The deployed contract is a `BridgeToken` beacon proxy pointing at
[`TokenImplementation`](wormhole/ethereum/contracts/bridge/token/TokenImplementation.sol),
initialised with the **origin token's** decimals, so a 6-decimal USDC stays
6-decimal everywhere.

`updateWrapped` /
[`_updateWrapped:559-567`](wormhole/ethereum/contracts/bridge/Bridge.sol#L559-L567)
refreshes name and symbol from a newer attestation, gated on the attestation's
`sequence` so an old VAA cannot roll metadata backwards.

### 3.5 `_completeTransfer`, the redemption path

[`wormhole/ethereum/contracts/bridge/Bridge.sol:679-762`](wormhole/ethereum/contracts/bridge/Bridge.sol#L679-L762)
is where a VAA becomes tokens. All four public entry points reach it:

| entry point | `unwrapWETH` | payload |
|---|---|---|
| [`completeTransfer`](wormhole/ethereum/contracts/bridge/Bridge.sol#L652) | false | 1 |
| [`completeTransferAndUnwrapETH`](wormhole/ethereum/contracts/bridge/Bridge.sol#L663) | true | 1 |
| [`completeTransferWithPayload`](wormhole/ethereum/contracts/bridge/Bridge.sol#L627) | false | 3 |
| [`completeTransferAndUnwrapETHWithPayload`](wormhole/ethereum/contracts/bridge/Bridge.sol#L641) | true | 3 |

The ordered checks, [`:680-700`](wormhole/ethereum/contracts/bridge/Bridge.sol#L680-L700):

1. **`parseAndVerifyVM`** — the core protocol validates signatures and quorum
   (section 1). Everything downstream assumes this passed.
2. **`verifyBridgeVM`** — is the emitter the registered token bridge on that
   chain? [`:774-777`](wormhole/ethereum/contracts/bridge/Bridge.sol#L774-L777):
   `bridgeContracts(vm.emitterChainId) == vm.emitterAddress`. Without this, any
   contract could emit a payload-1-shaped message and mint. Note it also rejects
   forks via `if (isFork()) revert InvalidFork()`.
3. **Payload-3 recipient gate** (section 3.3).
4. **Replay protection**, [`:693-694`](wormhole/ethereum/contracts/bridge/Bridge.sol#L693-L694):
   ```solidity
   if (isTransferCompleted(vm.hash)) revert TransferAlreadyCompleted();
   setTransferCompleted(vm.hash);
   ```
   Keyed on `vm.hash`, set **before** any transfer — checks-effects-interactions,
   on top of the `nonReentrant` modifier. This is precisely the invariant that the
   *"do not change how the hash is computed"* warning in section 1.3 protects.
5. **`transfer.toChain != chainId()`** — a VAA addressed to Polygon cannot be
   redeemed on Ethereum, even though the signatures are valid on both.

Then payout, [`:701-712`](wormhole/ethereum/contracts/bridge/Bridge.sol#L701-L712):
if the token is native here, take the custodied ERC20 and call `bridgedIn` to
decrement outstanding accounting; otherwise look up the wrapped asset and revert
with `WrappedAssetNotFound` if it was never created.

The arbiter fee is split off at
[`:724-747`](wormhole/ethereum/contracts/bridge/Bridge.sol#L724-L747), paid to
`msg.sender` only when the submitter is not the recipient — otherwise it is zeroed
so you cannot pay yourself. Then the remainder goes to the recipient by mint (if
wrapped) or transfer (if native), with a WETH-unwrap variant.

### 3.6 The accounting invariant

[`:764-772`](wormhole/ethereum/contracts/bridge/Bridge.sol#L764-L772):

```solidity
function bridgeOut(address token, uint normalizedAmount) internal {
    uint outstanding = outstandingBridged(token);
    if (outstanding + normalizedAmount > type(uint64).max) revert OutstandingExceedsMax();
    setOutstandingBridged(token, outstanding + normalizedAmount);
}

function bridgedIn(address token, uint normalizedAmount) internal {
    setOutstandingBridged(token, outstandingBridged(token) - normalizedAmount);
}
```

`outstandingBridged` tracks, per native token, how much has left this chain. It
is incremented on lock and decremented on release, and only for tokens native
here. The `uint64` ceiling is the `u64` compatibility bound from section 3.2. The
subtraction in `bridgedIn` is unchecked-by-absence — in Solidity 0.8 it reverts
on underflow, which is the desired behaviour: it is a solvency assertion. You
cannot release more than was ever locked.

---

## 4. Governance and the guardian set

Wormhole governs itself with its own messages. There is no owner address, no
timelock contract, no multisig on the destination chain. To change anything, the
Guardians sign a VAA and anyone submits it.

That is elegant and it is also the whole risk: the entity that secures the bridge
is the entity that can rewrite the bridge.

### 4.1 What makes a VAA a *governance* VAA

Four extra conditions on top of normal verification, in
[`verifyGovernanceVM:190-220`](wormhole/ethereum/contracts/Governance.sol#L190-L220):

```solidity
(bool isValid, string memory reason) = verifyVM(vm);
if (!isValid){ return (false, reason); }

// only current guardianset can sign governance packets
if (vm.guardianSetIndex != getCurrentGuardianSetIndex()) {
    return (false, "not signed by current guardian set");
}

if (uint16(vm.emitterChainId) != governanceChainId()) {
    return (false, "wrong governance chain");
}

if (vm.emitterAddress != governanceContract()) {
    return (false, "wrong governance contract");
}

if (governanceActionIsConsumed(vm.hash)){
    return (false, "governance action already consumed");
}
```

**The current-set requirement is stricter than normal verification.** Section 1.5
gate 3 accepts an expired-but-not-yet-lapsed old set for ordinary messages.
Governance does not: an old set, however recently retired, cannot sign governance
even inside its grace window. A retired quorum can therefore never un-retire
itself.

**Emitter pinning.** Governance messages must come from a fixed
`(governanceChainId, governanceContract)` pair, set once in
[`Setup.setup:32-33`](wormhole/ethereum/contracts/Setup.sol#L32-L33). Historically
this is a Solana address — Ethereum's comment at
[`Governance.sol:202`](wormhole/ethereum/contracts/Governance.sol#L202) still says
*"Verify the VAA is from the governance chain (Solana)"*.

**Replay protection** keyed on `vm.hash` in
`_state.consumedGovernanceActions`, declared at
[`State.sol:38`](wormhole/ethereum/contracts/State.sol#L38). Every handler calls
`setGovernanceActionConsumed(vm.hash)` **before** acting.

### 4.2 The handlers

All five follow one shape: parse, verify, check module, check chain, mark
consumed, act.

| function | action byte | effect |
|---|---|---|
| [`submitContractUpgrade`](wormhole/ethereum/contracts/Governance.sol#L27-L49) | 1 | replace the implementation |
| [`submitNewGuardianSet`](wormhole/ethereum/contracts/Governance.sol#L79-L112) | 2 | rotate the guardian set |
| [`submitSetMessageFee`](wormhole/ethereum/contracts/Governance.sol#L54-L74) | 3 | change `messageFee` |
| [`submitTransferFees`](wormhole/ethereum/contracts/Governance.sol#L117-L141) | 4 | sweep accumulated fees |
| [`submitRecoverChainId`](wormhole/ethereum/contracts/Governance.sol#L146-L169) | 5 | fix chain ids after a fork |

The module constant scopes a VAA to the core bridge,
[`Governance.sol:22`](wormhole/ethereum/contracts/Governance.sol#L22):

```solidity
bytes32 constant module = 0x00000000000000000000000000000000000000000000000000000000436f7265;
```

Those trailing bytes are ASCII `"Core"`. The token bridge uses `"TokenBridge"`
in its own governance, so a core-bridge upgrade VAA cannot be replayed against
the token bridge even though both verify against the same Guardians.

The chain check varies meaningfully. Contract upgrades demand
`upgrade.chain == chainId()` exactly
([`:42`](wormhole/ethereum/contracts/Governance.sol#L42)) — you cannot broadcast
one implementation address to every chain. But guardian set upgrades accept
`chain == 0` as a wildcard
([`:92`](wormhole/ethereum/contracts/Governance.sol#L92)):

```solidity
require((upgrade.chain == chainId() && !isFork()) || upgrade.chain == 0, "invalid Chain");
```

That is deliberate: a guardian rotation must reach *every* chain, and one VAA
broadcast everywhere is exactly right.

### 4.3 Guardian set rotation and the grace window

[`submitNewGuardianSet:94-111`](wormhole/ethereum/contracts/Governance.sol#L94-L111)
carries three guards worth naming:

```solidity
require(upgrade.newGuardianSet.keys.length > 0, "new guardian set is empty");
require(upgrade.newGuardianSetIndex == getCurrentGuardianSetIndex() + 1, "index must increase in steps of 1");
...
expireGuardianSet(getCurrentGuardianSetIndex());
storeGuardianSet(upgrade.newGuardianSet, upgrade.newGuardianSetIndex);
updateGuardianSetIndex(upgrade.newGuardianSetIndex);
```

**Non-empty** guards against the bricking scenario section 1.5 gate 2 also
defends. **Strictly +1** prevents skipping indices, which keeps the set history
dense and makes "index 7 exists" equivalent to "seven rotations have happened".
`storeGuardianSet` additionally rejects any zero key at
[`Setters.sol:19-21`](wormhole/ethereum/contracts/Setters.sol#L19-L21), closing
the `ecrecover`-returns-zero hole from the other side.

The grace window is one line,
[`Setters.sol:13-15`](wormhole/ethereum/contracts/Setters.sol#L13-L15):

```solidity
function expireGuardianSet(uint32 index) internal {
    _state.guardianSets[index].expirationTime = uint32(block.timestamp) + 86400;
}
```

**86400 seconds — 24 hours.** The old set stays valid for one day after being
replaced.

Why it must exist: VAAs are produced asynchronously and consumed whenever someone
gets around to submitting them. At the instant of rotation there are in-flight
VAAs already signed by the old set, sitting in relayer queues or in users'
browsers. Without a window every one of them would become permanently
unredeemable, and for the token bridge that means **tokens locked on the source
chain with no way to mint on the destination**. The window lets that backlog
drain.

Why it must be bounded: a retired set is retired for a reason, often because keys
were rotated after suspected compromise. An unbounded window would mean old keys
never lose power. Twenty-four hours is the compromise, and note it is applied to
the *old* set at rotation time, not set on the new one.

### 4.4 Upgrades

[`upgradeImplementation:174-185`](wormhole/ethereum/contracts/Governance.sol#L174-L185)
is a standard ERC-1967 upgrade plus a forced initializer:

```solidity
_upgradeTo(newImplementation);

(bool success, bytes memory reason) = newImplementation.delegatecall(abi.encodeWithSignature("initialize()"));
require(success, string(reason));
```

The proxy is
[`Wormhole.sol`](wormhole/ethereum/contracts/Wormhole.sol), a bare `ERC1967Proxy`
constructed pointing at `Setup`, which does one-time wiring and then immediately
`_upgradeTo(implementation)`
([`Setup.sol:37`](wormhole/ethereum/contracts/Setup.sol#L37)).

`initialize()` is guarded by a per-implementation flag rather than a version
number, [`Implementation.sol:64-75`](wormhole/ethereum/contracts/Implementation.sol#L64-L75),
recording `initializedImplementations[impl]`. That allows re-upgrading to a
previously used implementation address without re-running its initializer.

Note there is **no timelock**. A contract upgrade VAA takes effect the moment
anyone submits it. The delay, such as it is, is entirely social: it lives in the
Guardians' willingness to sign.

### 4.5 The fork story

`isFork()` at
[`Getters.sol:37-39`](wormhole/ethereum/contracts/Getters.sol#L37-L39) is a
single comparison:

```solidity
return evmChainId() != block.chainid;
```

The contract remembers the EIP-155 chain id it was deployed on. If the chain
hard-forks and the copy runs under a new `block.chainid`, that comparison flips
and the contract knows it is on the wrong side of history.

The response is aggressive. `submitContractUpgrade` refuses outright
([`:28`](wormhole/ethereum/contracts/Governance.sol#L28)), and
`verifyBridgeVM` in the token bridge reverts on any redemption
([`Bridge.sol:775`](wormhole/ethereum/contracts/bridge/Bridge.sol#L775)). A
forked deployment is frozen, not merely degraded.

This is a genuinely thoughtful piece of design and the reason is worth stating.
Signatures do not know about forks. Every VAA valid on the canonical chain is
equally valid on the fork, so without this check a fork would let every locked
token be minted twice. `submitRecoverChainId` is the deliberate, governance-gated
escape hatch for a legitimate fork, and its own check
([`:161`](wormhole/ethereum/contracts/Governance.sol#L161)) pins
`rci.evmChainId == block.chainid` so the recovery VAA is only usable on the
intended side.

---

## 5. The same protocol in Rust

Everything in sections 1 through 4 exists again in
[`wormhole/solana/bridge/program/src/`](wormhole/solana/bridge/program/src), in
Rust, doing the same job against a completely different execution model.

This section is not exhaustive. It picks four places where Solana's account model
**forces** a different design and explains why. The goal is that you can read
Solana code afterwards, not write it.

### 5.0 The three facts you need first

**1. Programs are stateless; accounts hold state.** An EVM contract owns its
storage. A Solana program owns nothing. Every byte it touches arrives as an
account passed in by the caller, and the program must *verify* that the accounts
it received are the ones it expected. That verification is the security model.

**2. A PDA is a deterministic address derived from seeds.** Where Solidity writes
`mapping(bytes32 => bool)`, Solana derives an address from seeds and checks
whether an account exists there. A PDA has no private key, so only the owning
program can sign for it.

**3. Transactions are bounded and small.** ~1232 bytes and a compute budget. You
cannot loop over 13 `ecrecover` calls and 13 storage reads in one instruction.

Fact 3 is the one that reshapes VAA verification entirely.

### 5.1 Verification is split across transactions

On EVM, `parseAndVerifyVM` is one call. On Solana it is a **multi-transaction
protocol** with an intermediate account holding partial progress.

```
  EVM                          SOLANA
  ───                          ──────
  parseAndVerifyVM(bytes)      tx 1: [secp256k1 ix][verify_signatures ix]  ─┐
    ├ parse                    tx 2: [secp256k1 ix][verify_signatures ix]   ├─► SignatureSet
    ├ check set                ...                                          │   account
    ├ check quorum             tx N: [secp256k1 ix][verify_signatures ix]  ─┘   accumulates
    ├ 13× ecrecover
    └ done, one tx             tx N+1: post_vaa  ──► reads SignatureSet,
                                                     checks quorum,
                                                     writes PostedVAA account

                               tx N+2: your program reads PostedVAA
```

**Signatures are not verified by the Wormhole program at all.** They are verified
by Solana's native `secp256k1_program`, and the Wormhole program's job is to
*inspect the transaction it is sitting in* and confirm that the neighbouring
instruction did the right work.

[`verify_signature.rs:91-108`](wormhole/solana/bridge/program/src/api/verify_signature.rs#L91-L108):

```rust
let current_instruction =
    solana_program::sysvar::instructions::load_current_index_checked(&accs.instruction_acc)?;
if current_instruction == 0 {
    return Err(InstructionAtWrongIndex.into());
}

// The previous ix must be a secp verification instruction
let secp_ix_index = (current_instruction - 1) as u8;
let secp_ix = solana_program::sysvar::instructions::load_instruction_at_checked(
    secp_ix_index as usize,
    &accs.instruction_acc,
)
.map_err(|_| ProgramError::InvalidAccountData)?;

// Check that the instruction is actually for the secp program
if secp_ix.program_id != solana_program::secp256k1_program::id() {
    return Err(InvalidSecpInstruction.into());
}
```

This has no EVM analogue whatsoever. There is no "read the previous opcode" in
Solidity. **Introspection of sibling instructions is a first-class Solana
pattern**, and section 7 explains how getting it wrong cost $326M.

The program then re-parses the secp instruction's own data layout to learn which
addresses were proven and over which message
([`:115-152`](wormhole/solana/bridge/program/src/api/verify_signature.rs#L115-L152)),
insisting every signature covered the *same* message
([`:141-146`](wormhole/solana/bridge/program/src/api/verify_signature.rs#L141-L146))
and that the message is exactly 32 bytes
([`:157-160`](wormhole/solana/bridge/program/src/api/verify_signature.rs#L157-L160)).

Finally it records progress into the `SignatureSet`
([`:196-215`](wormhole/solana/bridge/program/src/api/verify_signature.rs#L196-L215)):

```rust
let key = accs.guardian_set.keys[s.signer_index as usize];
// Check key in ix
if key != secp_ixs[s.sig_index as usize].address {
    return Err(ProgramError::InvalidArgument.into());
}

// Overwritten content should be zeros except double signs by the signer or harmless replays
accs.signature_set.signatures[s.signer_index as usize] = true;
```

**Note the data structure.** EVM uses an *array of signatures* and enforces
strictly ascending indices to prevent double-counting (section 1.4). Solana uses
a **bitmap indexed by guardian index**, `signatures: vec![false; keys.len()]`
([`:171`](wormhole/solana/bridge/program/src/api/verify_signature.rs#L171)).
Setting the same bit twice is idempotent, so duplicates are structurally
impossible and no ordering rule is needed. That is not a stylistic difference; it
falls out of the fact that state persists across transactions, so a bitmap can be
accumulated where an array could not.

The first call creates the account and pins its parameters; later calls must
match ([`:170-194`](wormhole/solana/bridge/program/src/api/verify_signature.rs#L170-L194)):

```rust
if accs.signature_set.guardian_set_index != accs.guardian_set.index {
    return Err(GuardianSetMismatch.into());
}

if accs.signature_set.hash != msg_hash {
    return Err(InvalidHash.into());
}
```

Without those two checks an attacker could accumulate signatures for VAA A and
then swap in VAA B's hash.

### 5.2 Quorum, and the same formula written differently

[`post_vaa.rs:122-138`](wormhole/solana/bridge/program/src/api/post_vaa.rs#L122-L138):

```rust
let signature_count: usize = accs.signature_set.signatures.iter().filter(|v| **v).count();

// Calculate how many signatures are required to reach consensus. This calculation is in
// expanded form to ease auditing.
let required_consensus_count = {
    let len = accs.guardian_set.keys.len();
    // Fixed point number transformation with one decimal to deal with rounding.
    let len = (len * 10) / 3;
    // Multiplication by two to get a 2/3 quorum.
    let len = len * 2;
    // Division to bring number back into range.
    len / 10 + 1
};

if signature_count < required_consensus_count {
    return Err(PostVAAConsensusFailed.into());
}
```

Compare with EVM's `((numGuardians * 2) / 3) + 1`. These are **not the same
expression**. Solana computes `((n*10/3)*2)/10 + 1`; EVM computes `(n*2)/3 + 1`.
Integer division at different points can diverge. For n=19: Solana gives
`(190/3)*2/10 + 1 = 63*2/10 + 1 = 126/10 + 1 = 12 + 1 = 13`. EVM gives
`38/3 + 1 = 12 + 1 = 13`. They agree here, and the comment's *"expanded form to
ease auditing"* is doing real work — but two implementations of a consensus
threshold written as different expressions is exactly the kind of thing worth
differential-testing.

Note also `signature_count` counts **set bits**, not array length. The bitmap
makes the count trivially sound.

### 5.3 Replay protection: a PDA instead of a mapping

EVM: `mapping(bytes32 => bool) completedTransfers`, keyed on `vm.hash`.

Solana has no mappings. Instead it derives an address from seeds and the *account
either exists or does not*. [`claim.rs:108-120`](wormhole/solana/bridge/program/src/accounts/claim.rs#L108-L120):

```rust
pub struct ClaimDerivationData {
    pub emitter_address: [u8; 32],
    pub emitter_chain: u16,
    pub sequence: u64,
}

impl<'b> Seeded<&ClaimDerivationData> for Claim<'b> {
    fn seeds(data: &ClaimDerivationData) -> Vec<Vec<u8>> {
        return vec![
            data.emitter_address.to_vec(),
            data.emitter_chain.to_be_bytes().to_vec(),
            data.sequence.to_be_bytes().to_vec(),
        ];
    }
}
```

**The key differs from EVM's.** Solana keys on the triple
`(emitter_address, emitter_chain, sequence)`; EVM keys on `vm.hash`. Both
uniquely identify a message (section 2.1), but the mechanism differs: creating a
PDA that already exists fails at the runtime level, so "mark as consumed" is
"create the account" and "check if consumed" is "try to create it".

Existence-as-a-boolean has a cost EVM does not have: **someone must pay rent**.
Every claim account is rent-exempt lamports locked forever, which is why the
program also ships `close_posted_message` and
`close_signature_set_and_posted_vaa` instructions — reclaiming rent is a first-class
concern, and nothing in the EVM contracts corresponds to it at all.

The posted VAA is itself a PDA keyed on the message hash,
[`posted_vaa.rs:34-38`](wormhole/solana/bridge/program/src/accounts/posted_vaa.rs#L34-L38):

```rust
fn seeds(data: &PostedVAADerivationData) -> Vec<Vec<u8>> {
    vec![b"PostedVAA".to_vec(), data.payload_hash.to_vec()]
}
```

So `post_vaa` is idempotent by construction — if the account exists, it returns
early ([`post_vaa.rs:112-114`](wormhole/solana/bridge/program/src/api/post_vaa.rs#L112-L114)).

And sequence numbers, which on EVM are `mapping(address => uint64)`, are their own
PDA per emitter, [`sequence.rs:28-37`](wormhole/solana/bridge/program/src/accounts/sequence.rs#L28-L37):

```rust
fn seeds(data: &SequenceDerivationData) -> Vec<Vec<u8>> {
    vec![
        "Sequence".as_bytes().to_vec(),
        data.emitter_key.to_bytes().to_vec(),
    ]
}
```

### 5.4 The emitter, and why Solana can do what EVM cannot

Recall section 2.1: on EVM the emitter is forced to `msg.sender` because the
chain cannot prove delegated authority. Solana can, and the account struct shows
it, [`post_message.rs:36-53`](wormhole/solana/bridge/program/src/api/post_message.rs#L36-L53):

```rust
pub struct PostMessage<'b> {
    /// Bridge config needed for fee calculation.
    pub bridge: Mut<Bridge<'b, { AccountState::Initialized }>>,

    /// Account to store the posted message
    pub message: Signer<Mut<UninitializedMessage<'b>>>,

    /// Emitter of the VAA
    pub emitter: Signer<MaybeMut<Info<'b>>>,

    /// Tracker for the emitter sequence
    pub sequence: Mut<Sequence<'b>>,
    ...
}
```

`emitter` is a **`Signer`**, an arbitrary account that signed the transaction.
Because a program can sign for its own PDAs, a Solana program can emit under a
PDA address it controls — the whitepaper's *"if the chain allows proving that the
caller controls or is authorized by said address (i.e. Solana PDAs)"* branch.

The practical consequence for anyone reading VAAs: **an emitter address from
Solana is a 32-byte pubkey that may be a PDA, and it is not derived from
`msg.sender` semantics.** Your `verifyBridgeVM`-equivalent check must be against
a registered address, never against any assumed derivation.

Also note `message` is a `Signer` too, and `Uninitialized` — a fresh keypair per
message, created in the same transaction. Where EVM emits a log and forgets,
Solana **allocates an account per message** and pays rent for it. Messages are
state on Solana and ephemera on EVM, which is the single starkest illustration
of the two models.
