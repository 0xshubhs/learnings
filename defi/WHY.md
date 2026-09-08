# Why these protocols exist

Read this before any other document here.

Every protocol in this repo was built because something was broken. The code only
makes sense once you know what. Each section below is the same four questions:
what hurt, what people did before, what the protocol changed, and what that
change cost. No code, no math. Fifteen minutes.

---

## Uniswap — you could not trade a token nobody wanted to make a market in

**The pain.** In 2017 listing a token meant convincing a centralised exchange, or
finding a market maker willing to quote both sides. Order books need someone
posting bids and asks continuously. On-chain that is ruinous: every quote update
is a transaction, and a market maker who cannot cancel cheaply gets picked off.
Long-tail tokens therefore had no market at all.

**What people did instead.** EtherDelta and its peers put an order book on-chain.
It worked, barely, and it was slow, expensive and thin.

**What Uniswap changed.** Delete the order book. Hold reserves of two tokens and
price every trade with a formula, `x * y = k`. There is no counterparty to find
and no quote to maintain. Anyone can create a market for any token in one
transaction, and anyone can be the market maker by depositing both sides.

**What it cost.** Liquidity providers now lose to arbitrageurs whenever the price
moves, which is impermanent loss. Capital is spread across every price from zero
to infinity, so most of it is never used. V3 attacks the second problem by letting
you concentrate liquidity in a price range, at the cost of positions becoming
non-fungible and needing active management. V4 keeps that math and attacks gas
and extensibility by putting every pool in one contract with pluggable hooks.

---

## Curve — the constant product formula is wrong for things that should trade 1:1

**The pain.** USDC and DAI are both meant to be a dollar. Swapping $1M between
them on Uniswap V2 in 2020 cost several percent in slippage, because `x * y = k`
prices the ten-thousandth dollar very differently from the first. That is correct
behaviour for ETH against a memecoin and absurd for two dollars.

**What people did instead.** Split large stablecoin trades across venues, or use
centralised exchanges, or accept the loss.

**What Curve changed.** Use a different curve. StableSwap behaves almost like a
constant-sum function (perfectly flat, zero slippage) while the pool is balanced,
and degrades gracefully toward constant product as it skews. One parameter `A`
tunes where on that spectrum the pool sits. The practical effect is roughly 50 to
100 times the depth of a Uniswap V2 pool at the same TVL, for assets that hold
their peg.

**What it cost.** The curve has no closed-form solution, so every swap runs
Newton's method on-chain, which is expensive. And `A` encodes a belief that these
assets are worth the same. When that belief breaks, as with UST, Curve LPs are
the ones holding the broken asset. Curve's second invention, the veCRV and gauge
system, exists to bribe liquidity into staying anyway.

---

## Aave — lending needed a counterparty, and finding one is slow

**The pain.** Peer-to-peer lending protocols required matching a specific lender
with a specific borrower on amount, duration and rate. Matching is slow, and money
sits idle waiting for it. Meanwhile a borrower who is anonymous and cannot be sued
cannot be trusted to repay at all.

**What people did instead.** MakerDAO let you mint DAI against ETH, but only DAI.
There was no way to borrow arbitrary assets against arbitrary collateral.

**What Aave changed.** Pool everything. Suppliers deposit into a shared pool and
receive a claim token that grows in value. Borrowers draw from the pool against
over-collateralised positions, and the interest rate is a function of how much of
the pool is currently borrowed. Nobody matches anybody. If a position's collateral
falls too close to its debt, anyone may liquidate it at a discount, which is what
replaces the legal system.

**What it cost.** Everything depends on an oracle, so a bad price is a total loss.
Every asset added to a shared pool exposes every other asset to it, which is why
v3 spent enormous complexity on isolation mode, caps, e-mode and siloed borrowing.
That complexity is precisely what Morpho later rejected.

---

## Morpho Blue — Aave's risk management is a governance bottleneck

**The pain.** Adding a market to Aave means a DAO vote on the oracle, the loan-to-value
ratio, the caps and the rate curve. That is slow, political, and it means every
depositor is exposed to every governance decision. It also means a market nobody
in the DAO cares about never gets listed.

**What people did instead.** Wait for the vote, or fork the whole protocol.

**What Morpho Blue changed.** Make the market the primitive, not the protocol. A
market is an immutable five-tuple: loan token, collateral token, oracle, interest
rate model, liquidation threshold. Anyone can create one, permissionlessly, and
markets are isolated so one cannot poison another. The core is 557 lines with no
governance over live markets and no upgradeability. Risk curation moves up a layer
to vaults like MetaMorpho, where a curator allocates depositors' funds across
markets and competes on results.

**What it cost.** Liquidity fragments across markets that cannot share it. There
is no pause, no freeze, no cap, and no circuit breaker. If a market's oracle
breaks, nobody can stop it. You are trusting a curator instead of a DAO, which is
a different risk, not an absent one.

---

## Liquity — every stablecoin was one governance vote from changing the rules

**The pain.** MakerDAO charged a variable stability fee set by governance, could
add or remove collateral types, and could in principle change the terms of your
loan after you took it. Borrowing costs were unpredictable and the peg depended on
active management.

**What people did instead.** Accept governance risk, or stay in centralised
stablecoins.

**What Liquity changed.** Remove governance entirely. No admin keys, no upgrades,
no parameters to vote on. Borrow at a one-time fee with zero ongoing interest, at
a minimum collateral ratio of 110% instead of 150%. The peg is held by hard
redeemability: anyone can always swap 1 LUSD for $1 of ETH from the riskiest
positions, which creates a price floor no treasury has to defend. Liquidations
are absorbed first by a Stability Pool of volunteers, and if that empties, debt is
redistributed across remaining borrowers in constant time.

**What it cost.** Immutability means bugs are permanent and the protocol cannot
adapt. Being redeemed against is unpleasant if you are the riskiest borrower.
Recovery Mode, the systemic circuit breaker, is itself a griefing surface. V2
addresses several of these by letting borrowers set their own interest rate, which
turns redemption priority into a market.

---

## Lido — staking Ethereum meant 32 ETH, a server, and no way out

**The pain.** Running an Ethereum validator requires exactly 32 ETH, software that
must stay online or you get penalised, and, until the Shanghai upgrade, no ability
to withdraw ever. Three separate barriers: capital, operations, and liquidity.
Most holders could clear none of them.

**What people did instead.** Stake through a centralised exchange and accept the
custody risk, or do not stake.

**What Lido changed.** Pool deposits of any size, delegate operations to
professional node operators, and issue stETH, a token that represents your stake
and can be sold, lent or used as collateral while the underlying ETH stays locked.
Rewards arrive as a daily rebase, so your balance grows without a transaction.

**What it cost.** You trust an oracle quorum to report validator balances honestly
and node operators not to get slashed, and losses socialise across every holder.
stETH's price is a market price, not a redemption guarantee, so it can and did
trade below ETH. And a single protocol holding a large share of all staked ETH is
a concern about Ethereum itself, not just about Lido.

---

## Wormhole — chains cannot read each other, at all

**The pain.** A contract on Ethereum can read Ethereum state and nothing else.
There is no opcode for reading Solana. Verifying a Solana block header inside the
EVM would mean running a light client over roughly 1,500 validators on every
block, which costs more gas than it could ever be worth. So assets and messages
were trapped on whichever chain they started on.

**What people did instead.** Centralised exchanges as the bridge: sell on one
chain, withdraw on another.

**What Wormhole changed.** Accept an explicit trust assumption instead of pretending
to eliminate it. A set of guardians watches every supported chain. When a message
is published, they sign an observation of it. That signed bundle, a VAA, can be
verified cheaply on any other chain by checking signatures against the known
guardian set. Token transfers are then just messages: lock on one side, mint on
the other.

**What it cost.** You are trusting roughly 13 of 19 guardians, not cryptography.
If a quorum is compromised or a verification bug lets a forged VAA through, every
wrapped asset is worthless. That is not hypothetical: a single under-constrained
account type cost $326M in February 2022.

---

## LI.FI — there are too many bridges and too many DEXes to integrate one by one

**The pain.** Moving USDC on Arbitrum into ETH on Base means picking a bridge from
dozens, each with its own interface, trust model, fee structure and failure mode,
then swapping on both sides. Every wallet and app that wanted this had to
integrate all of them and keep the integrations alive.

**What people did instead.** Support two or three bridges and hope.

**What LI.FI changed.** Put the routing off-chain and the execution on-chain. An
API computes the best route across bridges and DEXes, and returns calldata. The
on-chain side is a Diamond, one contract whose behaviour is assembled from facets,
with one facet per bridge integration. Adding a bridge is adding a facet, not
redeploying. Funds pass straight through and are never held.

**What it cost.** The contracts make arbitrary external calls by design, so the
entire security model rests on an allowlist of which contracts and function
selectors may be called. Aggregators have been drained exactly when that
allowlist was wrong. You also trust the off-chain API to return an honest route.

---

## The through-line

Read in order, the pattern repeats. Each protocol removes a human from a loop.

| Protocol | Removes |
|---|---|
| Uniswap | the market maker |
| Curve | the market maker, for pegged assets specifically |
| Aave | the lender you had to match with |
| Morpho | the DAO that had to approve your market |
| Liquity | governance, entirely |
| Lido | the 32 ETH and the server |
| Wormhole | the exchange you used to bridge through |
| LI.FI | the integration work of supporting every bridge |

And each pays for it the same way: the removed human was also absorbing some risk,
and now the code has to, or you do. Impermanent loss, oracle dependence,
liquidation, curator trust, guardian trust, allowlist correctness. Every chapter
in this repo is ultimately about who is holding the risk after the middleman
leaves.

---

Next: [`README.md`](README.md) for the reading order, or [`DEFILLAMA.md`](DEFILLAMA.md)
for where each of these sits in the wider landscape by size.
