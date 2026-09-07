# Session log — how these documents were produced

A record of what was run and what came out of it, across two rounds. Everything
planned was completed; nothing is outstanding.

## What was set up

Nineteen protocol repositories were shallow-cloned and their `.git` directories
removed, giving one flat greppable corpus:

```
uni/     v1-contracts  v2-core  v2-periphery  v3-core  v3-periphery  v4-core
curve/   curve-contract  stableswap-ng  curve-dao-contracts
aave/    v1-aave-protocol  v2-protocol  v3-core-original  aave-v3-origin  v4-aave
lifi/    contracts
morpho/  morpho-blue  metamorpho  morpho-blue-oracles  morpho-blue-bundlers
liquity/ v1-dev  v2-bold
```

Aave v4 turned out to be public at `aave/aave-v4`, with audits dated through
2026, so it is covered from real source rather than from the announcement.

## How the work was split

Twenty-nine agent runs across three waves, each owning exactly one file. Two
layers were commissioned: **deep dives** that teach the ideas and derive the
math, and **complete references** that walk every contract and every function.
Running them in parallel meant each wave landed in roughly the time one document
takes rather than in sequence over many hours.

Wave one lost six agents to a session rate limit; three were resumed from their
own transcripts and finished. Wave two produced eleven finished documents and
eight partial ones before it was stopped to conserve budget. Wave three finished
all eight partials and wrote the one document that had never been started.

The single most common failure was a Bash heredoc exceeding the exec limit
mid-write. Wave three briefs required chunked appends and none hit it.

## The documents

All twenty-four are complete. Deep dives first, then references.

| Document | Lines | Coverage |
|---|---|---|
| `uni/UNISWAP-V1-DEEP-DIVE.md` | 1,327 | all 44 functions of both contracts |
| `uni/UNISWAP-DEEP-DIVE.md` | 874 | v2, v3, v4 |
| `curve/CURVE-DEEP-DIVE.md` | 988 | StableSwap classic and NG, the veCRV flywheel |
| `aave/AAVE-V1-V2-DEEP-DIVE.md` | 960 | |
| `aave/AAVE-DEEP-DIVE.md` | 773 | v3.6 |
| `aave/AAVE-V4-DEEP-DIVE.md` | 1,255 | Hub and Spoke |
| `lifi/LIFI-DEEP-DIVE.md` | 1,204 | |
| `aave/V3-PROTOCOL-COMPLETE-REFERENCE.md` | 4,102 | 60 files |
| `aave/V3-PERIPHERY-COMPLETE-REFERENCE.md` | 3,756 | 154 files |
| `aave/V1-V2-COMPLETE-REFERENCE.md` | 3,498 | 73 v1 + 121 v2 files |
| `curve/DAO-COMPLETE-REFERENCE.md` | 3,428 | 68 files |
| `lifi/LIBRARIES-PERIPHERY-COMPLETE-REFERENCE.md` | 3,271 | 97 files |
| `uni/V3-PERIPHERY-COMPLETE-REFERENCE.md` | 3,181 | 76 files |
| `curve/STABLESWAP-NG-COMPLETE-REFERENCE.md` | 3,126 | 21 files |
| `aave/V4-COMPLETE-REFERENCE.md` | 2,900 | 119 files |
| `uni/V3-CORE-COMPLETE-REFERENCE.md` | 2,689 | 62 files |
| `uni/V4-COMPLETE-REFERENCE.md` | 2,638 | 84 files |
| `uni/V2-COMPLETE-REFERENCE.md` | 2,447 | 35 files |
| `lifi/FACETS-COMPLETE-REFERENCE.md` | 2,239 | all 42 facets |
| `curve/CLASSIC-POOLS-COMPLETE-REFERENCE.md` | 1,993 | 33 pools, 5 templates, 22 zaps, 77 files |
| `morpho/MORPHO-COMPLETE-REFERENCE.md` | 2,521 | 102 files across four repos |
| `liquity/LIQUITY-COMPLETE-REFERENCE.md` | 2,119 | v1 and v2 in full |
| `morpho/MORPHO-DEEP-DIVE.md` | 1,237 | written as a comparison against Aave |
| `liquity/LIQUITY-DEEP-DIVE.md` | 1,078 | v1 and v2 |

Every reference ends with selector tables computed rather than transcribed, a
storage-layout table, an events reference, a revert decoder, and a use-case
index mapping intents to full internal call chains.

## Verified rather than assumed

These are the claims most likely to be wrong in notes written from memory, so
each was checked against the compiler, `cast`, or a real grep:

- The `v3-core` tree compiles to the canonical mainnet `POOL_INIT_CODE_HASH`, so
  the cloned source is the deployed protocol.
- Uniswap v4 selectors were recomputed with `cast sig`. The repo's own
  `signatures/` JSON is wrong for `swap`, having hashed the literal word
  `PoolKey` instead of the expanded tuple.
- Aave `supply(address,uint256,address,uint16)` computes to `0x617ba037`,
  matching mainnet, which validates the whole extracted selector table.
- Curve classic pools span Vyper 0.1.0b16 to 0.2.12, so none is affected by the
  July 2023 `@nonreentrant` compiler bug. The DAO tree does contain affected
  versions, but none of those contracts uses `@nonreentrant`.
- `aave/aave-v3-origin` says 3.6.0 in `package.json` but ships a `docs/3.7/`
  changelog describing this code, so it is unreleased 3.7.

## Things the exhaustive pass found that the conceptual pass did not

Real defects and hazards in shipped code, each confirmed against source:

- `UniswapV2Router01.getAmountIn` calls `UniswapV2Library.getAmountOut`. Fixed in
  Router02. Only the public view helper was affected.
- `Quoter` and `QuoterV2` share selectors for `quoteExactInput` and
  `quoteExactOutput`. Return types are not part of a selector, so a V1 ABI
  pointed at a V2 quoter decodes garbage instead of reverting.
- `LibSwap.swap` performs no allowlist check of its own; the gate lives in its
  callers. `Executor` has no allowlist at all and is safe only because it holds
  no funds and rejects `callTo == erc20Proxy`.
- `PoolProxySidechain.bridge` asserts `minimum >= balance` while its message and
  docstring say the balance must exceed the minimum, and it transfers before
  checking.
- `CRVInfo.add_contract` is a no-op: the constructor sets `num_contracts = 18`
  without populating the array, so writes land past where reads stop.
- Aave v2's `AaveOracle` calls `latestAnswer()` with no staleness or
  round-completeness check, so a frozen feed is undetectable.
- Aave v2 `Errors.sol` codes are not in declaration order. Match on the
  identifier, not the number.

## Known limits

- Storage layouts in the Aave references are hand-derived, not compiler-checked,
  because `lib/` holds only submodule stubs so `forge inspect` cannot run. The
  documents say so where it applies.
- Audit PDFs are inventoried but unread.
- Curve classic pool `A` and fee values are recorded only where `pooldata.json`
  states them; the 0.1.0b generation set those at deploy time.


## Round two: Morpho and Liquity

Added after the original four, to fill the two clearest gaps. Morpho Blue does
roughly what Aave v3 does in 557 lines of core rather than 10,000, and DefiLlama
ranks it 9th overall at $9.72B. Liquity is a fully immutable CDP stablecoin with
no governance.

This round hit a different failure mode: **the Claude Code session restarted
three times**, killing every writing agent each time. The first restart cost an
entire document, which had been written in one large heredoc and never saved. The
fix was to have each agent commit after every section it finished, so a restart
costs one section instead of the whole file. After that change, two further
restarts cost nothing.

One restart also **injected NUL bytes into two documents mid-write**, 2,701 into
the Liquity deep dive and 1,470 into the Liquity reference. Both were detected by
a byte-level check rather than by reading, and both were repaired. Every document
in the repo is now verified NUL-free. If agents are writing files here again, keep
that check in the finish criteria.

### What round two found

- **Morpho Blue has zero reentrancy guards** across all 557 lines, and is still
  sound: state is written before every callback, the only post-callback work is
  transferring a pre-computed amount, and health is asserted last.
- **Its anti-inflation defence is not the virtual shares everyone cites.** The
  contract never reads `balanceOf` for accounting at all, so donations are simply
  lost. Verified: `grep balanceOf src/Morpho.sol` returns nothing.
- **This Liquity tree has no epoch machinery.** `grep -c 'epoch'` on the v1
  StabilityPool returns 0, and the `Snapshots` struct is `{S, P, G, scale}`. The
  epoch design every write-up describes was replaced by `MIN_LUSD_IN_SP = 1e18`,
  which keeps the pool from emptying so `P` can never reach zero. Both Liquity
  agents initially described epochs; both corrected themselves against the source.
- **Liquity v2's price feed returns two different prices**, the max of market and
  canonical for redemptions and the min for everything else, so an oracle
  discrepancy always prices against whoever is acting.
