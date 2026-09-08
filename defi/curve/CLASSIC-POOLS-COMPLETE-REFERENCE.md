# Curve Classic Pools — Complete Reference

> **Why this exists.** Constant product prices two dollars as if they might not be worth the same. Curve's curve stays flat while a pool is balanced, giving stablecoin swaps far more depth at the same TVL.
>
> Background and the derivations behind it: [`CURVE-DEEP-DIVE.md`](CURVE-DEEP-DIVE.md).
> The problem each protocol in this repo solves: [`WHY.md`](../WHY.md).

Every pool template and every deployed pool family in `curve/curve-contract/`,
function by function. This is the *first* generation of Curve StableSwap: 33
production pools written in Vyper between 2020 and 2021, before the factory-based
NG rewrite.

Companion documents, cited but not duplicated here:

- [`CURVE-DEEP-DIVE.md`](CURVE-DEEP-DIVE.md) — §1 walks the 3pool conceptually
  and derives the StableSwap invariant from first principles. Read that first if
  the math is new to you.
- [`STABLESWAP-NG-COMPLETE-REFERENCE.md`](STABLESWAP-NG-COMPLETE-REFERENCE.md) —
  the next generation, which replaces all of this with one factory and one
  parameterised implementation.

Every `path:line` below was checked with `grep -n` against the files in this
folder. Paths are relative to `curve/curve-contract/contracts/`.

---

## Contents

- [0. How this codebase is organised](#0-how-this-codebase-is-organised)
- [1. Full inventory](#1-full-inventory)
  - [1.1 The five templates](#11-the-five-templates)
  - [1.2 The 33 pools](#12-the-33-pools)
  - [1.3 The 22 zaps](#13-the-22-zaps)
  - [1.4 Compiler versions and the July 2023 Vyper bug](#14-compiler-versions-and-the-july-2023-vyper-bug)
- [2. The shared math, derived](#2-the-shared-math-derived)
  - [2.1 The invariant](#21-the-invariant)
  - [2.2 `_get_D` — Newton on D](#22-_get_d)
  - [2.3 `_get_y` — solving for one balance](#23-_get_y)
  - [2.4 `_get_y_D` — solving at a reduced D](#24-_get_y_d)
  - [2.5 `_xp` / `RATES` / `PRECISION_MUL`](#25-_xp)
  - [2.6 `_A` — the amplification ramp](#26-_a)
  - [2.7 `get_virtual_price`](#27-get_virtual_price)
  - [2.8 The imbalance fee](#28-the-imbalance-fee)
  - [2.9 `_calc_withdraw_one_coin`](#29-_calc_withdraw_one_coin)
- [3. `pool-templates/base` — the plain template](#3-pool-templatesbase--the-plain-template)
- [4. `pool-templates/y` — the lending template](#4-pool-templatesy--the-lending-template)
- [5. `pool-templates/a` — the Aave template](#5-pool-templatesa--the-aave-template)
- [6. `pool-templates/eth` — the native-ETH template](#6-pool-templateseth--the-native-eth-template)
- [7. `pool-templates/meta` — the metapool template](#7-pool-templatesmeta--the-metapool-template)
- [8. Pool families, as diffs from their template](#8-pool-families-as-diffs-from-their-template)
- [9. The zaps](#9-the-zaps)
- [10. The LP tokens: CurveTokenV1/V2/V3](#10-the-lp-tokens)
- [11. Rate calculators and `testing/`](#11-rate-calculators-and-testing)
- [12. ABI / selector tables](#12-abi--selector-tables)
- [13. Storage layout tables](#13-storage-layout-tables)
- [14. Events reference](#14-events-reference)
- [15. Revert-message table](#15-revert-message-table)
- [16. Use-case index](#16-use-case-index)
- [17. Security notes](#17-security-notes)

---

## 0. How this codebase is organised

Curve classic has no factory. Every pool is a **separately compiled, separately
deployed Vyper contract**, produced by taking a template and substituting
compile-time constants into it. The templates carry literal placeholders:

```
N_COINS: constant(int128) = ___N_COINS___
PRECISION_MUL: constant(uint256[N_COINS]) = ___PRECISION_MUL___
RATES: constant(uint256[N_COINS]) = ___RATES___
```

([`pool-templates/base/SwapTemplateBase.vy:81-83`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L81-L83))

Those triple-underscore tokens are replaced by the deployment scripts using the
values in each pool's `pooldata.json`. That is why `N_COINS` can appear inside an
array type — it is a compile-time constant, not a variable. It is also why there
are 33 near-identical 800-to-1100-line files in `pools/`: each is a template
instance frozen at deploy time, and each was free to diverge afterwards.

The practical consequence for a reader: **learn the five templates and you have
learned all 33 pools.** Section 8 then covers only what each pool family changed.

There are five template families:

```
                     SwapTemplateBase          plain ERC20 coins, fixed RATES
                       |        |    \
      SwapTemplateY ---+        |     +--- SwapTemplateEth     native ETH, no RATES
   (lending: yToken)            |
                                |
                     SwapTemplateA            Aave aTokens (rebasing) + dynamic fee
                                |
                     SwapTemplateMeta         coin[1] is another pool's LP token
```

They are siblings rather than a true inheritance chain — Vyper 0.2 has no
inheritance, so each template is a full standalone copy with edits.

---

## 1. Full inventory

### 1.1 The five templates

| Template | File | Lines | `@version` | What it adds over base |
|---|---|---|---|---|
| base | `pool-templates/base/SwapTemplateBase.vy` | 891 | `^0.2.8` | — (the reference implementation) |
| y | `pool-templates/y/SwapTemplateY.vy` | 1040 | `^0.2.8` | `_stored_rates()` from yToken `getPricePerFullShare`, `exchange_underlying`, `get_dx`, wrapped/underlying coin pairs |
| a | `pool-templates/a/SwapTemplateA.vy` | 1126 | `^0.2.8` | Rebasing aToken balances read live, dynamic fee, `aave_referral`, `set_aave_referral` |
| eth | `pool-templates/eth/SwapTemplateEth.vy` | 902 | `^0.2.8` | Native ETH as coin 0 via the `0xEeee…EEeE` sentinel, no `RATES` (all coins 18-dec), `@payable` exchange |
| meta | `pool-templates/meta/SwapTemplateMeta.vy` | 1119 | `^0.2.12` | coin[1] is a base pool's LP token; `_vp_rate()` caching, `exchange_underlying` across both pools |

Two templates ship a zap and two ship a rate calculator:

| File | Lines | `@version` | Purpose |
|---|---|---|---|
| `pool-templates/meta/DepositTemplateMeta.vy` | 378 | `0.2.12` | Add/remove liquidity in terms of the *underlying* base coins |
| `pool-templates/y/DepositTemplateY.vy` | 280 | `^0.2.0` | Wrap/unwrap yTokens around deposits and withdrawals |
| `pool-templates/eth/RateCalculatorTemplateETH.vy` | 15 | `0.2.11` | Stub returning a constant rate |
| `pool-templates/meta/RateCalculatorTemplateMeta.vy` | 15 | `0.2.11` | Stub returning a constant rate |

### 1.2 The 33 pools

`pool_types` and coin decimals come from each pool's `pooldata.json`.

| Pool | Type | Base | Coins (decimals) | LP token | Lines | `@version` | Zap |
|---|---|---|---|---|---|---|---|
| `3pool` | plain | — | DAI(18) + USDC(6) + USDT(6) | V2 | 847 | 0.2.4 | — |
| `aave` | arate | — | aDAI(18) + aUSDC(6) + aUSDT(6) | V3 | 1053 | 0.2.8 | — |
| `aeth` | eth,crate | — | ETH(18) + ankrETH(18) | V3 | 843 | 0.2.8 | — |
| `bbtc` | meta | sbtc | bBTC(8) + sbtcCRV(18) | V3 | 1076 | 0.2.8 | yes |
| `busd` | plain | — | yDAI + yUSDC + yUSDT + yBUSD | V1 | 624 | 0.1.0b16 | yes |
| `compound` | crate | — | cDAI(18) + cUSDC(6) | V1 | 685 | 0.1.0b16 | yes |
| `dusd` | meta | 3pool | DUSD(18) + 3CRV(18) | V2 | 1083 | 0.2.7 | yes |
| `eurs` | plain | — | EURS(2) + sEUR(18) | V3 | 884 | 0.2.8 | — |
| `gusd` | meta | 3pool | GUSD(2) + 3CRV(18) | V2 | 1082 | 0.2.5 | yes |
| `hbtc` | plain | — | hBTC(18) + wBTC(8) | V2 | 756 | 0.2.4 | — |
| `husd` | meta | 3pool | HUSD(8) + 3CRV(18) | V2 | 1083 | 0.2.5 | yes |
| `ib` | crate | — | cyDAI(18) + cyUSDC(6) + cyUSDT(6) | V3 | 1006 | 0.2.8 | — |
| `link` | plain | — | LINK(18) + sLINK(18) | V3 | 886 | 0.2.8 | — |
| `linkusd` | meta | 3pool | LINKUSD(18) + 3CRV(18) | V2 | 1082 | 0.2.5 | yes |
| `musd` | meta | 3pool | MUSD(18) + 3CRV(18) | V2 | 1083 | 0.2.5 | yes |
| `obtc` | meta | sbtc | oBTC(18) + sbtcCRV(18) | V3 | 1076 | 0.2.8 | yes |
| `pax` | plain | — | ycDAI + ycUSDC + ycUSDT + PAX(18) | V1 | 707 | 0.1.0b17 | yes |
| `pbtc` | meta | sbtc | pBTC(18) + sbtcCRV(18) | V2 | 1076 | 0.2.8 | yes |
| `ren` | plain | — | renBTC(8) + wBTC(8) | V1 | 743 | 0.1.0b17 | — |
| `reth` | eth,crate | — | ETH(18) + rETH(18) | V3 | 843 | 0.2.12 | — |
| `rsv` | meta | 3pool | RSV(18) + 3CRV(18) | V2 | 1083 | 0.2.5 | yes |
| `saave` | arate | — | aDAI(18) + aSUSD(18) | V3 | 997 | 0.2.8 | — |
| `sbtc` | plain | — | renBTC(8) + wBTC(8) + sBTC(18) | V1 | 743 | 0.1.0b17 | — |
| `seth` | eth | — | ETH(18) + sETH(18) | V3 | 883 | 0.2.8 | — |
| `steth` | eth,arate | — | ETH(18) + stETH(18) | V3 | 839 | 0.2.8 | — |
| `susd` | plain | — | DAI + USDC + USDT + SUSD(18) | V1 | 658 | 0.1.0b17 | yes |
| `tbtc` | meta | sbtc | tBTC(18) + sbtcCRV(18) | V2 | 1078 | 0.2.7 | yes |
| `usdk` | meta | 3pool | USDK(18) + 3CRV(18) | V2 | 1083 | 0.2.5 | yes |
| `usdn` | meta | 3pool | USDN(18) + 3CRV(18) | V2 | 1083 | 0.2.5 | yes |
| `usdp` | meta | 3pool | USDP(18) + 3CRV(18) | V3 | 1113 | 0.2.8 | yes |
| `usdt` | plain | — | cDAI(18) + cUSDC(6) + USDT(6) | V1 | 677 | 0.1.0b16 | yes |
| `ust` | meta | 3pool | UST(18) + 3CRV(18) | V3 | 1081 | 0.2.8 | yes |
| `y` | plain | — | yDAI + yUSDC + yUSDT + yTUSD | V1 | 620 | 0.1.0b16 | yes |

Read the `pool_types` column as: `plain` = coins used directly; `crate` =
Compound-style rate (`exchangeRateStored`); `arate` = Aave-style rate (aTokens
rebase, so the rate is 1 and balances are read live); `eth` = coin 0 is native
ETH; `meta` = coin 1 is another pool's LP token.

### 1.3 The 22 zaps

| Zap | Lines | `@version` | Zap | Lines | `@version` |
|---|---|---|---|---|---|
| `pools/bbtc/DepositBBTC.vy` | 366 | 0.2.8 | `pools/pax/DepositPax.vy` | 363 | 0.1.0b17 |
| `pools/busd/DepositBUSD.vy` | 338 | 0.1.0b17 | `pools/pbtc/DepositPBTC.vy` | 366 | 0.2.8 |
| `pools/compound/DepositCompound.vy` | 371 | 0.1.0b16 | `pools/rsv/DepositRSV.vy` | 376 | 0.2.7 |
| `pools/dusd/DepositDUSD.vy` | 376 | 0.2.7 | `pools/susd/DepositSUSD.vy` | 373 | 0.1.0b17 |
| `pools/gusd/DepositGUSD.vy` | 376 | 0.2.7 | `pools/tbtc/DepositTBTC.vy` | 366 | 0.2.7 |
| `pools/husd/DepositHUSD.vy` | 376 | 0.2.7 | `pools/usdk/DepositUSDK.vy` | 376 | 0.2.7 |
| `pools/linkusd/DepositLinkUSD.vy` | 376 | 0.2.7 | `pools/usdn/DepositUSDN.vy` | 376 | 0.2.7 |
| `pools/musd/DepositMUSD.vy` | 376 | 0.2.7 | `pools/usdp/DepositUSDP.vy` | 376 | 0.2.8 |
| `pools/obtc/DepositOBTC.vy` | 366 | 0.2.8 | `pools/usdt/DepositUSDT.vy` | 374 | 0.1.0b16 |
| | | | `pools/ust/DepositUST.vy` | 376 | 0.2.8 |
| | | | `pools/y/DepositY.vy` | 338 | 0.1.0b17 |

### 1.4 Compiler versions and the July 2023 Vyper bug

On 30 July 2023 it emerged that Vyper **0.2.15, 0.2.16 and 0.3.0** miscompiled
`@nonreentrant` locks when the same lock key was applied to functions of
differing mutability. Roughly $70M was drained from four Curve pools that used
those compilers (alETH/ETH, msETH/ETH, pETH/ETH, CRV/ETH).

A `grep "@version"` sweep over every swap contract in this tree gives:

```
0.1.0b16  busd, compound, usdt, y
0.1.0b17  pax, ren, sbtc, susd
0.2.4     3pool, hbtc
0.2.5     gusd, husd, linkusd, musd, rsv, usdk, usdn
0.2.7     dusd, tbtc
0.2.8     aave, aeth, bbtc, eurs, ib, link, obtc, pbtc, saave, seth, steth, ust, usdp
0.2.12    reth
templates ^0.2.8 (base, y, a, eth), ^0.2.12 (meta)
```

**No pool in this repository is compiled with 0.2.15, 0.2.16 or 0.3.0.** The
versions here span 0.1.0b16 through 0.2.12, so none is affected by that specific
compiler bug. The four pools that were drained are not part of this repository —
they were factory-deployed crypto pools from a later era.

The lesson to carry forward is nonetheless the one that matters most in this
codebase: `@nonreentrant('lock')` is a *compiler-generated* guard, and its
correctness is a property of the compiler version, not of the source you are
reading. Always check the pragma. And note the separate, source-level problem in
§17.1, which no compiler fixes.

---

## 2. The shared math, derived

Every template computes the same four quantities. The code below is from
`pool-templates/base/SwapTemplateBase.vy`; the other templates differ only in how
they obtain `xp` (the normalised balances), never in the iteration itself.

### 2.1 The invariant

Curve interpolates between a constant sum (zero slippage, no protection against
depegs) and a constant product (Uniswap). With `n` coins, balances `x_i`, and
amplification `A`:

```
A·n^n·Σx_i  +  D  =  A·D·n^n  +  D^(n+1) / (n^n · Πx_i)
```

`D` is the invariant: the total pool value expressed as if every coin were at
parity. When the pool is perfectly balanced, `x_i = D/n` for all `i`, and the
equation is satisfied exactly.

Setting `A = 0` collapses it to `D^(n+1) = n^n·Πx_i`, i.e. constant product.
Letting `A → ∞` makes the left side dominate and gives `Σx_i = D`, constant sum.
`A` therefore tunes *how strongly the pool believes the coins are worth the
same*. That single number is the entire product decision.

There is no closed form for `D` given the `x_i`, nor for one `x_i` given `D` and
the others. Both are solved by Newton iteration.

### 2.2 `_get_D`

[`pool-templates/base/SwapTemplateBase.vy:206-243`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L206-L243), `@pure @internal`.

Signature: `_get_D(_xp: uint256[N_COINS], _amp: uint256) -> uint256`

The docstring states the converging solution directly (`:212-217`):

```
D[j+1] = (A·n^n·Σx_i − D[j]^(n+1) / (n^n·Πx_i)) / (A·n^n − 1)
```

The implementation (`:223-238`):

```python
D: uint256 = S
Ann: uint256 = _amp * N_COINS
for _i in range(255):
    D_P: uint256 = D
    for _x in _xp:
        D_P = D_P * D / (_x * N_COINS)
    Dprev = D
    D = (Ann * S / A_PRECISION + D_P * N_COINS) * D / ((Ann - A_PRECISION) * D / A_PRECISION + (N_COINS + 1) * D_P)
    if D > Dprev:
        if D - Dprev <= 1:
            return D
    else:
        if Dprev - D <= 1:
            return D
raise
```

Reading it piece by piece:

- `S = Σx_i`, accumulated at `:219-220`. If `S == 0` the function short-circuits
  to `0` (`:221-222`) — an empty pool has no invariant.
- `D_P` is `D^(n+1) / (n^n·Πx_i)`, built by starting at `D` and dividing by
  `x_i·n` once per coin. The inline comment at `:229` is worth quoting: *"If
  division by 0, this will be borked: only withdrawal will work. And that is
  good"* — a pool emptied of one coin cannot be traded, but `remove_liquidity`
  (which never calls `_get_D`) still lets LPs exit.
- `Ann = A·n`, not `A·n^n`. Curve folds the remaining `n^(n-1)` into the
  algebra, which is why the update line looks different from the docstring.
- `A_PRECISION = 100` (`:105`). `A` is stored pre-multiplied by 100 so it can be
  ramped with sub-integer resolution; every use divides it back out.
- The loop is capped at 255 iterations and `raise`s if it does not converge.
  The comment at `:239-240` notes convergence "typically occurs in 4 rounds or
  less, this should be unreachable". Newton's method on this function is
  quadratically convergent from `D = S`, which is already close.
- Termination is `|D − D_prev| <= 1`, i.e. equality to within one wei of the
  18-decimal normalised unit. The two-branch comparison exists because these are
  unsigned integers and `D - Dprev` would underflow.

**Rounding.** Every division truncates toward zero, so the returned `D` is at or
slightly below the true value. Since `D` is what the pool credits to LPs, a
slightly low `D` favours the pool.

### 2.3 `_get_y`

[`pool-templates/base/SwapTemplateBase.vy:379-430`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L379-L430), `@view @internal`.

Signature: `_get_y(i: int128, j: int128, x: uint256, _xp: uint256[N_COINS]) -> uint256`

"Given that coin `i` will hold `x` after the trade, what must coin `j` hold to
keep `D` unchanged?" Substituting all known balances into the invariant and
collecting terms in the single unknown `y` reduces it to a quadratic, as the
docstring states (`:383-388`):

```
y² + y·(S' + D·A_PRECISION/Ann − D) = D^(n+1) / (n^(2n) · Π'x · A)
y² + b·y = c        with the Newton step   y ← (y² + c) / (2y + b − D)
```

where `S'` and `Π'` run over every coin *except* `j`.

Checks first (`:391-397`): `i != j` (`# dev: same coin`), `j >= 0`
(`# dev: j below zero`), `j < N_COINS` (`# dev: j above N_COINS`), plus two
"should be unreachable, but good for safety" asserts on `i`.

Then `c` and `b` are accumulated (`:407-417`):

```python
for _i in range(N_COINS):
    if _i == i:
        _x = x
    elif _i != j:
        _x = _xp[_i]
    else:
        continue
    S += _x
    c = c * D / (_x * N_COINS)
c = c * D * A_PRECISION / (Ann * N_COINS)
b: uint256 = S + D * A_PRECISION / Ann  # - D
```

Note the `continue` at `:413`: coin `j` is skipped entirely, because `y` is what
we are solving for. The trailing comment `# - D` on the `b` line records that
the `−D` term is applied later, inside the Newton step's denominator
(`2*y + b - D`), rather than folded into `b` — doing it there keeps `b`
unsigned.

The loop (`:419-430`) is the same 255-iteration, tolerance-1 pattern as `_get_D`.

**Why callers subtract 1.** `_get_y` truncates downward, so the computed `y` may
be a wei below the exact root, which would over-pay the trader. Every caller
compensates: `get_dy` uses `dy = xp[j] - y - 1` (`:440`) and `exchange` does the
same at `:466` with the comment *"-1 just in case there were some rounding
errors"*.

### 2.4 `_get_y_D`

[`pool-templates/base/SwapTemplateBase.vy:614-656`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L614-L656), `@pure @internal`.

Signature: `_get_y_D(A: uint256, i: int128, _xp: uint256[N_COINS], D: uint256) -> uint256`

The mirror image of `_get_y`: instead of fixing `D` and changing one balance, it
fixes the balances of every coin except `i` and asks what `x_i` would be if the
invariant were `D` rather than its current value. That is exactly the question a
single-sided withdrawal poses.

Algebraically it is the same quadratic — compare `:617-622` with `:383-388`, they
are identical — so the iteration at `:646-657` is byte-for-byte the same as
`_get_y`'s. The only differences are the signature (`A` and `D` are passed in
rather than read, making it `@pure`) and the absence of an `x` substitution: the
loop at `:635-641` simply skips `i` and uses stored balances for the rest.

### 2.5 `_xp`, `RATES` and `PRECISION_MUL`

The invariant only makes sense if all balances are in the same unit. Curve
normalises everything to 18 decimals before doing any math.

`_xp` (`:188-193`) and `_xp_mem` (`:197-202`):

```python
@view
@internal
def _xp() -> uint256[N_COINS]:
    result: uint256[N_COINS] = RATES
    for i in range(N_COINS):
        result[i] = result[i] * self.balances[i] / PRECISION
    return result
```

`RATES[i]` is the compile-time constant `PRECISION_MUL[i] * 10**18`. For 3pool
that is `[1e18, 1e30, 1e30]`: DAI already has 18 decimals so its multiplier is 1,
while USDC and USDT have 6 and need `1e12`. Multiplying by `RATES[i]` and
dividing by `PRECISION = 1e18` therefore scales a raw balance up to 18 decimals.

`_xp_mem` is the `@pure` variant that normalises a caller-supplied balance array
instead of storage — used wherever a hypothetical post-trade state is evaluated,
such as `calc_token_amount` (`:284`) and `add_liquidity` (`:309`).

In the lending templates `RATES` is not constant; see §4.1 and §5.1.

### 2.6 `_A` — the amplification ramp

[`pool-templates/base/SwapTemplateBase.vy:154-171`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L154-L171), `@view @internal`.

```python
t1: uint256 = self.future_A_time
A1: uint256 = self.future_A
if block.timestamp < t1:
    A0: uint256 = self.initial_A
    t0: uint256 = self.initial_A_time
    if A1 > A0:
        return A0 + (A1 - A0) * (block.timestamp - t0) / (t1 - t0)
    else:
        return A0 - (A0 - A1) * (block.timestamp - t0) / (t1 - t0)
else:
    return A1
```

Linear interpolation in time between `(t0, A0)` and `(t1, A1)`. The `if A1 > A0`
split exists only because these are unsigned: `A1 - A0` would underflow on a
downward ramp.

Once `block.timestamp >= t1` the function returns `future_A` forever, which is
also the correct answer when no ramp was ever scheduled (`future_A_time == 0`).

Two public wrappers: `A()` (`:176-177`) returns `self._A() / A_PRECISION`, the
human-readable value; `A_precise()` (`:182-183`) returns the raw
100×-multiplied form.

**Why ramp at all, and why slowly.** Changing `A` re-prices the entire pool
without a single trade, because it changes `D` for the same balances. If `A`
could jump, whoever knew the change was coming could position beforehand and
extract the difference from LPs. The constraints in `ramp_A` (§3.16) bound the
rate of change so that the profit from front-running a ramp is smaller than the
arbitrage cost of moving the pool.

### 2.7 `get_virtual_price`

[`pool-templates/base/SwapTemplateBase.vy:252-263`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L252-L263), `@view @external`.

```python
D: uint256 = self._get_D(self._xp(), self._A())
token_supply: uint256 = ERC20(self.lp_token).totalSupply()
return D * PRECISION / token_supply
```

`D` is the pool's total value in normalised units; dividing by LP supply gives
value per LP token, scaled to 1e18. It starts at exactly `1e18` (the first
depositor receives `mint_amount = D1`, see §3.7) and rises as swap fees
accumulate, since fees increase balances without minting LP tokens.

It is **not** monotonic in general: an `A` ramp moves `D` without any value
changing hands, so the virtual price steps up or down across a ramp.

This function is the single most-integrated view in Curve — lending markets price
LP collateral with it. It is also the source of the read-only reentrancy class of
bug. See §17.1.

### 2.8 The imbalance fee

Proportional deposits and withdrawals are free. Anything that changes the pool's
*ratio* pays, because it shifts risk onto the remaining LPs. The fee is applied
per coin against how far that coin ended up from its ideal post-trade balance.

The multiplier appears identically in `add_liquidity` (`:331`),
`remove_liquidity_imbalance` (`:569`) and `_calc_withdraw_one_coin` (`:673`):

```python
fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))
```

For `n = 2` that is `fee·2/4 = fee/2`; for `n = 3`, `fee·3/8`; for `n = 4`,
`fee/3`. The factor equalises the expected cost of an imbalanced deposit against
the cost of achieving the same position by swapping, so neither route is
systematically cheaper.

The per-coin application (`:334-342`):

```python
ideal_balance: uint256 = D1 * old_balances[i] / D0
difference: uint256 = 0
new_balance: uint256 = new_balances[i]
if ideal_balance > new_balance:
    difference = ideal_balance - new_balance
else:
    difference = new_balance - ideal_balance
fees[i] = fee * difference / FEE_DENOMINATOR
self.balances[i] = new_balance - (fees[i] * admin_fee / FEE_DENOMINATOR)
new_balances[i] -= fees[i]
```

`ideal_balance` is what coin `i` would hold if the deposit had been perfectly
proportional. Note the asymmetry in the last two lines: **stored** balances lose
only the admin's cut of the fee, while the **local** array used to recompute `D2`
loses the whole fee. The difference stays in the pool and accrues to LPs — which
is precisely how `get_virtual_price` rises.

### 2.9 `_calc_withdraw_one_coin`

[`pool-templates/base/SwapTemplateBase.vy:661-687`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L661-L687), `@view @internal`.
Returns `(dy, dy_fee, total_supply)`.

Single-sided withdrawal is the most intricate calculation in the contract, and it
runs `_get_y_D` twice:

```python
D0: uint256 = self._get_D(xp, amp)
total_supply: uint256 = CurveToken(self.lp_token).totalSupply()
D1: uint256 = D0 - _token_amount * D0 / total_supply
new_y: uint256 = self._get_y_D(amp, i, xp, D1)
xp_reduced: uint256[N_COINS] = xp
fee: uint256 = self.fee * N_COINS / (4 * (N_COINS - 1))
for j in range(N_COINS):
    dx_expected: uint256 = 0
    if j == i:
        dx_expected = xp[j] * D1 / D0 - new_y
    else:
        dx_expected = xp[j] - xp[j] * D1 / D0
    xp_reduced[j] -= fee * dx_expected / FEE_DENOMINATOR
dy: uint256 = xp_reduced[i] - self._get_y_D(amp, i, xp_reduced, D1)
```

Step by step:

1. `D1` is the invariant after burning `_token_amount` LP tokens — the withdrawal
   is defined as a pro-rata reduction of `D`, not of balances.
2. `new_y` is where coin `i` would sit at `D1` if the withdrawal took *everything*
   from coin `i`. The naive answer is `xp[i] - new_y`.
3. The loop computes, for every coin, how far this withdrawal pushes it from the
   proportional outcome. For `j == i` the deviation is measured against `new_y`;
   for the others it is the amount they *would* have given up in a proportional
   withdrawal but now do not. Each coin's `xp_reduced` is docked the imbalance fee
   on its own deviation.
4. `_get_y_D` runs a *second* time on the fee-reduced balances, and `dy` is the
   difference. Charging the fee by shrinking the inputs to the solver, rather
   than by subtracting from the output, keeps the result consistent with what the
   pool state will actually be afterwards.

Finally (`:684-686`):

```python
precisions: uint256[N_COINS] = PRECISION_MUL
dy = (dy - 1) / precisions[i]   # Withdraw less to account for rounding errors
dy_0: uint256 = (xp[i] - new_y) / precisions[i]  # w/o fees
return dy, dy_0 - dy, total_supply
```

The `- 1` is the same defensive truncation seen in `exchange`. `dy_0 - dy` is the
fee actually charged, returned so `remove_liquidity_one_coin` can split off the
admin share.

---

## 3. `pool-templates/base` — the plain template

`pool-templates/base/SwapTemplateBase.vy`, 891 lines, `@version ^0.2.8`.
Header: *"Minimal pool implementation with no lending"* (`:6`).

This is the reference implementation. Coins are ordinary ERC20s held directly by
the pool, and their decimal scaling is baked in at compile time.

### 3.1 Compile-time constants

| Constant | Line | Value | Meaning |
|---|---|---|---|
| `N_COINS` | 81 | `___N_COINS___` | Substituted at build time |
| `PRECISION_MUL` | 82 | `___PRECISION_MUL___` | `10**(18-decimals)` per coin |
| `RATES` | 83 | `___RATES___` | `PRECISION_MUL[i] * 10**18` |
| `FEE_DENOMINATOR` | 86 | `10**10` | Fees are parts per 1e10 |
| `PRECISION` | 87 | `10**18` | Normalised unit |
| `MAX_ADMIN_FEE` | 89 | `10 * 10**9` | 100% of the swap fee |
| `MAX_FEE` | 90 | `5 * 10**9` | 50% — an absurd ceiling, never approached |
| `MAX_A` | 91 | `10**6` | |
| `MAX_A_CHANGE` | 92 | `10` | One ramp may change `A` by at most 10× |
| `ADMIN_ACTIONS_DELAY` | 94 | `3 * 86400` | 3-day timelock on fee/owner changes |
| `MIN_RAMP_TIME` | 95 | `86400` | A ramp must span at least a day |
| `A_PRECISION` | 105 | `100` | `A` stored ×100 |
| `KILL_DEADLINE_DT` | 119 | `2 * 30 * 86400` | `kill_me` only works for ~60 days after deploy |

### 3.2 Storage

| Slot order | Variable | Line | Visibility | Notes |
|---|---|---|---|---|
| 1 | `coins: address[N_COINS]` | 97 | public | |
| 2 | `balances: uint256[N_COINS]` | 98 | public | Pool's *accounted* balance, excludes admin fees |
| 3 | `fee: uint256` | 99 | public | ×1e10 |
| 4 | `admin_fee: uint256` | 100 | public | ×1e10, share of `fee` taken by the DAO |
| 5 | `owner: address` | 102 | public | |
| 6 | `lp_token: address` | 103 | public | |
| 7 | `initial_A` / `future_A` | 106-107 | public | ×100 |
| 8 | `initial_A_time` / `future_A_time` | 108-109 | public | |
| 9 | `admin_actions_deadline` | 111 | public | |
| 10 | `transfer_ownership_deadline` | 112 | public | |
| 11 | `future_fee` / `future_admin_fee` | 113-114 | public | |
| 12 | `future_owner` | 115 | public | |
| 13 | `is_killed: bool` | 117 | private | |
| 14 | `kill_deadline: uint256` | 118 | private | |

The critical invariant: `self.balances[i]` is **not** the token balance. The
difference `ERC20(coins[i]).balanceOf(self) - balances[i]` is the accumulated
admin fee, which is exactly how `admin_balances` (§3.21) and
`withdraw_admin_fees` (§3.22) compute their figures. Any token donated directly
to the pool is therefore indistinguishable from an admin fee and is claimable by
the owner.

### 3.3 `__init__`

`:123-150`, `@external`.

```
__init__(_owner: address, _coins: address[N_COINS], _pool_token: address,
         _A: uint256, _fee: uint256, _admin_fee: uint256)
```

- Checks: `_coins[i] != ZERO_ADDRESS` for every `i` (`:140-141`).
- Writes: `coins`, `initial_A = future_A = _A * A_PRECISION`, `fee`,
  `admin_fee`, `owner`, `kill_deadline = block.timestamp + KILL_DEADLINE_DT`,
  `lp_token`.
- Note `_A` is documented as "Amplification coefficient multiplied by n * (n - 1)"
  (`:136`), a legacy of the pre-`A_PRECISION` parameterisation. In practice the
  deployment scripts pass the plain `A` from `pooldata.json`.
- No event. There is no `LP token` sanity check either — the token's `minter`
  must be set to the pool separately, and getting that wrong bricks deposits.

### 3.4 `_A`, `A`, `A_precise`

Covered in §2.6. `_A` at `:154-171` (`@view @internal`), `A` at `:176-177`,
`A_precise` at `:182-183` (both `@view @external`, no access control).

### 3.5 `_xp`, `_xp_mem`

Covered in §2.5. `:188-193` and `:197-202`.

### 3.6 `_get_D`, `_get_D_mem`, `get_virtual_price`, `calc_token_amount`

`_get_D` (`:206-243`) and the math are in §2.2. `_get_D_mem` (`:246-247`) is a
one-liner: `return self._get_D(self._xp_mem(_balances), _amp)`.

`get_virtual_price` (`:252-263`) is in §2.7.

**`calc_token_amount(_amounts, _is_deposit) -> uint256`**, `:267-291`,
`@view @external`.

- Purpose: estimate LP tokens minted or burned. The docstring is explicit
  (`:270-271`): *"This calculation accounts for slippage, but not fees. Needed to
  prevent front-running, not for precise calculations!"*
- Computes `D0` from current balances, applies `_amounts` in the given direction,
  computes `D1`, and returns `diff * token_supply / D0`.
- Because it ignores fees it **over-estimates** deposits and **under-estimates**
  withdrawal cost. Never use it as a settlement figure; use it to derive a
  `_min_mint_amount` with a margin.
- Reverts by underflow if a withdrawal exceeds a balance.

### 3.7 `add_liquidity`

`:296-372`, `@external @nonreentrant('lock')`.

```
add_liquidity(_amounts: uint256[N_COINS], _min_mint_amount: uint256) -> uint256
```

Flow:

1. `assert not self.is_killed` (`:303`, `# dev: is killed`).
2. `D0` from current balances (`:309`).
3. Build `new_balances`. If `token_supply == 0`, every `_amounts[i]` must be
   non-zero (`:316`, `# dev: initial deposit requires all coins`) — the first
   deposit sets the pool's price, so it must define all of it.
4. `D1` from new balances; `assert D1 > D0` (`:322`).
5. **If not the first deposit**: charge the imbalance fee per coin (§2.8),
   recompute `D2` from fee-reduced balances (`:344`), and mint
   `token_supply * (D2 - D0) / D0` (`:345`).
   **If first deposit**: store balances directly and mint `mint_amount = D1`
   (`:347-348`, comment *"Take the dust if there was any"*). This is what pins the
   initial virtual price at 1e18.
6. `assert mint_amount >= _min_mint_amount, "Slippage screwed you"` (`:349`).
7. Pull each non-zero `_amounts[i]` with a hand-rolled safe `transferFrom`
   (`:352-368`): a `raw_call` of `transferFrom(address,address,uint256)` whose
   return data is only checked if non-empty — the standard accommodation for
   USDT and other tokens that return nothing.
8. `CurveToken(lp_token).mint(msg.sender, mint_amount)` (`:370`).
9. `log AddLiquidity(msg.sender, _amounts, fees, D1, token_supply + mint_amount)`.

**Gotcha.** Tokens are pulled *after* balances are written and *after* the mint
amount is decided. The `@nonreentrant('lock')` guard is what makes that safe; a
fee-on-transfer token would still break the accounting, since the pool credits
`_amounts[i]` rather than the delta actually received.

### 3.8 `_get_y` and `get_dy`

`_get_y` (`:379-430`) is derived in §2.3.

**`get_dy(i, j, _dx) -> uint256`**, `:434-442`, `@view @external`.

```python
xp: uint256[N_COINS] = self._xp()
rates: uint256[N_COINS] = RATES
x: uint256 = xp[i] + (_dx * rates[i] / PRECISION)
y: uint256 = self._get_y(i, j, x, xp)
dy: uint256 = xp[j] - y - 1
fee: uint256 = self.fee * dy / FEE_DENOMINATOR
return (dy - fee) * PRECISION / rates[j]
```

Normalise, solve, subtract the defensive wei, take the flat fee, denormalise.
Note the fee here is the **flat** `self.fee`, not the imbalance multiplier — swaps
pay the plain rate.

### 3.9 `exchange`

`:447-508`, `@external @nonreentrant('lock')`.

```
exchange(i: int128, j: int128, _dx: uint256, _min_dy: uint256) -> uint256
```

1. `assert not self.is_killed` (`:457`).
2. Normalise balances, compute `x`, solve `y` via `_get_y` (`:460-464`).
3. `dy = xp[j] - y - 1`; `dy_fee = dy * self.fee / FEE_DENOMINATOR` (`:466-467`).
4. Denormalise: `dy = (dy - dy_fee) * PRECISION / rates[j]`; then
   `assert dy >= _min_dy, "Exchange resulted in fewer coins than expected"` (`:471`).
5. `dy_admin_fee = dy_fee * self.admin_fee / FEE_DENOMINATOR`, denormalised
   (`:473-474`).
6. Balance updates (`:477-479`):
   ```python
   self.balances[i] = old_balances[i] + _dx
   self.balances[j] = old_balances[j] - dy - dy_admin_fee
   ```
   The comment at `:478` — *"When rounding errors happen, we undercharge admin
   fee in favor of LP"* — records the deliberate bias.
7. Safe `transferFrom` of `_dx` in (`:481-492`), safe `transfer` of `dy` out
   (`:494-505`).
8. `log TokenExchange(msg.sender, i, _dx, j, dy)`.

The LP's share of the fee is never moved anywhere: `balances[j]` is reduced by
`dy + dy_admin_fee` while the contract actually only paid out `dy`, so the LP
portion silently remains as un-accounted balance and lifts `D`.

### 3.10 `remove_liquidity`

`:513-547`, `@external @nonreentrant('lock')`.

```
remove_liquidity(_amount, _min_amounts) -> uint256[N_COINS]
```

The only mutating function with **no** `is_killed` check — by design, LPs must
always be able to exit a killed pool. It also never calls `_get_D` or `_get_y`,
so it works even when the invariant solver would fail.

Per coin (`:525-541`): `value = old_balance * _amount / total_supply`, assert
`value >= _min_amounts[i]` with `"Withdrawal resulted in fewer coins than
expected"`, decrement the stored balance, safe-transfer out. Then
`burnFrom(msg.sender, _amount)` (`:543`, `# dev: insufficient funds`) and
`log RemoveLiquidity(...)` with an all-zero fees array.

**Ordering gotcha.** Tokens go out *before* the LP tokens are burned. Combined
with a coin that yields control on transfer, that is the read-only reentrancy
shape described in §17.1 — though in this plain template both legs are ERC20
transfers, so the risk only materialises with a callback-bearing token.

### 3.11 `remove_liquidity_imbalance`

`:552-609`, `@external @nonreentrant('lock')`.

```
remove_liquidity_imbalance(_amounts, _max_burn_amount) -> uint256
```

1. `assert not self.is_killed` (`:559`).
2. `D0`, subtract `_amounts`, `D1` (`:562-567`).
3. Imbalance fee per coin exactly as in `add_liquidity` (§2.8), giving `D2`
   (`:569-584`).
4. `token_amount = (D0 - D2) * token_supply / D0` (`:587`);
   `assert token_amount != 0` (`:588`, `# dev: zero tokens burned`);
   then `token_amount += 1` with the comment *"In case of rounding errors - make
   it unfavorable for the 'attacker'"* (`:589`);
   `assert token_amount <= _max_burn_amount, "Slippage screwed you"` (`:590`).
5. Burn first (`:592`), then transfer each non-zero `_amounts[i]` out
   (`:593-606`). Note this is the opposite order from `remove_liquidity`.
6. `log RemoveLiquidityImbalance(...)`.

### 3.12 `_get_y_D`, `_calc_withdraw_one_coin`, `calc_withdraw_one_coin`

`_get_y_D` (`:614-656`) is §2.4; `_calc_withdraw_one_coin` (`:661-687`) is §2.9.

`calc_withdraw_one_coin(_token_amount, i)` (`:692-699`, `@view @external`) simply
returns element 0 of the internal triple.

### 3.13 `remove_liquidity_one_coin`

`:704-738`, `@external @nonreentrant('lock')`.

1. `assert not self.is_killed` (`:712`).
2. `dy, dy_fee, total_supply = self._calc_withdraw_one_coin(_token_amount, i)`
   (`:717`).
3. `assert dy >= _min_amount, "Not enough coins removed"` (`:718`).
4. `self.balances[i] -= (dy + dy_fee * self.admin_fee / FEE_DENOMINATOR)`
   (`:720`) — the admin's slice of the withdrawal fee is removed from accounted
   balances so it becomes claimable; the LP slice stays and lifts `D`.
5. `burnFrom` (`:721`), safe-transfer `dy` out (`:723-734`),
   `log RemoveLiquidityOne(...)`.

### 3.14 Admin: fee and ownership timelocks

All six are `assert msg.sender == self.owner  # dev: only owner`.

| Function | Lines | Behaviour |
|---|---|---|
| `commit_new_fee(_new_fee, _new_admin_fee)` | 779-791 | Requires `admin_actions_deadline == 0` (`# dev: active action`), `_new_fee <= MAX_FEE`, `_new_admin_fee <= MAX_ADMIN_FEE`. Sets a deadline 3 days out. Logs `CommitNewFee`. |
| `apply_new_fee()` | 794-806 | Requires `block.timestamp >= admin_actions_deadline` and `!= 0`. Applies and clears. Logs `NewFee`. |
| `revert_new_parameters()` | 809-812 | Clears the deadline. No event. |
| `commit_transfer_ownership(_owner)` | 816-825 | Same 3-day pattern. Logs `CommitNewAdmin`. |
| `apply_transfer_ownership()` | 828-838 | Applies. Logs `NewAdmin`. |
| `revert_transfer_ownership()` | 841-844 | Clears. No event. |

The 3-day delay is the DAO's commitment device: fee and ownership changes are
visible on-chain before they bite, so LPs can exit.

### 3.15 `ramp_A` / `stop_ramp_A`

**`ramp_A(_future_A, _future_time)`**, `:742-761`.

Checks, in order (`:743-753`):

```python
assert msg.sender == self.owner                                  # dev: only owner
assert block.timestamp >= self.initial_A_time + MIN_RAMP_TIME
assert _future_time >= block.timestamp + MIN_RAMP_TIME           # dev: insufficient time
assert _future_A > 0 and _future_A < MAX_A
if future_A_p < initial_A:
    assert future_A_p * MAX_A_CHANGE >= initial_A
else:
    assert future_A_p <= initial_A * MAX_A_CHANGE
```

So: at least one day since the last ramp started, at least one day of duration,
`0 < A < 1e6`, and at most a 10× change in either direction. Writes
`initial_A = self._A()` (the *current* interpolated value, not the old target),
`future_A`, and both timestamps. Logs `RampA`.

**`stop_ramp_A()`**, `:765-775`. Freezes `A` at its current interpolated value by
setting `initial_A = future_A = self._A()` and both times to now. The comment at
`:773` explains why that works: *"now (block.timestamp < t1) is always False, so
we return saved A"*. Logs `StopRampA`. This is the emergency brake.

### 3.16 `admin_balances`, `withdraw_admin_fees`, `donate_admin_fees`

**`admin_balances(i) -> uint256`**, `:849-850`, `@view @external`, no access
control:

```python
return ERC20(self.coins[i]).balanceOf(self) - self.balances[i]
```

**`withdraw_admin_fees()`**, `:854-871`, owner only. Loops coins, computes the
same difference, and safe-transfers any positive amount to `msg.sender`. Note it
sends to the *caller* (the owner), not to a configured receiver — the DAO's
`PoolProxy` is the owner in production and forwards onward.

**`donate_admin_fees()`**, `:875-878`, owner only:

```python
for i in range(N_COINS):
    self.balances[i] = ERC20(self.coins[i]).balanceOf(self)
```

Absorbs the outstanding admin fees into accounted balances, gifting them to LPs.
This is also the function that "adopts" any tokens donated to the pool.

### 3.17 `kill_me` / `unkill_me`

`:882-886` and `:889-891`, owner only. `kill_me` additionally requires
`self.kill_deadline > block.timestamp` (`# dev: deadline has passed`), so the
kill switch expires roughly 60 days after deployment and the pool becomes
permanently unkillable. `unkill_me` has no deadline.

While killed, `add_liquidity`, `exchange`, `remove_liquidity_imbalance` and
`remove_liquidity_one_coin` all revert; only `remove_liquidity` works.

---

## 4. `pool-templates/y` — the lending template

`pool-templates/y/SwapTemplateY.vy`, 1040 lines, `@version ^0.2.8`.

The pool holds **wrapped, interest-bearing** tokens (yearn yTokens) but wants to
quote prices in the **underlying** asset. It therefore keeps two coin arrays and
recomputes the conversion rate on every call.

### 4.1 `_stored_rates` — the only real change

`:222-226`, `@view @internal`:

```python
def _stored_rates() -> uint256[N_COINS]:
    result: uint256[N_COINS] = PRECISION_MUL
    for i in range(N_COINS):
        result[i] *= yERC20(self.coins[i]).getPricePerFullShare()
    return result
```

Where the base template has a compile-time `RATES` constant, this reads
`getPricePerFullShare()` from each yToken at call time. Everything downstream is
identical, which is why `_xp` (`:231-235`) and `_xp_mem` (`:240-244`) take
`_rates` as a parameter here rather than reading a constant.

`LENDING_PRECISION: constant(uint256) = 10 ** 18` is declared alongside
`PRECISION`; both are 1e18 and the split is documentation, not arithmetic.

**Trust.** The rate comes from an external contract on every quote. A yToken that
misreports `getPricePerFullShare` mis-prices the entire pool. There is no
sanity band, no EMA, and no staleness check.

### 4.2 Extra storage

`underlying_coins: public(address[N_COINS])` sits alongside `coins`. Both are set
in `__init__`.

### 4.3 `exchange_underlying`

`:603-655`, `@external @nonreentrant('lock')`.

```
exchange_underlying(i, j, _dx, _min_dy) -> uint256
```

The interesting part is the wrap/unwrap sandwich (`:613-638`):

```python
rates: uint256[N_COINS] = self._stored_rates()
precisions: uint256[N_COINS] = PRECISION_MUL
dx: uint256 = _dx * PRECISION / (rates[i] / precisions[i])
dy_: uint256 = self._exchange(i, j, dx, rates)
dy: uint256 = dy_ * (rates[j] / precisions[j]) / PRECISION
assert dy >= _min_dy, "Exchange resulted in fewer coins than expected"
# ... transferFrom the underlying in ...
yERC20(self.coins[i]).deposit(_dx)
yERC20(self.coins[j]).withdraw(dy_)
dy = ERC20(self.underlying_coins[j]).balanceOf(self)
assert dy >= _min_dy, "Exchange resulted in fewer coins than expected"
```

Note the double check on `_min_dy`. The comment at `:637` explains the reason:
*"y-tokens calculate imprecisely - use all available"*. Rather than trust the
predicted `dy`, the contract deposits, swaps, withdraws, then reads its **actual**
underlying balance and sends all of it. That works only because the pool is never
supposed to hold a bare underlying balance between transactions.

### 4.4 The other additions

`get_dx`, `get_dy_underlying`, `get_dx_underlying` are view helpers that apply the
same rate conversion around `_get_y`. `_exchange` is the shared internal that both
`exchange` and `exchange_underlying` call, factored out because the two differ
only in what they transfer.

---

## 5. `pool-templates/a` — the Aave template

`pool-templates/a/SwapTemplateA.vy`, 1126 lines, `@version ^0.2.8`.

Aave aTokens **rebase**: your balance grows without a transfer. That breaks the
base template's core assumption that `self.balances[i]` tracks holdings, so this
template abandons stored balances entirely and adds a dynamic fee.

### 5.1 `_balances` — live reads instead of stored state

`:273-277`, `@view @internal`:

```python
def _balances() -> uint256[N_COINS]:
    result: uint256[N_COINS] = empty(uint256[N_COINS])
    for i in range(N_COINS):
        result[i] = ERC20(self.coins[i]).balanceOf(self) - self.admin_balances[i]
    return result
```

Compare with base, where `balances` is a storage array. Here it is derived: the
pool's true holdings minus the admin fees it owes. Interest accrued by rebasing
therefore flows to LPs automatically, with no bookkeeping at all.

Consequently `admin_balances` becomes a **storage array** in this template rather
than the computed getter of §3.16 — the subtraction runs the other way.

Because aTokens are always 1:1 with their underlying, `RATES` stays constant;
`pool_types` calls this `arate`.

### 5.2 `_dynamic_fee` — the ancestor of NG's fee

`:233-241`, `@view @internal`:

```python
def _dynamic_fee(_xpi: uint256, _xpj: uint256, _fee: uint256, _feemul: uint256) -> uint256:
    if _feemul <= FEE_DENOMINATOR:
        return _fee
    else:
        xps2: uint256 = (_xpi + _xpj)
        xps2 *= xps2  # Doing just ** 2 can overflow apparently
        return (_feemul * _fee) / (
            (_feemul - FEE_DENOMINATOR) * 4 * _xpi * _xpj / xps2 + \
            FEE_DENOMINATOR)
```

Write `m = _feemul / FEE_DENOMINATOR` and let `r = 4·x_i·x_j / (x_i + x_j)²`.
Then `r = 1` exactly when the two balances are equal, and `r → 0` as they
diverge. The fee becomes

```
fee_dyn = fee · m / ((m − 1)·r + 1)
```

At balance (`r = 1`) that is `fee·m/m = fee`, the base rate. Fully imbalanced
(`r → 0`) it approaches `fee·m`. So `offpeg_fee_multiplier` is a straight cap on
how much worse the fee gets when the pool is off peg, and setting it to
`FEE_DENOMINATOR` or below disables the mechanism (the early return at `:234-235`).

The inline comment at `:238` is a genuine Vyper gotcha: `(_xpi + _xpj) ** 2`
overflows where `xps2 *= xps2` on a pre-narrowed value does not.

Public wrapper `dynamic_fee(i, j)` at `:246-256`.

The dynamic fee is applied at the *midpoint* of the trade, not the endpoints —
see `:561` and `:592`, both of which pass `(xp[i] + x) / 2, (xp[j] + y) / 2`.
Charging on the average of pre- and post-trade balances stops a trader from
splitting one large swap into many small ones to stay near the cheap end.

### 5.3 Aave-specific plumbing

- `aave_referral: uint256` (`:125`) and `set_aave_referral` — a uint16 referral
  code (`# dev: uint16 overflow`) passed through to Aave's `deposit`/`withdraw`
  at `:438`, `:467` and `:689`.
- `offpeg_fee_multiplier: public(uint256)` (`:117`) with
  `future_offpeg_fee_multiplier` (`:136`), ramped through the same 3-day
  timelock. `commit_new_fee` gains a third parameter (`:1007`) and an extra
  guard: `assert _new_offpeg_fee_multiplier * _new_fee <= MAX_FEE * FEE_DENOMINATOR`
  (`:1012`, `# dev: offpeg multiplier exceeds maximum`) — the *worst-case*
  dynamic fee, not the base fee, is what must stay under `MAX_FEE`.

---

## 6. `pool-templates/eth` — the native-ETH template

`pool-templates/eth/SwapTemplateEth.vy`, 902 lines, `@version ^0.2.8`.

### 6.1 What is missing

There is no `RATES`, no `PRECISION_MUL`, no `_xp` and no `_xp_mem`. Compare the
constants block at `:84` with base's `:81-83`: only `N_COINS` survives. Every
coin in an ETH pool is 18 decimals (ETH itself, and 18-decimal LSTs), so raw
balances *are* normalised balances. `_get_y` and `_get_D` are handed
`self.balances` directly — see `exchange` at `:441-442`, which calls
`self._get_y(i, j, x, old_balances)` with no conversion.

That removal is the single largest structural difference in the family, and it is
why the ETH template is shorter than base despite adding native-currency handling.

### 6.2 The ETH sentinel

Native ETH is represented by the address
`0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE`, checked inline. From `exchange`
(`:458-489`):

```python
coin: address = self.coins[i]
if coin == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE:
    assert msg.value == _dx
else:
    assert msg.value == 0
    # ... safe transferFrom ...

coin = self.coins[j]
if coin == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE:
    raw_call(msg.sender, b"", value=dy)
else:
    # ... safe transfer ...
```

Two things to note. First, the input branch asserts `msg.value == 0` for the
ERC20 side, so ETH cannot be stranded. Second — and this is the important one —
the output branch uses `raw_call(msg.sender, b"", value=dy)`, which **forwards all
remaining gas**. Vyper's `send()` would forward only the 2300-gas stipend; this
does not. The recipient gets full control mid-function.

The `@nonreentrant('lock')` decorator stops that callee from re-entering
`exchange`. It does **not** stop it from calling a `@view` function. That is §17.1.

---

## 7. `pool-templates/meta` — the metapool template

`pool-templates/meta/SwapTemplateMeta.vy`, 1119 lines, `@version ^0.2.12`.

A metapool has exactly two coins: a new asset, and the **LP token of an existing
base pool**. `GUSD/3CRV` is a 2-coin pool where coin 1 is worth whatever one 3CRV
is worth. That lets a new stablecoin get depth against DAI, USDC and USDT without
fragmenting liquidity.

### 7.1 Extra storage and constants

| Name | Line | Purpose |
|---|---|---|
| `BASE_N_COINS` | 107 | Compile-time coin count of the base pool |
| `BASE_CACHE_EXPIRES` | 129 | `10 * 60` — ten minutes |
| `base_pool: public(address)` | 130 | |
| `base_virtual_price: public(uint256)` | 131 | Cached rate |
| `base_cache_updated: public(uint256)` | 132 | Cache timestamp |
| `base_coins: public(address[BASE_N_COINS])` | 133 | Underlying coins of the base pool |

`__init__` (`:183-195`) stores the base pool, seeds
`base_virtual_price = Curve(_base_pool).get_virtual_price()`, reads each
`base_coins[i]` from the base pool, and grants the base pool a max approval for
each of them so `exchange_underlying` can deposit without re-approving.

### 7.2 `_vp_rate` and `_vp_rate_ro`

`:259-266` (mutating) and `:271-275` (`@view`):

```python
@internal
def _vp_rate() -> uint256:
    if block.timestamp > self.base_cache_updated + BASE_CACHE_EXPIRES:
        vprice: uint256 = Curve(self.base_pool).get_virtual_price()
        self.base_virtual_price = vprice
        self.base_cache_updated = block.timestamp
        return vprice
    else:
        return self.base_virtual_price
```

`RATES[1]` is not a constant here — it is the base pool's virtual price, i.e. how
much one LP token is worth. Every math entry point sets
`rates[MAX_COIN] = self._vp_rate()` before calling `_get_D` or `_get_y`; see
`exchange_underlying` at `:651-652`.

The ten-minute cache exists purely for gas: `get_virtual_price` on the base pool
runs a full Newton iteration, and a metapool would otherwise pay for it on every
single call. `_vp_rate_ro` is the read-only twin used by `@view` functions, which
cannot write the cache.

**The consequence worth understanding:** for up to ten minutes, a metapool prices
its base LP token using a *stale* virtual price. Since virtual price moves only
with accrued fees, that drift is tiny in normal operation. But it also means a
metapool inherits every correctness property of the base pool's
`get_virtual_price` — including the read-only reentrancy of §17.1 when the base
pool holds native ETH.

### 7.3 `exchange_underlying`

`:640-751`, `@external @nonreentrant('lock')`.

This is the function that makes metapools useful: trade GUSD directly for USDC,
even though the pool only holds GUSD and 3CRV.

Index mapping (`:655-663`): indices `0..MAX_COIN` address the metapool's own
coins, and anything at or above `MAX_COIN` addresses a base-pool coin.

```python
base_i: int128 = i - MAX_COIN
base_j: int128 = j - MAX_COIN
meta_i: int128 = MAX_COIN
meta_j: int128 = MAX_COIN
if base_i < 0:
    meta_i = i
if base_j < 0:
    meta_j = j
```

A negative `base_i` means "this index is a metapool coin", and `meta_i` stays at
`MAX_COIN` otherwise, so the metapool-level swap always runs between valid local
indices. Coin addresses are then resolved from either `self.coins` or
`self.base_coins` (`:669-676`).

There are three routes, depending on where the two coins live:

1. **Both metapool coins** — a plain local swap.
2. **One metapool coin, one base coin** — swap locally against the LP token, then
   add or remove liquidity on the base pool to convert.
3. **Both base coins** — the metapool has nothing to do; the trade is delegated
   entirely to the base pool.

`FEE_ASSET` handling at `:678-698` deserves a note: for tokens that take a
transfer fee (USDT historically), the contract measures its own balance before
and after the `transferFrom` and uses the delta:

```python
dx_w_fee: uint256 = _dx
if input_coin == FEE_ASSET:
    dx_w_fee = ERC20(FEE_ASSET).balanceOf(self)
# ... transferFrom ...
if input_coin == FEE_ASSET:
    dx_w_fee = ERC20(FEE_ASSET).balanceOf(self) - dx_w_fee
```

This is the only fee-on-transfer accommodation anywhere in classic Curve, and it
is hard-coded to one specific asset rather than applied generally.

---

## 8. Pool families, as diffs from their template

The 33 pools fall into six groups. Within a group the contracts are close to
identical; the differences that matter are listed per group. Constructor
parameters (`_A`, `_fee`, `_admin_fee`) come from each `pooldata.json` and are
tabulated in §1.2.

### 8.1 First generation (Vyper 0.1.0b16 / 0.1.0b17)

**Pools:** `busd`, `compound`, `usdt`, `y` (0.1.0b16); `pax`, `ren`, `sbtc`,
`susd` (0.1.0b17).

These predate the templates and differ from base in ways no later pool repeats:

- **`get_D` and `get_y` are `@external`**, not `_`-prefixed internals. Anyone can
  call them with arbitrary arrays. They are pure, so this leaks nothing, but it
  does mean these pools expose a larger ABI than modern ones.
- **`get_dy_underlying` exists on all eight.** Later plain pools dropped it.
- **No `A_PRECISION`.** `A` is stored unscaled and cannot be ramped with
  sub-integer resolution.
- **`commit_new_parameters` / `apply_new_parameters`** replace the base
  template's `commit_new_fee` / `apply_new_fee`, and they bundle `A` changes in
  with the fee change rather than exposing `ramp_A` / `stop_ramp_A`. `susd` has
  no `ramp_A` at all.
- **`remove_liquidity_one_coin` is absent from `susd`**, so single-sided exit
  requires the zap.
- **`admin_balances` and `donate_admin_fees` are absent** from `susd`, `ren` and
  `sbtc`.

Rate handling splits the group in two:

| Sub-group | Pools | Rate source |
|---|---|---|
| yToken lending | `busd`, `y` | `_stored_rates()` from `getPricePerFullShare` |
| Compound lending | `compound`, `usdt`, `susd` | `_stored_rates()` + `_current_rates()` from `exchangeRateStored`/`Current` |
| Mixed lending | `pax` | `_rates()` with a `USE_LENDING` flag array |
| BTC, partial lending | `ren`, `sbtc` | `_rates()` with `USE_LENDING`, `exchangeRateCurrent` |

The `USE_LENDING` pattern in [`pools/ren/StableSwapRen.vy:166-172`](curve-contract/contracts/pools/ren/StableSwapRen.vy#L166-L172) is the
interesting one, because it lets a single pool mix wrapped and unwrapped coins:

```python
def _rates() -> uint256[N_COINS]:
    result: uint256[N_COINS] = PRECISION_MUL
    use_lending: bool[N_COINS] = USE_LENDING
    for i in range(N_COINS):
        rate: uint256 = LENDING_PRECISION  # Used with no lending
        if use_lending[i]:
            rate = cERC20(self.coins[i]).exchangeRateCurrent()
```

Coins flagged `False` get the identity rate; flagged coins are asked for
`exchangeRateCurrent()`. The actual flags are:

```
pax/StableSwapPax.vy:54    USE_LENDING = [True, True, True, False]   # ycDAI, ycUSDC, ycUSDT, PAX
sbtc/StableSwapSBTC.vy:55  USE_LENDING = [True, False, False]        # renBTC, wBTC, sBTC
ren/StableSwapRen.vy:55    USE_LENDING = [True, False]               # renBTC, wBTC
```

renBTC being flagged `True` is not an oversight. The file header explains it
([`pools/ren/StableSwapRen.vy:3`](curve-contract/contracts/pools/ren/StableSwapRen.vy#L3)): *"Pools for renBTC/wBTC. Ren can potentially
change amount of underlying bitcoins."* renBTC was designed to be able to
re-denominate, so the pool queries it for a rate exactly as it would a cToken.
The test mock `testing/renERC20.vy` carries an `exchangeRateStored` field
(`:32`) and a `set_exchange_rate` setter (`:87-88`) for precisely this.

`ren` and `sbtc` share a source file almost exactly (both 743 lines, both
0.1.0b17); `sbtc` is `ren` plus sBTC as a third, non-lending coin.

### 8.2 Second generation plain pools (0.2.4 / 0.2.8)

**Pools:** `3pool`, `hbtc` (0.2.4); `eurs`, `link` (0.2.8).

Closest to `SwapTemplateBase`, with three notable deltas:

- **`3pool` and `hbtc` still name the solvers `get_D` / `get_y`** (public), and
  still carry `get_dy_underlying` ([`pools/3pool/StableSwap3Pool.vy:416-425`](curve-contract/contracts/pools/3pool/StableSwap3Pool.vy#L416-L425)).
  For a plain pool with no wrapped coins, `get_dy_underlying` differs from
  `get_dy` only in that it scales by `PRECISION_MUL` rather than `RATES` — the
  same number by a different route. It is a leftover from the lending pools.
- **`eurs` is the precision outlier.** EURS has **2 decimals**, so
  `PRECISION_MUL[0] = 10**16`, the largest scaling factor anywhere in the tree.
  Every EURS balance is multiplied by 1e16 before entering the invariant. The
  practical effect is that one raw EURS unit is worth 1e16 normalised units, so
  rounding losses of "one wei" in normalised space are invisible at the token
  level — the opposite of the usual worry.
- **`link` adds a flash-loan tripwire.** It carries two extra storage slots
  ([`pools/link/StableSwapLINK.vy:99-100`](curve-contract/contracts/pools/link/StableSwapLINK.vy#L99-L100)):

  ```python
  previous_balances: public(uint256[N_COINS])
  block_timestamp_last: public(uint256)
  ```

  and an `_update()` internal (`:187-194`) called at the start of state-changing
  functions:

  ```python
  if block.timestamp > self.block_timestamp_last:
      self.previous_balances = self.balances
      self.block_timestamp_last = block.timestamp
  ```

  The docstring says it plainly (`:189-190`): *"Commits pre-change balances for
  the previous block. Can be used to compare against current values for flash
  loan checks."* An integrator can read `previous_balances` and `balances` and
  refuse to act if they diverge within a block. `link` is the only classic pool
  with this; it is the ancestor of NG's price oracle.

### 8.3 BTC metapools over `sbtc` (0.2.7 / 0.2.8)

**Pools:** `bbtc`, `obtc`, `pbtc`, `tbtc`. All meta, base pool `sbtc`, all with
a zap.

Standard `SwapTemplateMeta` instances. The distinguishing feature is decimal
handling: `bBTC` has **8 decimals** while the other three assets are 18, and the
base LP token `sbtcCRV` is always 18. So `bbtc` runs `PRECISION_MUL = [10**10, 1]`
while `obtc`, `pbtc` and `tbtc` run `[1, 1]`.

`tbtc` is the odd one at 1078 lines against 1076 for the other three, and is
compiled with 0.2.7 rather than 0.2.8.

### 8.4 USD metapools over `3pool` (0.2.5 / 0.2.7 / 0.2.8)

**Pools:** `dusd`, `gusd`, `husd`, `linkusd`, `musd`, `rsv`, `usdk`, `usdn`,
`usdp`, `ust`. All meta, base pool `3pool`, all with a zap.

The largest family, and the most uniform: seven of the ten are 1082-1083 lines
compiled with 0.2.5. Differences are entirely in constructor constants and
decimals:

| Pool | New-coin decimals | `PRECISION_MUL[0]` | `A` | fee (bps) | admin fee |
|---|---|---|---|---|---|
| `gusd` | 2 | `10**16` | 200 | 4 | 0 |
| `husd` | 8 | `10**10` | 200 | 4 | 0 |
| `dusd`, `musd`, `rsv`, `usdk` | 18 | `1` | 200 | 4 | 0 |
| `usdn`, `ust` | 18 | `1` | 100 | 4 | 0 / 50% (`ust`) |
| `usdp` | 18 | see note | 100 | 4 | 50% |
| `linkusd` | 18 | `1` | **5** | **15** | 0 |

`linkusd` is worth singling out: `A = 5` and a 15 bps fee, against the family's
usual `A = 200` and 4 bps. That is a deliberate statement that LINKUSD was *not*
expected to hold its peg tightly, so the pool behaves much more like a constant
product and charges nearly four times as much per trade.

`usdp` is the largest at 1113 lines and uses `CurveTokenV3`; `usdn` and `usdk`
use `CurveTokenV2`. `usdp` is also the one pool in this family that declares no
`PRECISION_MUL` at all — both its coins are 18 decimals, so it hard-codes
`RATES: constant(uint256[N_COINS]) = [10**18, 10**18]`
([`pools/usdp/StableSwapUSDP.vy:103`](curve-contract/contracts/pools/usdp/StableSwapUSDP.vy#L103)) and skips the multiplier array entirely.

### 8.5 Lending pools (0.2.8)

**Pools:** `aave`, `saave` (`arate`, from `SwapTemplateA`); `ib` (`crate`);
`compound`, `usdt`, `busd`, `y`, `pax` (first generation, covered in §8.1).

`aave` (1053 lines) and `saave` (997 lines) are `SwapTemplateA` instances:
rebasing aToken balances read live, `offpeg_fee_multiplier`, `aave_referral`.
`aave` is 3-coin (aDAI/aUSDC/aUSDT), `saave` is 2-coin (aDAI/aSUSD).

`ib` (1006 lines) is the most interesting rate implementation in the repository.
Its coins are Iron Bank cyTokens, and rather than reading a stored exchange rate
it **extrapolates the rate forward** to the current block
([`pools/ib/StableSwapIB.vy:226-234`](curve-contract/contracts/pools/ib/StableSwapIB.vy#L226-L234)):

```python
def _stored_rates() -> uint256[N_COINS]:
    # exchangeRateStored * (1 + supplyRatePerBlock * (getBlockNumber - accrualBlockNumber) / 1e18)
    result: uint256[N_COINS] = PRECISION_MUL
    for i in range(N_COINS):
        coin: address = self.coins[i]
        rate: uint256 = cyToken(coin).exchangeRateStored()
        rate += rate * cyToken(coin).supplyRatePerBlock() * (block.number - cyToken(coin).accrualBlockNumber()) / PRECISION
        result[i] *= rate
    return result
```

`exchangeRateStored` is only accurate as of the cyToken's last accrual, so `ib`
adds the interest that has accrued since, using the cyToken's own advertised
supply rate. This avoids the gas of calling `exchangeRateCurrent` (which writes
state) on every quote, at the cost of trusting `supplyRatePerBlock`. `ib` also
carries the `link`-style `_update()` flash-loan tripwire (`:238`).

### 8.6 ETH pools (0.2.8 / 0.2.12)

**Pools:** `seth` (`eth`), `steth` (`eth,arate`), `aeth` and `reth`
(`eth,crate`).

All four are `SwapTemplateEth` instances holding native ETH as coin 0.

- **`seth`** (883 lines) is the plain case: ETH + sETH, both 18 decimals, no rate.
- **`steth`** (839 lines) adds `arate` handling because stETH **rebases**. Like
  the Aave template it derives balances live rather than storing them
  ([`pools/steth/StableSwapSTETH.vy:190-194`](curve-contract/contracts/pools/steth/StableSwapSTETH.vy#L190-L194)):

  ```python
  def _balances(_value: uint256 = 0) -> uint256[N_COINS]:
      return [
          self.balance - self.admin_balances[0] - _value,
          ERC20(self.coins[1]).balanceOf(self) - self.admin_balances[1]
      ]
  ```

  The `_value` parameter exists so a `@payable` function can subtract the ETH it
  was just sent, since `self.balance` already includes `msg.value` by the time the
  body runs.

- **`aeth`** and **`reth`** (843 lines each) pair ETH with a non-rebasing LST
  (ankrETH, rETH) whose value grows against ETH, so they need a rate. Both ship a
  `RateCalculator` contract: `pools/aeth/RateCalculatorAETH.vy` (22 lines) reads
  the ratio from the LST, while the template stubs
  (`pool-templates/eth/RateCalculatorTemplateETH.vy`, 15 lines) return a constant.
  `reth` is the only 0.2.12 pool in the tree.

The ETH pools are where §17.1 applies. `steth` is the canonical example.

---

## 9. The zaps

A **zap** is an unprivileged helper contract that wraps a pool so users can
deposit and withdraw in a more convenient denomination. Zaps hold no funds
between transactions, have no admin, and can be replaced freely — they are
convenience, not protocol.

Two shapes exist.

### 9.1 Lending zaps (`DepositTemplateY` shape)

`pool-templates/y/DepositTemplateY.vy`, 280 lines, `@version ^0.2.0`.
Instances: `pools/y/DepositY.vy`, `pools/busd/DepositBUSD.vy`,
`pools/compound/DepositCompound.vy`, `pools/usdt/DepositUSDT.vy`,
`pools/pax/DepositPax.vy`, `pools/susd/DepositSUSD.vy`.

The pool holds yTokens or cTokens; the user holds DAI and USDC. The zap wraps on
the way in and unwraps on the way out.

| Function | Line | Purpose |
|---|---|---|
| `__init__` | 48 | Stores pool, coins, underlying coins, LP token; grants approvals |
| `add_liquidity(_underlying_amounts, _min_mint_amount)` | 99 | Pull underlying, `deposit()` into each wrapper, call pool `add_liquidity`, forward LP tokens |
| `_unwrap_and_transfer(_addr, _min_amounts)` | 145 | Internal: `withdraw()` from each wrapper and send the underlying on |
| `remove_liquidity(...)` | 181 | Pull LP, pool `remove_liquidity`, then `_unwrap_and_transfer` |
| `remove_liquidity_imbalance(...)` | 200 | Same, imbalanced; returns unused LP tokens |
| `remove_liquidity_one_coin(...)` | 242 | Single-coin exit, unwrapped |

The recurring assert messages here are `"Not enough coins withdrawn"`,
`"Could not mint coin"` and `"Could not redeem coin"` — all specific to the
wrap/unwrap legs and found only in this zap family.

### 9.2 Metapool zaps (`DepositTemplateMeta` shape)

`pool-templates/meta/DepositTemplateMeta.vy`, 378 lines, `@version 0.2.12`.
Instances: the sixteen `Deposit*.vy` files listed in §1.3 belonging to metapools.

The metapool holds `[NEW_COIN, 3CRV]`; the user wants to think in
`[NEW_COIN, DAI, USDC, USDT]`. `N_ALL_COINS = N_COINS + BASE_N_COINS - 1`.

| Function | Line | Purpose |
|---|---|---|
| `__init__(_pool, _token)` | 56 | Stores pool and token, grants max approvals to pool and base pool |
| `add_liquidity(_amounts[N_ALL_COINS], _min_mint_amount)` | 101 | Splits input into the meta coin and the base coins, `add_liquidity` on the base pool first, then on the metapool |
| `remove_liquidity(_amount, _min_amounts[N_ALL_COINS])` | 165 | Metapool withdrawal, then base-pool withdrawal, then forward all |
| `remove_liquidity_one_coin(_token_amount, i, _min_amount)` | 217 | Routes to the metapool or through the base pool depending on `i` |
| `remove_liquidity_imbalance(_amounts[N_ALL_COINS], _max_burn_amount)` | 260 | The hardest one: works out how much base LP is needed, burns the minimum, refunds the remainder |
| `calc_withdraw_one_coin(_token_amount, i)` | 341 | View helper composing both pools' estimates |
| `calc_token_amount(_amounts[N_ALL_COINS], _is_deposit)` | 357 | View helper; inherits `calc_token_amount`'s fee-blindness (§3.6) |

A zap always costs more gas than going direct, and it always makes **two**
imbalance-fee payments where a direct route makes one. Use `exchange_underlying`
on the metapool for swaps; use the zap only for liquidity operations.

---

## 10. The LP tokens

Three versions, all in `tokens/`. The pool is the token's `minter`; nothing else
may mint or burn.

| | V1 (`CurveTokenV1.vy`, 171 lines, 0.1.0b16) | V2 (`CurveTokenV2.vy`, 175 lines, `^0.2.0`) | V3 (`CurveTokenV3.vy`, 192 lines, `^0.2.0`) |
|---|---|---|---|
| `set_minter` | yes | yes | yes |
| `set_name` | **no** | yes | yes |
| `totalSupply` / `allowance` as functions | yes | yes | **no** (public vars) |
| `burn` (self) | yes | **no** | **no** |
| `_burn` internal | yes | no | no |
| `increaseAllowance` / `decreaseAllowance` | no | no | **yes** |
| `decimals` as a function | no | no | yes |

The progression is a tightening one. V1 lets a holder `burn` their own tokens
outside the pool's accounting, which desynchronises `totalSupply` from the pool's
view of it and permanently strands the underlying — V2 removed it. V2 added
`set_name` so the DAO could rename a token after launch. V3 replaced the
`approve`-race-prone interface with OpenZeppelin's increase/decrease pattern and
exposed `totalSupply` and `allowance` as public variables rather than functions,
which is cheaper.

Which pool uses which is listed in §1.2. Broadly: first-generation pools use V1,
the 0.2.4-0.2.7 era uses V2, and 0.2.8 onward uses V3.

---

## 11. Rate calculators and `testing/`

**Rate calculators.** Small contracts that answer "how much is one unit of this
LST worth in ETH?". `pool-templates/eth/RateCalculatorTemplateETH.vy` and
`pool-templates/meta/RateCalculatorTemplateMeta.vy` are 15-line stubs returning a
constant. `pools/aeth/RateCalculatorAETH.vy` (22 lines) is the only real
implementation, reading the ratio from ankrETH.

**`testing/`.** Mocks used by the brownie test-suite, not deployed:

| File | Purpose |
|---|---|
| `ERC20Mock.vy` | Plain ERC20 with mintable supply |
| `ERC20MockNoReturn.vy` | Returns nothing from `transfer`/`approve` — the USDT shape; this is what the `raw_call` + conditional-decode pattern exists for |
| `cERC20.vy` | Compound cToken mock (`exchangeRateStored`, `supplyRatePerBlock`) |
| `yERC20.vy` | yearn yToken mock (`getPricePerFullShare`) |
| `aERC20.sol` / `AaveLendingPoolMock.sol` | Aave aToken and pool mocks (Solidity) |
| `aETH.vy` | ankrETH mock |
| `rETH.vy` | Rocket Pool rETH mock |
| `renERC20.vy` | renBTC mock |
| `SwapMock.vy` | Minimal pool used to test zaps in isolation |
| `LiquidityGaugeV2Mock.vy` | Gauge stand-in |

`ERC20MockNoReturn.vy` is the most instructive file here: every hand-rolled
`raw_call` safe-transfer in this codebase exists because of tokens shaped like it.

---

## 12. ABI / selector tables

Selectors computed with `cast sig`. Array-typed parameters make the selector
depend on `N_COINS`, so those rows are given per coin count.

### 12.1 Core swap interface (all templates)

| Signature | Selector |
|---|---|
| `exchange(int128,int128,uint256,uint256)` | `0x3df02124` |
| `exchange_underlying(int128,int128,uint256,uint256)` | `0xa6417ed6` |
| `get_dy(int128,int128,uint256)` | `0x5e0d443f` |
| `get_virtual_price()` | `0xbb7b8b80` |
| `calc_withdraw_one_coin(uint256,int128)` | `0xcc2b27d7` |
| `remove_liquidity_one_coin(uint256,int128,uint256)` | `0x1a4d01d2` |
| `coins(uint256)` | `0xc6610657` |
| `balances(uint256)` | `0x4903b0d1` |
| `A()` | `0xf446c1d0` |
| `A_precise()` | `0x76a2f0f0` |
| `admin_balances(uint256)` | `0xe2e7d264` |

### 12.2 Array-typed, by coin count

| Signature | Selector |
|---|---|
| `add_liquidity(uint256[2],uint256)` | `0x0b4c7e4d` |
| `add_liquidity(uint256[3],uint256)` | `0x4515cef3` |
| `remove_liquidity(uint256,uint256[3])` | `0xecb586a5` |
| `remove_liquidity_imbalance(uint256[3],uint256)` | `0x9fdaea0c` |
| `calc_token_amount(uint256[3],bool)` | `0x3883e119` |

This is the single most common integration bug against classic Curve: a 2-coin
pool and a 3-coin pool expose **different selectors for the same function name**.
A router that hard-codes `0x4515cef3` will revert against every 2-coin pool.

### 12.3 Admin interface

| Signature | Selector |
|---|---|
| `ramp_A(uint256,uint256)` | `0x3c157e64` |
| `stop_ramp_A()` | `0x551a6588` |
| `withdraw_admin_fees()` | `0x30c54085` |
| `kill_me()` | `0xe3698853` |
| `unkill_me()` | `0x3046f972` |

First-generation pools (§8.1) expose `commit_new_parameters` /
`apply_new_parameters` instead of `commit_new_fee` / `apply_new_fee`, and several
lack `ramp_A` entirely.

---

## 13. Storage layout tables

Vyper 0.2 lays storage out in declaration order, one slot per scalar, and `n`
consecutive slots for a fixed array of `n` scalars. No packing.

### 13.1 `SwapTemplateBase` (N = 3)

| Slot | Variable | Type |
|---|---|---|
| 0-2 | `coins` | `address[3]` |
| 3-5 | `balances` | `uint256[3]` |
| 6 | `fee` | `uint256` |
| 7 | `admin_fee` | `uint256` |
| 8 | `owner` | `address` |
| 9 | `lp_token` | `address` |
| 10 | `initial_A` | `uint256` |
| 11 | `future_A` | `uint256` |
| 12 | `initial_A_time` | `uint256` |
| 13 | `future_A_time` | `uint256` |
| 14 | `admin_actions_deadline` | `uint256` |
| 15 | `transfer_ownership_deadline` | `uint256` |
| 16 | `future_fee` | `uint256` |
| 17 | `future_admin_fee` | `uint256` |
| 18 | `future_owner` | `address` |
| 19 | `is_killed` | `bool` |
| 20 | `kill_deadline` | `uint256` |

### 13.2 Template deltas

| Template | Added storage |
|---|---|
| `y` | `underlying_coins: address[N]` after `coins` |
| `a` | `admin_balances: uint256[N]` (an array, not a computed getter), `offpeg_fee_multiplier`, `future_offpeg_fee_multiplier`, `aave_referral` |
| `eth` | none (but `balances` is unnormalised) |
| `meta` | `base_pool`, `base_virtual_price`, `base_cache_updated`, `base_coins: address[BASE_N_COINS]` |

### 13.3 Pool-specific additions

| Pool | Added storage | Lines |
|---|---|---|
| `link`, `ib` | `previous_balances: uint256[N]`, `block_timestamp_last: uint256` | [`pools/link/StableSwapLINK.vy:99-100`](curve-contract/contracts/pools/link/StableSwapLINK.vy#L99-L100) |
| `steth` | `admin_balances: uint256[N]` (rebasing) | — |

---

## 14. Events reference

All seven events are declared identically in every template
([`pool-templates/base/SwapTemplateBase.vy:20-78`](curve-contract/contracts/pool-templates/base/SwapTemplateBase.vy#L20-L78)).

| Event | Line | Fields | Emitted by |
|---|---|---|---|
| `TokenExchange` | 20 | `buyer` (indexed), `sold_id`, `tokens_sold`, `bought_id`, `tokens_bought` | `exchange`, `exchange_underlying` |
| `AddLiquidity` | 27 | `provider` (indexed), `token_amounts[N]`, `fees[N]`, `invariant`, `token_supply` | `add_liquidity` |
| `RemoveLiquidity` | 34 | `provider` (indexed), `token_amounts[N]`, `fees[N]`, `token_supply` | `remove_liquidity` (fees always zero) |
| `RemoveLiquidityOne` | 40 | `provider` (indexed), `token_amount`, `coin_amount`, `token_supply` | `remove_liquidity_one_coin` |
| `RemoveLiquidityImbalance` | 46 | `provider` (indexed), `token_amounts[N]`, `fees[N]`, `invariant`, `token_supply` | `remove_liquidity_imbalance` |
| `CommitNewAdmin` | 53 | `deadline` (indexed), `admin` (indexed) | `commit_transfer_ownership` |
| `NewAdmin` | 57 | `admin` (indexed) | `apply_transfer_ownership` |
| `CommitNewFee` | 60 | `deadline` (indexed), `fee`, `admin_fee` | `commit_new_fee` |
| `NewFee` | 65 | `fee`, `admin_fee` | `apply_new_fee` |
| `RampA` | 69 | `old_A`, `new_A`, `initial_time`, `future_time` | `ramp_A` |
| `StopRampA` | 75 | `A`, `t` | `stop_ramp_A` |

**Notes for indexers.**

- Only `provider` / `buyer` and the admin fields are indexed. There is no indexed
  coin id, so filtering by traded pair requires decoding the data.
- `AddLiquidity` and `RemoveLiquidityImbalance` carry `invariant` (`D1`), which
  together with `token_supply` lets you reconstruct virtual price at that block
  without an archive call.
- `RemoveLiquidity` emits an all-zero `fees` array because proportional
  withdrawal is free — do not treat the zero as missing data.
- **No event is emitted** by `withdraw_admin_fees`, `donate_admin_fees`,
  `kill_me`, `unkill_me`, `revert_new_parameters` or `revert_transfer_ownership`.
  Admin fee collection is invisible to log-based indexers; it must be inferred
  from balance deltas.

---

## 15. Revert-message table

Two mechanisms are in play. Quoted strings are real revert reasons visible
on-chain. `# dev:` comments are Vyper's dev-revert annotations: they compile to a
bare revert, and the message is only recoverable through a tool that maps
program counters back to source.

### 15.1 Quoted revert strings

| Message | Count | Where |
|---|---|---|
| `"Slippage screwed you"` | 76 | `add_liquidity`, `remove_liquidity_imbalance` |
| `"Too few coins in result"` | 45 | Zaps |
| `"Not enough coins removed"` | 39 | `remove_liquidity_one_coin` |
| `"Exchange resulted in fewer coins than expected"` | 36 | `exchange`, `exchange_underlying` |
| `"Withdrawal resulted in fewer coins than expected"` | 24 | `remove_liquidity` |
| `"Not enough coins withdrawn"` | 7 | Lending zaps |
| `"Could not redeem coin"` | 6 | Lending zaps (unwrap leg) |
| `"Could not mint coin"` | 6 | Lending zaps (wrap leg) |

Counts are occurrences across `pools/` and `pool-templates/`. Every one of these
is a **slippage guard**, which is the point worth internalising: classic Curve has
essentially no other user-facing error surface. If a call reverts with a string,
the user's minimum was not met.

### 15.2 `# dev:` annotations

| Annotation | Count | Meaning |
|---|---|---|
| `only owner` | 61 | `msg.sender != self.owner` |
| `failed transfer` | 21 | A `raw_call` transfer returned `False` |
| `is killed` | 20 | Pool is killed; only `remove_liquidity` works |
| `insufficient time` | 15 | Timelock or ramp duration not satisfied |
| `insufficient funds` | 15 | `burnFrom` failed — caller lacks LP tokens |
| `zero tokens burned` | 5 | `remove_liquidity_imbalance` rounded to zero |
| `same coin` | 5 | `i == j` in `_get_y` |
| `no active transfer` / `no active action` | 5 each | `apply_*` with no pending commit |
| `active transfer` / `active action` | 5 each | `commit_*` while one is pending |
| `j below zero` / `j above N_COINS` | 5 each | Coin index out of range |
| `i below zero` / `i above N_COINS` | 5 each | Coin index out of range |
| `initial deposit requires all coins` | 5 | First `add_liquidity` had a zero amount |
| `fee exceeds maximum` | 5 | `> MAX_FEE` |
| `admin fee exceeds maximum` | 5 | `> MAX_ADMIN_FEE` |
| `deadline has passed` | 5 | `kill_me` after `kill_deadline` |
| `offpeg multiplier exceeds maximum` | 1 | Aave template only (`a:1012`) |
| `uint16 overflow` | 1 | `set_aave_referral` |

Unannotated bare asserts also exist — `assert D1 > D0` in `add_liquidity`
(`base:322`) and the two "should be unreachable" index checks in `_get_y`
(`base:396-397`) revert with no information at all.

---

## 16. Use-case index

### 16.1 Swap in a plain pool

`exchange(i, j, _dx, _min_dy)` → `base:447`.

```
exchange
 ├── assert not is_killed                          base:457
 ├── _xp_mem(old_balances)                         base:197
 ├── _get_y(i, j, x, xp)                           base:379
 │     └── _get_D(_xp, A)                          base:206
 ├── dy = xp[j] - y - 1;  fee;  denormalise        base:466-470
 ├── assert dy >= _min_dy                          base:471
 ├── balances[i] += _dx;  balances[j] -= dy+admin  base:477-479
 ├── raw_call transferFrom(sender → pool, _dx)     base:481
 └── raw_call transfer(pool → sender, dy)          base:494
```

Quote first with `get_dy(i, j, _dx)` (`base:434`) and set `_min_dy` below it.

### 16.2 Swap underlying in a lending pool

`exchange_underlying(i, j, _dx, _min_dy)` → `y:603`.

```
exchange_underlying
 ├── _stored_rates()  → getPricePerFullShare per coin   y:222
 ├── dx = _dx * PRECISION / (rates[i]/precisions[i])    y:616
 ├── _exchange(i, j, dx, rates)      (the local swap)
 ├── transferFrom underlying in
 ├── yERC20(coins[i]).deposit(_dx)                      y:634
 ├── yERC20(coins[j]).withdraw(dy_)                     y:635
 ├── dy = balanceOf(underlying[j])   ← re-read, not predicted  y:638
 └── transfer underlying out
```

### 16.3 Swap underlying in a metapool

`exchange_underlying(i, j, _dx, _min_dy)` → `meta:640`.

Indices `0..MAX_COIN-1` are metapool coins; `MAX_COIN` and above are base-pool
coins. Three routes (§7.3): both-meta, one-of-each, both-base. `rates[MAX_COIN]`
is set from `_vp_rate()` (`meta:652`) before any math runs.

For GUSD → USDC on `gusd`: `i = 0` (GUSD), `j = 2` (USDC, since 3pool is
DAI/USDC/USDT and `MAX_COIN = 1`).

### 16.4 Deposit via zap

Metapool: `Deposit*.add_liquidity(_amounts[N_ALL_COINS], _min_mint_amount)` →
[`pool-templates/meta/DepositTemplateMeta.vy:101`](curve-contract/contracts/pool-templates/meta/DepositTemplateMeta.vy#L101). Adds to the base pool first,
then the metapool. Two imbalance fees.

Lending: `Deposit*.add_liquidity(_underlying_amounts, _min_mint_amount)` →
[`pool-templates/y/DepositTemplateY.vy:99`](curve-contract/contracts/pool-templates/y/DepositTemplateY.vy#L99). Wraps each coin, then deposits.

### 16.5 Withdraw in one coin

`remove_liquidity_one_coin(_token_amount, i, _min_amount)` → `base:704`.

```
remove_liquidity_one_coin
 ├── _calc_withdraw_one_coin(_token_amount, i)     base:661
 │     ├── _get_D(xp, amp)                → D0
 │     ├── D1 = D0 - amount*D0/supply
 │     ├── _get_y_D(amp, i, xp, D1)       → new_y  base:614   (first solve)
 │     ├── per-coin imbalance fee → xp_reduced
 │     └── _get_y_D(amp, i, xp_reduced, D1)        base:614   (second solve)
 ├── assert dy >= _min_amount                      base:718
 ├── balances[i] -= dy + admin share of fee        base:720
 ├── burnFrom(sender, _token_amount)               base:721
 └── raw_call transfer(pool → sender, dy)          base:723
```

Preview with `calc_withdraw_one_coin` (`base:692`). Unlike `calc_token_amount`,
this one **does** account for fees, so it is safe as a settlement estimate.

### 16.6 Withdraw proportionally

`remove_liquidity(_amount, _min_amounts)` → `base:513`. No fee, no invariant
solve, works even when killed or when a coin balance is zero. This is the exit of
last resort.

### 16.7 Read the virtual price safely

`get_virtual_price()` → `base:252`.

**Do not call this from inside a callback.** See §17.1. If you are integrating a
pool that holds native ETH, either read it only at the top of your own
transaction, or force the pool's `lock` first by calling a `@nonreentrant`
function such as `withdraw_admin_fees()` or `remove_liquidity(0, [0,...])`.

### 16.8 Claim admin fees

`withdraw_admin_fees()` → `base:854`, owner only, sends to `msg.sender`. In
production the owner is the DAO's `PoolProxy`. `admin_balances(i)` (`base:849`)
previews the amount and is callable by anyone.

### 16.9 Ramp A

`ramp_A(_future_A, _future_time)` → `base:742`, owner only. At least one day
since the last ramp began, at least one day of duration, at most 10× change.
`stop_ramp_A()` (`base:765`) freezes at the current interpolated value.

### 16.10 Kill a pool

`kill_me()` → `base:882`, owner only, and only within ~60 days of deployment
(`KILL_DEADLINE_DT`, `base:119`). After that the pool can never be killed.
`unkill_me()` (`base:889`) has no deadline.

---

## 17. Security notes

### 17.1 Read-only reentrancy through `get_virtual_price`

This is the most important thing in this document.

Take `pools/steth/StableSwapSTETH.vy`. Its `remove_liquidity` (`:477-505`) does
the following, in this order:

```python
amounts: uint256[N_COINS] = self._balances()
lp_token: address = self.lp_token
total_supply: uint256 = ERC20(lp_token).totalSupply()
CurveToken(lp_token).burnFrom(msg.sender, _amount)          # :491  supply drops

for i in range(N_COINS):
    value: uint256 = amounts[i] * _amount / total_supply
    assert value >= _min_amounts[i], "Withdrawal resulted in fewer coins than expected"
    amounts[i] = value
    if i == 0:
        raw_call(msg.sender, b"", value=value)              # :499  ETH out, full gas
    else:
        assert ERC20(self.coins[1]).transfer(msg.sender, value)   # :501  stETH out
```

At the moment of the `raw_call` on `:499`:

- LP `totalSupply` has already been reduced (`:491`).
- The pool's ETH balance has already been reduced (the call is sending it).
- The pool's **stETH balance has not yet been reduced** — that happens on the next
  loop iteration, at `:501`.

The recipient has full gas and full control. `remove_liquidity` carries
`@nonreentrant('lock')` (`:476`), so it cannot re-enter any *mutating* function.
But `get_virtual_price` (`:251`) is declared:

```python
@view
@external
def get_virtual_price() -> uint256:
```

with **no** `@nonreentrant`. It reads `_balances()` (`:190-194`), which pulls
`self.balance` and `ERC20(coins[1]).balanceOf(self)` live, and divides `D` by the
already-reduced `totalSupply`. The numerator is missing only the ETH; the
denominator is missing the whole burn. The result is transiently **inflated**.

The attacker's own position is unaffected. The victim is any third party that
prices something off `get_virtual_price` during that window — most damagingly, a
lending market accepting the LP token as collateral, which can be induced to
over-lend. Hence "read-only": the exploit never writes to Curve at all.

**Which pools in this tree are exposed.** Any pool that sends native ETH inside a
loop before the loop finishes, and exposes an unguarded view over the same state.
That is the four ETH pools: `seth`, `steth`, `aeth`, `reth`. Plain ERC20 pools are
exposed only if a coin yields control on transfer. Metapools over an ETH base pool
inherit it through `_vp_rate` (§7.2).

**Mitigations.**

- *As an integrator:* before reading `get_virtual_price`, call a
  `@nonreentrant('lock')` function on the pool so a reentrant read reverts.
  `withdraw_admin_fees()` is owner-only, so the usual choice is
  `remove_liquidity(0, [0, 0])`, which locks, does nothing, and unlocks.
- *As a protocol designer:* this is why StableSwap-NG marks `get_virtual_price`,
  `totalSupply`, `price_oracle` and `D_oracle` as `@view @nonreentrant('lock')`,
  and why it refuses native ETH outright. See
  [`STABLESWAP-NG-COMPLETE-REFERENCE.md`](STABLESWAP-NG-COMPLETE-REFERENCE.md).

### 17.2 The Vyper `@nonreentrant` compiler bug (30 July 2023)

Vyper 0.2.15, 0.2.16 and 0.3.0 generated broken reentrancy locks when one lock
key was shared across functions of differing mutability. Four Curve pools were
drained for roughly $70M.

**No contract in this repository uses an affected version.** The sweep in §1.4
shows a range of 0.1.0b16 to 0.2.12. The drained pools were factory-deployed and
live elsewhere.

Keep the general lesson: `@nonreentrant` is a compiler-emitted guard, so its
correctness is a property of the toolchain, not of the source. Read the pragma
before you trust the decorator.

### 17.3 `A` ramp manipulation

Changing `A` re-prices the pool with no trade (§2.6). The guards in `ramp_A`
(`base:742-761`) — one day minimum since the last ramp, one day minimum duration,
10× maximum change, owner-only — exist to make front-running a ramp unprofitable
relative to the arbitrage cost of moving the pool.

`MAX_A = 10**6` (`base:91`) is not arbitrary either. At extreme `A` the pool
behaves as a constant sum, and the scarce coin can be drained at nearly 1:1;
the Newton iterations also lose precision.

First-generation pools (§8.1) have no `ramp_A` and change `A` through
`commit_new_parameters`, which is subject only to the 3-day timelock.

### 17.4 Donations and admin fees are the same thing

`admin_balances(i)` is `balanceOf(self) - self.balances[i]` (`base:849`). The
contract cannot distinguish a fee from a gift. Anyone who transfers tokens
directly to a classic pool has donated them to the **owner**, not to LPs, until
someone calls `donate_admin_fees()` (`base:875`).

There is no share-inflation attack of the ERC-4626 kind here, because the
numeraire is `D` — computed from `self.balances`, which a donation does not touch
— rather than `balanceOf`. The first depositor receives exactly `D1` LP tokens
(`base:347-348`), fixing the initial virtual price at 1e18.

### 17.5 Rate oracles are trusted absolutely

The lending templates read an external rate on every quote:
`getPricePerFullShare` (`y:225`), `exchangeRateStored` extrapolated by
`supplyRatePerBlock` (`ib:231-232`), `exchangeRateCurrent` (`ren:172`).

None is bounded, smoothed, or checked for staleness. A wrapper that misreports
its rate mis-prices the pool immediately and completely. `ib`'s extrapolation
additionally trusts a *forward-looking* number, `supplyRatePerBlock`, which is
itself a projection.

### 17.6 Fee-on-transfer and rebasing tokens

Classic Curve assumes a transfer moves exactly the requested amount. The single
exception is the metapool template's hard-coded `FEE_ASSET` handling
(`meta:678-698`), which measures balances before and after — and it applies to one
specific address, not to fee-on-transfer tokens generally.

Rebasing tokens are handled only where the template was built for them: the Aave
template derives balances live (`a:273-277`) and `steth` does the same
(`steth:190-194`). Putting a rebasing token into a plain pool would strand every
rebase as claimable admin fee.

### 17.7 Slippage guards are the only protection

Every mutating function takes a minimum or maximum: `_min_dy`, `_min_mint_amount`,
`_min_amounts`, `_max_burn_amount`, `_min_amount`. There is no deadline parameter
anywhere in classic Curve, so a transaction can sit in the mempool and execute at
a much later price — the guard must be sized for that, not just for one block.

The classic sandwich target is a large `remove_liquidity_one_coin`, which moves
the pool the most per unit of value.

### 17.8 Killed pools

While `is_killed`, only `remove_liquidity` works — `add_liquidity` (`base:303`),
`exchange` (`base:457`), `remove_liquidity_imbalance` (`base:559`) and
`remove_liquidity_one_coin` (`base:712`) all revert. The switch is owner-only and
expires about 60 days after deployment (`base:119`), after which the pool is
permanently unkillable. `unkill_me` never expires.

---

## Appendix: reproducing the sweeps

```bash
cd curve/curve-contract/contracts

# compiler versions
for f in pool-templates/*/Swap*.vy pools/*/StableSwap*.vy; do
  echo "$f $(grep -m1 '@version' "$f")"
done

# quoted revert strings
grep -rhoE '"[^"]{4,60}"' --include='*.vy' pools pool-templates | sort | uniq -c | sort -rn

# dev annotations
grep -rhoE '# dev: [a-zA-Z0-9 _]+' --include='*.vy' pool-templates | sort | uniq -c | sort -rn

# what a given pool changed relative to its template
diff pool-templates/base/SwapTemplateBase.vy pools/3pool/StableSwap3Pool.vy
```
