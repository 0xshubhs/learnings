# Curve DAO — Complete Contract Reference

Exhaustive, function-by-function reference for **every** Vyper file in
`curve-dao-contracts/contracts/` — 68 files, 19,366 lines.

This is the *reference*. The conceptual walkthrough lives in
[`CURVE-DEEP-DIVE.md`](CURVE-DEEP-DIVE.md) (§3 covers the DAO). Read that to
understand the system; read this to have seen all of it. Every `file:line`
below was verified with `grep -n` against the tree in this folder. Paths are
relative to `curve/curve-dao-contracts/`.

---

## Table of contents

| § | Contract / group | File | Ver | Lines |
|---|---|---|---|---|
| [1](#1-erc20crvvy--the-crv-token) | **ERC20CRV** — the CRV token | `contracts/ERC20CRV.vy` | 0.2.4 | 374 |
| [2](#2-votingescrowvy--vecrv) | **VotingEscrow** — veCRV | `contracts/VotingEscrow.vy` | 0.2.4 | 671 |
| [3](#3-gaugecontrollervy) | **GaugeController** | `contracts/GaugeController.vy` | 0.2.4 | 596 |
| [4](#4-the-gauge-family) | **Gauges** ×7 | `contracts/gauges/*.vy` | 0.2.4–0.3.1 | 4,372 |
| [5](#5-mintervy) | **Minter** | `contracts/Minter.vy` | 0.2.4 | 99 |
| [6](#6-feedistributorvy) | **FeeDistributor** | `contracts/FeeDistributor.vy` | 0.2.7 | 466 |
| [7](#7-the-proxy-admin-layer) | **Proxies** ×4 | `PoolProxy`, `CryptoPoolProxy`, `PoolProxySidechain`, `GaugeProxy` | 0.2.7–0.2.8 | 1,534 |
| [8](#8-vesting) | **Vesting** ×3 | `contracts/vests/*.vy` | 0.2.4 | 623 |
| [9](#9-streamers) | **Streamers** ×3 | `contracts/streamers/*.vy` | 0.2.12–0.2.16 | 482 |
| [10](#10-sidechain-root-gauges--wrappers) | **Sidechain gauges & wrappers** ×9 | `gauges/sidechain/`, `gauges/wrappers/` | 0.2.8–0.2.16 | 2,062 |
| [11](#11-the-burner-family) | **Burners** ×30 | `contracts/burners/**` | 0.2.7–0.3.7 | 6,441 |
| [12](#12-bridging) | **Bridging** ×3 | `contracts/bridging/*.vy` | 0.3.0 | 236 |
| [13](#13-crvinfovy) | **CRVInfo** | `contracts/CRVInfo.vy` | 0.3.7 | 100 |
| [14](#14-testing-helpers) | **Testing helpers** ×3 | `contracts/testing/*.vy` | — | 981 |
| [15](#15-the-flywheel-end-to-end) | The flywheel, end to end | — | — | — |
| [16](#16-use-case-index) | Use-case index | — | — | — |
| [17](#17-events-reference) | Events reference | — | — | — |
| [18](#18-revert-string-decoder) | Revert-string decoder | — | — | — |
| [19](#19-storage-layout-tables) | Storage layout tables | — | — | — |
| [20](#20-selector-tables) | Selector tables | — | — | — |

**Conventions used throughout.** `WEEK = 604800`. All "fixed point" values are
`1e18`-scaled unless stated. `@nonreentrant('lock')` is Vyper's storage-flag
mutex — see [§18](#18-revert-string-decoder) for the July-2023 compiler caveat.
Curve's ownership pattern is two-step everywhere: `commit_*` stores a
`future_*`, then `apply_*`/`accept_*` promotes it. Which of the two names is
used is inconsistent across contracts and is called out per contract.

---

## 1. `ERC20CRV.vy` — the CRV token

`contracts/ERC20CRV.vy`, Vyper 0.2.4, 374 lines, `implements: ERC20`.

A plain ERC-20 with one twist: **supply is not fixed and not arbitrary**. A
single `minter` address may mint, but only up to a hard ceiling that grows
along a published piecewise-linear schedule. The contract is the *rate limiter*
on emissions; the GaugeController decides who gets them.

### 1.1 Constants and the schedule (`:50-67`)

| Constant | Line | Value | Meaning |
|---|---|---|---|
| `YEAR` | `:50` | `86400*365` | 31,536,000 s |
| `INITIAL_SUPPLY` | `:62` | `1_303_030_303` | premined whole tokens (43%) |
| `INITIAL_RATE` | `:63` | `274_815_283e18 / YEAR` = `8714335457889396245` | wei per second, year 0 |
| `RATE_REDUCTION_TIME` | `:64` | `YEAR` | epoch length |
| `RATE_REDUCTION_COEFFICIENT` | `:65` | `1189207115002721024` | 2^(1/4)·1e18 |
| `RATE_DENOMINATOR` | `:66` | `1e18` | |
| `INFLATION_DELAY` | `:67` | `86400` | 1 day before mining may start |

Each epoch the rate is divided by 2^(1/4), so it **halves every four years**:

```
rate_n = INITIAL_RATE / 2^(n/4)
```

Computed from the real constants (integer division as on-chain):

| Epoch | rate (wei/s) | CRV emitted that year | Supply at epoch start | Annual inflation |
|---:|---:|---:|---:|---:|
| 0 | 8714335457889396245 | 274,815,283 | 1,303,030,303 | 21.09% |
| 1 | 7327853447857530670 | 231,091,186 | 1,577,845,586 | 14.65% |
| 2 | 6161965695807970181 | 194,323,750 | 1,808,936,772 | 10.74% |
| 3 | 5181574864521283150 | 163,406,145 | 2,003,260,523 | 8.16% |
| 4 | 4357167728944698747 | 137,407,642 | 2,166,666,667 | 6.34% |
| 5 | 3663926723928765860 | 115,545,593 | 2,304,074,309 | 5.01% |
| 6 | 3080982847903985532 | 97,161,875 | 2,419,619,902 | 4.02% |
| 7 | 2590787432260641946 | 81,703,072 | 2,516,781,777 | 3.25% |
| 8 | 2178583864472349685 | 68,703,821 | 2,598,484,850 | 2.64% |
| 9 | 1831963361964383192 | 57,772,797 | 2,667,188,670 | 2.17% |
| 10 | 1540491423951992986 | 48,580,938 | 2,724,961,467 | 1.78% |

Summing the geometric series to exhaustion gives 1,727,272,728 CRV ever
emitted, for an **asymptotic total supply of 3,030,303,030 CRV** and a premine
share of exactly 0.43 — which is what the comment on `:63` claims.

Storage: `name/symbol/decimals` (`:38-40`), `balanceOf` (`:42`), `allowances`
(`:43`, private), `total_supply` (`:44`, private — exposed via the explicit
`totalSupply()` at `:252`), `minter` (`:46`), `admin` (`:47`), `mining_epoch`
(`:70`), `start_epoch_time` (`:71`), `rate` (`:72`), `start_epoch_supply`
(`:74`, private).

### 1.2 `__init__(_name, _symbol, _decimals)` — `:78`

Mints `INITIAL_SUPPLY * 10**decimals` to the deployer (`:89-90`), sets
`admin = msg.sender` (`:91`), logs `Transfer(0x0, deployer, init_supply)`
(`:92`).

The clever bit is `:94`:

```python
self.start_epoch_time = block.timestamp + INFLATION_DELAY - RATE_REDUCTION_TIME
self.mining_epoch = -1
self.rate = 0
```

`start_epoch_time` is set one *year minus one day* in the past, `mining_epoch`
to −1 and `rate` to 0. So the first call to `_update_mining_parameters` becomes
legal exactly `INFLATION_DELAY` (1 day) after deployment, and it moves the
system into epoch 0 at the initial rate. Until then `rate == 0`, so
`_available_supply()` equals the premine and `mint` can only fail.

### 1.3 `_update_mining_parameters()` `@internal` — `:101`

Advances one epoch. Order matters:

1. Caches `_rate` and `_start_epoch_supply` (`:106-107`).
2. `start_epoch_time += RATE_REDUCTION_TIME`; `mining_epoch += 1` (`:109-110`).
3. If `_rate == 0` (first ever call) → `_rate = INITIAL_RATE` (`:112-113`),
   and `start_epoch_supply` is left at the premine.
4. Otherwise credit the whole finished epoch's emission to
   `start_epoch_supply` (`:115-116`) *then* reduce the rate (`:117`):
   `_rate = _rate * 1e18 / RATE_REDUCTION_COEFFICIENT`.
5. Writes `self.rate` (`:119`), logs `UpdateMiningParameters` (`:121`).

**Gotcha:** the double integer division in step 4 (multiply by `RATE_DENOMINATOR`,
divide by the coefficient) rounds the rate *down* every epoch. The comment at
`mintable_in_timeframe:219` calls this out explicitly — "double-division with
rounding made rate a bit less => good". Rounding against the emitters is the
safe direction.

**Gotcha 2:** `update_mining_parameters` is permissionless and the docstring at
`:129` warns "Total supply becomes slightly larger if this function is called
late". Because `start_epoch_time` advances by exactly one `RATE_REDUCTION_TIME`
per call rather than jumping to now, a late call leaves the old (higher) rate
applying for the extra elapsed time.

### 1.4 The epoch accessors

| Function | Line | Access | Behaviour |
|---|---|---|---|
| `update_mining_parameters()` | `:125` | any | `assert block.timestamp >= start_epoch_time + RATE_REDUCTION_TIME  # dev: too soon!` (`:131`), then `_update_mining_parameters()` |
| `start_epoch_time_write() -> uint256` | `:136` | any | Rolls the epoch if due (`:143-145`), returns current `start_epoch_time` |
| `future_epoch_time_write() -> uint256` | `:151` | any | Same, but returns `start_epoch_time + RATE_REDUCTION_TIME` |

`future_epoch_time_write` is the one every gauge calls in its constructor and
in `_checkpoint` (e.g. `LiquidityGaugeV5.vy:170`, `:291`) — the gauge needs to
know *when the rate will next change* so it can split its integral at that
boundary.

### 1.5 Supply views

**`_available_supply() -> uint256` `@internal @view` — `:167`**

```python
return self.start_epoch_supply + (block.timestamp - self.start_epoch_time) * self.rate
```

The ceiling: everything credited in completed epochs plus linear accrual so far
this epoch. `available_supply()` (`:173`) is the external wrapper.

**`mintable_in_timeframe(start, end) -> uint256` `@external @view` — `:182`**

How much CRV *may* be minted in `[start, end]`. Walks epochs **backwards**.

- `assert start <= end  # dev: start > end` (`:189`).
- If `end` is past the current epoch's end, step one epoch forward in memory
  first (`:195-197`) — this lets you query one epoch into the future without
  having called `update_mining_parameters`.
- `assert end <= current_epoch_time + RATE_REDUCTION_TIME  # dev: too far in future` (`:199`) — you may look at most one un-started epoch ahead.
- Loop `range(999)` (`:201`) clamping `[current_start, current_end]` to the
  epoch window and accumulating `current_rate * (current_end - current_start)`
  (`:213`), then stepping the epoch *back* and multiplying the rate back up
  (`:218-219`).
- `assert current_rate <= INITIAL_RATE  # This should never happen` (`:220`) is
  a paranoia rail against the multiply-back overshooting past epoch 0.

The comment on `:201` — *"Curve will not work in 1000 years. Darn!"* — is the
loop bound.

### 1.6 Admin

| Function | Line | Guard | Notes |
|---|---|---|---|
| `set_minter(_minter)` | `:226` | `msg.sender == admin` (`:232`), `minter == ZERO_ADDRESS` (`:233`) | **One-shot.** Once the Minter is wired it can never be changed. This is the single most important immutability guarantee in the DAO. |
| `set_admin(_admin)` | `:239` | `msg.sender == admin` (`:245`) | One-step, no `future_admin`. After setup the admin can *only* rename the token. |
| `set_name(_name, _symbol)` | `:365` | `msg.sender == admin`, `"Only admin is allowed to change name"` (`:372`) | Cosmetic only |

### 1.7 ERC-20 surface

`totalSupply()` `:252`, `allowance()` `:261`, `transfer()` `:272`,
`transferFrom()` `:289`, `approve()` `:308`, `mint()` `:325`, `burn()` `:350`.

**`approve(_spender, _value)` `:308`** carries the 2020-era race-condition
guard at `:318`:

```python
assert _value == 0 or self.allowances[msg.sender][_spender] == 0
```

You must zero an allowance before setting a new non-zero one. Many integrations
trip over this.

**`mint(_to, _value) -> bool` `:325`** — the only inflation path.

1. `assert msg.sender == self.minter  # dev: minter only` (`:333`)
2. `assert _to != ZERO_ADDRESS  # dev: zero address` (`:334`)
3. Rolls the epoch if due (`:336-337`) — so minting never needs a separate
   keeper call
4. `assert _total_supply <= self._available_supply()  # dev: exceeds allowable mint amount` (`:340`) — **the ceiling check**
5. Writes `total_supply` and `balanceOf[_to]`, logs `Transfer(0x0, _to, _value)`

**`burn(_value) -> bool` `:350`** — permissionless self-burn; reduces
`total_supply` (`:358`). Note burning does **not** raise the mint ceiling,
because `_available_supply()` is computed from `start_epoch_supply` and elapsed
time, not from `total_supply`. Burned CRV is gone.

---

## 2. `VotingEscrow.vy` — veCRV

`contracts/VotingEscrow.vy`, Vyper 0.2.4, 671 lines.

Lock CRV for up to 4 years; receive a **non-transferable, linearly decaying**
balance called veCRV. This is the original vote-escrow contract that the entire
"ve" design space was copied from.

### 2.1 The model

A lock is `(amount, end)`. Voting power at time `t`:

```
veCRV(t) = amount * (end - t) / MAXTIME        for t < end,  else 0
```

That is a straight line hitting zero at `end`. The contract stores it as a
**bias/slope pair** rather than recomputing:

```
slope = amount / MAXTIME          (constant, the decay rate)
bias  = slope * (end - now)       (the value right now)
```

so `veCRV(t) = bias - slope*(t - now)`. Locking 1000 CRV for 4 years gives 1000
veCRV; for 2 years, 500; for 1 year, 250.

Summing a straight line over all users is itself a straight line — **until a
lock expires**, at which point the total's slope must drop by that user's
slope. That is the entire difficulty of this contract, and it is solved by
`slope_changes`.

### 2.2 Types, constants, storage

```python
struct Point:                     # :25
    bias: int128
    slope: int128                 # - dweight / dt
    ts: uint256
    blk: uint256                  # block

struct LockedBalance:             # :34
    amount: int128
    end: uint256
```

| Constant | Line | Value |
|---|---|---|
| `WEEK` | `:84` | `7*86400` — all future times rounded down to weeks |
| `MAXTIME` | `:85` | `4*365*86400` = 126,144,000 s |
| `MULTIPLIER` | `:86` | `1e18` |
| `DEPOSIT_FOR_TYPE / CREATE_LOCK_TYPE / INCREASE_LOCK_AMOUNT / INCREASE_UNLOCK_TIME` | `:55-58` | `0 / 1 / 2 / 3` — the `type` field in the `Deposit` event |

| Storage | Line | Meaning |
|---|---|---|
| `token` | `:88` | CRV |
| `supply` | `:89` | total CRV locked (real tokens, not veCRV) |
| `locked[addr]` | `:91` | `LockedBalance` |
| `epoch` | `:93` | index of the newest global point |
| `point_history[epoch]` | `:94` | global `Point` history |
| `user_point_history[addr][uepoch]` | `:95` | per-user `Point` history |
| `user_point_epoch[addr]` | `:96` | per-user epoch counter |
| `slope_changes[ts]` | `:97` | signed slope delta scheduled at week boundary `ts` |
| `controller`, `transfersEnabled` | `:100-101` | Aragon compatibility shims |
| `name/symbol/version/decimals` | `:103-106` | |
| `smart_wallet_checker`, `future_smart_wallet_checker` | `:110-111` | contract whitelist |
| `admin`, `future_admin` | `:113-114` | |

The array dimensions on `:94-95` (`Point[1e29]`, `Point[1e9]`) are Vyper's way
of declaring a practically-unbounded mapping; no storage is pre-allocated.

### 2.3 `__init__(token_addr, _name, _symbol, _version)` — `:118`

Sets `admin`/`controller` to the deployer, seeds `point_history[0]` with the
current block and timestamp (`:128-129`), reads `decimals` from CRV and
`assert _decimals <= 255` (`:134`).

### 2.4 Why non-transferable, and `assert_not_contract`

There is **no** `transfer`, `transferFrom` or `approve` in this contract. veCRV
cannot move. If it could, the lock would be tokenizable and the whole
commitment mechanism would collapse into a liquid governance token.

To stop wrappers rebuilding transferability, `assert_not_contract(addr)`
`@internal` (`:185`) rejects any caller that is not `tx.origin` unless a
`SmartWalletChecker` approves it:

```python
if addr != tx.origin:
    checker: address = self.smart_wallet_checker
    if checker != ZERO_ADDRESS:
        if SmartWalletChecker(checker).check(addr):
            return
    raise "Smart contract depositors not allowed"
```

Called from `create_lock` (`:418`), `increase_amount` (`:438`) and
`increase_unlock_time` (`:455`) — but **deliberately not** from `deposit_for`
(`:393`), because topping up someone else's existing lock cannot create a new
tokenized position.

The whitelist is itself two-step: `commit_smart_wallet_checker(addr)` (`:166`)
and `apply_smart_wallet_checker()` (`:176`), both `assert msg.sender == self.admin`.

Ownership: `commit_transfer_ownership(addr)` (`:143`) / `apply_transfer_ownership()`
(`:154`). Note `apply_` is guarded by `msg.sender == self.admin` (`:158`), not
by the *future* admin — the current admin promotes, the future admin does not
accept. `changeController(_newController)` (`:666`) is a dead Aragon shim.

### 2.5 `_checkpoint(addr, old_locked, new_locked)` `@internal` — `:234`

The heart of the contract. Called by `_deposit_for` (`:374`), `withdraw`
(`:488`) and the public `checkpoint()` (`:388`, with `addr = ZERO_ADDRESS`).

**Phase 1 — user slopes (`:247-265`), skipped when `addr == 0x0`.**

```python
if old_locked.end > block.timestamp and old_locked.amount > 0:
    u_old.slope = old_locked.amount / MAXTIME
    u_old.bias  = u_old.slope * convert(old_locked.end - block.timestamp, int128)
if new_locked.end > block.timestamp and new_locked.amount > 0:
    u_new.slope = new_locked.amount / MAXTIME
    u_new.bias  = u_new.slope * convert(new_locked.end - block.timestamp, int128)
```

Expired or empty locks give a zero `Point`. Then it reads the currently
scheduled slope changes at both ends (`:260-265`), reusing `old_dslope` when
the two ends coincide.

**Phase 2 — replay history week by week (`:267-308`).**

`block_slope` (`:277`) is `1e18 * Δblock / Δtime` since the last point: an
estimate of blocks-per-second used to stamp an approximate block number onto
each synthesised historical point, because `balanceOfAt`/`totalSupplyAt` are
queried by block but the maths is in time.

```python
t_i: uint256 = (last_checkpoint / WEEK) * WEEK
for i in range(255):
    t_i += WEEK
    d_slope: int128 = 0
    if t_i > block.timestamp:
        t_i = block.timestamp
    else:
        d_slope = self.slope_changes[t_i]
    last_point.bias -= last_point.slope * convert(t_i - last_checkpoint, int128)
    last_point.slope += d_slope
    if last_point.bias < 0: last_point.bias = 0
    if last_point.slope < 0: last_point.slope = 0
    ...
    _epoch += 1
    if t_i == block.timestamp:
        last_point.blk = block.number
        break
    else:
        self.point_history[_epoch] = last_point
```

One iteration per week since the last checkpoint: decay the bias across the
week, then apply that week's scheduled slope change. 255 iterations ≈ **4.9
years**; the comment at `:284` accepts that if nobody touches the contract for
five years the vote weight breaks (withdrawals still work). The clamps at
`:294-297` are defensive; `bias < 0` genuinely happens from integer truncation.

Note the loop writes each intermediate week to `point_history` but the final
point is written once after the loop at `:322` — that is why `_epoch` is
incremented inside and assigned to `self.epoch` at `:308`.

**Phase 3 — apply the user's delta (`:311-319`).**

```python
last_point.slope += (u_new.slope - u_old.slope)
last_point.bias  += (u_new.bias  - u_old.bias)
```

**Phase 4 — reschedule slope changes (`:324-347`).**

```python
if old_locked.end > block.timestamp:
    old_dslope += u_old.slope                 # cancel the old drop
    if new_locked.end == old_locked.end:
        old_dslope -= u_new.slope             # re-add at the same date
    self.slope_changes[old_locked.end] = old_dslope

if new_locked.end > block.timestamp:
    if new_locked.end > old_locked.end:
        new_dslope -= u_new.slope             # schedule the new drop
        self.slope_changes[new_locked.end] = new_dslope
```

Slope changes are stored **negative** (the total slope falls when a lock
expires). Cancelling an old schedule therefore *adds* the slope back. The
`new_locked.end == old_locked.end` branch handles a pure `increase_amount`,
where the date does not move and both operations collapse into one write.

Finally the user's own point is appended (`:342-347`) with
`user_point_epoch[addr] += 1`.

### 2.6 `_deposit_for(_addr, _value, unlock_time, locked_balance, type)` `@internal` — `:351`

1. `self.supply = supply_before + _value` (`:362`).
2. Mutate the lock in memory: `_locked.amount += _value`, and `_locked.end =
   unlock_time` **only if `unlock_time != 0`** (`:365-367`), which is how the
   four entry points share one routine.
3. Write `self.locked[_addr]` (`:368`).
4. `self._checkpoint(_addr, old_locked, _locked)` (`:374`).
5. `assert ERC20(self.token).transferFrom(_addr, self, _value)` **after** the
   checkpoint (`:376-377`).
6. `log Deposit(...)`, `log Supply(...)` (`:379-380`).

Note the transfer pulls from `_addr`, not `msg.sender`. For `deposit_for` this
means **the beneficiary must have approved this contract**, not the caller.

### 2.7 The four entry points

All are `@external @nonreentrant('lock')`.

| Function | Line | Asserts | `type` |
|---|---|---|---|
| `deposit_for(_addr, _value)` | `:393` | `_value > 0  # dev: need non-zero value` (`:403`); `_locked.amount > 0, "No existing lock found"` (`:404`); `_locked.end > block.timestamp, "Cannot add to expired lock. Withdraw"` (`:405`) | `0` |
| `create_lock(_value, _unlock_time)` | `:412` | `assert_not_contract`; `_value > 0` (`:422`); `_locked.amount == 0, "Withdraw old tokens first"` (`:423`); `unlock_time > block.timestamp, "Can only lock until time in the future"` (`:424`); `unlock_time <= block.timestamp + MAXTIME, "Voting lock can be 4 years max"` (`:425`) | `1` |
| `increase_amount(_value)` | `:432` | `assert_not_contract`; `_value > 0` (`:441`); `"No existing lock found"` (`:442`); `"Cannot add to expired lock. Withdraw"` (`:443`) | `2` |
| `increase_unlock_time(_unlock_time)` | `:450` | `assert_not_contract`; `_locked.end > block.timestamp, "Lock expired"` (`:459`); `_locked.amount > 0, "Nothing is locked"` (`:460`); `unlock_time > _locked.end, "Can only increase lock duration"` (`:461`); `unlock_time <= block.timestamp + MAXTIME, "Voting lock can be 4 years max"` (`:462`) | `3` |

`create_lock` and `increase_unlock_time` both round the target **down** to a
week boundary: `unlock_time = (_unlock_time / WEEK) * WEEK` (`:419`, `:457`).
This is what makes `slope_changes` a sparse weekly map rather than a
per-second one. Consequence: asking for exactly 4 years usually yields slightly
under 4 years of power, because the rounding moves `end` backwards by up to a
week while `MAXTIME` in the denominator is unchanged.

**`withdraw()` `:469`** — `assert block.timestamp >= _locked.end, "The lock
didn't expire"` (`:475`), zeroes the lock, decrements `supply`, checkpoints
(`:488`), then transfers (`:490`). There is no early exit and no penalty: the
only way out is to wait.

**`checkpoint()` `:384`** — permissionless global-history advance with
`ZERO_ADDRESS`. `FeeDistributor._checkpoint_total_supply` calls it (`:197`).

### 2.8 Balance and supply queries

| Function | Line | Kind |
|---|---|---|
| `get_last_user_slope(addr) -> int128` | `:200` | view; used by `GaugeController.vote_for_gauge_weights` (`:492`) |
| `user_point_history__ts(_addr, _idx) -> uint256` | `:212` | view; used by every gauge's `kick` |
| `locked__end(_addr) -> uint256` | `:224` | view; used by `GaugeController` (`:493`) |
| `balanceOf(addr, _t = block.timestamp)` | `:525` | view |
| `balanceOfAt(addr, _block)` | `:546` | view |
| `totalSupply(t = block.timestamp)` | `:626` | view |
| `totalSupplyAt(_block)` | `:639` | view |
| `find_block_epoch(_block, max_epoch)` `@internal` | `:502` | binary search |
| `supply_at(point, t)` `@internal` | `:597` | week-walk |

**`balanceOf` `:525`** takes the user's latest point and decays it linearly:

```python
last_point.bias -= last_point.slope * convert(_t - last_point.ts, int128)
if last_point.bias < 0: last_point.bias = 0
```

Because a *user's* line has no slope changes of its own, no loop is needed.

**`balanceOfAt(addr, _block)` `:546`** is the MiniMe interface and does real
work. `assert _block <= block.number` (`:556`). Then:

1. Binary-search the user's point history by **block** (`:559-568`, inlined
   rather than calling `find_block_epoch` because "Vyper cannot pass by
   reference yet", `:554`).
2. Binary-search the *global* history for the same block via `find_block_epoch`
   (`:573`).
3. **Interpolate a timestamp for `_block`** (`:575-586`):

```python
if _epoch < max_epoch:
    point_1 = self.point_history[_epoch + 1]
    d_block = point_1.blk - point_0.blk
    d_t     = point_1.ts  - point_0.ts
else:
    d_block = block.number    - point_0.blk
    d_t     = block.timestamp - point_0.ts
block_time = point_0.ts
if d_block != 0:
    block_time += d_t * (_block - point_0.blk) / d_block
```

Linear interpolation between the two bracketing global points converts a block
number into an approximate timestamp; the user's bias is then decayed to that
time (`:588`). This is why every `Point` carries **both** `ts` and `blk`.

**`supply_at(point, t)` `@internal @view` `:597`** replays the weekly loop of
`_checkpoint` read-only — same `range(255)`, same `slope_changes` application
(`:606-617`) — and clamps negatives (`:619-620`).

**`totalSupply(t)` `:626`** = `supply_at(point_history[epoch], t)`.

**`totalSupplyAt(_block)` `:639`** finds the bracketing epoch, computes a `dt`
offset by block interpolation (`:651-657`), then calls `supply_at(point,
point.ts + dt)`.

### 2.9 Worked example

Alice locks 1000 CRV for 2 years; Bob locks 400 CRV for 1 year, same block,
`t = 0`.

```
MAXTIME = 126,144,000 s
Alice: end = 62,899,200 (day 728, week-rounded)  slope = 7,927,447,995,941   bias = 498.63 veCRV
Bob:   end = 31,449,600 (day 364, week-rounded)  slope = 3,170,979,198,376   bias =  99.73 veCRV

slope_changes[62,899,200] = −7,927,447,995,941
slope_changes[31,449,600] = −3,170,979,198,376
```

The idealised values are 500 and 100; the shortfall is the week-rounding of
`end`.

| Day | Alice | Bob | Total |
|---:|---:|---:|---:|
| 0 | 498.63 | 99.73 | 598.36 |
| 180 | 375.34 | 50.41 | 425.75 |
| 364 | 249.32 | 0.00 | 249.32 |
| 365 | 248.63 | 0.00 | 248.63 |
| 500 | 156.16 | 0.00 | 156.16 |
| 729 | 0.00 | 0.00 | 0.00 |

At day 364 the global point's slope drops by Bob's slope. The *total* line is
piecewise linear with a kink at each expiry — exactly what `slope_changes`
encodes, and why `supply_at` must walk weeks instead of using one subtraction.

---

## 3. `GaugeController.vy`

`contracts/GaugeController.vy`, Vyper 0.2.4, 596 lines.

Decides **what fraction of the weekly CRV emission each gauge receives**, by
veCRV vote. It never touches tokens.

### 3.1 The model

Every quantity here is a bias/slope pair in *week buckets*, mirroring
`VotingEscrow` — because a vote is backed by veCRV, and veCRV decays. A user
voting 40% of their power onto a gauge contributes a line that decays at
`0.40 × (their ve slope)` and hits zero when their lock ends.

Three levels of aggregation, each with its own history and its own catch-up
routine:

```
points_weight[gauge][t]  ── per-gauge bias/slope       ← _get_weight
points_sum[type][t]      ── sum over gauges of a type  ← _get_sum
points_total[t]          ── Σ_type (sum_type × type_weight)  ← _get_total
points_type_weight[type][t] ── DAO-set multiplier per type ← _get_type_weight
```

and the payout share is

```
relative_weight(gauge, t) = 1e18 × type_weight[type][t] × weight[gauge][t] / total[t]
```

### 3.2 Constants, types, storage

| Constant | Line | Value |
|---|---|---|
| `WEEK` | `:11` | `604800` |
| `WEIGHT_VOTE_DELAY` | `:14` | `10 * 86400` — 10 days between votes **per gauge** |
| `MULTIPLIER` | `:66` | `1e18` |

```python
struct Point:          # :17
    bias: uint256
    slope: uint256

struct VotedSlope:     # :21
    slope: uint256
    power: uint256     # bps, 0..10000
    end: uint256
```

Note these are **unsigned** here, unlike `VotingEscrow`'s `int128` — the
controller only ever handles non-negative aggregates.

| Storage | Line | Meaning |
|---|---|---|
| `admin`, `future_admin` | `:68-69` | |
| `token`, `voting_escrow` | `:71-72` | CRV, veCRV |
| `n_gauge_types`, `n_gauges` | `:76-77` | counters |
| `gauge_type_names[int128]` | `:78` | |
| `gauges[1e9]` | `:81` | enumeration array |
| `gauge_types_[addr]` | `:85` | **stored +1** so 0 means "not registered" |
| `vote_user_slopes[user][gauge]` | `:87` | `VotedSlope` |
| `vote_user_power[user]` | `:88` | total bps used, ≤ 10000 |
| `last_user_vote[user][gauge]` | `:89` | cooldown timestamp |
| `points_weight[gauge][t]`, `changes_weight[gauge][t]`, `time_weight[gauge]` | `:97-99` | per-gauge |
| `points_sum[type][t]`, `changes_sum[type][t]`, `time_sum[1e9]` | `:101-103` | per-type |
| `points_total[t]`, `time_total` | `:105-106` | global |
| `points_type_weight[type][t]`, `time_type_weight[1e9]` | `:108-109` | type multipliers |

The `+1` offset on `gauge_types_` (`:83-85`) is why `gauge_types(_addr)`
(`:153`) asserts `gauge_type != 0` (`:160`) and returns `gauge_type - 1`
(`:162`). `Minter._mint_for` relies on this reverting for unregistered gauges
(`Minter.vy:44`).

`__init__(_token, _voting_escrow)` `:113` asserts both non-zero (`:119-120`)
and sets `time_total = block.timestamp / WEEK * WEEK` (`:125`).

Ownership: `commit_transfer_ownership` `:129` / `apply_transfer_ownership`
`:140`, both `assert msg.sender == self.admin  # dev: admin only`.

### 3.3 The four catch-up routines

All four have the same shape: walk forward in `WEEK` steps from the last
recorded time, filling in history, stopping once past `block.timestamp`. All
are `@internal` and **state-changing** — they memoise.

**`_get_type_weight(gauge_type) -> uint256` `:166`.** Type weights do not
decay; the loop just copies the last value forward (`:176-182`). Returns 0 if
never initialised (`:185`).

**`_get_sum(gauge_type) -> uint256` `:189`.** Decays a bias/slope pair week by
week (`:199-213`):

```python
d_bias: uint256 = pt.slope * WEEK
if pt.bias > d_bias:
    pt.bias -= d_bias
    d_slope: uint256 = self.changes_sum[gauge_type][t]
    pt.slope -= d_slope
else:
    pt.bias = 0
    pt.slope = 0
```

The `else` branch is the unsigned-arithmetic guard: rather than underflow, a
line that would go negative is pinned to zero **and its slope is zeroed too**.

**`_get_weight(gauge_addr) -> uint256` `:259`.** Identical to `_get_sum` but
keyed by gauge address (`:269-283`).

**`_get_total() -> uint256` `:220`.** The composite.

```python
t: uint256 = self.time_total
if t > block.timestamp:
    t -= WEEK                      # :228-230
for gauge_type in range(100):      # :233-237  refresh every type first
    if gauge_type == _n_gauge_types: break
    self._get_sum(gauge_type)
    self._get_type_weight(gauge_type)
for i in range(500):               # :239-254
    if t > block.timestamp: break
    t += WEEK
    pt = 0
    for gauge_type in range(100):
        if gauge_type == _n_gauge_types: break
        pt += self.points_sum[gauge_type][t].bias * self.points_type_weight[gauge_type][t]
    self.points_total[t] = pt
    if t > block.timestamp:
        self.time_total = t
```

The rewind at `:228-230` matters: `time_total` is normally *one week in the
future*, and the loop must recompute that future bucket because a new vote may
have changed it. Bounds are `range(100)` types and `range(500)` weeks — about
9.6 years of unchecked history.

### 3.4 Relative weight

**`_gauge_relative_weight(addr, time)` `@internal @view` `:347`** — pure read,
no catch-up:

```python
t: uint256 = time / WEEK * WEEK
_total_weight: uint256 = self.points_total[t]
if _total_weight > 0:
    gauge_type: int128 = self.gauge_types_[addr] - 1
    _type_weight: uint256 = self.points_type_weight[gauge_type][t]
    _gauge_weight: uint256 = self.points_weight[addr][t].bias
    return MULTIPLIER * _type_weight * _gauge_weight / _total_weight
else:
    return 0
```

Returns `1e18`-scaled. If the requested week was never checkpointed it reads
zero and returns 0 — hence the write variant.

**`gauge_relative_weight(addr, time = block.timestamp)` `@external @view`
`:371`** — the view wrapper. This is what gauges call inside their integral
loop (`LiquidityGaugeV5.vy:308`) — a view, so the *gauge* must have ensured the
history exists first, which it does by calling `checkpoint_gauge` at `:302`.

**`gauge_relative_weight_write(addr, time = block.timestamp)` `@external`
`:384`** — `_get_weight(addr)`, `_get_total()`, then the same read. Callable by
anyone; idempotent.

**`checkpoint()` `:328`** = `_get_total()`. **`checkpoint_gauge(addr)` `:336`**
= `_get_weight(addr)` then `_get_total()`.

### 3.5 Admin: types and gauges

**`add_type(_name, weight = 0)` `:422`** — `assert msg.sender == self.admin`
(`:428`). Assigns `type_id = n_gauge_types`, stores the name, increments. Only
calls `_change_type_weight` and logs `AddType` **if `weight != 0`** (`:432-434`)
— a type added with weight 0 emits no event, which is a genuine indexing trap.

**`_change_type_weight(type_id, weight)` `@internal` `:401`** — refreshes old
values, then

```python
_total_weight = _total_weight + old_sum * weight - old_sum * old_weight   # :412
self.points_total[next_time]              = _total_weight
self.points_type_weight[type_id][next_time] = weight
self.time_total                            = next_time
self.time_type_weight[type_id]             = next_time
```

with `next_time = (block.timestamp + WEEK) / WEEK * WEEK` (`:410`) — **changes
always land at the next week boundary**, never mid-week. Logs `NewTypeWeight`.
`change_type_weight(type_id, weight)` `:438` is the admin-guarded wrapper.

**`add_gauge(addr, gauge_type, weight = 0)` `:290`**

```python
assert msg.sender == self.admin                                  # :297
assert (gauge_type >= 0) and (gauge_type < self.n_gauge_types)   # :298
assert self.gauge_types_[addr] == 0  # dev: cannot add the same gauge twice   # :299
```

Appends to `gauges[n]`, sets `gauge_types_[addr] = gauge_type + 1` (`:305`). If
`weight > 0` it folds the weight into sum and total at `next_time`
(`:308-318`). Always sets `time_weight[addr] = next_time` (`:322`) and seeds
`time_sum[gauge_type]` if unset (`:320-321`). Logs `NewGauge`.

**`_change_gauge_weight(addr, weight)` `@internal` `:449`** / **`change_gauge_weight`
`:474`** — admin override of a gauge's weight; recomputes sum and total by
delta (`:462-467`). Logs `NewGaugeWeight`. There is no "remove gauge"; the DAO
sets weight to 0 and/or the gauge is killed at the gauge contract.

### 3.6 `vote_for_gauge_weights(_gauge_addr, _user_weight)` — `:485`

The only user-facing write. `_user_weight` is **bps**: 0..10000.

**Reads and checks (`:491-501`):**

```python
slope    = convert(VotingEscrow(escrow).get_last_user_slope(msg.sender), uint256)
lock_end = VotingEscrow(escrow).locked__end(msg.sender)
next_time = (block.timestamp + WEEK) / WEEK * WEEK
assert lock_end > next_time, "Your token lock expires too soon"
assert (_user_weight >= 0) and (_user_weight <= 10000), "You used all your voting power"
assert block.timestamp >= self.last_user_vote[msg.sender][_gauge_addr] + WEIGHT_VOTE_DELAY, "Cannot vote so often"
gauge_type = self.gauge_types_[_gauge_addr] - 1
assert gauge_type >= 0, "Gauge not added"
```

The cooldown is **per (user, gauge)** (`:498`, `:551`), not global — you can
vote on many gauges in one block, but not re-vote the same gauge for 10 days.

**Old and new slopes (`:503-514`):**

```python
old_slope = self.vote_user_slopes[msg.sender][_gauge_addr]
old_dt = 0
if old_slope.end > next_time:
    old_dt = old_slope.end - next_time
old_bias = old_slope.slope * old_dt
new_slope = VotedSlope({slope: slope * _user_weight / 10000, end: lock_end, power: _user_weight})
new_dt = lock_end - next_time     # dev: raises when expired
new_bias = new_slope.slope * new_dt
```

The user's vote line is their veCRV slope scaled by the bps fraction, measured
from `next_time` (not now) to their lock end.

**Power budget (`:517-520`):**

```python
power_used = self.vote_user_power[msg.sender]
power_used = power_used + new_slope.power - old_slope.power
self.vote_user_power[msg.sender] = power_used
assert (power_used >= 0) and (power_used <= 10000), 'Used too much power'
```

Voting 0 on a gauge is how you free the budget back up.

**Bookkeeping (`:525-544`):**

```python
self.points_weight[_gauge_addr][next_time].bias = max(old_weight_bias + new_bias, old_bias) - old_bias
self.points_sum[gauge_type][next_time].bias     = max(old_sum_bias + new_bias, old_bias) - old_bias
if old_slope.end > next_time:
    self.points_weight[_gauge_addr][next_time].slope = max(old_weight_slope + new_slope.slope, old_slope.slope) - old_slope.slope
    self.points_sum[gauge_type][next_time].slope     = max(old_sum_slope + new_slope.slope, old_slope.slope) - old_slope.slope
else:
    self.points_weight[_gauge_addr][next_time].slope += new_slope.slope
    self.points_sum[gauge_type][next_time].slope     += new_slope.slope
if old_slope.end > block.timestamp:
    self.changes_weight[_gauge_addr][old_slope.end] -= old_slope.slope
    self.changes_sum[gauge_type][old_slope.end]     -= old_slope.slope
self.changes_weight[_gauge_addr][new_slope.end] += new_slope.slope
self.changes_sum[gauge_type][new_slope.end]     += new_slope.slope
```

The `max(a + new, old) - old` idiom is unsigned-safe subtraction: it computes
`a + new − old` but floors at 0 instead of underflowing. Then `_get_total()`
(`:546`), store the new `VotedSlope` (`:548`), stamp the cooldown (`:551`), log
`VoteForGauge` (`:553`).

Note `changes_*` here are stored **positive** (added at `:543-544`, subtracted
in `_get_sum:206`/`_get_weight:276`), the opposite sign convention to
`VotingEscrow.slope_changes`.

### 3.7 Views

| Function | Line | Returns |
|---|---|---|
| `gauge_types(_addr) -> int128` | `:153` | type id, reverts if unregistered |
| `get_gauge_weight(addr)` | `:558` | `points_weight[addr][time_weight[addr]].bias` |
| `get_type_weight(type_id)` | `:569` | latest type weight |
| `get_total_weight()` | `:580` | `points_total[time_total]` |
| `get_weights_sum_per_type(type_id)` | `:590` | `points_sum[type_id][time_sum[type_id]].bias` |

### 3.8 From vote to CRV

Putting it together: in week `w`, a gauge with relative weight `r` (1e18-scaled)
receives

```
CRV_for_gauge = rate × WEEK × r / 1e18
```

where `rate` comes from `ERC20CRV.rate()`. Since `Σ_gauges r = 1e18` by
construction of `points_total`, the whole weekly emission is partitioned.
Inside the gauge that budget is then divided among stakers by *working balance*
— see §4.

---

## 4. The gauge family

Seven contracts in `contracts/gauges/`, 4,372 lines, spanning Vyper 0.2.4 →
0.3.1 and three years of iteration.

| File | Ver | Lines | CRV? | Extra rewards | Boost source | ERC-20? |
|---|---|---:|---|---|---|---|
| `LiquidityGauge.vy` | 0.2.4 | 356 | yes | — | `veCRV.balanceOf` | no |
| `LiquidityGaugeReward.vy` | 0.2.4 | 442 | yes | 1 token, Synthetix staking | `veCRV.balanceOf` | no |
| `LiquidityGaugeV2.vy` | 0.2.8 | 758 | yes | 8 tokens, sig-based pull | `veCRV.balanceOf` | yes |
| `LiquidityGaugeV3.vy` | 0.2.12 | 806 | yes | 8 tokens, sig-based + claim throttle | `veCRV.balanceOf` | yes |
| `LiquidityGaugeV4.vy` | 0.2.16 | 705 | yes | 8 tokens, **push** (`deposit_reward_token`) | **veBoost proxy** | yes |
| `LiquidityGaugeV5.vy` | 0.3.1 | 819 | yes | 8 tokens, push | veBoost proxy | yes + `permit` |
| `RewardsOnlyGauge.vy` | 0.2.12 | 486 | **no** | 8 tokens, sig-based | — | yes |

### 4.1 The CRV integral — the idea

A gauge must answer "how much CRV does each staker deserve?" without touching
every staker's storage as time passes. The standard accumulator trick:

```
integrate_inv_supply(T) = ∫₀ᵀ rate(t) · w(t) / working_supply(t)  dt      × 1e18
```

a single global number: CRV per unit of working balance, ever. Then per user:

```
integrate_fraction[u] += working_balance[u] × (integrate_inv_supply − integrate_inv_supply_of[u]) / 1e18
integrate_inv_supply_of[u] = integrate_inv_supply
```

`integrate_fraction[u]` is the user's **lifetime CRV entitlement**. The Minter
subtracts what it has already paid. This is the same shape as Uniswap V3's
`feeGrowthInside` and Aave's `RewardsDistributor` index.

The integral cannot be a single multiplication because two things change on
week boundaries — the gauge's `relative_weight` and (once a year) the inflation
`rate` — so `_checkpoint` integrates **week by week**.

### 4.2 The boost — `_update_liquidity_limit`

`LiquidityGauge.vy:125`, `V2:177`, `V3:181`, `V4:183`, `V5:191`.

```python
lim: uint256 = l * TOKENLESS_PRODUCTION / 100
if voting_total > 0:
    lim += L * voting_balance / voting_total * (100 - TOKENLESS_PRODUCTION) / 100
lim = min(l, lim)
old_bal: uint256 = self.working_balances[addr]
self.working_balances[addr] = lim
_working_supply: uint256 = self.working_supply + lim - old_bal
self.working_supply = _working_supply
```

With `TOKENLESS_PRODUCTION = 40` (`LiquidityGauge.vy:56`, `V5:92`):

```
working_balance = min( l ,  0.40·l + 0.60·L·(veUser/veTotal) )
```

- `l` = the user's LP balance, `L` = the gauge's `totalSupply`.
- With no veCRV you earn on 40% of your deposit.
- The cap `min(l, …)` means the **maximum boost is 1/0.4 = 2.5×**.
- Full boost needs `veUser/veTotal ≥ l/L` — your share of all veCRV must match
  your share of this gauge.

Worked, with `l = 1000`, `L = 100,000` (so `l/L = 1%`):

| `veUser/veTotal` | working_balance | boost |
|---:|---:|---:|
| 0 | 400.00 | 1.000× |
| 0.1% | 460.00 | 1.150× |
| **1%** | **1000.00** | **2.500×** |
| 5% | 1000.00 | 2.500× (capped) |

Because `working_supply` is the denominator of the integral, boosting yourself
dilutes everyone else — the emission is fixed by the GaugeController, the
gauge only decides its split.

**Version differences.** V1 and V2/V3 read `ERC20(voting_escrow).balanceOf(addr)`
and `.totalSupply()` directly (`LiquidityGauge.vy:136-137`). V1 additionally
gates the boost behind `BOOST_WARMUP = 2 weeks` (`:57`, `:140`):

```python
if (voting_total > 0) and (block.timestamp > self.period_timestamp[0] + BOOST_WARMUP):
```

so for the gauge's first fortnight everyone is unboosted. V4 and V5 replace the
direct read with `VotingEscrowBoost(VEBOOST_PROXY).adjusted_balance_of(addr)`
(`V4:194`, `V5:201`) — this is the delegable-boost proxy, letting a veCRV
holder lend boost to another address without moving the lock.

### 4.3 `_checkpoint(addr)` — the integral, line by line

`LiquidityGauge.vy:153`, `V2:258`, `V3:296`, `V4:271`, `V5:279`. Structure is
identical across versions; V5 shown (`:279-343`).

**Step 1 — detect a rate change (`:284-293`).**

```python
_period: int128 = self.period
_period_time: uint256 = self.period_timestamp[_period]
_integrate_inv_supply: uint256 = self.integrate_inv_supply[_period]
rate: uint256 = self.inflation_rate
new_rate: uint256 = rate
prev_future_epoch: uint256 = self.future_epoch_time
if prev_future_epoch >= _period_time:
    self.future_epoch_time = CRV20(CRV).future_epoch_time_write()
    new_rate = CRV20(CRV).rate()
    self.inflation_rate = new_rate
```

If the CRV epoch boundary falls at or after our last checkpoint, we may cross
it during this integration, so fetch both the *new* rate and the *next*
boundary. `future_epoch_time_write` is state-changing — this is where a gauge
checkpoint can roll the CRV epoch for the whole protocol.

**Step 2 — killed gauges (`:295-297`).**

```python
if self.is_killed:
    rate = 0
```

Note only the local `rate` is zeroed, not `new_rate`. A killed gauge stops
accruing but keeps its bookkeeping consistent.

**Step 3 — the weekly loop (`:300-332`).**

```python
if block.timestamp > _period_time:
    _working_supply: uint256 = self.working_supply
    Controller(GAUGE_CONTROLLER).checkpoint_gauge(self)
    prev_week_time: uint256 = _period_time
    week_time: uint256 = min((_period_time + WEEK) / WEEK * WEEK, block.timestamp)

    for i in range(500):
        dt: uint256 = week_time - prev_week_time
        w: uint256 = Controller(GAUGE_CONTROLLER).gauge_relative_weight(self, prev_week_time / WEEK * WEEK)

        if _working_supply > 0:
            if prev_future_epoch >= prev_week_time and prev_future_epoch < week_time:
                _integrate_inv_supply += rate * w * (prev_future_epoch - prev_week_time) / _working_supply
                rate = new_rate
                _integrate_inv_supply += rate * w * (week_time - prev_future_epoch) / _working_supply
            else:
                _integrate_inv_supply += rate * w * dt / _working_supply

        if week_time == block.timestamp:
            break
        prev_week_time = week_time
        week_time = min(week_time + WEEK, block.timestamp)
```

Points to notice:

- `checkpoint_gauge` is called **first** so the subsequent `gauge_relative_weight`
  *view* calls find populated history.
- The relative weight is sampled at the **week bucket start**
  (`prev_week_time / WEEK * WEEK`), so weight is piecewise-constant per week.
- The `prev_future_epoch` branch splits a week that straddles a CRV epoch
  boundary into two integrals at two rates.
- **The bug-shaped comment at `:315-316`:** *"If more than one epoch is crossed
  - the gauge gets less, but that'd mean it wasn't called for more than 1
  year."* Only one rate change is handled per checkpoint. A gauge untouched for
  over a year under-pays. The 500-iteration bound (≈9.6 years) is the other
  cliff.
- `_working_supply == 0` weeks are skipped entirely — emission allocated to an
  empty gauge is simply never minted.
- The precision note at `:322-327` argues worst-case loss is ~1e-9.

**Step 4 — commit (`:334-343`).**

```python
_period += 1
self.period = _period
self.period_timestamp[_period] = block.timestamp
self.integrate_inv_supply[_period] = _integrate_inv_supply

_working_balance: uint256 = self.working_balances[addr]
self.integrate_fraction[addr] += _working_balance * (_integrate_inv_supply - self.integrate_inv_supply_of[addr]) / 10 ** 18
self.integrate_inv_supply_of[addr] = _integrate_inv_supply
self.integrate_checkpoint_of[addr] = block.timestamp
```

Every checkpoint appends a new period, even if nothing changed.

**Critical ordering invariant.** `_checkpoint(addr)` uses the user's **current**
`working_balance`, so it must run *before* balances change, and
`_update_liquidity_limit` must run *after*. Every caller obeys this — e.g.
`V5.deposit` (`:459` then `:472`), `V5.withdraw` (`:488` then `:501`).

### 4.4 `LiquidityGauge.vy` (v1) — full function list

| Function | Line | Access | Notes |
|---|---|---|---|
| `__init__(lp_addr, _minter, _admin)` | `:100` | — | Reads `crv_token`/`controller` **from the Minter** (`:113-116`), `voting_escrow` from the Controller (`:117`); seeds `period_timestamp[0]`, `inflation_rate`, `future_epoch_time` (`:118-120`) |
| `_update_liquidity_limit(addr, l, L)` | `:125` | internal | With `BOOST_WARMUP` gate |
| `_checkpoint(addr)` | `:153` | internal | Calls `Controller.checkpoint_gauge` at `:170` (outside the `if`, unlike later versions) |
| `user_checkpoint(addr) -> bool` | `:223` | `msg.sender == addr or == minter  # dev: unauthorized` (`:229`) | checkpoint + limit |
| `claimable_tokens(addr) -> uint256` | `:236` | any, **not a view** | `_checkpoint` then `integrate_fraction[addr] - Minter.minted(addr, self)` (`:243`). Docstring `:239`: *"should be manually changed to view in the ABI"* |
| `kick(addr)` | `:247` | any | See below |
| `set_approve_deposit(addr, can_deposit)` | `:268` | any | v1/v2/v3 only |
| `deposit(_value, addr = msg.sender)` | `:279` | `@nonreentrant('lock')` | `assert self.approved_to_deposit[msg.sender][addr], "Not approved"` when depositing for another (`:286`) |
| `withdraw(_value)` | `:305` | `@nonreentrant('lock')` | |
| `integrate_checkpoint() -> uint256` | `:326` | view | `period_timestamp[period]` |
| `kill_me()` | `:331` | `msg.sender == self.admin` (`:332`) | **Toggles** `is_killed` |
| `commit_transfer_ownership(addr)` | `:337` | admin | |
| `apply_transfer_ownership()` | `:348` | admin (`:352`) | |

**`kick(addr)` `:247`** — the anti-freeloader. A user's boost is fixed at their
last checkpoint; if their lock expires, their `working_balance` stays
inflated until they interact. `kick` lets anyone force a re-limit:

```python
t_last: uint256 = self.integrate_checkpoint_of[addr]
t_ve: uint256 = VotingEscrow(_voting_escrow).user_point_history__ts(
    addr, VotingEscrow(_voting_escrow).user_point_epoch(addr))
_balance: uint256 = self.balanceOf[addr]

assert ERC20(self.voting_escrow).balanceOf(addr) == 0 or t_ve > t_last  # dev: kick not allowed
assert self.working_balances[addr] > _balance * TOKENLESS_PRODUCTION / 100  # dev: kick not needed
```

First assert: only if their veCRV is now zero, **or** they had a ve event after
their last gauge checkpoint. Second: only if they are actually still boosted.
Then checkpoint and re-limit (`:263-264`). Identical in every boosted version
(`V2:417`, `V3:478`, `V4:422`, `V5:430`).

### 4.5 `LiquidityGaugeReward.vy` — the Synthetix bolt-on

Vyper 0.2.4, 442 lines. v1 plus **one** extra reward token staked into a
Synthetix-style `StakingRewards` contract.

Constructor `:114` takes `_reward_contract` and `_rewarded_token`.

**`_checkpoint_rewards(addr, claim_rewards)` `@internal` `:173`** — the
balance-diff pattern that all later versions refine: snapshot
`rewarded_token.balanceOf(self)`, optionally call the reward contract's
`getReward()`, diff, fold into `reward_integral` per unit of `totalSupply`,
then credit the user via `reward_integral_for[addr]`.

**`_checkpoint(addr, claim_rewards)` `:195`** — v1's integral plus the reward
checkpoint.

| Function | Line |
|---|---|
| `user_checkpoint(addr)` | `:267` |
| `claimable_tokens(addr)` | `:280` |
| `claimable_reward(addr)` `@view` | `:292` |
| `kick(addr)` | `:311` |
| `set_approve_deposit(addr, can_deposit)` | `:332` |
| `deposit(_value, addr = msg.sender)` | `:343` |
| `withdraw(_value, claim_rewards = True)` | `:370` |
| `claim_rewards(addr = msg.sender)` | `:393` |
| `integrate_checkpoint()` | `:403` |
| `kill_me()` | `:408` |
| `commit_transfer_ownership(addr)` / `apply_transfer_ownership()` | `:414` / `:425` |
| `toggle_external_rewards_claim(val)` | `:436` |

`toggle_external_rewards_claim` is the escape hatch: if the external staking
contract breaks, the admin disables claiming so deposits/withdrawals keep
working.

### 4.6 `LiquidityGaugeV2.vy` — ERC-20 + 8 rewards by selector

Vyper 0.2.8, 758 lines. Two big changes: the gauge **is itself an ERC-20**
(deposit receipts become transferable), and external rewards generalise to 8
tokens with an arbitrary staking contract driven by raw selectors.

New storage (`:113-122`): `reward_contract`, `reward_tokens[8]`,
`reward_sigs: bytes32`, `reward_integral[token]`,
`reward_integral_for[token][user]`.

**`_checkpoint_rewards(_addr, _total_supply)` `@internal` `:205`.** Returns
immediately if `_total_supply == 0` (`:210-211`). Snapshots all 8 balances,
then:

```python
raw_call(self.reward_contract, slice(self.reward_sigs, 8, 4))  # dev: bad claim sig
```

Bytes 8..12 of `reward_sigs` are the **claim** selector; 0..4 deposit, 4..8
withdraw. After the call, `dI = 1e18 * (balanceAfter - balanceBefore) / _total_supply`
(`:227`) and rewards are transferred to the user immediately via `raw_call`
(`:245-256`) — V2 has no "accrue without transferring" mode.

**`set_rewards(_reward_contract, _sigs, _reward_tokens[8])` `:649`,
`@nonreentrant('lock')`, admin only (`:663`).** The most interesting function in
the file. To migrate away from an existing contract it checkpoints, withdraws
the entire `total_supply` using the stored withdraw selector, and revokes
approval (`:668-676`). To install a new one it does a **live test round-trip**
(`:678-708`):

```python
assert _reward_contract.is_contract  # dev: not a contract
...
assert total_supply != 0  # dev: zero total supply
ERC20(lp_token).approve(_reward_contract, MAX_UINT256)
raw_call(_reward_contract, concat(deposit_sig, convert(total_supply, bytes32)))  # dev: failed deposit
assert ERC20(lp_token).balanceOf(self) == 0
raw_call(_reward_contract, concat(withdraw_sig, convert(total_supply, bytes32)))  # dev: failed withdraw
assert ERC20(lp_token).balanceOf(self) == total_supply
raw_call(_reward_contract, concat(deposit_sig, convert(total_supply, bytes32)))
```

Deposit everything, assert the balance went to zero, withdraw everything,
assert it came back, then deposit for real. A wrong selector cannot be
installed. `assert convert(withdraw_sig, uint256) == 0  # dev: withdraw without
deposit` (`:710`) forbids a withdraw-only configuration. Finally
`assert i != 0  # dev: no reward token` (`:719`).

ERC-20 surface: `allowance` `:525`, `_transfer` `:536`, `transfer` `:560`,
`transferFrom` `:574`, `approve` `:592`, `increaseAllowance` `:612`,
`decreaseAllowance` `:630`. `_transfer` checkpoints **both** parties and
re-limits both (`:536-556`) — transferring a gauge position moves the boost
basis with it.

Others: `decimals()` `:161`, `integrate_checkpoint()` `:172`,
`user_checkpoint` `:328`, `claimable_tokens` `:341`,
`claimable_reward(_addr,_token)` `:353` (`@nonreentrant`, not a view — it
claims to compute), `claim_rewards(_addr)` `:378`,
`claim_historic_rewards(_reward_tokens[8], _addr)` `:388` (drains tokens no
longer in the active list), `kick` `:417`, `set_approve_deposit` `:438`,
`deposit(_value,_addr)` `:449`, `withdraw(_value)` `:489`,
`set_killed(_is_killed)` `:726` (now a **setter**, not a toggle),
`commit_transfer_ownership` `:738`, `accept_transfer_ownership` `:750` —
renamed from `apply_` and now guarded by the *future* admin.

### 4.7 `LiquidityGaugeV3.vy` — throttling and packed claim data

Vyper 0.2.12, 806 lines. V2 plus three refinements.

**1. Claim throttle.** `CLAIM_FREQUENCY: constant(uint256) = 3600` (`:74`). The
reward contract is only polled once an hour (`:224`):

```python
if _total_supply != 0 and reward_data != 0 and block.timestamp > shift(reward_data, -160) + CLAIM_FREQUENCY:
```

`reward_data: uint256` (`:112`) packs `[uint96 last_claim][uint160 contract]`,
rewritten at `:238`. Exposed as `reward_contract()` `:391` and `last_claim()`
`:401`.

**2. Packed per-user claim data.** `claim_data[user][token]: uint256` (`:128`)
holds `[uint128 claimable][uint128 claimed]`. This decouples *accruing* from
*transferring*: `_checkpoint_rewards(_user, _total_supply, _claim, _receiver)`
(`:209`) takes a `_claim` flag, and when false it accumulates into the high 128
bits (`:293-294`) instead of transferring. That is what makes
`deposit(..., _claim_rewards = False)` cheap. `claimed_reward` `:411`,
`claimable_reward` `:423` (a true `@view`), `claimable_reward_write` `:438`.

**3. Reward receivers.** `rewards_receiver[user]` (`:119`) with setter
`set_rewards_receiver(_receiver)` `:453`; resolution logic at `:249-255`.

Everything else mirrors V2: `_checkpoint` `:296`, `user_checkpoint` `:366`,
`claimable_tokens` `:379`, `claim_rewards(_addr, _receiver)` `:464`, `kick`
`:478`, `deposit(_value,_addr,_claim_rewards)` `:500`,
`withdraw(_value,_claim_rewards)` `:540`, `_transfer` `:577`, `transfer` `:601`,
`transferFrom` `:615`, `approve` `:633`, `increaseAllowance` `:653`,
`decreaseAllowance` `:671`, `set_rewards` `:690`, `set_killed` `:774`,
`commit_transfer_ownership` `:786`, `accept_transfer_ownership` `:798`.
`set_approve_deposit` is **gone** — anyone may deposit for anyone.

### 4.8 `LiquidityGaugeV4.vy` — push rewards, hardcoded addresses

Vyper 0.2.16, 705 lines. The model inverts: instead of the gauge *pulling* from
a staking contract, a designated distributor **pushes** tokens in.

```python
struct Reward:                # V5 :76, same in V4
    token: address
    distributor: address
    period_finish: uint256
    rate: uint256
    last_update: uint256
    integral: uint256
```

`reward_count` (`:125`), `reward_tokens[8]`, `reward_data[token]: Reward`.

**`add_reward(_reward_token, _distributor)` `:614`** — `assert msg.sender ==
self.admin  # dev: only owner`, `reward_count < MAX_REWARDS`, and
`self.reward_data[_reward_token].distributor == ZERO_ADDRESS` (no re-add).

**`set_reward_distributor(_reward_token, _distributor)` `:630`** — callable by
the current distributor **or** the admin; both old and new must be non-zero.

**`deposit_reward_token(_reward_token, _amount)` `:642`, `@nonreentrant("lock")`**
— `assert msg.sender == self.reward_data[_reward_token].distributor`, checkpoint
globally, `transferFrom` via `raw_call`, then the Synthetix rate roll:

```python
period_finish: uint256 = self.reward_data[_reward_token].period_finish
if block.timestamp >= period_finish:
    self.reward_data[_reward_token].rate = _amount / WEEK
else:
    remaining: uint256 = period_finish - block.timestamp
    leftover: uint256 = remaining * self.reward_data[_reward_token].rate
    self.reward_data[_reward_token].rate = (_amount + leftover) / WEEK
self.reward_data[_reward_token].last_update = block.timestamp
self.reward_data[_reward_token].period_finish = block.timestamp + WEEK
```

Topping up mid-period stretches the remainder over a fresh week.

`_checkpoint_rewards` (`:210`) becomes purely arithmetic — no `raw_call` to a
foreign staking contract:

```python
last_update: uint256 = min(block.timestamp, self.reward_data[token].period_finish)
duration: uint256 = last_update - self.reward_data[token].last_update
if duration != 0:
    self.reward_data[token].last_update = last_update
    if _total_supply != 0:
        integral += duration * self.reward_data[token].rate * 10**18 / _total_supply
        self.reward_data[token].integral = integral
```

Also new: `VEBOOST_PROXY` for boost delegation (`:194`), and the constructor
`__init__(_lp_token, _admin)` `:146` drops the `_minter` argument — Minter, CRV,
VotingEscrow, GaugeController and the veBoost proxy are all **hardcoded
constants**. Remaining: `decimals` `:167`, `integrate_checkpoint` `:178`,
`_checkpoint` `:271`, `user_checkpoint` `:339`, `claimable_tokens` `:352`,
`claimed_reward` `:364`, `claimable_reward` `:376`, `set_rewards_receiver`
`:397`, `claim_rewards` `:408`, `kick` `:422`, `deposit` `:443`, `withdraw`
`:474`, `_transfer` `:502`, `transfer` `:526`, `transferFrom` `:540`, `approve`
`:558`, `increaseAllowance` `:578`, `decreaseAllowance` `:596`, `set_killed`
`:673`, `commit_transfer_ownership` `:685`, `accept_transfer_ownership` `:697`.

### 4.9 `LiquidityGaugeV5.vy` — immutables and EIP-2612

Vyper 0.3.1, 819 lines. V4 plus modern Vyper.

Hardcoded mainnet constants (`:95-99`):

| Constant | Address |
|---|---|
| `MINTER` | `0xd061D61a4d941c39E5453435B6345Dc261C2fcE0` |
| `CRV` | `0xD533a949740bb3306d119CC777fa900bA034cd52` |
| `VOTING_ESCROW` | `0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2` |
| `GAUGE_CONTROLLER` | `0x2F50D538606Fa9EDD2B11E2446BEb18C9D5846bB` |
| `VEBOOST_PROXY` | `0x8E0c00ed546602fD9927DF742bbAbF726D5B0d16` |

`NAME`, `SYMBOL`, `DOMAIN_SEPARATOR`, `LP_TOKEN` are `immutable` (`:102-106`),
set in `__init__` (`:159-181`) — name is built as `concat("Curve.fi ",
lp_symbol, " Gauge Deposit")` (`:173`) and symbol as `concat(lp_symbol,
"-gauge")` (`:176`). Being immutables, they are exposed through explicit
getters: `name()` `:768`, `symbol()` `:777`, `decimals()` `:786` (returns a
literal `18`), `lp_token()` `:797`, `version()` `:806` (`"v5.0.0"`, `:89`),
`DOMAIN_SEPARATOR()` `:815`.

**`permit(_owner, _spender, _value, _deadline, _v, _r, _s) -> bool` `:586`** —
EIP-2612, with **ERC-1271 support** for contract wallets (`:292-297`):

```python
if _owner.is_contract:
    sig: Bytes[65] = concat(_abi_encode(_r, _s), slice(convert(_v, bytes32), 31, 1))
    assert ERC1271(_owner).isValidSignature(digest, sig) == ERC1271_MAGIC_VAL
else:
    assert ecrecover(digest, convert(_v, uint256), convert(_r, uint256), convert(_s, uint256)) == _owner
```

`assert _owner != ZERO_ADDRESS` (`:281`), `assert block.timestamp <= _deadline`
(`:282`), nonce bumped at `:300`. `ERC1271_MAGIC_VAL` `:86`, `EIP712_TYPEHASH`
`:87`, `PERMIT_TYPEHASH` `:88`.

One subtle V5-only detail: `_update_liquidity_limit` (`:191`) drops V4's
`BOOST_WARMUP`-style gating entirely and `_checkpoint` moves the
`working_supply` read *inside* the `if block.timestamp > _period_time` block
(`:301`).

### 4.10 `RewardsOnlyGauge.vy` — sidechain rewards, no CRV

Vyper 0.2.12, 486 lines. Everything about CRV is deleted: no `integrate_*`, no
`working_balances`, no boost, no GaugeController. It is V3's reward half plus
an ERC-20.

`__init__(_admin, _lp_token)` `:77`. `_checkpoint_rewards(_user,
_total_supply, _claim, _receiver)` `:104` is V3's, including the
`CLAIM_FREQUENCY` throttle and packed `claim_data`. Views: `decimals` `:94`,
`reward_contract` `:176`, `last_claim` `:186`, `claimed_reward` `:196`,
`claimable_reward` `:208`, `claimable_reward_write` `:223`. Actions:
`set_rewards_receiver` `:238`, `claim_rewards` `:249`, `deposit` `:264`,
`withdraw` `:290`, `_transfer` `:314`, `transfer` `:332`, `transferFrom` `:346`,
`approve` `:364`, `increaseAllowance` `:384`, `decreaseAllowance` `:402`,
`set_rewards(_reward_contract, _claim_sig, _reward_tokens[8])` `:421`,
`commit_transfer_ownership` `:466`, `accept_transfer_ownership` `:478`.

This is what a sidechain LP stakes into; CRV reaches the chain separately via a
root gauge (§10) and a streamer (§9).

---

## 5. `Minter.vy`

`contracts/Minter.vy`, Vyper 0.2.4, 99 lines. The only address CRV will mint
for.

Storage: `token` (`:26`), `controller` (`:27`),
`minted[user][gauge]` (`:30`), `allowed_to_mint_for[minter][user]` (`:33`).
`__init__(_token, _controller)` `:37`.

### `_mint_for(gauge_addr, _for)` `@internal` — `:43`

```python
assert GaugeController(self.controller).gauge_types(gauge_addr) >= 0  # dev: gauge is not added

LiquidityGauge(gauge_addr).user_checkpoint(_for)
total_mint: uint256 = LiquidityGauge(gauge_addr).integrate_fraction(_for)
to_mint: uint256 = total_mint - self.minted[_for][gauge_addr]

if to_mint != 0:
    MERC20(self.token).mint(_for, to_mint)
    self.minted[_for][gauge_addr] = total_mint
    log Minted(_for, gauge_addr, total_mint)
```

Four lines carry the whole design:

1. **Registration check.** `gauge_types` reverts for an unregistered gauge
   (`GaugeController.vy:160`), so a fake gauge cannot mint. The `>= 0` is
   almost decorative — the revert does the work.
2. **Force a checkpoint.** `user_checkpoint(_for)` brings
   `integrate_fraction[_for]` up to now. The gauge allows this because the
   caller is the Minter (`LiquidityGauge.vy:229`).
3. **Idempotence.** `minted[_for][gauge]` is a high-water mark. `integrate_fraction`
   only ever grows, so `to_mint` is the un-paid remainder. Calling `mint` twice
   in a block yields zero the second time; there is no reentrancy value in the
   accounting itself, though every entry point is `@nonreentrant('lock')`.
4. **Event caveat.** `log Minted(_for, gauge_addr, total_mint)` emits the
   *cumulative* total, not `to_mint`. Indexers that sum `Minted.minted` will
   overcount badly.

### Entry points

| Function | Line | Guard |
|---|---|---|
| `mint(gauge_addr)` | `:59` | `@nonreentrant('lock')`; mints for `msg.sender` |
| `mint_many(gauge_addrs: address[8])` | `:69` | `@nonreentrant('lock')`; loops, breaks at first `ZERO_ADDRESS` (`:75-76`) |
| `mint_for(gauge_addr, _for)` | `:82` | `@nonreentrant('lock')`; **silently does nothing** if not approved (`:89-90`) |
| `toggle_approve_mint(minting_user)` | `:94` | any; flips `allowed_to_mint_for[minting_user][msg.sender]` (`:99`) |

`mint_for` uses `if` rather than `assert` (`:89`) — an unauthorised call
succeeds and mints nothing. Wrappers that call it and assume tokens arrived
will silently under-deliver.

---

## 6. `FeeDistributor.vy`

`contracts/FeeDistributor.vy`, Vyper 0.2.7, 466 lines.

Pays trading fees (historically 3CRV, later crvUSD) to veCRV holders. The
economics: 50% of every Curve swap fee is the "admin fee", which the burner
chain (§11) converts into `token` and pushes here; this contract splits it
across weeks and pays each holder in proportion to their veCRV **at each week
boundary**.

### 6.1 Storage and constants

| Name | Line | Meaning |
|---|---|---|
| `WEEK` | `:46` | `7*86400` |
| `TOKEN_CHECKPOINT_DEADLINE` | `:47` | `86400` — throttle for permissionless token checkpoints |
| `start_time` | `:49` | week-rounded distribution start |
| `time_cursor` | `:50` | next week needing a `ve_supply` snapshot |
| `time_cursor_of[user]` | `:51` | next week to pay this user |
| `user_epoch_of[user]` | `:52` | cached ve epoch cursor |
| `last_token_time` | `:54` | last `_checkpoint_token` |
| `tokens_per_week[t]` | `:55` | fees allocated to week `t` |
| `voting_escrow`, `token` | `:57-58` | |
| `total_received`, `token_last_balance` | `:59-60` | |
| `ve_supply[t]` | `:62` | veCRV total supply at week boundary `t` |
| `admin`, `future_admin` | `:64-65` | |
| `can_checkpoint_token` | `:66` | permissionless-checkpoint flag |
| `emergency_return` | `:67` | kill/recover destination |
| `is_killed` | `:68` | |

`__init__(_voting_escrow, _start_time, _token, _admin, _emergency_return)` `:72`
rounds `_start_time` down to a week and seeds `start_time`, `last_token_time`
and `time_cursor` to it (`:88-91`).

The contract redeclares `struct Point` (`:39`) to match `VotingEscrow`'s,
because it reads `point_history`/`user_point_history` directly.

### 6.2 `_checkpoint_token()` `@internal` — `:99`

Splits newly-arrived tokens across the weeks they arrived over.

```python
token_balance: uint256 = ERC20(self.token).balanceOf(self)
to_distribute: uint256 = token_balance - self.token_last_balance
self.token_last_balance = token_balance

t: uint256 = self.last_token_time
since_last: uint256 = block.timestamp - t
self.last_token_time = block.timestamp
this_week: uint256 = t / WEEK * WEEK

for i in range(20):
    next_week = this_week + WEEK
    if block.timestamp < next_week:
        ... self.tokens_per_week[this_week] += to_distribute * (block.timestamp - t) / since_last
        break
    else:
        ... self.tokens_per_week[this_week] += to_distribute * (next_week - t) / since_last
    t = next_week
    this_week = next_week
```

Balance-diff accounting: anything that appeared since the last checkpoint is
spread **pro-rata over elapsed time**, not dumped into the current week. The
`since_last == 0` branches (`:113`, `:119`) avoid division by zero in the
same-timestamp case. `range(20)` caps the catch-up at 20 weeks — leave this
uncalled for longer and allocation is wrong.

**`checkpoint_token()` `@external` `:130`** —

```python
assert (msg.sender == self.admin) or\
       (self.can_checkpoint_token and (block.timestamp > self.last_token_time + TOKEN_CHECKPOINT_DEADLINE))
```

Admin always; anyone else only once `can_checkpoint_token` is on and a day has
passed.

### 6.3 `_checkpoint_total_supply()` `@internal` — `:193`

Snapshots veCRV total supply at each week boundary.

```python
VotingEscrow(ve).checkpoint()          # :197  force ve history current
for i in range(20):
    if t > rounded_timestamp: break
    epoch: uint256 = self._find_timestamp_epoch(ve, t)
    pt: Point = VotingEscrow(ve).point_history(epoch)
    dt: int128 = 0
    if t > pt.ts:
        dt = convert(t - pt.ts, int128)
    self.ve_supply[t] = convert(max(pt.bias - pt.slope * dt, 0), uint256)
    t += WEEK
self.time_cursor = t
```

**Note the approximation:** it decays the bracketing global point linearly to
`t` **without** applying `slope_changes` in between. `VotingEscrow.totalSupply`
does apply them (`supply_at:612`). So `ve_supply[t]` can differ slightly from
the true total. It is consistent between numerator and denominator only if the
user's own decay is computed the same way — which it is (`_claim:279`). The
`range(20)` bound again caps catch-up at 20 weeks.

`_find_timestamp_epoch(ve, _timestamp)` `:144` and
`_find_timestamp_user_epoch(ve, user, _timestamp, max_user_epoch)` `:161` are
binary searches over ve history; both use `(_min + _max + 2) / 2` (`:150`,
`:167`) rather than the usual `+1`, an upper-biased midpoint.

**`checkpoint_total_supply()` `@external` `:217`** — permissionless, unthrottled.

**`ve_for_at(_user, _timestamp) -> uint256` `@view @external` `:178`** — the
public helper: find the user's ve epoch at that time and decay it.

### 6.4 `_claim(addr, ve, _last_token_time)` `@internal` — `:228`

Walks the user forward week by week, at most 50 weeks per call.

Setup (`:233-259`): `max_user_epoch == 0` → return 0 (no lock, no fees,
`:236-238`). First-ever claim does a binary search from `start_time`
(`:243`) and sets `week_cursor` to the week **after** the user's first point
(`:253`): `(user_point.ts + WEEK - 1) / WEEK * WEEK`. Returns 0 if the cursor
has caught up to `_last_token_time` (`:255-256`).

The loop (`:263-285`):

```python
for i in range(50):
    if week_cursor >= _last_token_time: break

    if week_cursor >= user_point.ts and user_epoch <= max_user_epoch:
        user_epoch += 1
        old_user_point = user_point
        if user_epoch > max_user_epoch:
            user_point = empty(Point)
        else:
            user_point = VotingEscrow(ve).user_point_history(addr, user_epoch)
    else:
        dt: int128 = convert(week_cursor - old_user_point.ts, int128)
        balance_of: uint256 = convert(max(old_user_point.bias - dt * old_user_point.slope, 0), uint256)
        if balance_of == 0 and user_epoch > max_user_epoch:
            break
        if balance_of > 0:
            to_distribute += balance_of * self.tokens_per_week[week_cursor] / self.ve_supply[week_cursor]
        week_cursor += WEEK
```

The two-armed loop alternates: advance the ve-point cursor until it is ahead of
the week cursor, then pay that week. The payout line is the whole economics:

```
user_week_fees = veCRV(user, week) × tokens_per_week[week] / ve_supply[week]
```

Then `user_epoch = min(max_user_epoch, user_epoch - 1)` (`:287`) and cursors are
persisted (`:288-289`).

**The 50-week cap is user-visible.** The docstring on `claim` (`:301-305`)
explains: if the emitted `Claimed(addr, amount, claim_epoch, max_epoch)` has
`claim_epoch < max_epoch`, call again. A holder with a long, busy ve history
must claim repeatedly.

### 6.5 External surface

| Function | Line | Notes |
|---|---|---|
| `claim(_addr = msg.sender) -> uint256` | `:298` | `@nonreentrant('lock')`; `assert not self.is_killed` (`:309`); auto-checkpoints supply (`:311-312`) and token (`:316-318`) if allowed; floors `last_token_time` to the week (`:320`); transfers and decrements `token_last_balance` (`:325-326`) |
| `claim_many(_receivers: address[20]) -> bool` | `:333` | `@nonreentrant('lock')`; stops at first `ZERO_ADDRESS` (`:360-361`); one `token_last_balance` decrement for the batch (`:368-369`) |
| `burn(_coin) -> bool` | `:375` | `assert _coin == self.token` (`:381`), `assert not self.is_killed`; pulls the **caller's entire balance** (`:384-386`) then maybe checkpoints. Named `burn` to fit the burner interface (§11) — this is the terminus of the fee chain |
| `commit_admin(_addr)` | `:394` | `msg.sender == self.admin  # dev: access denied` |
| `apply_admin()` | `:405` | `msg.sender == self.admin`, `future_admin != ZERO_ADDRESS` |
| `toggle_allow_checkpoint_token()` | `:417` | admin; flips `can_checkpoint_token`, logs `ToggleAllowCheckpointToken` |
| `kill_me()` | `:428` | admin; sets `is_killed = True` **irreversibly** and sweeps the whole `token` balance to `emergency_return` (`:436-439`) |
| `recover_balance(_coin) -> bool` | `:443` | admin; `assert _coin != self.token` (`:451`); `raw_call` transfer to `emergency_return`, tolerating non-standard ERC-20s (`:454-464`) |

---

## 7. The proxy admin layer

Four contracts sit **between the DAO's Aragon votes and the pools/gauges they
own**. They exist for two reasons. First, pool ownership is a single address,
but Curve wants three different privilege levels; the proxy demultiplexes one
owner into `ownership_admin` / `parameter_admin` / `emergency_admin`. Second,
they are where **admin fees are collected and handed to burners** (§11), which
is the first link in the chain that ends at `FeeDistributor.burn` (§6.5).

| Contract | Ver | Lines | Owns | Admin model |
|---|---|---|---|---|
| `PoolProxy.vy` | 0.2.7 | 494 | StableSwap pools on Ethereum | 3 admins |
| `CryptoPoolProxy.vy` | 0.2.7 | 459 | CryptoSwap (v2) pools | 3 admins |
| `PoolProxySidechain.vy` | 0.2.8 | 462 | pools on sidechains | 1 admin + bridging |
| `GaugeProxy.vy` | 0.2.8 | 119 | LiquidityGaugeV2+ | 2 admins |

### 7.1 The three-admin model — `PoolProxy.vy`

Storage is six slots of admin plus the burner registry:

| Slot | Line | Meaning |
|---|---|---|
| `ownership_admin` | `:63` | can transfer pool ownership, set burners, set referrals |
| `parameter_admin` | `:64` | can commit fees / A ramps |
| `emergency_admin` | `:65` | can `kill_me` a pool |
| `future_*_admin` ×3 | `:67-69` | two-step handover |
| `min_asymmetries` | `:71` | per-pool guard, see §7.3 |
| `burners` | `:73` | coin → burner contract |
| `burner_kill` | `:74` | global burn circuit breaker |
| `donate_approval` | `:77` | pool → caller → may call `donate_admin_fees` |

`__init__(_ownership_admin, _parameter_admin, _emergency_admin)` `:80` sets all
three. `__default__()` `:92` is `@payable` and empty — **required**, because
ETH-containing pools pay admin fees in native ETH.

Handover is two-step but unusual: `commit_set_admins(_o, _p, _e)` `:98` and
`apply_set_admins()` `:115` are **both** gated on the *current*
`ownership_admin` (`:105`, `:119`). The incoming admin never signs. Contrast
`GaugeProxy.accept_set_admins()` `:53`, which is gated on
`future_ownership_admin` (`:58`) — the correct pattern. `PoolProxy`'s version
can hand ownership to an address that cannot use it.

### 7.2 Burner wiring — `_set_burner` `:132`

```python
old_burner: address = self.burners[_coin]
if _coin != 0xEeee...eEEeE:                 # :134  not native ETH
    if old_burner != ZERO_ADDRESS:
        # revoke approval on previous burner
        raw_call(_coin, concat(method_id("approve(address,uint256)"),
                 convert(old_burner, bytes32), convert(0, bytes32)), max_outsize=32)
    if _burner != ZERO_ADDRESS:
        # infinite approval for current burner
        raw_call(_coin, concat(method_id("approve(address,uint256)"),
                 convert(_burner, bytes32), convert(MAX_UINT256, bytes32)), max_outsize=32)
self.burners[_coin] = _burner
```

Each swap is *revoke-then-grant*, and each `raw_call` tolerates non-standard
ERC-20s by only checking the return value when one exists (`:146-147`,
`:160-161`). The ETH sentinel is skipped because native ETH has no `approve`.

`set_burner(_coin, _burner)` `:170` and `set_many_burners(_coins[20],
_burners[20])` `:183` are `ownership_admin`-only, `@nonreentrant('lock')`; the
batch stops at the first `ZERO_ADDRESS` (`:193-194`).

### 7.3 Fee collection and the asymmetry guard

**`withdraw_admin_fees(_pool)` `:200`** and **`withdraw_many(_pools[20])`
`:210`** are **permissionless** — no `assert` at all. Anyone may push a pool's
accrued admin fees into the proxy. That is safe because the destination is
fixed.

**`burn(_coin)` `:223`** and **`burn_many(_coins[20])` `:241`** hand the coin to
its burner:

```python
assert tx.origin == msg.sender          # :229  EOA only
assert not self.burner_kill             # :230
_value: uint256 = 0
if _coin == 0xEeee...eEEeE:
    _value = self.balance               # :234  forward all native ETH
Burner(self.burners[_coin]).burn(_coin, value=_value)
```

`tx.origin == msg.sender` blocks contract callers, which the docstring
(`:226`) explains as flash-loan protection: burners route through AMMs, so a
contract could sandwich its own burn. `burner_kill` (`:284`, settable by
emergency *or* ownership admin) is the panic switch.

**`apply_new_parameters(_pool)` `:360`** is the only interesting parameter
function. It is EOA-gated (`:366`) and, if a `min_asymmetry` was set for the
pool, recomputes the pool's balance asymmetry before allowing the change:

```
asymmetry = prod(x_i) / (sum(x_i)/N)^N = prod( N*x_i / sum(x_j) )
```

Implemented at `:378-394`: normalise every underlying balance to 18 decimals
(`:385`), sum them, then start from `N * 1e18` and multiply by `x/S` per coin.

```python
assert asymmetry >= min_asymmetry, "Unsafe to apply"    # :396
```

The point: a fee or `A` change re-prices the curve, and doing it while the pool
is far off balance hands value to arbitrageurs. The DAO commits the parameters
and the guard refuses to apply them until the pool is healthy enough.

### 7.4 The rest of `PoolProxy`'s surface

| Function | Line | Caller |
|---|---|---|
| `kill_me(_pool)` | `:263` | `emergency_admin` **only** |
| `unkill_me(_pool)` | `:274` | emergency **or** ownership |
| `set_burner_kill(_is_killed)` | `:284` | emergency **or** ownership |
| `commit_transfer_ownership(_pool, new_owner)` | `:295` | ownership |
| `apply_transfer_ownership(_pool)` | `:307` | **anyone** |
| `accept_transfer_ownership(_pool)` | `:317` | **anyone** |
| `revert_transfer_ownership(_pool)` | `:327` | ownership or emergency |
| `commit_new_parameters(_pool, A, fee, admin_fee, min_asymmetry)` | `:338` | parameter |
| `revert_new_parameters(_pool)` | `:403` | any of the three |
| `commit_new_fee(_pool, new_fee, new_admin_fee)` | `:414` | parameter |
| `apply_new_fee(_pool)` | `:427` | **anyone** |
| `ramp_A(_pool, _future_A, _future_time)` | `:437` | parameter |
| `stop_ramp_A(_pool)` | `:450` | parameter or emergency |
| `set_aave_referral(_pool, referral_code)` | `:461` | ownership |
| `set_donate_approval(_pool, _caller, _is_approved)` | `:472` | ownership |
| `donate_admin_fees(_pool)` | `:486` | ownership, or an approved caller (`:492`) |

The pattern is consistent and worth internalising: **`commit_*` is
privileged, `apply_*` is usually not.** The timelock lives in the pool, so once
the DAO has committed and the delay has passed, anybody may push the button.
`revert_*` is deliberately available to more admins than `commit_*` — killing a
pending change is safer than making one.

Every pool call is annotated `# dev: if implemented by the pool` (e.g. `:355`,
`:398`, `:468`) because the proxy owns pools of several vintages and older ones
lack some of these entry points; the call simply reverts.

### 7.5 `CryptoPoolProxy.vy` — the same shape for v2 pools

Identical admin model, burner logic, `donate_approval` and EOA-gating. The
differences are entirely in the pool interface:

| `PoolProxy` | `CryptoPoolProxy` | Note |
|---|---|---|
| `ramp_A(_future_A, _future_time)` `:437` | `ramp_A_gamma(_pool, _A, _gamma, _time)` `:402` | CryptoSwap ramps `A` **and** `gamma` |
| `stop_ramp_A` `:450` | `stop_ramp_A_gamma(_pool)` `:415` | |
| `commit_new_parameters(A, fee, admin_fee, min_asymmetry)` `:338` | `commit_new_parameters(_pool, mid_fee, out_fee, admin_fee, fee_gamma, price_threshold, adjustment_step, ma_half_time)` `:344` | v2's dynamic-fee parameter set |
| `commit_new_fee` / `apply_new_fee` | *absent* | folded into `commit_new_parameters` |
| `min_asymmetries` `:71` | *absent* | `apply_new_parameters` `:379` is EOA-gated only (`:385`) |
| — | `set_admin_fee_receiver` in the interface `:32` | v2 pools push fees themselves |
| — | `claim_admin_fees()` in the interface `:15` | v2's name for `withdraw_admin_fees` |
| — | `price_oracle(k)` in the interface `:28` | declared, unused by the proxy |

Note the dropped asymmetry guard: CryptoSwap pools are *designed* to hold
uncorrelated assets at arbitrary ratios, so "asymmetry" carries no information.

### 7.6 `PoolProxySidechain.vy` — one admin plus a bridge

Collapses the three admins into a single `admin` (`:62`) with a **correct**
two-step handover: `commit_new_admin(addr)` `:80` (admin-only, `:85`) then
`accept_new_admin()` `:92` gated on `msg.sender == future_admin` (`:97`).

Everything from `set_burner` through `donate_admin_fees` mirrors `PoolProxy`
with `self.admin` substituted for all three roles. Two extras:

- `set_reward_receiver(_pool, _receiver)` `:404` and
  `set_admin_fee_receiver(_pool, _receiver)` `:411`.
- The bridging path: `bridging_contract` (`:58`), `bridge_minimums` (`:59`),
  `set_bridging_contract` `:418`, `set_bridge_minimum(_coin, _min)` `:425`,
  `set_bridge_root_receiver(_receiver)` `:432`.

**`bridge(_coin)` `:438`** sends the proxy's whole balance of a coin to the
bridging contract, then triggers the bridge:

```python
amount: uint256 = ERC20(_coin).balanceOf(self)
if amount > 0:
    raw_call(_coin, _abi_encode(bridging_contract, amount,
             method_id=method_id("transfer(address,uint256)")), max_outsize=32)
if msg.sender != self.admin:
    minimum: uint256 = self.bridge_minimums[_coin]
    assert minimum != 0,  "Coin not approved for bridging"
    assert minimum >= ERC20(_coin).balanceOf(bridging_contract), "Balance below minimum bridge amount"
Bridger(bridging_contract).bridge(_coin)
```

> **The comparison at `:460` is inverted.** The docstring (`:441-444`) says
> non-admins may bridge only "where the balance exceeds a minimum amount",
> to stop dust bridging that is uneconomic to claim on the root chain. The code
> asserts `minimum >= balance`, i.e. the balance must be **at or below** the
> minimum — the exact opposite. Combined with the transfer happening *before*
> the check (`:450-455`), a non-admin can bridge any amount up to the minimum
> and is blocked from bridging large amounts. The revert string
> ("Balance below minimum bridge amount") describes the intent, not the code.
> Verified by reading `:456-460`; setting `bridge_minimums[_coin] = 0` disables
> non-admin bridging entirely, which is the intended default.

### 7.7 `GaugeProxy.vy` — 119 lines, gauge ownership

Two admins only (`:24-25`), because gauges have no fee parameters to tune.

| Function | Line | Caller |
|---|---|---|
| `__init__(_ownership_admin, _emergency_admin)` | `:32` | |
| `commit_set_admins(_o_admin, _e_admin)` | `:38` | ownership (`:44`) |
| `accept_set_admins()` | `:53` | **`future_ownership_admin`** (`:58`) — the correct two-step |
| `commit_transfer_ownership(_gauge, new_owner)` | `:69` | ownership (`:75`) |
| `accept_transfer_ownership(_gauge)` | `:81` | anyone |
| `set_killed(_gauge, _is_killed)` | `:91` | ownership or emergency (`:98`) |
| `set_rewards(_gauge, _reward_contract, _sigs, _reward_tokens[8])` | `:105` | ownership (`:117`) |

`set_killed` is the lever that zeroes a gauge's CRV rate (see §4.7); `set_rewards`
installs the third-party staking contract and its four-byte selector triple
described at `:111-114` and unpacked in §4.6.

---

## 8. Vesting

Three contracts distribute the pre-mine (the 62 % of CRV allocated to
shareholders, employees and the community reserve at genesis — see §1.1) on a
linear schedule. None of them interacts with veCRV, gauges or the Minter; they
are plain escrows over an ERC-20.

| Contract | Ver | Lines | Recipients | Deployed |
|---|---|---|---|---|
| `vests/VestingEscrow.vy` | 0.2.4 | 275 | up to 100, funded in batches | directly |
| `vests/VestingEscrowSimple.vy` | 0.2.4 | 235 | exactly one | as a forwarder clone |
| `vests/VestingEscrowFactory.vy` | 0.2.4 | 113 | — | directly |

### 8.1 The vesting curve

Both escrows share the same three-line schedule
(`VestingEscrowSimple.vy:124-131`, `VestingEscrow.vy:164-173`):

```python
if _time < start:
    return 0
return min(locked * (_time - start) / (end - start), locked)
```

So for a grant of `L` tokens over `[t0, t1]`:

```
vested(t) = 0                                   t <  t0
          = L · (t − t0) / (t1 − t0)            t0 ≤ t ≤ t1
          = L                                   t >  t1
```

**There is no cliff.** Vesting begins accruing the second `start_time` passes,
and `min(..., locked)` clamps the tail. A cliff, where Curve wanted one, was
implemented by setting `start_time` in the future rather than by any code here.
The `_time` parameter defaults to `block.timestamp` but is passed explicitly by
`claim` so a disabled recipient's clock can be frozen (§8.3).

Integer division truncates, so `vested(t)` is always rounded **down** — the
escrow keeps the dust until the schedule completes, at which point the `min`
branch pays it out exactly.

The five views are all thin wrappers on that one function:

| View | Simple | Escrow | Returns |
|---|---|---|---|
| `vestedSupply()` | `:146` | `:186` | `_total_vested()` over `initial_locked_supply` |
| `lockedSupply()` | `:156` | `:196` | `initial_locked_supply − _total_vested()` |
| `vestedOf(_recipient)` | `:166` | `:206` | ever-vested, claimed or not |
| `balanceOf(_recipient)` | `:176` | `:216` | `vestedOf − total_claimed` — the **claimable** amount |
| `lockedOf(_recipient)` | `:186` | `:226` | `initial_locked − vestedOf` |

Note `balanceOf` is not an ERC-20 balance; these contracts are not tokens.

### 8.2 `VestingEscrowSimple.vy` — the clone target

Storage (`:31-43`): `token`, `start_time`, `end_time`,
`initial_locked`/`total_claimed` per recipient, `initial_locked_supply`,
`can_disable` + `disabled_at`, `admin`/`future_admin`.

The initialisation pattern is the interesting part:

```python
@external
def __init__():
    # ensure that the original contract cannot be initialized
    self.admin = msg.sender          # :48
```

```python
def initialize(_admin, _token, _recipient, _amount, _start_time, _end_time, _can_disable) -> bool:
    assert self.admin == ZERO_ADDRESS  # dev: can only initialize once   # :75
    ...
    assert ERC20(_token).transferFrom(msg.sender, self, _amount)          # :83
    self.initial_locked[_recipient] = _amount
    self.initial_locked_supply = _amount
```

The constructor deliberately **poisons the master copy** by setting a non-zero
admin, so `initialize` can never run on it. A `create_forwarder_to` clone has
fresh storage, so its `admin` reads zero and the guard passes exactly once
(`:53`, `@nonreentrant('lock')`). This is the standard minimal-proxy
initialisation dance, written before OpenZeppelin's `Initializable` was common
in Vyper.

`initialize` pulls the tokens from `msg.sender` — the factory — which is why the
factory must approve first (§8.4).

### 8.3 `claim` and the disable mechanism

```python
@external
@nonreentrant('lock')
def claim(addr: address = msg.sender):          # :196
    t: uint256 = self.disabled_at[addr]
    if t == 0:
        t = block.timestamp
    claimable: uint256 = self._total_vested_of(addr, t) - self.total_claimed[addr]
    self.total_claimed[addr] += claimable
    assert ERC20(self.token).transfer(addr, claimable)
    log Claim(addr, claimable)
```

`claim` takes an address so anyone may push a claim to its rightful recipient;
funds always go to `addr`, never to `msg.sender`.

**`toggle_disable(_recipient)` `:93`** (admin-only `:101`, and only while
`can_disable` `:102`) writes `disabled_at[_recipient] = block.timestamp`, or
clears it back to zero if already set (`:104-108`). Because `claim` evaluates
the schedule at `t = disabled_at` rather than now, disabling **freezes the
vesting clock**: already-vested tokens stay claimable forever, future vesting
stops. The docstring at `:96-98` states this explicitly. Re-enabling resumes on
the original schedule — the paused interval is *not* credited back, but neither
is it lost, since the curve is a function of absolute time.

**`disable_can_disable()` `:114`** (admin-only) flips `can_disable` to `False`
permanently, renouncing the power. There is no matching re-enable.

Ownership: `commit_transfer_ownership(addr)` `:212` and
`apply_transfer_ownership()` `:225`, both admin-gated (`:217`, `:229`), with
`assert _admin != ZERO_ADDRESS` (`:231`) preventing accidental renouncement.

### 8.4 `VestingEscrowFactory.vy`

Three storage slots: `admin`, `future_admin`, `target` (`:33-35`). `__init__(
_target, _admin)` `:38` records the pre-deployed `VestingEscrowSimple` master
copy, which the docstring at `:41-42` says must exist first.

```python
def deploy_vesting_contract(_token, _recipient, _amount, _can_disable,
                            _vesting_duration, _vesting_start = block.timestamp) -> address:
    assert msg.sender == self.admin              # :70
    assert _vesting_start >= block.timestamp     # :71  dev: start time too soon
    assert _vesting_duration >= MIN_VESTING_DURATION   # :72  dev: duration too short

    _contract: address = create_forwarder_to(self.target)     # :74
    assert ERC20(_token).approve(_contract, _amount)          # :75
    VestingEscrowSimple(_contract).initialize(
        self.admin, _token, _recipient, _amount,
        _vesting_start, _vesting_start + _vesting_duration, _can_disable)
    return _contract
```

`MIN_VESTING_DURATION = 86400 * 365` (`:11`) — **one year minimum**, enforced on
every grant. `create_forwarder_to` is Vyper's EIP-1167 minimal proxy: the clone
holds only a `delegatecall` stub, so all logic executes from `target` against
the clone's own storage. That is why `VestingEscrowSimple.__init__` never runs
for a clone and `initialize` has to exist.

The order at `:74-76` matters: deploy, then `approve` the clone, then let the
clone `transferFrom` the factory during `initialize`. Tokens must therefore be
sitting in the *factory* beforehand — the docstring says so at `:60-62`.

Ownership is the usual `commit_transfer_ownership` `:90` /
`apply_transfer_ownership` `:103` pair, both admin-gated (`:95`, `:107`). The
docstring at `:92` mistakenly says "Transfer ownership of GaugeController" — a
copy-paste from `GaugeController.vy`.

### 8.5 `VestingEscrow.vy` — many recipients, one contract

Same schedule and same views, but built for the genesis distribution where one
escrow serves up to 100 addresses. Differences from `VestingEscrowSimple`:

| | `VestingEscrowSimple` | `VestingEscrow` |
|---|---|---|
| Deployment | clone via factory, `initialize` `:53` | direct, `__init__` `:51` |
| Recipients | one, set at init | many, set by `fund` `:99` |
| Extra storage | — | `unallocated_supply` `:38`, `fund_admins` `:47`, `fund_admins_enabled` `:46` |
| Funding | `transferFrom` inside `initialize` `:83` | `add_tokens` `:86` then `fund` `:99` |
| Time guards | none | `_start_time >= block.timestamp` `:66`, `_end_time > _start_time` `:67` |

`__init__` `:51` takes `_fund_admins: address[4]` and sets
`fund_admins_enabled` if any is non-zero (`:75-82`).

**`add_tokens(_amount)` `:86`** — admin-only (`:92`); pulls tokens and credits
`unallocated_supply`. Kept separate from `fund` so that funding admins, who may
not hold tokens, can still allocate.

**`fund(_recipients[100], _amounts[100])` `:99`** — admin, or a fund admin while
`fund_admins_enabled` (`:106-107`). Loops to the first `ZERO_ADDRESS`
(`:115-116`), accumulates into `initial_locked[recipient]` with `+=` so a
recipient may be funded across several calls, then moves the total from
`unallocated_supply` into `initial_locked_supply` (`:121-122`). That subtraction
underflows and reverts if the batch over-allocates, which is the only check that
the escrow is solvent.

**`disable_fund_admins()` `:154`** — admin-only (`:158`); permanently revokes
the temporary funding accounts once the distribution is loaded.

---

## 9. Streamers

Gauges on sidechains cannot mint CRV — the Minter and GaugeController live on
Ethereum. `RewardsOnlyGauge` (§4.10) therefore has no CRV integral at all; it
only knows how to pull *reward tokens* from a `reward_contract` and account
them per-LP. The streamers are what sits on the other side of that pull: they
receive a lump sum bridged from mainnet and release it at a constant rate so the
gauge sees a smooth stream instead of a step function.

| Contract | Ver | Lines | Role |
|---|---|---|---|
| `streamers/RewardStream.vy` | 0.2.12 | 166 | one token, split evenly between N receivers |
| `streamers/ChildChainStreamer.vy` | 0.2.16 | 225 | up to 8 tokens, one receiver |
| `streamers/RewardClaimer.vy` | 0.2.16 | 91 | passthrough over up to 4 streamers |

```
mainnet                          sidechain
-------                          ---------
RootGauge*  --bridge-->  ChildChainStreamer.notify_reward_amount(token)
                                  |  rate = amount / duration
                                  v  get_reward()  (called by the gauge)
                          RewardsOnlyGauge  --> LPs
```

### 9.1 `RewardStream.vy` — even split, no stake weighting

Storage (`:12-25`): `owner`/`future_owner`, `distributor`, `reward_token`,
`period_finish`, `reward_rate`, `reward_duration`, `last_update_time`,
`reward_per_receiver_total`, `receiver_count`, `reward_receivers` (a set), and
private `reward_paid`.

The accounting is the same "growth per unit" trick as the gauges (§4.1), but the
denominator is a **head count**, not a stake:

```python
@internal
def _update_per_receiver_total() -> uint256:            # :37
    total: uint256 = self.reward_per_receiver_total
    count: uint256 = self.receiver_count
    if count == 0:
        return total
    last_time: uint256 = min(block.timestamp, self.period_finish)
    total += (last_time - self.last_update_time) * self.reward_rate / count
    self.reward_per_receiver_total = total
    self.last_update_time = last_time
    return total
```

`reward_per_receiver_total` is a monotonically increasing "how much has each
receiver earned in total, ever" counter. A receiver's claim is
`total − reward_paid[receiver]`. The `min(block.timestamp, period_finish)` clamp
(`:44`) is what stops accrual after the period ends. When `count == 0` the
function returns early **without** advancing `last_update_time` (`:41-42`), so
the elapsed time is not lost — it is credited to whoever is added next. That is
a subtle leak: rewards accrue to nobody yet the clock keeps running from the old
`last_update_time`, so the first receiver added after an empty period collects
the whole backlog.

| Function | Line | Caller | Behaviour |
|---|---|---|---|
| `add_receiver(_receiver)` | `:53` | owner (`:61`) | settles first, then sets `reward_paid[_receiver] = total` (`:67`) so the newcomer starts at zero — the docstring at `:56-57` promises exactly this |
| `remove_receiver(_receiver)` | `:71` | owner (`:77`) | settles, decrements the count, **pays out** the balance (`:83-85`), zeroes `reward_paid` |
| `get_reward()` | `:90` | any active receiver (`:94`) | settles, transfers `total − reward_paid[msg.sender]` |
| `notify_reward_amount(_amount)` | `:103` | distributor (`:110`) | see below |
| `set_reward_duration(_duration)` | `:127` | owner; only when `block.timestamp > period_finish` (`:134`) |
| `set_reward_distributor(_distributor)` | `:137` | owner (`:144`) |
| `commit_transfer_ownership(_owner)` / `accept_transfer_ownership()` | `:147` / `:158` | owner / future owner (`:163`) — correct two-step |

**`notify_reward_amount`** is the Synthetix rate-reset formula:

```python
self._update_per_receiver_total()
assert ERC20(self.reward_token).transferFrom(msg.sender, self, _amount)
duration: uint256 = self.reward_duration
if block.timestamp >= self.period_finish:
    self.reward_rate = _amount / duration
else:
    remaining: uint256 = self.period_finish - block.timestamp
    leftover: uint256 = remaining * self.reward_rate
    self.reward_rate = (_amount + leftover) / duration
self.last_update_time = block.timestamp
self.period_finish = block.timestamp + duration
```

Topping up mid-period folds the undistributed remainder into the new rate and
restarts the clock, so the stream never stalls but always stretches to a full
`duration` from now. Note `reward_rate` is **per second for the whole set**,
divided by `count` only at accrual time — so adding a receiver dilutes everyone
going forward without touching what they have already earned.

### 9.2 `ChildChainStreamer.vy` — up to 8 tokens, one receiver

Storage (`:20-27`): `owner`/`future_owner`, `reward_receiver`,
`reward_tokens: address[8]`, `reward_count`, `reward_data`, `last_update_time`.
Each token carries a `RewardToken` struct (`:11-18`): `distributor`,
`period_finish`, `rate`, `duration`, `received`, `paid`.

The key structural difference from `RewardStream`: there is exactly one
receiver, so there is no per-receiver bookkeeping. `_update_reward` simply
**pushes** tokens out.

```python
@internal
def _update_reward(_token: address, _last_update: uint256):     # :94
    last_time: uint256 = min(block.timestamp, self.reward_data[_token].period_finish)
    if last_time > _last_update:
        amount: uint256 = (last_time - _last_update) * self.reward_data[_token].rate
        if amount > 0:
            self.reward_data[_token].paid += amount
            raw_call(_token, concat(method_id("transfer(address,uint256)"),
                     convert(self.reward_receiver, bytes32),
                     convert(amount, bytes32)), max_outsize=32)
```

`raw_call` with a conditional return check (`:110-111`) again tolerates
non-standard ERC-20s. Because tokens are *pushed*, `set_receiver` warns at
`:117-118` that a contract receiver must recognise rewards that arrive without a
`get_reward` call — which is exactly how `RewardsOnlyGauge` works, since it
reads its own balance.

| Function | Line | Caller | Notes |
|---|---|---|---|
| `__init__(_owner, _receiver, _reward)` | `:31` | | seeds the first reward token |
| `add_reward(_token, _distributor, _duration)` | `:42` | owner (`:49`) | `"Reward token already added"` (`:50`) |
| `remove_reward(_token)` | `:60` | owner (`:66`) | `"Reward token not added"` (`:67`); sweeps the remaining balance out (`:81`) |
| `set_receiver(_receiver)` | `:115` | owner (`:122`) | |
| `get_reward()` | `:127` | **anyone** | loops all 8 slots, pushes each, then stamps `last_update_time` (`:136`) |
| `notify_reward_amount(_token)` | `:140` | see below | |
| `set_reward_duration(_token, _duration)` | `:183` | owner; `"Reward period still active"` (`:191`) |
| `set_reward_distributor(_token, _distributor)` | `:196` | owner (`:202`) |
| `commit_transfer_ownership` / `accept_transfer_ownership` | `:207` / `:218` | owner / future owner (`:223`) |

**`notify_reward_amount(_token)` `:140` is permissionless when the period has
expired.** It works by balance diff rather than `transferFrom`:

```python
received: uint256 = self.reward_data[token].received
expected_balance: uint256 = received - self.reward_data[token].paid
actual_balance: uint256 = ERC20(token).balanceOf(self)
if actual_balance > expected_balance:
    new_amount: uint256 = actual_balance - expected_balance
    duration: uint256 = self.reward_data[token].duration
    if block.timestamp >= self.reward_data[token].period_finish:
        self.reward_data[token].rate = new_amount / duration
    else:
        assert msg.sender == self.reward_data[_token].distributor, "Reward period still active"
        ...
```

This is the design that makes bridging work. A bridge deposits tokens with a
plain `transfer` — it cannot call `transferFrom` or any custom function. So the
streamer detects the surplus itself, and **anyone may start the new period once
the old one has finished** (`:167-168`). Only shortening an *active* period is
restricted to the distributor (`:169`). `assert is_updated` (`:178`) rejects a
call naming a token that is not registered or has nothing new.

Note the loop calls `_update_reward` for **every** token before checking the
named one (`:161-165`), so a single `notify_reward_amount` flushes all pending
streams. Also note `:169` reads `self.reward_data[_token].distributor` (the
argument) while the surrounding block otherwise uses `token` (the loop
variable); they are equal on the only branch that reaches it, so the behaviour
is correct, but the inconsistency is worth knowing when reading.

### 9.3 `RewardClaimer.vy` — a 91-line fan-in

Sits between a gauge and up to four streamers. `reward_data: RewardData[4]`
(`:25`) holds `{claim, reward}` pairs (`:16-18`).

```python
@external
def get_reward():                                   # :40
    assert msg.sender == self.reward_receiver       # :45
    for i in range(4):
        data: RewardData = self.reward_data[i]
        if data.reward == ZERO_ADDRESS:
            break
        RewardStream(data.claim).get_reward()
        amount: uint256 = ERC20(data.reward).balanceOf(self)
        if amount > 0:
            assert ERC20(data.reward).transfer(msg.sender, amount)
```

It calls each streamer, then forwards whatever landed. `RewardsOnlyGauge`
accepts a single `reward_contract` address with a single claim selector, so this
is the adapter that lets one gauge draw from several independent streams.
`set_reward_data(_idx, _claim, _reward)` `:59` is owner-only (`:67`) and does no
bounds-checking beyond Vyper's own array bound. Ownership is the standard
two-step (`:73`, `:84`).

---

## 10. Sidechain root gauges and wrappers

Nine contracts that extend the gauge system past its two structural limits:
CRV can only be minted on Ethereum, and a gauge deposit is a non-transferable
storage entry.

| Contract | Ver | Lines | Purpose |
|---|---|---|---|
| `gauges/sidechain/RootGaugeXdai.vy` | 0.2.8 | 216 | mint + bridge to Gnosis Chain |
| `gauges/sidechain/RootGaugePolygon.vy` | 0.2.8 | 218 | mint + bridge to Polygon |
| `gauges/sidechain/RootGaugeHarmony.vy` | 0.2.8 | 213 | mint + bridge to Harmony |
| `gauges/sidechain/RootGaugeAnyswap.vy` | 0.2.12 | 216 | mint + bridge via Anyswap |
| `gauges/sidechain/RootGaugeArbitrum.vy` | 0.2.12 | 285 | mint + bridge to Arbitrum |
| `gauges/sidechain/CheckpointProxy.vy` | 0.2.12 | 20 | EOA-only `checkpoint` shim |
| `gauges/wrappers/LiquidityGaugeWrapper.vy` | 0.2.8 | 360 | tokenise a `LiquidityGauge` position |
| `gauges/wrappers/LiquidityGaugeRewardWrapper.vy` | 0.2.8 | 408 | same, for `LiquidityGaugeReward` |
| `gauges/wrappers/LiquidityGaugeWrapperUnit.vy` | 0.2.8 | 346 | wrapper usable as unit.xyz collateral |

### 10.1 Root gauges — a gauge with no LPs

A root gauge registers with the `GaugeController` like any other gauge and
receives a weight from veCRV votes. But it has **no depositors**. Its entire job
is: once a week, work out how much CRV its weight entitles it to, mint that from
the `Minter`, and push it over a bridge. The sidechain side then distributes it
through a streamer (§9) into a `RewardsOnlyGauge` (§4.10).

The `Minter` interface it satisfies is minimal, and deliberately self-referential:

```python
@view
@external
def integrate_fraction(addr: address) -> uint256:      # RootGaugeXdai.vy:166
    assert addr == self, "Gauge can only mint for itself"
    return self.emissions
```

`Minter._mint_for` (§5) computes `integrate_fraction(addr) - minted[addr][gauge]`
and transfers the difference. By reporting a cumulative `emissions` counter for
itself, the root gauge makes the Minter pay it exactly the new emissions.
`user_checkpoint(addr)` `:160` is a no-op returning `True` — the Minter calls it
first, and there is nothing per-user to record.

**`checkpoint()` `:92`** is the whole contract. Storage it maintains:
`period` (`:54`, the last week index processed), `emissions` (`:55`, cumulative),
`inflation_rate` (`:56`), `start_epoch_time` (`:52`).

```python
assert self.checkpoint_admin in [ZERO_ADDRESS, msg.sender]      # :97
last_period: uint256 = self.period
current_period: uint256 = block.timestamp / WEEK - 1
if last_period < current_period:
    Controller(controller).checkpoint_gauge(self)
    rate: uint256 = self.inflation_rate
    ...
    for i in range(last_period, last_period + 255):
        if i > current_period: break
        gauge_weight: uint256 = Controller(controller).gauge_relative_weight(self, i * WEEK)
        if next_epoch_time >= period_time and next_epoch_time < period_time + WEEK:
            # the week straddles an inflation epoch — split it
            period_emission = gauge_weight * rate * (next_epoch_time - period_time) / 10**18
            rate = rate * RATE_DENOMINATOR / RATE_REDUCTION_COEFFICIENT
            period_emission += gauge_weight * rate * (period_time + WEEK - next_epoch_time) / 10**18
            self.inflation_rate = rate
            self.start_epoch_time = next_epoch_time
            next_epoch_time += RATE_REDUCTION_TIME
        else:
            period_emission = gauge_weight * rate * WEEK / 10**18
        new_emissions += period_emission
```

Three things worth pinning down:

- **`current_period = block.timestamp / WEEK - 1`** (`:99`). It always works on
  *completed* weeks. `gauge_relative_weight` for a future week is not final
  because votes can still move, so the root gauge lags one week behind.
- **The epoch-crossing branch recomputes the rate locally** rather than reading
  `ERC20CRV.rate()`. The comment at `:117-120` explains why: emissions are being
  generated for a week that may span the annual reduction, and `ERC20CRV` may not
  have had `update_mining_parameters` called yet. So the constants
  `RATE_REDUCTION_COEFFICIENT = 1189207115002721024` and `RATE_REDUCTION_TIME =
  YEAR` (`:44-45`) are duplicated here, mirroring §1.3 exactly.
- **`range(last_period, last_period + 255)`** caps catch-up at 255 weeks (~4.9
  years), the same bound the gauges use.

Then the payout:

```python
self.period = current_period
self.emissions += new_emissions
if new_emissions > 0 and not self.is_killed:
    Minter(self.minter).mint(self)
    raw_call(XDAI_BRIDGE, concat(method_id("relayTokens(address,address,uint256)"),
             convert(self.crv_token, bytes32), convert(self, bytes32),
             convert(new_emissions, bytes32)))
```

`emissions` is credited **even when killed** — only the mint-and-bridge is
skipped (`:138`). Killing therefore permanently forfeits that week's CRV rather
than deferring it, because the Minter will later net it out against `minted`.

**The five root gauges differ only in the bridge call:**

| Gauge | Bridge target | Mechanism |
|---|---|---|
| `RootGaugeXdai` | `XDAI_BRIDGE` const `:46` | `raw_call relayTokens(token, receiver, amount)` `:139-147` |
| `RootGaugePolygon` | `POLYGON_BRIDGE_MANAGER` `:46`, `POLYGON_BRIDGE_RECEIVER` `:47` | infinite `approve` in `__init__` `:89`, then `raw_call` on the manager `:141` |
| `RootGaugeHarmony` | `HARMONY_BRIDGE` const `:49` | infinite `approve` in `__init__` `:93`, then `lockToken(crv, amount, self)` `:144` |
| `RootGaugeAnyswap` | `anyswap_bridge` **storage** `:62`, set in `__init__` `:86` | plain `ERC20.transfer(bridge, amount)` `:147` |
| `RootGaugeArbitrum` | `GATEWAY_ROUTER` `:46`, `GATEWAY` `:47` | needs ETH for L2 gas; exposes `get_total_bridge_cost()` `:118` and the caller must send that value (`:133`) |

`RootGaugeArbitrum` is the outlier: Arbitrum retryable tickets require prepaid
L2 gas, so `checkpoint` is `@payable` and the docstring at `:133` instructs
callers to quote `get_total_bridge_cost()` first.

Common admin surface on all five: `set_killed(_is_killed)` `:172` (admin
`:178`), `commit_transfer_ownership(addr)` `:184` / `accept_transfer_ownership()`
`:196` (correct two-step, `:201`), `set_checkpoint_admin(_admin)` `:208`
(admin `:214`), and the view `future_epoch_time()` `:154`.

`checkpoint_admin` (`:60`) defaults to `ZERO_ADDRESS`, which the guard at `:97`
treats as "anyone may checkpoint". Setting it restricts checkpointing to one
address — used with `CheckpointProxy`.

### 10.2 `CheckpointProxy.vy` — 20 lines, one assert

```python
@external
def checkpoint(_gauge: address) -> bool:
    # anyswap bridge cannot handle multiple transfers in one call, so we
    # block smart contracts that could checkpoint multiple gauges at once
    assert msg.sender == tx.origin        # :17
    RootGauge(_gauge).checkpoint()
    return True
```

Set as a root gauge's `checkpoint_admin` so that the gauge can only be
checkpointed through this EOA-gated shim. The comment at `:15-16` gives the
reason: the Anyswap bridge cannot process two transfers in one transaction, so
batching checkpoints would silently drop emissions.

### 10.3 The wrappers — making a gauge position transferable

A `LiquidityGauge` balance is a plain storage entry: it cannot be transferred,
used as collateral, or held by a contract on someone's behalf. The wrappers fix
that by holding the gauge position themselves and issuing a **real ERC-20**
against it (`implements: ERC20`).

`LiquidityGaugeWrapper.vy` is the base case. `deposit(_value, addr)` `:177` pulls
LP tokens, deposits them into the gauge, and mints wrapper tokens 1:1;
`withdraw(_value)` `:203` reverses it. In between, the wrapper token behaves
normally: `transfer` `:249`, `transferFrom` `:262`, `approve` `:279`,
`increaseAllowance` `:299`, `decreaseAllowance` `:317`, `allowance` `:223`.

The CRV accounting is a second integral layered on the gauge's own:

```python
@internal
def _checkpoint(addr: address):                       # :105
    crv_token: address = self.crv_token
    d_reward: uint256 = ERC20(crv_token).balanceOf(self)
    Minter(self.minter).mint(self.gauge)
    d_reward = ERC20(crv_token).balanceOf(self) - d_reward

    total_balance: uint256 = self.totalSupply
    dI: uint256 = 0
    if total_balance > 0:
        dI = 10 ** 18 * d_reward / total_balance
    I: uint256 = self.crv_integral + dI
    self.crv_integral = I
    self.claimable_crv[addr] += self.balanceOf[addr] * (I - self.crv_integral_for[addr]) / 10 ** 18
    self.crv_integral_for[addr] = I
```

Balance-diff around the `Minter.mint` call measures what actually arrived, then
`crv_integral` is CRV-per-wrapper-token scaled by 1e18 and each holder's
`crv_integral_for` snapshot yields their share. `_transfer` `:234` checkpoints
**both** sides before moving balances, which is what keeps the integral honest
across transfers.

**The cost of wrapping is the boost.** The wrapper is a single depositor from
the gauge's point of view, so `working_balance` is computed against the
*wrapper's* veCRV — normally zero. Every wrapper holder therefore earns the
unboosted 0.4× rate, and the 2.5× boost (§4.2) is unavailable. That is the
trade for transferability.

| Function | Line | Notes |
|---|---|---|
| `user_checkpoint(addr)` | `:123` | public checkpoint |
| `claimable_tokens(addr)` | `:135` | `@nonreentrant`-free view that mutates via `mint` |
| `claim_tokens(addr = msg.sender)` | `:154` | checkpoints then transfers `claimable_crv` |
| `set_approve_deposit(addr, can_deposit)` | `:166` | lets a third party deposit on your behalf |
| `kill_me()` | `:335` | admin |
| `commit_transfer_ownership` / `apply_transfer_ownership` | `:341` / `:352` | |

**`LiquidityGaugeRewardWrapper.vy`** adds a parallel integral for the Synthetix
`rewarded_token` (§4.5): `_checkpoint` `:115` claims both CRV and the reward,
and `claimable_reward(addr)` `:179` mirrors `claimable_tokens`. Otherwise the
function list is identical, offset by the extra code.

**`LiquidityGaugeWrapperUnit.vy`** is built for the unit.xyz lending vault and
changes the checkpoint in three ways (`:107-130`):

```python
if block.timestamp != claim_data % 2**40:
    last_claimable: uint256 = shift(claim_data, -40)
    claimable: uint256 = LiquidityGauge(self.gauge).claimable_tokens(self)
    d_reward: uint256 = claimable - last_claimable
    ...
    self.last_claim_data = block.timestamp + shift(claimable, 40)

for addr in _user_addresses:
    if addr in [ZERO_ADDRESS, UNIT_VAULT]:
        # do not calculate an integral for the vault to ensure it cannot ever claim
        continue
    user_balance: uint256 = self.balanceOf[addr] + self.depositedBalanceOf[addr]
```

- It reads `claimable_tokens` instead of minting, and packs
  `(timestamp, claimable)` into one slot as `timestamp + (claimable << 40)`
  (`:119`) — the same throttling trick as `LiquidityGaugeV3` (§4.7), one SLOAD
  per block.
- It checkpoints **two** addresses at once (`address[2]`), because a vault
  deposit moves tokens between two accounts.
- `UNIT_VAULT` is explicitly skipped (`:122-123`) so that collateral sitting in
  the vault still accrues to its **depositor**, tracked via
  `depositedBalanceOf` (`:127`), not to the vault. That single `continue` is the
  entire reason this variant exists.

It also declares `decimals()` as a function `:102` rather than a public constant.

---

## 11. The burner family

Thirty contracts, 6,441 lines, all implementing one interface:

```python
def burn(_coin: address) -> bool: payable
```

`PoolProxy.burn` (§7.3) looks up `burners[_coin]` and calls it. Each burner
converts one *kind* of asset one step closer to 3CRV, then forwards to the next
burner in the chain. The chain terminates at `UnderlyingBurner`, which mints
3CRV and hands it to `FeeDistributor` (§6.5).

```
pool admin fees
      | PoolProxy.withdraw_admin_fees / burn
      v
[ specialist burner ]   aToken -> USDC,  cToken -> USDC,  LP -> coins,  synth -> sUSD ...
      |  receiver
      v
UnderlyingBurner   DAI/USDC/USDT -> add_liquidity(3pool) -> 3CRV
      |  receiver
      v
FeeDistributor.burn(3CRV)  ->  veCRV holders claim
```

### 11.1 The shared skeleton

Every burner has the same six-slot storage and the same admin surface. Using
`eth/ABurner.vy` as the reference:

| Slot | Line | Meaning |
|---|---|---|
| `receiver` | `:17` | next hop in the chain |
| `recovery` | `:18` | where `recover_balance` sends tokens |
| `is_killed` | `:19` | circuit breaker |
| `owner`, `emergency_owner` | `:21-22` | two-tier admin |
| `future_owner`, `future_emergency_owner` | `:23-24` | two-step handover |

| Function | ABurner line | Caller |
|---|---|---|
| `__init__(_receiver, _recovery, _owner, _emergency_owner)` | `:28` | |
| `burn(_coin) -> bool` | `:47` | anyone (but `PoolProxy` gates on EOA) |
| `recover_balance(_coin) -> bool` | `:72` | owner **or** emergency owner (`:79`) |
| `set_recovery(_recovery) -> bool` | `:98` | owner only (`:104`) |
| `set_killed(_is_killed) -> bool` | — | owner or emergency owner |
| `commit_transfer_ownership` / `accept_transfer_ownership` | — | owner / future owner |
| `commit_transfer_emergency_ownership` / `accept_transfer_emergency_ownership` | — | emergency owner / future |

The two-tier admin split is the point: the **emergency owner** can kill and
recover but cannot change *where* recovery sends funds. Only the full owner can
call `set_recovery`. So compromising the emergency key lets you freeze the fee
chain, not steal from it.

**The `burn` preamble is identical everywhere:**

```python
assert not self.is_killed  # dev: is killed                  # :53
amount: uint256 = ERC20(_coin).balanceOf(msg.sender)
if amount != 0:
    ERC20(_coin).transferFrom(msg.sender, self, amount)      # :58
# get actual balance in case of transfer fee or pre-existing balance
amount = ERC20(_coin).balanceOf(self)                        # :61
```

Pull everything the caller holds, then **re-read own balance**. The comment at
`:60` gives both reasons: fee-on-transfer tokens deliver less than requested,
and a previous partial burn may have left a residue. Every subsequent step
operates on the re-read figure, never the requested one.

`recover_balance` uses the same `raw_call` + conditional-return-check pattern as
`PoolProxy._set_burner` (`:82-92`), tolerating non-standard ERC-20s.

### 11.2 Complete inventory

| Contract | Ver | Lines | Converts | To |
|---|---|---|---|---|
| `eth/ABurner.vy` | 0.2.8 | 173 | Aave aTokens | underlying → `UnderlyingBurner` |
| `eth/CBurner.vy` | 0.2.8 | 186 | Compound cTokens | underlying → `UnderlyingBurner` |
| `eth/YBurner.vy` | 0.2.8 | 260 | yEarn yTokens | underlying → `UnderlyingBurner` |
| `eth/UnderlyingBurner.vy` | 0.2.8 | 294 | DAI/USDC/USDT | **3CRV → FeeDistributor** |
| `eth/LPBurner.vy` | 0.2.7 | 263 | Curve LP tokens | one coin, configurable |
| `eth/MetaBurner.vy` | 0.2.7 | 212 | metapool coins | 3CRV directly |
| `eth/SynthBurner.vy` | 0.2.8 | 294 | Synthetix synths | sUSD via `exchangeWithTracking` |
| `eth/UniswapBurner.vy` | 0.2.8 | 241 | arbitrary tokens | USDC via Uniswap |
| `eth/USDNBurner.vy` | 0.2.7 | 224 | USDN | 3CRV (bespoke) |
| `eth/WrappedBurner.vy` | 0.3.3 | 53 | WETH | native ETH |
| `eth/wstETHBurner.vy` | 0.3.7 | 60 | wstETH | stETH |
| `eth/CryptoLPBurner.vy` | 0.3.0 | 224 | CryptoSwap LP | configurable |
| `eth/CryptoFactoryLPBurner.vy` | 0.3.7 | 385 | factory CryptoSwap LP | configurable |
| `eth/TricryptoFactoryLPBurner.vy` | 0.3.7 | 308 | tricrypto factory LP | configurable |
| `eth/SwapStableBurner.vy` | 0.3.7 | 276 | stable pool coins | configurable |
| `eth/SwapCryptoBurner.vy` | 0.3.7 | 354 | crypto pool coins | configurable |
| `eth/crvUSDBurner.vy` | 0.3.7 | 341 | anything | crvUSD |
| `eth/deprecated/BTCBurner.vy` | 0.2.8 | 272 | BTC synths | *deprecated* |
| `eth/deprecated/ETHBurner.vy` | 0.2.8 | 291 | ETH synths | *deprecated* |
| `eth/deprecated/EuroBurner.vy` | 0.2.8 | 269 | EUR synths | *deprecated* |
| `fantom/CBurnerFantom.vy` | 0.3.0 | 166 | cTokens on Fantom | underlying |
| `fantom/GBurnerFantom.vy` | 0.3.0 | 158 | gTokens (Geist) | underlying |
| `fantom/BTCBurnerFantom.vy` | 0.3.0 | 173 | BTC assets | — |
| `fantom/LPBurnerFantom.vy` | 0.3.0 | 182 | LP tokens | configurable |
| `fantom/TripCryptoBurnerFantom.vy` | 0.3.0 | 125 | tricrypto LP | — |
| `fantom/UnderlyingBurnerFantom.vy` | 0.3.0 | 147 | stablecoins | LP → bridge |
| `polygon/ABurnerPolygon.vy` | 0.3.0 | 158 | amTokens (Aave Polygon) | underlying |
| `polygon/BTCBurnerPolygon.vy` | 0.3.0 | 180 | BTC assets | — |
| `polygon/TriCryptoBurnerPolygon.vy` | 0.3.0 | 142 | tricrypto LP | — |
| `optimism/TricrvBurnerOptimism.vy` | 0.3.7 | 139 | stablecoins | 3CRV on Optimism |

Sidechain burners forward to a `PoolProxySidechain` (§7.6), whose `bridge`
sends the proceeds to Ethereum rather than to a `FeeDistributor`.

### 11.3 The unwrap burners — `ABurner`, `CBurner`, `YBurner`

The simplest shape. `ABurner.burn` `:47` after the shared preamble:

```python
if amount != 0:
    underlying: address = aToken(_coin).UNDERLYING_ASSET_ADDRESS()
    LendingPool(0x7d2768dE32b0b80b7a3454c06BdAc94A69DDc7A9).withdraw(underlying, amount, self.receiver)
```

One call, straight to `receiver` — the burner never holds the underlying. The
Aave v2 `LendingPool` address is hardcoded at `:66`. `CBurner` and `YBurner`
differ only in the unwrap method (`redeem` / `withdraw`) and in that they must
transfer the proceeds themselves, since those protocols do not take a receiver.

`ABurnerPolygon` is the same contract pointed at Aave's Polygon deployment.

### 11.4 `UnderlyingBurner.vy` — the terminus

The only burner that produces 3CRV. Constants at `:37-51` pin the whole path:
`TRIPOOL`, `TRIPOOL_LP`, `TRIPOOL_COINS` (DAI/USDC/USDT), `USDC = TRIPOOL_COINS[1]`,
plus Synthetix's `SNX`, `SUSD`, `SUSD_CURRENCY_KEY` and `TRACKING_CODE` (the
ASCII string `CURVE`, used to credit Curve in Synthetix's fee rebates).

It has **two** entry points instead of one:

- **`burn(_coin)` `:100`** — accepts a 3pool coin and simply holds it, or
  routes a non-3pool coin through `exchange_with_best_rate` into USDC.
- **`execute()` `:169`** — the second half, callable once the balances have
  accumulated:

```python
amounts: uint256[3] = [
    ERC20(TRIPOOL_COINS[0]).balanceOf(self),
    ERC20(TRIPOOL_COINS[1]).balanceOf(self),
    ERC20(TRIPOOL_COINS[2]).balanceOf(self),
]
if amounts[0] != 0 and amounts[1] != 0 and amounts[2] != 0:
    StableSwap(TRIPOOL).add_liquidity(amounts, 0)
amount: uint256 = ERC20(TRIPOOL_LP).balanceOf(self)
if amount != 0:
    ERC20(TRIPOOL_LP).transfer(self.receiver, amount)
```

Two details matter. **`min_mint_amount` is 0** — this deposit accepts unlimited
slippage, which is why `PoolProxy.burn` insists on an EOA caller: a contract
could sandwich the 3pool deposit. And **all three balances must be non-zero**
for the deposit to happen; a single missing coin silently skips it and the funds
wait for the next call.

`convert_synth(_currency_key, _amount)` `:155` handles Synthetix's deferred
settlement: synth exchanges have a waiting period, so the burner settles and
converts in a separate transaction.

### 11.5 The configurable burners

Twelve burners store a per-coin route rather than hardcoding one. `grep -l
'swap_data'` finds them: `LPBurner`, `CryptoLPBurner`, `CryptoFactoryLPBurner`,
`crvUSDBurner`, `SwapStableBurner`, `SwapCryptoBurner`, `SynthBurner`,
`YBurner`, the three deprecated synth burners, and `LPBurnerFantom`.

The pattern is a `swap_data` mapping plus an owner-only `set_swap_data` that
records, per coin, which pool to trade through and which indices to use. This
is what lets one deployment serve many coins without a redeploy, and it is why
these burners are larger.

`crvUSDBurner.vy` (0.3.7, 341 lines) is the most modern. It carries
`MAX_NUM = 8` (`:36`), `BPS = 10000` (`:37`) and `SLIPPAGE = 2 * 100` (`:38`,
2 %) — unlike `UnderlyingBurner` it enforces a real slippage bound, computed
against `price_oracle()` / `get_virtual_price()` (`:17-18`). It adds a
`set_pools(_pools: DynArray[address, MAX_NUM])` `:186` route registry and a
third admin role, `manager`, with `commit_new_manager` `:319` /
`accept_new_manager` `:333`. It also splits burning into `burn(_coin)` `:145`
and `burn_amount(_coin, _amount_to_burn)` `:165` so a large position can be
drained in slices.

### 11.6 The two tiny modern burners

`WrappedBurner.vy` (53 lines) is the whole pattern stripped to nothing —
`immutable` state, no admin, no kill switch:

```python
@external
def burn(_coin: address) -> bool:      # :42
    amount: uint256 = WETH.balanceOf(msg.sender)
    WETH.transferFrom(msg.sender, self, amount)
    amount = WETH.balanceOf(self)
    WETH.withdraw(amount)
    raw_call(RECEIVER, b"", value=self.balance)
    return True
```

`_coin` is ignored — the docstring at `:45` says "Remained for compatability".
`__default__()` `:31` is payable so the WETH withdrawal can land.

`wstETHBurner.vy` (60 lines) is the same shape for Lido: `WSTETH.unwrap(amount)`
then `STETH.transfer(RECEIVER, amount)`. Note it re-reads `STETH.balanceOf(self)`
after unwrapping rather than trusting the return value, because stETH is a
rebasing token and its transfers are share-based — a 1-wei rounding difference
is normal and expected.

---

## 12. Bridging

Three small contracts that move sidechain fee proceeds back to Ethereum. They
are the counterpart to `PoolProxySidechain.bridge` (§7.6), which calls
`Bridger(bridging_contract).bridge(_coin)`.

| Contract | Ver | Lines | Chain | Mechanism |
|---|---|---|---|---|
| `bridging/AnyswapBridger.vy` | 0.3.0 | 86 | any | `Swapout(amount, root_receiver)` |
| `bridging/PolygonBridger.vy` | 0.3.0 | 73 | Polygon | `withdraw(amount)` on the child token |
| `bridging/RootForwarder.vy` | 0.3.0 | 77 | Ethereum | receives and forwards to `PoolProxy` |

### 12.1 `AnyswapBridger.vy`

Storage: `admin`/`future_admin` (`:24-25`) and `root_receiver` (`:27`). The
constructor docstring (`:33-35`) states the admin **should be the
`PoolProxySidechain`**, which is what makes the `assert` below meaningful.

```python
@external
def bridge(_token: address) -> bool:        # :42
    assert msg.sender == self.admin
    amount: uint256 = AnyswapToken(_token).balanceOf(self)
    AnyswapToken(_token).Swapout(amount, self.root_receiver)
    log AssetBridged(_token, amount)
    return True
```

It bridges its **own** balance, which the proxy has just transferred in. The
`root_receiver` is named explicitly, so no forwarder is needed on the far side.
`set_root_receiver(_receiver)` `:80` and the standard two-step ownership
(`commit_transfer_ownership` `:56`, `accept_transfer_ownership` `:68`, gated on
`future_admin` at `:73`) complete the surface. The docstring at `:58` again says
"Transfer ownership of GaugeController" — the same copy-paste as §8.4.

### 12.2 `PolygonBridger.vy`

Identical shape minus `root_receiver`, because Polygon's PoS bridge credits the
**same address** on L1:

```python
amount: uint256 = BridgeToken(_token).balanceOf(self)
BridgeToken(_token).withdraw(amount)        # :46
```

`withdraw` burns the child token and emits the event that the Polygon checkpoint
mechanism later proves on Ethereum. Because the L1 recipient is fixed to this
contract's address, `RootForwarder` must be deployed at the same address on
Ethereum. The docstring at `:41` mistakenly says "via Anyswap".

### 12.3 `RootForwarder.vy`

Deployed on Ethereum at the **same address** as the sidechain bridger — the
docstring at `:6-8` is explicit that this is required for bridges that cannot
name a receiver. Storage: `owner`/`future_owner` (`:15-16`) and `pool_proxy`
(`:18`).

```python
@external
def transfer(_token: address) -> bool:      # :28
    amount: uint256 = ERC20(_token).balanceOf(self)
    raw_call(_token, _abi_encode(self.pool_proxy, amount,
             method_id=method_id("transfer(address,uint256)")), max_outsize=32)
```

`transfer_many(_tokens: address[10])` `:43` is the batched form, breaking at the
first `ZERO_ADDRESS` (`:46-47`). Both are **permissionless** — there is no
`assert msg.sender` — which is safe because the destination is the immutable
`pool_proxy` and the contract holds nothing else. From there the funds re-enter
the burner chain (§11) as if they had been earned on Ethereum.

---

## 13. `CRVInfo.vy`

A 0.3.7 utility (100 lines) by "fiddy" that estimates CRV circulating supply by
subtracting known non-circulating balances from `totalSupply`. It is not part of
the protocol; nothing else in the tree reads it.

Storage: `admin` (`:13`), `contracts: address[100000]` (`:16`), `num_contracts`
(`:17`). `CRV` is a public constant (`:14`), and `cached_contracts` is a public
constant array of 18 hardcoded addresses (`:19-38`) with inline comments naming
each: employees, vesting, community fund, the token minter, founder, investors,
the CRV token itself, LPs and veCRV.

```python
@external
@view
def circulating_supply() -> uint256:        # :60
    crv_total_supply: uint256 = ERC20(CRV).totalSupply()
    not_circulating: uint256 = self._get_crv_balances_of_cached_contracts()
    return crv_total_supply - not_circulating
```

| Function | Line | Caller |
|---|---|---|
| `__init__()` | `:42` | sets `admin = msg.sender`, `num_contracts = 18` |
| `add_contract(_contract)` | `:48` | admin (`:54`) |
| `circulating_supply() -> uint256` | `:60` | view |
| `set_admin(_new_admin)` | `:70` | admin (`:76`); the docstring at `:73` calls it "lazy admin transfer" — deliberately one-step |
| `_add_contract(_contract)` `@internal` | `:81` | `assert _contract not in self.contracts` |
| `_get_crv_balances_of_cached_contracts()` `@internal @view` | `:88` | |

> **`add_contract` has no effect on the result.** `__init__` sets
> `num_contracts = 18` (`:44`) but never writes to `self.contracts`, so indices
> 0–17 of that array stay empty. `_add_contract` (`:81-84`) writes to
> `self.contracts[self.num_contracts]`, i.e. index **18** for the first
> addition. But the summation loop is
> ```python
> for i in range(10000):
>     if self.contracts[i] == empty(address):
>         break
>     balances += ERC20(CRV).balanceOf(self.contracts[i])
> ```
> (`:95-98`), which reads from index 0, finds `empty(address)`, and breaks
> immediately. Every address added after deployment is silently ignored; only
> the 18 compile-time `cached_contracts` (`:92-93`) are ever counted. The
> contract's own docstring already calls the figure "an estimate" (`:5-7`), and
> nothing depends on it, so the effect is cosmetic — but do not use this as a
> data source.

---

## 14. Testing helpers

Three contracts under `contracts/testing/`, compiled only for the test suite.
They are not deployed and nothing in the protocol imports them.

| Contract | Ver | Lines | Purpose |
|---|---|---|---|
| `testing/CurvePool.vy` | 0.2.4 | 773 | a full two-coin StableSwap pool, used to give gauges a real LP token to stake |
| `testing/ERC20LP.vy` | 0.2.4 | 176 | a minimal `implements: ERC20` LP token for that pool |
| `testing/UnitVault.vy` | 0.2.11 | 32 | a stub of the unit.xyz vault |

`CurvePool.vy` is a trimmed copy of the mainline StableSwap implementation
("Pool for two plain coins", `:2`) — `get_D`, `get_y`, `exchange`,
`add_liquidity`, the three `remove_liquidity*` variants and the `A`-ramp
machinery. It is documented in full in
[`CLASSIC-POOLS-COMPLETE-REFERENCE.md`](CLASSIC-POOLS-COMPLETE-REFERENCE.md);
the invariant math is derived in
[`CURVE-DEEP-DIVE.md`](CURVE-DEEP-DIVE.md) §1.

`ERC20LP.vy` is a stock ERC-20 with `mint`/`burnFrom` restricted to the pool.

`UnitVault.vy` is 32 lines and exists only so `LiquidityGaugeWrapperUnit` (§10.3)
has something to call:

```python
collaterals: public(HashMap[address, HashMap[address, uint256]])   # :6
```

It records `asset -> owner -> amount` so the wrapper's `depositedBalanceOf`
logic can be exercised.

---
