# Liquity Deep Dive

A code-first walkthrough of Liquity v1 (LUSD) and v2 (BOLD), written against the
exact sources cloned in this folder:

| Folder | What it is | Language |
|---|---|---|
| `v1-dev/packages/contracts/contracts/` | Liquity v1: LUSD, ETH-only, zero interest | Solidity 0.6.11 |
| `v2-bold/contracts/src/` | Liquity v2: BOLD, multi-collateral, user-set rates | Solidity 0.8.24 |

Every `path:line` below was checked with `grep -n` and is a clickable link. Open
the code beside the prose.

A companion document, [`LIQUITY-COMPLETE-REFERENCE.md`](LIQUITY-COMPLETE-REFERENCE.md),
walks every contract and every function. This one explains the ideas.

You have already read the Aave documents in this repo. Liquity is the most useful
possible contrast to them. It solves the same problem, over-collateralised
borrowing, and arrives at a completely different answer. Where Aave has
governance, a risk council, upgradeable proxies and per-asset parameters voted
on-chain, Liquity has none. Where Aave liquidates through a partial close with a
bonus, Liquity liquidates the whole position instantly against a pre-funded pool.
Read this as the counterfactual: what a lending protocol looks like when the
designers refuse to keep any control at all.

---

## 0. The mental model: a CDP stablecoin with no governance

**The primitive.** You lock ETH in a "Trove" and mint LUSD against it. The Trove
is yours alone. There is no shared interest rate, no utilisation curve, no supply
side. Nobody deposits ETH to earn yield on it. That is the first thing to unlearn
coming from Aave: **Liquity has no lenders.** LUSD is created out of nothing when
you borrow and destroyed when you repay. The only "depositors" are Stability Pool
providers, and they are not lending, they are underwriting liquidations.

**Why a peg holds without a treasury.** Most stablecoins defend a peg by holding
reserves and standing ready to trade. Liquity holds no reserves at all. The peg
comes from two hard bounds compiled into the contract, plus arbitrage between
them.

*The floor, near $1.00.* Anyone holding LUSD can redeem it for ETH at face value:
$1 of LUSD buys exactly $1 of ETH at the oracle price. The code is unambiguous at
[`v1-dev/packages/contracts/contracts/TroveManager.sol:831`](v1-dev/packages/contracts/contracts/TroveManager.sol#L831):

```solidity
// Get the ETHLot of equivalent value in USD
singleRedemption.ETHLot = singleRedemption.LUSDLot.mul(DECIMAL_PRECISION).div(_price);
```

No discount, no auction, no counterparty. If LUSD trades at $0.98 anywhere, you
buy it cheap and redeem it for a dollar of ETH. Only the redemption fee limits
that arbitrage, so the real floor sits at `1 - redemptionRate`.

*The ceiling, near $1.10.* The minimum collateral ratio is 110%
([`Dependencies/LiquityBase.sol:22`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L22)).
Anyone can mint 1 LUSD by locking $1.10 of ETH. If LUSD trades above $1.10, you
mint at maximum leverage and sell, which is free money, and the price falls back.

The peg is therefore not defended by a balance sheet. It is defended by the fact
that **the contract will always trade $1 of LUSD for $1 of ETH in one direction,
and accept $1.10 of ETH for $1 of new LUSD in the other.** Everything between is
arbitrage.

**Worked example.** ETH at $2,000. Alice opens a Trove with 10 ETH and requests
10,000 LUSD.

```
requested debt                        10,000 LUSD
borrowing fee, 0.5% floor                 50 LUSD   -> minted to LQTY stakers
net debt                              10,050 LUSD
gas compensation reserve                 200 LUSD   -> minted to the GasPool
composite debt (the ICR denominator)  10,250 LUSD

ICR = 10 ETH x $2,000 / 10,250 = 195%
```

Alice receives 10,000 LUSD and owes 10,250. The extra 250 is the fee she paid
plus a 200 LUSD refundable deposit that will pay whoever liquidates her.

Now LUSD drifts to $0.97. Bob buys 10,050 LUSD for $9,749 and redeems against
Alice's Trove. He receives `10,050 / 2,000 = 5.025 ETH`, worth $10,050, less the
redemption fee. Alice's Trove closes, her debt is gone, and her surplus ETH waits
for her to claim. Bob cleared roughly $250 and pushed LUSD back toward $1. Nobody
voted on any of it.

**What this buys and what it costs.** Liquity cannot be governed into failure,
cannot be rug-pulled, and needs no ongoing human judgement. In exchange every
parameter is frozen forever: the 110% MCR, the 200 LUSD reserve, the 0.5% fee
floor are all constants. If the design turns out to be wrong the only remedy is
to deploy a different protocol, which is precisely what v2 is.

---
## 1. Liquity v1

### 1.1 Contract map, and the immutability claim

```
                    ┌──────────────────┐
   borrower ───────▶│ BorrowerOperations│──┐  open/adjust/close
                    └──────────────────┘  │
                             │            │
   liquidator ──┐            ▼            │
   redeemer  ───┼───▶┌──────────────┐◀────┘  writes Trove structs
                └───▶│ TroveManager │
                     └──────────────┘
                       │    │    │
        offset(debt,coll)   │    └──▶ SortedTroves   (list ordered by NICR)
                       │    │
                       ▼    └──────▶ ActivePool  ⇄  DefaultPool
              ┌───────────────┐       (live funds)   (redistributed, unclaimed)
              │ StabilityPool │
              └───────────────┘              GasPool (200 LUSD per Trove)
                  ▲       │                  CollSurplusPool (claimable remainder)
   SP depositor ──┘       └──▶ ETH gains + LQTY

   PriceFeed ──▶ Chainlink, with Tellor fallback
   LQTYStaking ◀── borrowing and redemption fees
```

The immutability claim is checkable rather than rhetorical. Every contract has
exactly one `onlyOwner` function, a one-shot `setAddresses` (or `setParams`), and
each ends by destroying its own owner. In `TroveManager` that is
[`TroveManager.sol:287`](v1-dev/packages/contracts/contracts/TroveManager.sol#L287):

```solidity
        _renounceOwnership();
```

and `_renounceOwnership` simply zeroes the owner slot, at
[`Dependencies/Ownable.sol:62-65`](v1-dev/packages/contracts/contracts/Dependencies/Ownable.sol#L62-L65).
Verify the pattern for yourself:

```bash
grep -rn "_renounceOwnership()" --include=*.sol . | grep -v TestContracts
grep -rn "onlyOwner" --include=*.sol . | grep -vE "TestContracts|Ownable.sol|Proxy"
```

Thirteen production contracts renounce, and the only `onlyOwner` functions in the
tree are those one-time setters. There are no proxies, so there is nothing to
upgrade behind. After deployment the system has no privileged caller of any kind.

Compare Aave, where `ACLManager` maintains six live roles and `PoolConfigurator`
exposes dozens of permanently callable admin functions. Both designs are
defensible. Only one of them can be audited once and then trusted forever.

### 1.2 Troves and `SortedTroves`: a linked list as a priority queue

Liquidation and redemption both need "the riskiest Trove in the system", cheaply.
An unsorted array would need an O(n) scan per operation. Liquity keeps a doubly
linked list sorted by **Nominal ICR**, collateral over debt scaled by 1e20 and
deliberately *not* multiplied by price
([`Dependencies/LiquityMath.sol:92-100`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L92-L100)):

```solidity
    function _computeNominalCR(uint _coll, uint _debt) internal pure returns (uint) {
        if (_debt > 0) {
            return _coll.mul(NICR_PRECISION).div(_debt);
```

Leaving price out is the trick that makes the list stable. Every Trove's ICR
moves when ETH moves, but they all move by the same factor, so the *ordering*
never changes. The list only needs touching when a borrower changes their own
collateral or debt. A price crash re-prices every Trove and re-sorts none.

Insertion still has to find the right slot, and walking the list on-chain is what
costs gas. So the caller supplies a hint and the contract verifies it, descending
or ascending only if the hint was stale
([`SortedTroves.sol:377`](v1-dev/packages/contracts/contracts/SortedTroves.sol#L377)).
Hints come from `HintHelpers.getApproxHint`
([`HintHelpers.sol:129-161`](v1-dev/packages/contracts/contracts/HintHelpers.sol#L129-L161)),
which does something pleasingly crude: sample `_numTrials` Troves pseudo-randomly
and keep the closest.

```solidity
            uint arrayIndex = latestRandomSeed % arrayLength;
            address currentAddress = troveManager.getTroveFromTroveOwnersArray(arrayIndex);
            uint currentNICR = troveManager.getNominalICR(currentAddress);

            // check if abs(current - CR) > abs(closest - CR), and update closest if current is closer
            uint currentDiff = LiquityMath._getAbsoluteDifference(currentNICR, _CR);
```

This is a `view` function, so the sampling happens off-chain for free, and the
protocol pays only for the short walk from a good starting point. The design
lesson generalises: **when on-chain search is expensive, make the caller do the
search and have the contract verify the answer.**

### 1.3 `BorrowerOperations`: the borrower-facing surface

Every borrower action funnels through one contract, which is also the only
non-liquidation writer of Trove state.

| Function | Line | What it does |
|---|---|---|
| `openTrove` | [156](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L156) | mint LUSD against new ETH, insert into the list |
| `addColl` | [213](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L213) | `_adjustTrove` with coll increase |
| `moveETHGainToTrove` | [218](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L218) | Stability Pool ETH gain straight into a Trove |
| `withdrawColl` | [224](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L224) | `_adjustTrove` with coll decrease |
| `withdrawLUSD` | [229](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L229) | borrow more |
| `repayLUSD` | [234](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L234) | burn debt |
| `adjustTrove` | [238](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L238) | combined coll and debt change |
| `closeTrove` | [321](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L321) | repay everything, withdraw all coll |
| `claimCollateral` | [356](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L356) | pull surplus from `CollSurplusPool` |

`openTrove` ([`BorrowerOperations.sol:156-210`](v1-dev/packages/contracts/contracts/BorrowerOperations.sol#L156-L210))
is the one worth reading in full. Its shape recurs everywhere:

1. **Read price, decide mode.** `priceFeed.fetchPrice()` then `_checkRecoveryMode`.
2. **Charge the fee, but only in Normal Mode.** In Recovery Mode the borrowing
   fee is skipped entirely, because the system wants new collateral badly enough
   to stop taxing it.
3. **Build composite debt.** `netDebt + 200 LUSD`. The gas reserve counts against
   your ICR even though you never receive it.
4. **Check the right threshold.** Recovery Mode demands the new Trove clear
   150% (`_requireICRisAboveCCR`); Normal Mode demands 110% *and* that the
   resulting TCR still clears 150%.
5. **Write state, then move value.** Trove struct, reward snapshots, stake, list
   insertion, owner array. Only afterwards does ETH go to the ActivePool and LUSD
   get minted.

The gas reserve is worth dwelling on. Liquidating somebody is a public good with
a private cost, so Liquity pre-pays it: 200 LUSD is minted to a `GasPool` at open
and handed to whoever liquidates you, plus 0.5% of your collateral
([`Dependencies/LiquityBase.sol:56-58`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L56-L58)).
Aave solves the same problem by letting liquidators keep a bonus out of seized
collateral, which works only when collateral still exceeds debt. Liquity's reserve
is denominated in debt and set aside in advance, so it pays even in the cases
where the collateral has evaporated.

---
### 1.4 Liquidation: the two-tier absorption

This is where Liquity diverges most sharply from everything else in this repo.

Aave liquidates a *fraction* of a position, sells collateral to whoever shows up,
and pays them a bonus. It needs a liquidator with capital, willing to act, at the
moment of stress. Liquity needs none of that. It pre-funds the liquidator with a
pool of LUSD that is already committed to absorbing bad debt, and if that pool is
empty it socialises the loss across every remaining borrower. Liquidation is
always **complete**, always **atomic**, and never depends on someone bidding.

Entry points, all of which converge on the same inner functions:

| Function | Line | Use |
|---|---|---|
| `liquidate` | [303](v1-dev/packages/contracts/contracts/TroveManager.sol#L303) | one Trove; wraps a single-element batch |
| `liquidateTroves(n)` | [495](v1-dev/packages/contracts/contracts/TroveManager.sol#L495) | walk the list from the riskiest end |
| `batchLiquidateTroves(addr[])` | [643](v1-dev/packages/contracts/contracts/TroveManager.sol#L643) | caller-supplied list |

**Normal Mode** ([`_liquidateNormalMode`, TroveManager.sol:314-346](v1-dev/packages/contracts/contracts/TroveManager.sol#L314-L346))
liquidates any Trove with ICR < 110%. It takes the entire debt and the entire
collateral, skims gas compensation, and splits what is left between the Stability
Pool and redistribution.

**Recovery Mode** ([`_liquidateRecoveryMode`, TroveManager.sol:349-426](v1-dev/packages/contracts/contracts/TroveManager.sol#L349-L426))
switches on when the total collateral ratio falls below 150%
([`Dependencies/LiquityBase.sol:83-87`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L83-L87)).
It liquidates Troves that are still individually solvent, because the *system* is
not. Four branches, in order:

| ICR | Treatment |
|---|---|
| ≤ 100% | pure redistribution; nothing to the SP, since there is no value to buy |
| 100% < ICR < 110% | offset against SP as far as it goes, redistribute the rest |
| 110% ≤ ICR < TCR, and SP can cover the whole debt | offset only, **collateral seized capped at 110%** |
| otherwise | skipped, returns zero values |

That third branch is the humane one. `_getCappedOffsetVals`
([`TroveManager.sol:467-489`](v1-dev/packages/contracts/contracts/TroveManager.sol#L467-L489))
seizes only `debt × 1.1 / price` and books the remainder as a claimable surplus:

```solidity
        uint cappedCollPortion = _entireTroveDebt.mul(MCR).div(_price);

        singleLiquidation.collGasCompensation = _getCollGasCompensation(cappedCollPortion);
        singleLiquidation.LUSDGasCompensation = LUSD_GAS_COMPENSATION;

        singleLiquidation.debtToOffset = _entireTroveDebt;
        singleLiquidation.collToSendToSP = cappedCollPortion.sub(singleLiquidation.collGasCompensation);
        singleLiquidation.collSurplus = _entireTroveColl.sub(cappedCollPortion);
```

A borrower liquidated at 140% ICR during Recovery Mode loses 110% and can claim
back the other 30% from `CollSurplusPool`. Liquity is willing to close your
healthy position to save the system, but not to confiscate it.

The split between the two tiers is one small pure function,
[`_getOffsetAndRedistributionVals`, TroveManager.sol:431-462](v1-dev/packages/contracts/contracts/TroveManager.sol#L431-L462):

```solidity
            debtToOffset = LiquityMath._min(_debt, _LUSDInSPForOffsets);
            collToSendToSP = _coll.mul(debtToOffset).div(_debt);
            debtToRedistribute = _debt.sub(debtToOffset);
            collToRedistribute = _coll.sub(collToSendToSP);
```

The Stability Pool takes as much debt as it can fund, and exactly the pro-rata
share of collateral. Everything left over is redistributed.

### 1.5 Redistribution: deriving the O(1) accumulator

Redistribution is the fallback tier. When the Stability Pool is empty, a
liquidated Trove's debt and collateral are pushed onto **every remaining
borrower**, in proportion to their stake. Done naively that is an O(n) write per
liquidation, which is impossible on-chain.

The solution is the same pattern you met in Uniswap V3's `feeGrowthInside` and
Curve's gauge `integrate_inv_supply`: **track a global running sum of
value-per-unit-of-stake, and let each participant store a snapshot of it.** The
difference between the global sum now and your snapshot, times your stake, is
what you are owed. One global write per event, one lazy read per user.

Derivation. Let `S_total` be `totalStakes` and let a liquidation redistribute
collateral `C` and debt `D`. Define per-unit terms:

```
ΔL_ETH      = C / S_total
ΔL_LUSDDebt = D / S_total
```

A Trove with stake `s` should receive `s · ΔL_ETH` of collateral. So accumulate
`L_ETH += ΔL_ETH` forever and record each Trove's `L_ETH` at the moment it last
synced. Then

```
pending_ETH(trove) = s · (L_ETH − L_ETH_snapshot)
```

which needs no loop. The code, at
[`_redistributeDebtAndColl`, TroveManager.sol:1203-1237](v1-dev/packages/contracts/contracts/TroveManager.sol#L1203-L1237),
is that formula in fixed point, plus an error-feedback term:

```solidity
        uint ETHNumerator = _coll.mul(DECIMAL_PRECISION).add(lastETHError_Redistribution);
        uint LUSDDebtNumerator = _debt.mul(DECIMAL_PRECISION).add(lastLUSDDebtError_Redistribution);

        // Get the per-unit-staked terms
        uint ETHRewardPerUnitStaked = ETHNumerator.div(totalStakes);
        uint LUSDDebtRewardPerUnitStaked = LUSDDebtNumerator.div(totalStakes);

        lastETHError_Redistribution = ETHNumerator.sub(ETHRewardPerUnitStaked.mul(totalStakes));
        lastLUSDDebtError_Redistribution = LUSDDebtNumerator.sub(LUSDDebtRewardPerUnitStaked.mul(totalStakes));

        // Add per-unit-staked terms to the running totals
        L_ETH = L_ETH.add(ETHRewardPerUnitStaked);
        L_LUSDDebt = L_LUSDDebt.add(LUSDDebtRewardPerUnitStaked);
```

The error feedback deserves attention because it is a technique worth stealing.
Floor division throws away a remainder every time. Over thousands of
liquidations those remainders accumulate into real drift between "sum of Trove
balances" and "actual pool balance". So the contract *measures* the truncation it
just committed, `numerator − quotient × denominator`, stores it, and adds it back
into the next numerator. The loss is bounded at one wei rather than growing
without limit.

The read side is the mirror image, at
[`getPendingETHReward`, TroveManager.sol:1099-1109](v1-dev/packages/contracts/contracts/TroveManager.sol#L1099-L1109):

```solidity
        uint rewardPerUnitStaked = L_ETH.sub(snapshotETH);
        ...
        uint pendingETHReward = stake.mul(rewardPerUnitStaked).div(DECIMAL_PRECISION);
```

**Why "stake" and not simply collateral?** Because collateral itself grows from
redistribution, so using it as the weight would compound gains into future
weights and drift. `_computeNewStake`
([`TroveManager.sol:1186-1201`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1186-L1201))
normalises new collateral against a snapshot taken at the last liquidation:

```solidity
            stake = _coll.mul(totalStakesSnapshot).div(totalCollateralSnapshot);
```

so a Trove opened after several redistributions gets a stake comparable to one
opened before them. The two snapshot variables exist solely to keep that ratio
honest.

Redistributed value is parked in the `DefaultPool` and only moves to the
`ActivePool` when a borrower next touches their Trove and `_applyPendingRewards`
([`TroveManager.sol:1059-1084`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1059-L1084))
materialises it. Until then it is real but unrealised, exactly like uncollected
Uniswap fees.

---
### 1.6 The Stability Pool: deriving the product-and-sum scheme

This is the single most instructive piece of math in Liquity, and the reason to
read the protocol even if you never touch a CDP.

**The problem.** Depositors put LUSD into a pool. Each liquidation burns some of
that LUSD to cancel a Trove's debt, and pays the pool the Trove's collateral in
return. Every depositor's balance must shrink proportionally and their ETH claim
must grow proportionally, **for an unbounded number of depositors, in constant
gas.** Iterating over depositors is not an option.

**Deriving `P`, the compounding product.** A liquidation that offsets debt `D`
against total deposits `T` shrinks every deposit by the same factor:

```
factor = 1 − D/T
```

Since the factor is identical for everyone, do not apply it to each deposit.
Apply it once to a single global number and let each deposit carry the value that
number had when it joined. Maintain

```
P ← P · (1 − D/T)
```

and give every depositor a snapshot `P₀`. Then a deposit `d₀` is currently worth

```
d = d₀ · P / P₀
```

Two multiplications, no loop. The code sets `P = 1e18` initially
([`StabilityPool.sol:193`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L193))
and updates it at
[`StabilityPool.sol:589`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L589)
and following:

```solidity
        uint newProductFactor = uint(DECIMAL_PRECISION).sub(_LUSDLossPerUnitStaked);
```

with the reading side at
[`_getCompoundedStakeFromSnapshots`, StabilityPool.sol:781-806](v1-dev/packages/contracts/contracts/StabilityPool.sol#L781-L806):

```solidity
        if (scaleDiff == 0) {
            compoundedStake = initialStake.mul(P).div(snapshot_P);
```

**Deriving `S`, the gain sum.** The ETH side is subtler, because a depositor's
share of collateral depends on their *compounded* deposit at the time of the
liquidation, not their original one. Liquidation adds collateral `C`; a depositor
holding current balance `d` is owed `d · C/T`. Substituting `d = d₀ · P/P₀`:

```
gain = d₀ · (P/P₀) · (C/T)
```

Factor out the parts that are global at liquidation time, `P` and `C/T`, and
accumulate them into a running sum:

```
ΔS = (C/T) · P
```

Then the total owed to a depositor since they joined is

```
gain = d₀ · (S − S₀) / P₀
```

Verify by substitution: one liquidation contributes `d₀ · (C/T) · P / P₀`, which
is exactly `d · C/T`. Correct. Note that `S` must be updated **before** `P`,
since it uses the pre-liquidation `P`, and the code says so explicitly at
[`StabilityPool.sol:601-602`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L601-L602):

```solidity
        uint marginalETHGain = _ETHGainPerUnitStaked.mul(currentP);
        uint newS = currentS.add(marginalETHGain);
```

and the read at
[`_getETHGainFromSnapshots`, StabilityPool.sol:666-681](v1-dev/packages/contracts/contracts/StabilityPool.sol#L666-L681)
is the derived formula, `d₀ · (S − S₀) / P₀`, in fixed point.

**Why a scale factor.** `P` only ever shrinks. A liquidation that consumes 99% of
the pool multiplies it by 0.01. After a few of those, `P` underflows to zero and
every deposit reads as worthless. The fix is a floating-point-style exponent:
when `P` would fall below `1e9`, multiply it back up by `1e9` and increment a
scale counter
([`StabilityPool.sol:607-616`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L607-L616)):

```solidity
        if (currentP.mul(newProductFactor).div(DECIMAL_PRECISION) < SCALE_FACTOR) {
            newP = currentP.mul(newProductFactor).mul(SCALE_FACTOR).div(DECIMAL_PRECISION);
            currentScaleCached = currentScaleCached.add(1);
```

At most two increments can happen in one liquidation, because
`DECIMAL_PRECISION == SCALE_FACTOR²`, and the code handles that second case
inline. Since `P` is rescaled, `S` has to be tracked per scale, hence
`scaleToSum` as a mapping
([`StabilityPool.sol:205`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L205)),
and a gain that straddles one boundary is read as two portions, the second
divided by `SCALE_FACTOR`.

**A finding worth flagging: this version has no epochs.** The original Liquity
design used `epochToScaleToSum` and bumped an epoch counter whenever the pool was
fully emptied, since that drove `P` to exactly zero and made every snapshot ratio
undefined. In the tree cloned here, epochs are gone entirely:

```bash
grep -c "epoch\|Epoch" v1-dev/packages/contracts/contracts/StabilityPool.sol   # 0
```

They were replaced by a simpler invariant: never let the pool empty. A constant
`MIN_LUSD_IN_SP = 1e18` ([`StabilityPool.sol:185`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L185))
is held back from every offset by `getMaxAmountToOffset`
([`StabilityPool.sol:495-507`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L495-L507))
and defended on the withdrawal path too. That guarantees the strict inequality
asserted at
[`StabilityPool.sol:552`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L552):

```solidity
        assert(_debtToOffset < _totalLUSDDeposits);
```

so `newProductFactor > 0`, so `P` can never reach zero, which the code confirms
at [`StabilityPool.sol:622`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L622).
One constant removed an entire dimension of state and a whole class of edge case.
If you are reading older Liquity write-ups that describe epoch handling, they no
longer match this source.

**The pattern, one more time.** `L_ETH` for redistribution, `P` and `S` for the
Stability Pool, `G` for LQTY rewards, Uniswap's `feeGrowthInside`, Curve's
`integrate_inv_supply`, Aave's `liquidityIndex`. All the same idea: *never touch
N records; move one global number and let each record remember where it came in.*
Once you see it, you see it everywhere.

---
                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                             ### 1.7 Redemption: the mechanism that actually holds the peg

Liquidation protects solvency. **Redemption** is what makes LUSD worth a dollar.

Any holder can hand LUSD to the protocol and receive an equal dollar value of
ETH, taken from the *riskiest* Troves first, walking the sorted list from its
low-ICR end. `redeemCollateral`
([`TroveManager.sol:925`](v1-dev/packages/contracts/contracts/TroveManager.sol#L925))
loops Trove by Trove; each step runs `_redeemCollateralFromTrove`
([`TroveManager.sol:816-873`](v1-dev/packages/contracts/contracts/TroveManager.sol#L816-L873)).

Two outcomes per Trove. If the redemption consumes all the borrower's net debt,
the Trove closes: the 200 LUSD reserve is burned, and whatever ETH remains
becomes a claimable surplus
([`_redeemCloseTrove`, TroveManager.sol:882-891](v1-dev/packages/contracts/contracts/TroveManager.sol#L882-L891)).
Otherwise it is a partial redemption and the Trove must be re-inserted at its new
position. That re-insertion needs a hint, and if the hint is stale the contract
does not guess:

```solidity
            if (newNICR != _partialRedemptionHintNICR || _getNetDebt(newDebt) < MIN_NET_DEBT) {
                singleRedemption.cancelledPartial = true;
                return singleRedemption;
            }
```

Bailing out is deliberate. Searching the list on-chain without a hint would
likely run out of gas, so a stale hint cancels that one Trove rather than
reverting the whole redemption.

**Redemption is not a liquidation.** The redeemed borrower loses collateral but
loses debt of exactly equal dollar value, so their net worth is unchanged. What
changes is their leverage: they are left with a *higher* collateral ratio and less
exposure to ETH. It is still hostile if you did not want it, since you were
force-deleveraged at the worst possible moment, and it always targets whoever ran
the thinnest margin. The system is telling you that the price of running at 111%
is that you are first in line to be closed.

### 1.8 Fees: one base rate, two uses

A single `baseRate` variable prices both borrowing and redemption
([`TroveManager.sol:59`](v1-dev/packages/contracts/contracts/TroveManager.sol#L59)).
It rises with redemption volume and decays with time.

`_updateBaseRateFromRedemption`
([`TroveManager.sol:1358-1377`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1358-L1377)):

```solidity
        uint redeemedLUSDFraction = _ETHDrawn.mul(_price).div(_totalLUSDSupply);

        uint newBaseRate = decayedBaseRate.add(redeemedLUSDFraction.div(BETA));
        newBaseRate = LiquityMath._min(newBaseRate, DECIMAL_PRECISION); // cap baseRate at a maximum of 100%
```

Redeem 10% of the LUSD supply and, with `BETA = 2`
([`TroveManager.sol:57`](v1-dev/packages/contracts/contracts/TroveManager.sol#L57)),
the base rate jumps by 5 percentage points. Decay is exponential with a 12-hour
half-life, implemented by exponentiation-by-squaring over elapsed minutes
([`_calcDecayedBaseRate`, TroveManager.sol:1463-1468](v1-dev/packages/contracts/contracts/TroveManager.sol#L1463-L1468)
calling [`LiquityMath._decPow`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L63)).
The constant `MINUTE_DECAY_FACTOR = 999037758833783000` is just `(1/2)^(1/720)`
([`TroveManager.sol:46`](v1-dev/packages/contracts/contracts/TroveManager.sol#L46)).

Both fees are the base rate plus a 0.5% floor, borrowing additionally capped at
5% ([`TroveManager.sol:1387`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1387)
and [`:1418`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1418)).

The design intent is a self-regulating throttle. Heavy redemption means LUSD is
below peg, so redemption gets more expensive as it proceeds, and borrowing does
too, discouraging fresh supply while the peg recovers. Note what is *not* here:
no interest rate. A v1 Trove costs a one-off fee at open and then nothing,
forever. That is why v1 needed no per-Trove accrual machinery at all, and it is
the single biggest thing v2 changes.

Redemptions are also blocked for the first 14 days after deployment
([`_requireAfterBootstrapPeriod`, TroveManager.sol:1500-1503](v1-dev/packages/contracts/contracts/TroveManager.sol#L1500-L1503)),
so early borrowers are not instantly redeemed against a thin market.

### 1.9 LQTY: rewards without governance

LQTY is not a governance token, because there is nothing to govern. It captures
fees and nothing else.

`CommunityIssuance`
([`LQTY/CommunityIssuance.sol`](v1-dev/packages/contracts/contracts/LQTY/CommunityIssuance.sol))
pays LQTY to Stability Pool depositors on an exponentially decaying schedule that
asymptotically approaches a 32 million cap
([`:45`](v1-dev/packages/contracts/contracts/LQTY/CommunityIssuance.sol#L45)),
with `ISSUANCE_FACTOR = 999998681227695000`
([`:37`](v1-dev/packages/contracts/contracts/LQTY/CommunityIssuance.sol#L37)),
a one-year half-life. Cumulative issuance is computed from deployment time
rather than accumulated incrementally
([`:107-113`](v1-dev/packages/contracts/contracts/LQTY/CommunityIssuance.sol#L107-L113)),
so the schedule cannot drift regardless of how often it is poked.

`LQTYStaking` ([`LQTY/LQTYStaking.sol`](v1-dev/packages/contracts/contracts/LQTY/LQTYStaking.sol))
receives the borrowing fees, in LUSD, and the redemption fees, in ETH, and
distributes them with the same running-sum trick used everywhere else. Staking
LQTY confers no voting rights, only a claim on fee flow.

### 1.10 `PriceFeed`: an oracle that expects to be lied to

`PriceFeed` ([`PriceFeed.sol`](v1-dev/packages/contracts/contracts/PriceFeed.sol))
is a five-state machine over two independent oracles
([`:71-77`](v1-dev/packages/contracts/contracts/PriceFeed.sol#L71-L77)):

```solidity
    enum Status {
        chainlinkWorking, 
        usingTellorChainlinkUntrusted, 
        bothOraclesUntrusted,
        usingTellorChainlinkFrozen, 
        usingChainlinkTellorUntrusted
    }
```

`fetchPrice` ([`:129`](v1-dev/packages/contracts/contracts/PriceFeed.sol#L129))
reads Chainlink and Tellor, classifies each as working, frozen or broken, and
transitions. "Broken" means a reverted call, a zero round id, a zero or future
timestamp, or a non-positive answer
([`_badChainlinkResponse`, :350-361](v1-dev/packages/contracts/contracts/PriceFeed.sol#L350-L361)).
"Frozen" means older than the 4-hour `TIMEOUT`
([`:42`](v1-dev/packages/contracts/contracts/PriceFeed.sol#L42)). There is also a
sanity check that rejects a round which moved more than 50% from the previous one
([`:45`](v1-dev/packages/contracts/contracts/PriceFeed.sol#L45),
[`_chainlinkPriceChangeAboveMax`, :367-383](v1-dev/packages/contracts/contracts/PriceFeed.sol#L367-L383)),
and a 5% agreement band between the two oracles
([`:51`](v1-dev/packages/contracts/contracts/PriceFeed.sol#L51)).

Set that beside Aave v2, where `getAssetPrice` is
[`aave/v2-protocol/contracts/misc/AaveOracle.sol:96`](../aave/v2-protocol/contracts/misc/AaveOracle.sol#L96):

```solidity
      int256 price = IChainlinkAggregator(source).latestAnswer();
```

`latestAnswer()` returns no timestamp and no round id. It cannot distinguish a
fresh price from one frozen for a week. Aave v2 falls back only when the source
is unset or the answer is non-positive. Liquity checks staleness, round validity,
inter-round deviation and cross-oracle agreement, and degrades through explicit
named states.

The asymmetry is not because Liquity's authors were smarter. It is forced by
immutability. Aave can respond to a bad feed by having governance swap the source;
that escape hatch is a real mitigation. Liquity has no governance, so every
failure mode it wants to survive has to be handled in code written before launch.
**Removing the admin key does not remove the risk, it relocates it into the
source, where it must be enumerated in advance.**

---
