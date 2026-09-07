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
## 2. Liquity v2 (BOLD)

v2 keeps the shape of v1, Troves and a Stability Pool and redemptions, and
changes the economics underneath. Read it as a list of answers to things v1 got
wrong in practice.

### 2.1 Borrowers set their own interest rate

v1 charged a one-off fee and no interest. That made LUSD cheap to mint and hold,
which sounds good and was in fact the core problem: with no carrying cost, nobody
ever had a reason to close a Trove, and the supply could not contract when demand
fell. The peg leaned entirely on redemptions, which meant it leaned entirely on
whoever happened to be the riskiest borrower.

In v2 every borrower picks an annual rate, stored on the Trove
([`v2-bold/contracts/src/TroveManager.sol:57`](v2-bold/contracts/src/TroveManager.sol#L57)),
bounded between 0.5% and 250%
([`Dependencies/Constants.sol:46-47`](v2-bold/contracts/src/Dependencies/Constants.sol#L46-L47)).

The rate you choose is not a fee schedule, it is a **bid for redemption
priority**. `SortedTroves` is no longer sorted by collateral ratio. It is sorted
by interest rate, descending
([`v2-bold/contracts/src/SortedTroves.sol:15-18`](v2-bold/contracts/src/SortedTroves.sol#L15-L18)):

```
* A sorted doubly linked list with nodes sorted in descending order.
*
* Nodes map to active Troves in the system - the ID property is the address of a Trove owner.
* Nodes are ordered according to the borrower's chosen annual interest rate.
```

Redemptions now hit the **lowest-rate** Troves first. Pay more and you are
redeemed later. That converts v1's arbitrary punishment of thin-margin borrowers
into a market: the interest rate curve is discovered by borrowers pricing their
own redemption risk, and the aggregate rate rises automatically when BOLD is below
peg, because under-peg conditions mean redemption pressure and everyone bids up.

The list also gets cheaper. Under v1's NICR ordering, any collateral or debt
change moved you. Under interest-rate ordering, only an explicit rate change does,
so ordinary borrowing and repaying never touches the list at all.

### 2.2 Aggregate interest accounting

Charging per-Trove interest naively would mean touching every Trove on every
accrual. v2 instead keeps two global numbers in `ActivePool`
([`v2-bold/contracts/src/ActivePool.sol:41`](v2-bold/contracts/src/ActivePool.sol#L41)
and [`:47`](v2-bold/contracts/src/ActivePool.sol#L47)): `aggRecordedDebt`, the
total debt as last recorded, and `aggWeightedDebtSum`, the sum of every Trove's
`debt × rate`.

System-wide accrued interest then costs one multiplication
([`ActivePool.sol:104-113`](v2-bold/contracts/src/ActivePool.sol#L104-L113)):

```solidity
        return Math.ceilDiv(aggWeightedDebtSum * (block.timestamp - lastAggUpdateTime), ONE_YEAR * DECIMAL_PRECISION);
```

Interest is **simple, not compounded**, per interval, and compounds only when
someone touches the position. Note `ceilDiv` here against floor division for
individual Troves; the comment in the source explains why, and it is the same
instinct as Aave's `TokenMath` rounding. The aggregate must round *up* so that
`system debt ≥ sum(trove debt)` always holds, and the protocol can never end up
owing more than it has recorded.

Individual Troves derive their own share the same way, at
[`v2-bold/contracts/src/TroveManager.sol:970-974`](v2-bold/contracts/src/TroveManager.sol#L970-L974):

```solidity
        trove.annualInterestRate = Troves[_troveId].annualInterestRate;
        trove.weightedRecordedDebt = trove.recordedDebt * trove.annualInterestRate;
        ...
        trove.accruedInterest = _calcInterest(trove.weightedRecordedDebt, period);
```

### 2.3 Where the interest goes

Minted interest is split 75/25 between Stability Pool depositors and a router for
liquidity incentives
([`Dependencies/Constants.sol:81`](v2-bold/contracts/src/Dependencies/Constants.sol#L81),
applied at [`ActivePool.sol:248-264`](v2-bold/contracts/src/ActivePool.sol#L248-L264)):

```solidity
        mintedAmount = calcPendingAggInterest() + _upfrontFee;

        // Mint part of the BOLD interest to the SP and part to the router for LPs.
        if (mintedAmount > 0) {
            uint256 spYield = SP_YIELD_SPLIT * mintedAmount / DECIMAL_PRECISION;
            uint256 remainderToLPs = mintedAmount - spYield;
```

This is the other big economic change. A v1 Stability Pool depositor earned ETH
from liquidations plus LQTY emissions, so their yield depended on volatility and
on an inflating token. A v2 depositor earns **real borrower interest**, paid in
BOLD, continuously. The protocol now has an internal revenue stream that funds
its own backstop instead of paying for it with token emissions.

### 2.4 Multi-collateral, and redemption routed by unbackedness

v2 runs one branch per collateral, each with its own `TroveManager`,
`StabilityPool` and price feed, coordinated by `CollateralRegistry`
([`v2-bold/contracts/src/CollateralRegistry.sol`](v2-bold/contracts/src/CollateralRegistry.sol)).
Risk parameters differ per branch: WETH gets a 110% MCR, staked-ETH collateral
gets 120%
([`Dependencies/Constants.sol:23-24`](v2-bold/contracts/src/Dependencies/Constants.sol#L23-L24)).

A redemption is split across branches by **unbacked** BOLD, meaning debt not
covered by that branch's own Stability Pool
([`CollateralRegistry.sol:104-114`](v2-bold/contracts/src/CollateralRegistry.sol#L104-L114),
allocated at [`:154`](v2-bold/contracts/src/CollateralRegistry.sol#L154)):

```solidity
                uint256 redeemAmount = _boldAmount * unbackedPortions[index] / totals.unbacked;
```

The pressure lands where the protection is thinnest, which is exactly right: a
branch whose Stability Pool already covers its debt does not need redemptions to
shrink it. Two fallbacks handle the corners. If no branch has unbacked debt,
redemption is proportional to branch size
([`:118-128`](v2-bold/contracts/src/CollateralRegistry.sol#L118-L128)). And a
redemption larger than total unbacked debt is truncated rather than distributed
disproportionately, with the source citing the audit finding that prompted it
([`:130-135`](v2-bold/contracts/src/CollateralRegistry.sol#L130-L135)).

### 2.5 Liquidation penalties become explicit

v1 expressed liquidation loss implicitly: the Stability Pool got whatever
collateral the Trove had, minus gas compensation, which at a 110% ICR happened to
be roughly a 10% gain. v2 names the number
([`Dependencies/Constants.sol:33`](v2-bold/contracts/src/Dependencies/Constants.sol#L33)
and [`:36`](v2-bold/contracts/src/Dependencies/Constants.sol#L36)): a 5% penalty
when the Stability Pool absorbs, 10% when the loss is redistributed, per branch.

`_getCollPenaltyAndSurplus`
([`v2-bold/contracts/src/TroveManager.sol:398-412`](v2-bold/contracts/src/TroveManager.sol#L398-L412))
seizes only what the penalty justifies and returns the rest to the borrower:

```solidity
        uint256 maxSeizedColl = _debtToLiquidate * (DECIMAL_PRECISION + _penaltyRatio) / _price;
        if (_collToLiquidate > maxSeizedColl) {
            seizedColl = maxSeizedColl;
            collSurplus = _collToLiquidate - maxSeizedColl;
```

v1's capped-offset branch was a special case reachable only in Recovery Mode. In
v2 that behaviour is the default for every liquidation.

### 2.6 Troves as NFTs, delegation, and batch managers

A v1 Trove was keyed by owner address, so one address could hold exactly one
Trove and it could not be transferred. In v2 a Trove is an ERC-721
([`v2-bold/contracts/src/TroveNFT.sol:14`](v2-bold/contracts/src/TroveNFT.sol#L14))
with on-chain generated metadata, so positions are transferable and composable.

`AddRemoveManagers`
([`v2-bold/contracts/src/Dependencies/AddRemoveManagers.sol`](v2-bold/contracts/src/Dependencies/AddRemoveManagers.sol))
splits delegation in two: an add-manager may only improve your position, a
remove-manager may withdraw, and a separate receiver address takes the proceeds
([`:51`](v2-bold/contracts/src/Dependencies/AddRemoveManagers.sol#L51),
[`:65`](v2-bold/contracts/src/Dependencies/AddRemoveManagers.sol#L65)). Granting
someone the right to top you up is strictly safer than granting them the right to
take from you, and the contract encodes that difference.

**Batch managers** let a delegate set the interest rate for many Troves at once
([`BorrowerOperations.sol:849`](v2-bold/contracts/src/BorrowerOperations.sol#L849),
[`:967`](v2-bold/contracts/src/BorrowerOperations.sol#L967)), charging a fee
capped at 10% annually
([`Dependencies/Constants.sol:50`](v2-bold/contracts/src/Dependencies/Constants.sol#L50)).
Since choosing a rate is now an active management decision, v2 provides a way to
outsource it, and batched Troves share a list position so the whole batch moves
as one.

### 2.7 Branch shutdown and urgent redemption

v1 had Recovery Mode, a global emergency state. v2 replaces it with per-branch
shutdown: if a branch's TCR falls below its shutdown ratio, anyone can call
`shutdown` ([`v2-bold/contracts/src/TroveManager.sol:934`](v2-bold/contracts/src/TroveManager.sol#L934)),
which halts interest accrual on that branch
([`ActivePool.sol:105`](v2-bold/contracts/src/ActivePool.sol#L105)) and enables
`urgentRedemption`
([`TroveManager.sol:874`](v2-bold/contracts/src/TroveManager.sol#L874)), which
pays a 2% bonus
([`Dependencies/Constants.sol:74`](v2-bold/contracts/src/Dependencies/Constants.sol#L74))
to whoever helps wind the branch down. One collateral failing no longer freezes
the others.

### 2.8 v1 versus v2

| | v1 (LUSD) | v2 (BOLD) |
|---|---|---|
| Interest | none, one-off fee at open | per-Trove rate chosen by the borrower, 0.5%–250% |
| Sort order | nominal ICR | annual interest rate, descending |
| Redemption target | lowest collateral ratio | lowest interest rate |
| Redemption across markets | single market | split by unbacked debt per branch |
| Collateral | ETH only | many branches, per-branch MCR/CCR/SCR |
| Liquidation penalty | implicit; capped offset only in Recovery Mode | explicit 5% SP / 10% redistribution, always capped |
| Emergency state | global Recovery Mode below 150% TCR | per-branch shutdown plus urgent redemption |
| Position identity | one Trove per address | ERC-721, transferable |
| Delegation | none | add/remove managers, receivers, batch managers |
| SP yield | ETH from liquidations plus LQTY emissions | 75% of borrower interest, in BOLD |
| Gas reserve | 200 LUSD | 0.0375 ETH |
| Min debt | 1,800 LUSD net | 2,000 BOLD |
| Governance | none | none |

The through-line: v1 proved a CDP could run with no governance at all. v2 keeps
that property and fixes the economics, turning interest into a market-discovered
price for redemption priority rather than leaving the peg to depend on whoever
was least careful.

---
## 3. Liquity versus Aave: two answers to the same problem

Both protocols let you borrow against volatile collateral and both must handle
the case where collateral falls below debt. Almost every other decision differs.

| | Liquity | Aave v3 |
|---|---|---|
| **Liquidation trigger** | ICR < 110%, a fixed constant ([`LiquityBase.sol:22`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L22)) | health factor < 1, from per-asset thresholds in a config bitmap |
| **Who absorbs the loss** | Stability Pool depositors first, then all remaining borrowers by redistribution ([`TroveManager.sol:431`](v1-dev/packages/contracts/contracts/TroveManager.sol#L431)) | an external liquidator with capital, at the moment of stress |
| **Close factor** | always 100%, the whole Trove | 50% by default, 100% below a 0.95 health factor ([`LiquidationLogic.sol:43`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L43), [`:49`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L49)) |
| **Liquidator incentive** | pre-funded: 200 LUSD reserve plus 0.5% of collateral, paid regardless of collateral value | a bonus carved out of seized collateral, which fails when collateral is short |
| **Who can liquidate** | anyone, no capital needed, the pool pays | only someone holding the debt asset |
| **Governance surface** | none; every contract renounces ownership ([`TroveManager.sol:287`](v1-dev/packages/contracts/contracts/TroveManager.sol#L287)) | six live ACL roles ([`ACLManager.sol:15-20`](../aave/aave-v3-origin/src/contracts/protocol/configuration/ACLManager.sol#L15-L20)) plus a large configurator surface |
| **Oracle handling** | five-state machine, two oracles, staleness and deviation checks ([`PriceFeed.sol:71`](v1-dev/packages/contracts/contracts/PriceFeed.sol#L71)) | Chainlink with a fallback; v2 used bare `latestAnswer()` ([`AaveOracle.sol:96`](../aave/v2-protocol/contracts/misc/AaveOracle.sol#L96)) |
| **Interest rate** | v1 none; v2 chosen by each borrower ([`Constants.sol:46-47`](v2-bold/contracts/src/Dependencies/Constants.sol#L46-L47)) | a utilisation curve, parameters set by governance |
| **Collateral types** | v1 ETH only; v2 one branch per asset | many assets in one pool, with caps, eMode and isolation mode |
| **Upgradeability** | none, no proxies anywhere | proxies throughout; implementations replaceable by governance |
| **Bad debt** | socialised immediately and automatically via redistribution | accrues as a deficit; needs governance or an external module to clear |
| **Black swan** | Recovery Mode (v1) or branch shutdown (v2); mechanical, no human input | governance can freeze, pause or re-parameterise; requires humans to act in time |

**How to read this.** Liquity's design assumes nobody will be available to help.
The Stability Pool is capital committed *in advance* to absorbing liquidations,
so no bidder has to appear during a crash. Redistribution is a backstop that
needs no participants at all. Recovery Mode and branch shutdown fire on a number,
not a vote.

Aave's design assumes a functioning market and an attentive DAO. Liquidators
arrive because the bonus is profitable. Parameters adapt because a risk team
proposes changes. That is genuinely more capable in normal conditions: Aave
supports dozens of assets with tuned risk, which Liquity structurally cannot.

The trade is legibility against adaptability. Liquity's entire risk surface is
readable in one afternoon and then fixed forever. Aave's is larger and never
final, but it can respond to a world its authors did not foresee. Neither is the
right answer in general. Knowing which you are looking at is the point.

One concrete lesson worth carrying: **Liquity pre-funds its liquidation
incentive in the debt asset, Aave pays it out of the collateral.** When
collateral gaps below debt in a fast crash, Aave's incentive shrinks exactly when
it is most needed, while Liquity's 200 LUSD reserve is untouched. That single
choice explains much of the behavioural difference between the two under stress.

---
## 4. Security notes

**Recovery Mode is a circuit breaker with a griefing edge.** Below a 150% TCR the
system will liquidate Troves that are individually healthy
([`Dependencies/LiquityBase.sol:83-87`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L83-L87)).
Since TCR is a global figure, a large borrower can push the system into Recovery
Mode by withdrawing collateral or minting heavily, making other people's positions
liquidatable. The capped-offset branch limits the damage, seizing only 110% and
returning the surplus
([`TroveManager.sol:467-489`](v1-dev/packages/contracts/contracts/TroveManager.sol#L467-L489)),
so the attack costs the attacker real fees and yields the victim's surplus back.
It is a griefing vector, not a theft vector. v2 replaces the global mode with
per-branch shutdown, which shrinks the blast radius considerably.

**The oracle is the whole trust model.** With no governance, a bad price is
unrecoverable: nobody can swap the feed. Hence the five-state machine and its four
independent sanity checks. Note the residual risk that remains anyway: the 50%
inter-round deviation guard
([`PriceFeed.sol:45`](v1-dev/packages/contracts/contracts/PriceFeed.sol#L45))
will not catch a slow manipulation delivered in several sub-50% steps, and the
`bothOraclesUntrusted` state means the system keeps operating on the last good
price rather than halting. Freezing would be safer but there would be no one to
unfreeze it.

**110% is tight, and latency is the real parameter.** A 110% MCR leaves 10% of
headroom, but ETH can move 10% in minutes while Chainlink updates on a deviation
threshold. The Stability Pool is what makes this survivable: liquidation is
atomic and needs no bidder, so the gap between "became liquidatable" and "was
liquidated" is one transaction rather than an auction. The design compensates for
a thin buffer with a fast mechanism.

**Redemption is hostile by design, and that is the point.** Being redeemed costs
you nothing in dollar terms, but it force-deleverages you at a moment you did not
choose, and it always finds whoever ran the thinnest margin. In v1 that is
arbitrary punishment for efficient collateral use. v2's reordering by interest
rate is the fix: you now choose your own place in the queue by paying for it.

**Gas compensation exists because liquidation is a public good.** The 200 LUSD
reserve is minted into a `GasPool` at open and paid to the liquidator. It is why
liquidating a tiny underwater Trove is still worth someone's gas. The cost is that
every borrower carries 200 LUSD of debt they never receive, which makes small
Troves uneconomic and is why `MIN_NET_DEBT` is 1,800 LUSD
([`Dependencies/LiquityBase.sol:31`](v1-dev/packages/contracts/contracts/Dependencies/LiquityBase.sol#L31)).

**The last Trove cannot be liquidated.** `_liquidateRecoveryMode` returns early
when only one Trove remains
([`TroveManager.sol:362`](v1-dev/packages/contracts/contracts/TroveManager.sol#L362)),
and redemption enforces the same
([`_requireMoreThanOneTroveInSystem`, TroveManager.sol:1488](v1-dev/packages/contracts/contracts/TroveManager.sol#L1488)).
Without this the system could reach a state with debt, no Troves, and no way to
compute a meaningful TCR. It is the sort of edge case that only shows up when you
cannot ship a fix later.

**Stability Pool withdrawals are blocked while anyone is liquidatable.**
`_requireNoUnderCollateralizedTroves`
([`StabilityPool.sol:944`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L944))
stops depositors from front-running a liquidation they are supposed to absorb.
Without it, watching the mempool and withdrawing just ahead of a large liquidation
would be free money at the expense of everyone who stayed.

**The scale mechanism is precision, not economics.** A depositor whose stake has
shrunk by more than two scale factors reads as zero
([`_getCompoundedStakeFromSnapshots`, StabilityPool.sol:781-806](v1-dev/packages/contracts/contracts/StabilityPool.sol#L781-L806)),
which is correct: their deposit really has been reduced by a factor of 1e18. The
`MIN_LUSD_IN_SP` floor is what keeps `P` strictly positive
([`StabilityPool.sol:552`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L552),
[`:622`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L622)) and is the
reason this version needs no epoch dimension at all. If you port this pattern,
port the floor with it.

**Error feedback is load-bearing.** Both the redistribution accumulators
([`TroveManager.sol:1217-1225`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1217-L1225))
and the Stability Pool offset
([`StabilityPool.sol:531-577`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L531-L577))
measure their own truncation and carry it forward. Drop that and per-user balances
drift from pool balances over thousands of operations, eventually making the last
withdrawal fail. The Stability Pool additionally adds 1 to the loss quotient so the
rounding always favours the pool rather than the depositor.

**Immutability relocates risk, it does not remove it.** Everything above is
handled in code because there is no one to handle it later. That is the honest
summary of the whole design: Liquity is not safer than Aave by construction, it
has simply moved every decision forward in time to before deployment, where it can
be audited once and never revisited. Whether that is an improvement depends
entirely on whether the authors thought of everything.

---

## 5. Exercises: trace these yourself

1. **Prove the redistribution invariant.** Open
   [`TroveManager.sol:1203-1237`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1203-L1237).
   Three Troves have stakes 100, 200 and 700. A fourth is liquidated with 10 ETH
   and 20,000 LUSD to redistribute. Compute `L_ETH` and `L_LUSDDebt` by hand, then
   compute each Trove's pending reward via
   [`getPendingETHReward`](v1-dev/packages/contracts/contracts/TroveManager.sol#L1099)
   and confirm the three sum to 10 ETH, up to the truncation held in
   `lastETHError_Redistribution`.

2. **Derive `P` and `S` from scratch.** Without looking at §1.6, start from "every
   deposit shrinks by the same factor" and derive the update rule for `P` and then
   for `S`. Then check yourself against
   [`StabilityPool.sol:589`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L589)
   and [`:601-602`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L601-L602).
   Explain in one sentence why `S` must be updated before `P`.

3. **Break the scale factor.** Assume `MIN_LUSD_IN_SP` did not exist and a
   liquidation offsets the entire pool. Walk
   [`_updateRewardSumAndProduct`](v1-dev/packages/contracts/contracts/StabilityPool.sol#L580)
   and identify exactly which line fails and what every depositor's balance would
   read as afterwards. Then find the two asserts that make it unreachable.

4. **Compare a liquidation path against Aave.** A borrower holds 10 ETH against
   18,000 of debt, and ETH falls from $2,000 to $1,900. Trace the Liquity path
   through [`_liquidateNormalMode`](v1-dev/packages/contracts/contracts/TroveManager.sol#L314)
   and [`_getOffsetAndRedistributionVals`](v1-dev/packages/contracts/contracts/TroveManager.sol#L431),
   then the Aave path through
   [`executeLiquidationCall`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L166).
   How much debt is cleared in each? Who supplied the capital? What happens in each
   if no third party shows up?

5. **Recovery Mode branches.** In
   [`_liquidateRecoveryMode`](v1-dev/packages/contracts/contracts/TroveManager.sol#L349),
   construct four Troves that each take a different one of the four branches.
   For the capped-offset case, compute the surplus returned via
   [`_getCappedOffsetVals`](v1-dev/packages/contracts/contracts/TroveManager.sol#L467)
   and say which contract holds it until claimed.

6. **The stable sort.** Explain why
   [`_computeNominalCR`](v1-dev/packages/contracts/contracts/Dependencies/LiquityMath.sol#L92)
   deliberately omits price, and what would have to change in
   [`SortedTroves`](v1-dev/packages/contracts/contracts/SortedTroves.sol) if it did
   not. Then find the v2 equivalent and explain why interest-rate ordering makes
   the list even cheaper to maintain.

7. **Follow the interest in v2.** Starting at
   [`calcPendingAggInterest`](v2-bold/contracts/src/ActivePool.sol#L104), trace
   where minted interest goes via
   [`_mintAggInterest`](v2-bold/contracts/src/ActivePool.sol#L248). Why is the
   aggregate computed with `ceilDiv` while individual Troves use floor division?
   State the invariant that choice protects.

8. **Redemption routing.** In
   [`CollateralRegistry.redeemCollateral`](v2-bold/contracts/src/CollateralRegistry.sol#L92),
   work out how a 1,000,000 BOLD redemption splits across three branches with
   unbacked debts of 5M, 3M and 0. Then explain the two fallbacks at
   [`:118-135`](v2-bold/contracts/src/CollateralRegistry.sol#L118-L135) and what
   each is defending against.
