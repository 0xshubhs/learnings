# Curve Classic Pools — Complete Reference

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
  - [1.4 Compiler versions and the July 2023 Vyper bug](#14-compiler-versions)
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
- [3. `pool-templates/base` — the plain template](#3-pool-templatesbase)
- [4. `pool-templates/y` — the lending template](#4-pool-templatesy)
- [5. `pool-templates/a` — the Aave template](#5-pool-templatesa)
- [6. `pool-templates/eth` — the native-ETH template](#6-pool-templateseth)
- [7. `pool-templates/meta` — the metapool template](#7-pool-templatesmeta)
- [8. Pool families, as diffs from their template](#8-pool-families)
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

(`pool-templates/base/SwapTemplateBase.vy:81-83`)

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

`pool-templates/base/SwapTemplateBase.vy:206-243`, `@pure @internal`.

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

`pool-templates/base/SwapTemplateBase.vy:379-430`, `@view @internal`.

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

`pool-templates/base/SwapTemplateBase.vy:614-656`, `@pure @internal`.

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

`pool-templates/base/SwapTemplateBase.vy:154-171`, `@view @internal`.

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

`pool-templates/base/SwapTemplateBase.vy:252-263`, `@view @external`.

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

`pool-templates/base/SwapTemplateBase.vy:661-687`, `@view @internal`.
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
