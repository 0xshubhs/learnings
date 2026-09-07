# Practice

Reading these documents will not make the material stick. Doing will. This is a
graded plan built on what is already in the repo: **58 tracing exercises** spread
across the seven deep dives, plus hands-on labs against test suites that
actually run.

Two kinds of work here.

**Tracing** means opening a file at a line and following the logic on paper,
predicting what happens before you look. It is slow and it is the part that
builds intuition. The exercises live at the end of each deep dive.

**Labs** mean running code, breaking it, and watching it fail. Two protocol test
suites are wired up for this.

---

## Setup

The protocol repos were cloned shallow, so their `lib/` submodules are empty and
`forge test` cannot run. One script fixes that:

```bash
./setup-labs.sh          # or: ./setup-labs.sh uni   /   ./setup-labs.sh aave
```

Then confirm both work:

```bash
cd uni/v4-core         && FOUNDRY_PROFILE=debug forge test --match-path test/libraries/Hooks.t.sol
cd aave/aave-v3-origin && forge test --match-path tests/protocol/pool/Pool.Supply.t.sol
```

You should see 45 passing and 13 passing respectively. The fetched dependencies
are gitignored, so the repo stays small and the script is the source of truth.

One trap worth knowing, because it cost an hour to find: **forge-std must be
v1.9.5**. It is the only release that has both `src/mocks/MockERC20.sol`, removed
in v1.9.6, and the newer `Vm.expectEmit` overload, added after v1.9.4. Both trees
need both. Do not upgrade it.

---

## The plan

Seven weeks if you do one section per sitting. Faster if you already know the
territory. Each week is: read, then trace, then build.

### Week 1 — the smallest AMM that ever shipped

Read `uni/UNISWAP-V1-DEEP-DIVE.md` end to end. It is one afternoon and it is the
cheapest way to internalise `x*y=k`, LP shares, and the exact-in versus exact-out
distinction with nothing else in the way.

Then do all 8 exercises at the end of it. Exercise 5 is the one that matters:
predict the assertions in `v1-contracts/tests/exchange/test_token_to_token.py`
before reading them.

**Build:** on paper, derive `getOutputPrice` from `x*y=k` without looking. Then
check your `+1` against the source. If you did not independently arrive at the
`+1`, you have not understood who it protects.

### Week 2 — Uniswap V2, the pattern half of DeFi copies

Read `uni/UNISWAP-DEEP-DIVE.md` sections 0 and 1. Do exercises 1 and 2.

**Lab:** the k-check is the whole security model. Open
`uni/v2-core/contracts/UniswapV2Pair.sol` at the `swap` function, change `1000`
to `1001` in the adjusted-balance comparison, and reason about who can now steal
what. Revert it.

**Build:** write down, from memory, the full call chain of
`swapExactTokensForTokens` from router to pair to callback. Then check against
section 1.11.

### Week 3 — Curve, where the curve is the product

Read `curve/CURVE-DEEP-DIVE.md` sections 0 and 1. Do exercises 1 through 4.

This is the week with real math. Derive the Newton iteration for `get_D`
yourself before reading section 1.4. Exercise 4, computing `fee_dyn / fee` at
several imbalance ratios, is the one that makes the dynamic fee click.

**Build:** implement `get_D` in Python for a 3-coin pool and check it converges
to the same value the contract does for a balanced pool.

### Week 4 — Uniswap V3, the hardest math in the set

Read `uni/UNISWAP-DEEP-DIVE.md` section 2. Do exercises 3 through 6.

Exercise 4 is the important one: prove to yourself that `feeGrowthInside` only
counts fees earned while the price was in range. If you cannot explain the
`feeGrowthOutside` flip on `Tick.cross`, do it again.

**Build:** pick a position range and a price path, and hand-compute the fees
owed. Then read `uni/V3-CORE-COMPLETE-REFERENCE.md` for the rounding you got
wrong.

### Week 5 — lending

Read `aave/AAVE-V1-V2-DEEP-DIVE.md`, then `aave/AAVE-DEEP-DIVE.md`. Reading v1
and v2 first makes v3's choices legible as answers to specific failures rather
than arbitrary complexity. Do 8 exercises from each.

**Lab, and this is the best one in the set.** Aave's suite runs:

```bash
cd aave/aave-v3-origin
forge test --match-path tests/protocol/pool/Pool.Liquidations.t.sol -vvv
```

Read a liquidation test, predict the health factor at each step, then run with
`-vvvv` to see every internal call. Then break something on purpose: change the
close-factor threshold in `LiquidationLogic.sol` and watch which tests fail and
which do not. What does the gap tell you about test coverage?

**Build:** compute a user's health factor by hand from the oracle prices and
config bitmap, then assert it against `getUserAccountData`.

### Week 6 — the current generation

Read `uni/UNISWAP-DEEP-DIVE.md` section 3 and `aave/AAVE-V4-DEEP-DIVE.md`
together. Both replace "one contract per market" with "one shared core plus
pluggable modules". The parallel is not a coincidence.

Do exercises 7 through 9 from the Uniswap doc and all 8 from Aave v4.

**Lab:** v4's hook permissions are encoded in the address bits.

```bash
cd uni/v4-core
FOUNDRY_PROFILE=debug forge test --match-path test/libraries/Hooks.t.sol -vv
```

Then write a hook. `uni/V4-COMPLETE-REFERENCE.md` has a walkthrough grounded in
`test/FeeTakingHook.sol`. Mine an address with the right low bits, deploy it in a
test, and make a swap route through it. This is the single most employable skill
in the repo right now.

**Build:** trace the delta netting for a two-hop swap and explain why no
intermediate token ever moves.

### Week 7 — the integration layer

Read `lifi/LIFI-DEEP-DIVE.md`. Do all 9 exercises. Exercise 7, hand-encoding a
route for the DEX aggregator, is the one worth the time.

**Build:** pick a bridge facet nobody has explained to you, read it cold, and
write your own one-page summary in the style of the facets reference. Then diff
your understanding against `lifi/FACETS-COMPLETE-REFERENCE.md`.

---

## Harder things, once the above is done

These have no answer key.

1. **Find a bug the docs missed.** The exhaustive pass found several real ones,
   listed in `SESSION-LOG.md`. It did not find all of them. The Curve classic
   pools and the older Aave trees got the least scrutiny.

2. **Write the invariant test.** Pick an invariant stated in one of the deep
   dives, such as Curve's virtual price never decreasing, or Aave v4's four Hub
   invariants, and write a stateful fuzz suite that tries to break it. The
   `fizz` skill in this environment generates Echidna and Medusa harnesses.

3. **Port a mechanism.** Implement Curve's `get_y` in Solidity and gas-compare it
   against a Uniswap V2 swap. You will learn why Curve pools cost what they cost.

4. **Explain the read-only reentrancy** in `curve/CURVE-DEEP-DIVE.md` section 5.1
   to someone else without notes. If you can do that, you understand a class of
   bug that has drained real money and that most auditors still miss.

5. **Audit something small.** Take one facet or one library, and write a findings
   report. Then compare against the audit PDFs sitting in `aave/v4-aave/audits/`
   and `uni/v4-core/docs/security/audits/`, which nobody in this repo has read.

---

## How to know it worked

You have learned this material when you can, without notes:

- derive the constant-product and StableSwap output formulas
- explain what `sqrtPriceX96` and `liquidity` are and why V3 stores those two
- explain a scaled balance and why suppliers accrue linearly while borrowers compound
- compute a health factor and say what happens at each threshold
- describe what a hook can and cannot do to a swap
- name three ways an oracle read can lie to you

None of those is a fact to memorise. Each is a thing you can re-derive from the
code in front of you, which is the point of keeping the source in this repo.
