# DefiLlama: the map for everything in this repo

The other documents here take one protocol apart. This one zooms out and asks
where each of them sits, how big the territory is, and how anyone knows.

DefiLlama is the answer to that last question, and the interesting part is that
it is not a data vendor. It is a public repository of JavaScript files, one per
protocol, each of which reads on-chain state and returns a number. Everything you
read on the site is the output of code you can open. A slice of that code is
cloned here under [`defillama/adapters`](defillama/adapters), covering the
protocols this repo documents.

All figures below were pulled live from the DefiLlama API and are a snapshot, not
a constant. Rerun the commands in the last section to refresh them.

---

## 1. The shape of the territory

```
protocols listed            8,190
with non-zero TVL           5,830
categories                     84
chains tracked                466
total TVL                  $592.4B
total excluding exchanges  $284.9B
```

Two thirds of what DefiLlama tracks has no measurable TVL at all. That is the
first useful lesson: most of DeFi is either dead, too small to measure, or the
wrong shape for the metric.

The categories that matter, by capital held:

| Category | TVL | Covered here |
|---|---|---|
| Bridge | $52.9B | Wormhole, and LI.FI as a caller |
| Liquid Staking | $52.4B | Lido |
| Lending | $50.5B | Aave, Morpho Blue |
| RWA | $27.9B | no |
| Staking Pool | $14.5B | no |
| DEXs | $13.4B | Uniswap, Curve |
| Restaking | $10.1B | no |
| CDP | $7.8B | Liquity |
| Derivatives | $2.1B | no |

Eight protocols, and they sit on top of five of the nine largest categories. The
gaps are real and named: real-world assets, restaking, and derivatives.

---

## 2. Where the eight actually sit

| Protocol | DefiLlama entry | TVL | Chains |
|---|---|---|---|
| Lido | Lido | $24.07B | 5 |
| Aave | Aave V3 | $17.48B | 21 |
| Morpho | Morpho Blue | $9.69B | 42 |
| Uniswap | V3 / V4 / V2 | $1.58B / $1.02B / $1.00B | 46 / 18 / 15 |
| Curve | Curve DEX | $1.30B | 31 |
| Liquity | V1 + V2 | $0.28B | 1 |
| Wormhole | — | **$0** | — |
| LI.FI | — | **$0** | — |

Four things in that table are worth stopping on.

**Aave V4 is live.** $387M across two chains. The document in `aave/` was written
against source that had not yet been deployed at scale; it now has users.

**Morpho spans 42 chains against Aave's 21**, on roughly half the TVL. That is
what removing governance from market creation does to distribution. Nobody has to
approve a deployment.

**Uniswap V1 still holds $4M.** Seven years on, in a contract nobody can upgrade.

**Wormhole and LI.FI report zero**, which is the most instructive row here.

---

## 3. Why zero is the correct number for two of them

TVL measures capital sitting still. A router never holds anything: funds enter and
leave in one transaction. A messaging layer holds nothing by construction. So the
headline metric is not merely small for these, it is inapplicable.

Look at flow instead, and the picture inverts:

| Protocol | 24h volume | 24h fees |
|---|---|---|
| Uniswap V4 | $1,414.9M | $6.1M |
| Uniswap V3 | $640.7M | — |
| Lido | — | $1.6M |

**Uniswap V4 is now the largest DEX by volume**, ahead of V3, on two thirds of
V3's TVL. Concentrated liquidity plus hooks moves more value per dollar parked.
That is the entire thesis of `uni/UNISWAP-DEEP-DIVE.md` section 3, showing up in
someone else's dataset.

The general rule: **match the metric to the primitive.** Lending and staking are
stock businesses, so TVL fits. Exchanges and routers are flow businesses, so
volume and fees fit. Bridges are neither, and are usually measured by value
transferred. A protocol ranked by the wrong metric looks either trivial or
enormous, and both are wrong.

---

## 4. How a number gets made

Each protocol is one folder of JavaScript. The whole system is that plus a
convention.

**The simplest case is a lending market.** Aave's adapter is 100 lines and
delegates its own description to a shared string:

```js
methodology: methodologies.lendingMarket,   // projects/aave/index.js:81
```

**The interesting case is Lido**, because the adapter has to know the same v3
mechanics that `lido/LIDO-DEEP-DIVE.md` derives from source. Its comment is
almost a summary of that document:

```js
// Lido V3: ETH held in stVaults is outside getTotalPooledEther() except for the part
// minted as stETH against vault collateral, which shows up as getExternalEther().
// So the uncounted remainder is sum(totalValue) - getExternalEther().
```

That is [`projects/lido/index.js:35-37`](defillama/adapters/projects/lido/index.js#L35-L37).
It then calls `getTotalPooledEther`, adds the vaults' `totalValue`, and subtracts
`getExternalEther` to avoid counting the vault-backed portion twice. If you did
not know what external ether was, you could not write this file correctly. The
accounting quirk our Lido document flags is the same quirk the aggregator had to
solve.

**The most revealing case is Morpho**, because of what is missing. There is no
registry to query. The adapter reconstructs the market list from event logs:

```js
createMarket: 'event CreateMarket(bytes32 indexed id, (address loanToken, address collateralToken, address oracle, address irm, uint256 lltv) marketParams)'
```

At [`projects/morpho-blue/index.js:10`](defillama/adapters/projects/morpho-blue/index.js#L10),
then replayed at [`:23`](defillama/adapters/projects/morpho-blue/index.js#L23).
Permissionless market creation means no canonical list exists on-chain, so the
only way to enumerate markets is to replay history. The design choice documented
in `morpho/MORPHO-DEEP-DIVE.md` propagates all the way out to how the rest of the
world has to observe it.

**Uniswap's adapter shows the unglamorous part.** It carries hardcoded
per-chain blacklists of pool and token addresses starting at
[`projects/uniswap/index.js:18`](defillama/adapters/projects/uniswap/index.js#L18).
Permissionless pool creation means anyone can mint a worthless token, pair it
with itself, and claim a billion dollars of TVL. Someone maintains that list by
hand.

### Three fields worth knowing

Every adapter exports metadata alongside the numbers.

`methodology` is a prose string stating what is counted. Read it before trusting
any figure. Uniswap's says plainly that it pulls from a subgraph, so its number
is only as fresh as that indexer.

`doublecounted` marks TVL that also appears elsewhere. Lido sets it
`doublecounted: true`, because staked ETH shows up again wherever stETH is
deposited. This flag is why summing categories overstates the total, and why the
$592.4B headline is not money.

`hallmarks` are dated annotations drawn on charts. Lido's list is a compact
history of things going wrong:

```js
['2022-05-07', "UST depeg"],
['2022-06-10', "stETH depeg"],
['2022-11-08', "FTX collapse"],
['2023-05-15', "ETH Withdrawal Activation"],
```

---

## 5. What the number cannot tell you

TVL is a denominated quantity, so it moves when prices move. A protocol whose TVL
doubled may have gained no deposits at all. It is also trivially inflatable by
anyone willing to deposit against their own token, and double-counted by design
across composed protocols.

It says nothing about the things this repo spends 61,000 lines on. It does not
know that Morpho Blue has no reentrancy guards and does not need them, that
Liquity's stability pool absorbs losses in O(1), that Wormhole's guardian set is
a 13-of-19 trust assumption, or that Aave v2's oracle has no staleness check.

**Use it to decide what to read. Use the source to decide what to trust.**

---

## 6. Using it as a research tool

The API needs no key.

```bash
# every protocol, with TVL, category and chains
curl -s https://api.llama.fi/protocols

# one protocol's full history
curl -s https://api.llama.fi/protocol/morpho-blue

# TVL by chain
curl -s https://api.llama.fi/v2/chains

# flow metrics, which matter more than TVL for exchanges and routers
curl -s "https://api.llama.fi/overview/dexs?excludeTotalDataChart=true"
curl -s "https://api.llama.fi/overview/fees?excludeTotalDataChart=true"
```

Three workflows that are genuinely useful.

**Find what to study next.** Sort categories by TVL, subtract what you have read,
and the gap list writes itself. That is exactly how Lido and Wormhole were chosen
for this repo, and how EigenLayer and a perps protocol are the obvious next two.

**Find the canonical implementation.** When several protocols do the same thing,
the adapter folder tells you which one everyone else forked, and the `forkedFrom`
field on each protocol makes lineage explicit.

**Sanity-check your own reading.** If you believe a protocol works a certain way,
its adapter is an independent implementation of that belief written by someone
with no stake in your being right. Where your understanding and the adapter
disagree, one of you has a bug.

---

## 7. The map, with this repo drawn on it

```
                    exchange            credit           stablecoin
                    ────────            ──────           ──────────
   constant product  Uniswap V1/V2  ┐
   concentrated      Uniswap V3/V4  ├── $13.4B DEXs
   stable-asset      Curve          ┘

   pooled market                       Aave v1..v4    ┐
   isolated primitive                  Morpho Blue    ├── $50.5B Lending
                                                      ┘
   CDP                                                   Liquity  ── $7.8B

                    staking             plumbing
                    ───────             ────────
   liquid staking    Lido ── $52.4B
   restaking         (gap) ── $10.1B
   messaging                            Wormhole  ┐
   routing                              LI.FI     ├── $52.9B Bridge
                                                  ┘
   derivatives       (gap) ── $2.1B
   RWA               (gap) ── $27.9B
```

Everything solid is documented in this repo down to the function. Everything
marked as a gap is where to go next, and the numbers say which order.
