# Morpho Blue Deep Dive

> Read this **after** the Aave documents in this repo. It is written as a
> sustained comparison, not as a standalone tour. Companion docs:
> [`aave/AAVE-DEEP-DIVE.md`](../aave/AAVE-DEEP-DIVE.md) (v3.6),
> [`aave/V3-PROTOCOL-COMPLETE-REFERENCE.md`](../aave/V3-PROTOCOL-COMPLETE-REFERENCE.md),
> [`aave/AAVE-V4-DEEP-DIVE.md`](../aave/AAVE-V4-DEEP-DIVE.md).

**Sources.** `morpho/morpho-blue` (core), `morpho/metamorpho` (the ERC-4626 vault
layer), `morpho/morpho-blue-oracles`, `morpho/morpho-blue-bundlers`. Every
citation below was verified with `grep -n` against these exact files.

**The size claim, measured rather than asserted.** Aave's
`src/contracts/protocol/` is 8,973 lines of Solidity. Morpho Blue's entire core
is 1,734 lines, of which the contract itself is
[`morpho-blue/src/Morpho.sol`](morpho-blue/src/Morpho.sol) at **557 lines**, and
the substantive libraries add 206 more (`ConstantsLib` 21, `MarketParamsLib` 21,
`SafeTransferLib` 36, `UtilsLib` 38, `MathLib` 45, `SharesMathLib` 45). The rest
is interfaces and declaration-only event/error libraries. So the honest number is
roughly **760 lines of logic against Aave's ~9,000**, a factor of twelve.

---

## 0. The thesis: a lending primitive, not a lending protocol

A Morpho Blue market is defined entirely by an immutable five-tuple, and there is
nothing else to it ([`morpho-blue/src/interfaces/IMorpho.sol:6-12`](morpho-blue/src/interfaces/IMorpho.sol#L6-L12)):

```solidity
struct MarketParams {
    address loanToken;
    address collateralToken;
    address oracle;
    address irm;
    uint256 lltv;
}
```

The market's identity **is** the hash of those five words
([`morpho-blue/src/libraries/MarketParamsLib.sol:16-20`](morpho-blue/src/libraries/MarketParamsLib.sol#L16-L20)):

```solidity
function id(MarketParams memory marketParams) internal pure returns (Id marketParamsId) {
    assembly ("memory-safe") {
        marketParamsId := keccak256(marketParams, MARKET_PARAMS_BYTES_LENGTH)
    }
}
```

That single design choice does most of the work. Because the id is the hash of
the parameters, **the parameters can never change**. There is no setter for
`lltv`, no setter for `oracle`, no setter for `irm`. Changing any of them does
not modify a market; it names a different market that may or may not exist. Aave
spends a 256-bit configuration bitmap and a whole `PoolConfigurator` on exactly
the mutability that Morpho makes structurally impossible.

**What "primitive" means here.** A protocol decides things on your behalf: which
assets are listed, at what LTV, with what oracle, under whose risk framework. A
primitive decides nothing. `createMarket` is permissionless
([`morpho-blue/src/Morpho.sol:150`](morpho-blue/src/Morpho.sol#L150)) — no
`onlyOwner`, no proposal, no vote. The owner's power is confined to three things:
whitelisting an IRM contract, whitelisting an LLTV *value*, and setting a fee
capped at 25%. It cannot touch a live market's risk parameters, cannot pause,
cannot upgrade, and cannot un-whitelist
([`morpho-blue/src/interfaces/IMorpho.sol:86`](morpho-blue/src/interfaces/IMorpho.sol#L86): *"Warning: It is not possible to disable an IRM"*).

**Who bears the risk.** In Aave, a bad listing is the DAO's fault and every
supplier in the pool shares the loss, because liquidity is pooled across
reserves. In Morpho Blue, a bad market harms only the people who supplied to that
market. Risk is not mutualised; it is partitioned by construction. The cost is
that you must now evaluate each market yourself, or delegate that to a curator
(see §5).

### A worked example

Market: loan token USDC (6 dec), collateral WETH (18 dec), `lltv = 0.86e18`.
The oracle returns the price of 1 WETH in USDC scaled by `1e36`
([`morpho-blue/src/interfaces/IOracle.sol:10-14`](morpho-blue/src/interfaces/IOracle.sol#L10-L14)).
With ETH at $3,000, `price = 3000 * 1e36 * 1e6 / 1e18 = 3e24`.

1. **Alice supplies 100,000 USDC.** `totalSupplyAssets = 100_000e6`.
2. **Bob supplies 10 WETH collateral**, then borrows. His limit comes straight
   from `_isHealthy` ([`morpho-blue/src/Morpho.sol:534-536`](morpho-blue/src/Morpho.sol#L534-L536)):
   `maxBorrow = 10e18 * 3e24 / 1e36 * 0.86 = 25,800e6`, i.e. 25,800 USDC.
   He borrows 24,000 USDC. Healthy: `25,800 >= 24,000`.
3. **ETH falls to $2,700.** `maxBorrow = 10e18 * 2.7e24 / 1e36 * 0.86 = 23,220e6`.
   Now `23,220 < 24,000`. The position is liquidatable — and note there is no
   separate liquidation threshold. Aave has both an LTV *and* a liquidation
   threshold; Morpho has one number, `lltv`, doing both jobs.
4. **A liquidator calls `liquidate`.** With `lltv = 0.86`, the incentive factor
   is `min(1.15, 1 / (1 - 0.3 * 0.14)) = min(1.15, 1.0438) = 1.0438`
   ([`morpho-blue/src/Morpho.sol:366-369`](morpho-blue/src/Morpho.sol#L366-L369)).
   Repaying 10,000 USDC seizes
   `10,000 * 1.0438 * 1e36 / 2.7e24 = 3.866 WETH`, worth $10,438. The
   liquidator's profit is $438, and **all of it goes to the liquidator** — there
   is no protocol cut, unlike Aave's `liquidationProtocolFee`.

There is no close factor. The liquidator may repay any amount, including all of
it. §6 explains why that is safe here and why Aave needs a close factor.

---

## 1. What Aave does that Morpho Blue does not

Read this table with the Aave source open. The right-hand column is the point:
almost nothing was *deleted* in a functional sense; it was **relocated** to a
place where it is opt-in rather than mandatory.

| Aave v3 feature | Where it lives in Aave | Morpho Blue equivalent |
|---|---|---|
| **eMode** (correlated-asset LTV boost) | [`SupplyLogic.sol:304`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/SupplyLogic.sol#L304), `EModeCategory` at [`DataTypes.sol:141`](../aave/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol#L141) | **Nowhere, and not needed.** A high-LLTV market for a correlated pair *is* eMode. Create wstETH/WETH at `lltv = 0.945` and you have it, without a category system. |
| **Isolation mode** | Removed even from Aave — see the comment at [`ReserveConfiguration.sol:22`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L22): *"unoccupied hole of 2 bit at position 61-62 from pre 3.7 borrowableInIsolation and siloedBorrowing"* | **Every market is isolated.** Isolation is the default, not a mode. |
| **Siloed borrowing** | Also removed in Aave 3.7, same comment | Same: structural. |
| **Debt ceiling** | Removed in Aave 3.7, [`ReserveConfiguration.sol:30`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L30) | **MetaMorpho's per-market `cap`** ([`metamorpho/src/libraries/PendingLib.sol:7`](../morpho/metamorpho/src/libraries/PendingLib.sol#L7)), enforced per vault rather than protocol-wide. |
| **Supply / borrow caps** | [`ReserveConfiguration.sol:296`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L296), [`:321`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L321) | **Nowhere in core.** A market has no cap. MetaMorpho caps its *own* exposure. |
| **Reserve factor** (protocol's cut of interest) | [`ReserveConfiguration.sol:271`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L271) | **`market.fee`**, owner-set, capped at 25% by [`MAX_FEE`](morpho-blue/src/libraries/ConstantsLib.sol#L5). Default is zero. |
| **Global risk admin** | `RISK_ADMIN_ROLE` at [`ACLManager.sol:17`](../aave/aave-v3-origin/src/contracts/protocol/configuration/ACLManager.sol#L17) | **Nowhere.** Nobody can change a live market's risk. |
| **ACL with six roles** | [`ACLManager.sol:15-20`](../aave/aave-v3-origin/src/contracts/protocol/configuration/ACLManager.sol#L15-L20) | **One `owner`**, one modifier ([`Morpho.sol:87-90`](morpho-blue/src/Morpho.sol#L87-L90)), four powers. |
| **Stable rate borrowing** | Removed in Aave 3.2 | Never existed. |
| **aToken / variableDebtToken ERC20s** | A deployed token pair per reserve | **Nowhere.** Balances are plain struct fields: `position[id][user].supplyShares`. No transferable receipt token in core; MetaMorpho provides one at the vault level. |
| **Interest rate strategy contract** | [`DefaultReserveInterestRateStrategyV2.sol:124`](../aave/aave-v3-origin/src/contracts/misc/DefaultReserveInterestRateStrategyV2.sol#L124) | **`IIrm`**, an external address in the market tuple ([`IIrm.sol:13`](morpho-blue/src/interfaces/IIrm.sol#L13)). Same idea, but immutable per market and pluggable. |
| **256-bit config bitmap** | [`ReserveConfiguration.sol:13-32`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L13-L32) | **Nowhere.** There is nothing to configure. |
| **Upgradeable proxies** | `InitializableImmutableAdminUpgradeabilityProxy` throughout | **None.** `Morpho.sol` is deployed once and is not upgradeable. |
| **`paused` / `frozen` flags** | [`ReserveConfiguration.sol:21`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L21) | **Nowhere.** No circuit breaker exists. This is a real cost, not a win — see §7. |
| **Liquidation protocol fee** | [`LiquidationLogic.sol:583`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L583) | **Nowhere.** The full incentive goes to the liquidator. |
| **Close factor** | `DEFAULT_LIQUIDATION_CLOSE_FACTOR` at [`LiquidationLogic.sol:43`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L43) | **Nowhere.** Any fraction is liquidatable. |
| **Deficit / bad-debt machinery** | `executeEliminateDeficit` at [`LiquidationLogic.sol:76`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L76) | **Socialised immediately**, in eight lines ([`Morpho.sol:392-403`](morpho-blue/src/Morpho.sol#L392-L403)). |

**The pattern.** Aave 3.7 is itself deleting isolation mode, siloed borrowing and
debt ceilings — the bitmap comments are gravestones. Aave arrived at "isolate
risk with parameters inside one pooled market" and is now walking it back.
Morpho started from "isolate risk by making markets separate" and never needed
the parameters.

---

## 2. `Morpho.sol` walked in full

### Storage

Nine slots, all at [`Morpho.sol:53-70`](morpho-blue/src/Morpho.sol#L53-L70):

```solidity
address public owner;
address public feeRecipient;
mapping(Id => mapping(address => Position)) public position;
mapping(Id => Market) public market;
mapping(address => bool) public isIrmEnabled;
mapping(uint256 => bool) public isLltvEnabled;
mapping(address => mapping(address => bool)) public isAuthorized;
mapping(address => uint256) public nonce;
mapping(Id => MarketParams) public idToMarketParams;
```

Compare with Aave's `PoolStorage` plus per-reserve `ReserveData` plus two token
contracts per reserve. `DOMAIN_SEPARATOR` is the only immutable
([`:49`](morpho-blue/src/Morpho.sol#L49)), computed in the constructor from
`block.chainid` and `address(this)` ([`:78`](morpho-blue/src/Morpho.sol#L78)).
Note the documented consequence: the separator has no name/version field, so a
signed authorization **replays on any fork sharing the chain id**
([`IMorpho.sol:53-54`](morpho-blue/src/interfaces/IMorpho.sol#L53-L54)).

### The universal preamble

Every state-changing market function opens with the same three or four lines.
Learn it once and the rest of the contract reads quickly:

```
Id id = marketParams.id();                                  // hash the tuple
require(market[id].lastUpdate != 0, MARKET_NOT_CREATED);    // market exists
require(UtilsLib.exactlyOneZero(assets, shares), ...);      // amount XOR shares
require(onBehalf != address(0) | _isSenderAuthorized(...))  // who may act
_accrueInterest(marketParams, id);                          // bring state current
```

`exactlyOneZero` ([`UtilsLib.sol:13-17`](morpho-blue/src/libraries/UtilsLib.sol#L13-L17))
is `xor(iszero(x), iszero(y))` in assembly. It forces the caller to specify
*either* an exact asset amount *or* an exact share amount, never both and never
neither. This is how Morpho gets exact-in and exact-out semantics from one
function signature instead of two.

### Owner functions

| Function | Line | What it does | Guard |
|---|---|---|---|
| `setOwner` | [`:95`](morpho-blue/src/Morpho.sol#L95) | Transfers ownership. **Single-step, and the zero address is allowed** ([`IMorpho.sol:81-82`](morpho-blue/src/interfaces/IMorpho.sol#L81-L82)) | `onlyOwner`, `newOwner != owner` |
| `enableIrm` | [`:104`](morpho-blue/src/Morpho.sol#L104) | Whitelists an IRM. **Irreversible.** | `onlyOwner`, not already set |
| `enableLltv` | [`:113`](morpho-blue/src/Morpho.sol#L113) | Whitelists an LLTV value. **Irreversible.** Requires `lltv < WAD` | `onlyOwner` |
| `setFee` | [`:123`](morpho-blue/src/Morpho.sol#L123) | Sets a market's fee, `<= MAX_FEE` (25%). Accrues interest *first* at the old fee ([`:130`](morpho-blue/src/Morpho.sol#L130)) | `onlyOwner` |
| `setFeeRecipient` | [`:139`](morpho-blue/src/Morpho.sol#L139) | Global fee recipient. May be zero, in which case fees are lost ([`IMorpho.sol:99`](morpho-blue/src/interfaces/IMorpho.sol#L99)) | `onlyOwner` |

The ordering in `setFee` is the kind of detail worth noticing: accrue at the old
rate, *then* change it. Aave does the same thing in `updateState` before any
configurator change, but has to say so across several logic libraries.

### `createMarket` — [`:150-164`](morpho-blue/src/Morpho.sol#L150-L164)

**Inputs:** `MarketParams`. **Anyone may call.**

**Checks:** IRM whitelisted, LLTV whitelisted, market not already created
(`lastUpdate == 0` is the "does not exist" sentinel).

**Writes:** `market[id].lastUpdate = block.timestamp`, `idToMarketParams[id]`.

**External call:** the last line is subtle —

```solidity
if (marketParams.irm != address(0)) IIrm(marketParams.irm).borrowRate(marketParams, market[id]);
```

It calls the IRM once at creation so a *stateful* IRM can initialise itself.
Note also that `irm == address(0)` is legal, and produces a market where interest
never accrues (see `_accrueInterest`). That is a deliberate feature for markets
that only need collateralised borrowing at zero rate.

### `supply` — [`:169-197`](morpho-blue/src/Morpho.sol#L169-L197)

**Inputs:** `marketParams`, `assets` XOR `shares`, `onBehalf`, `data`.

**Checks:** market exists; exactly one of assets/shares; `onBehalf != 0`.
Note there is **no authorization check** — supplying on someone else's behalf is
a gift, so it needs no permission.

**Conversion** ([`:183-184`](morpho-blue/src/Morpho.sol#L183-L184)):

```solidity
if (assets > 0) shares = assets.toSharesDown(totalSupplyAssets, totalSupplyShares);
else            assets = shares.toAssetsUp(totalSupplyAssets, totalSupplyShares);
```

Rounding always favours the protocol: you get shares rounded *down*, or you pay
assets rounded *up*.

**Writes:** `position.supplyShares +=`, `market.totalSupplyShares +=`,
`market.totalSupplyAssets +=`.

**Then, in this order:** emit, *then* optionally call back
`onMorphoSupply(assets, data)` on `msg.sender`, *then* `safeTransferFrom`. The
callback fires **before** the pull, which is what makes it useful (§4).

### `withdraw` — [`:200-230`](morpho-blue/src/Morpho.sol#L200-L230)

Mirror of `supply`, with two differences. It requires
`_isSenderAuthorized(onBehalf)` ([`:212`](morpho-blue/src/Morpho.sol#L212)), and
after decrementing it asserts liquidity
([`:223`](morpho-blue/src/Morpho.sol#L223)):

```solidity
require(market[id].totalBorrowAssets <= market[id].totalSupplyAssets, INSUFFICIENT_LIQUIDITY);
```

That single line is Morpho's entire utilisation guard. Aave achieves the same
through `virtualUnderlyingBalance` bookkeeping
([`DataTypes.sol:73`](../aave/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol#L73)).

No callback here, and none on `borrow` either: both push tokens out, so there is
nothing to be gained by handing control back early.

### `borrow` — [`:235-266`](morpho-blue/src/Morpho.sol#L235-L266)

**Checks:** market exists, XOR, `receiver != 0`, sender authorized for `onBehalf`.

**Writes:** `position.borrowShares +=`, `totalBorrowShares +=`,
`totalBorrowAssets +=`.

**Then two post-conditions** ([`:258-259`](morpho-blue/src/Morpho.sol#L258-L259)):
health, then liquidity. Both are checked *after* the writes, which is the
cleanest way to express "the resulting state must be valid".

Compare the health check with Aave's. Morpho's is
[`_isHealthy`](morpho-blue/src/Morpho.sol#L527), thirteen lines, one oracle call,
one market. Aave's is `calculateUserAccountData`
([`GenericLogic.sol:65`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/GenericLogic.sol#L65)),
which loops every reserve the user touches, reads a price for each, and computes
weighted-average LTV and liquidation threshold. Morpho does not need the loop
because a position cannot span markets.

### `repay` — [`:269-298`](morpho-blue/src/Morpho.sol#L269-L298)

Mirror of `borrow`, no authorization needed (repaying is a gift), callback before
the pull. One line deserves attention
([`:288`](morpho-blue/src/Morpho.sol#L288)):

```solidity
market[id].totalBorrowAssets = UtilsLib.zeroFloorSub(market[id].totalBorrowAssets, assets).toUint128();
```

`zeroFloorSub` is saturating subtraction. The comment on the next line explains
why: *"`assets` may be greater than `totalBorrowAssets` by 1"*, a consequence of
rounding up when converting shares to assets. Without the floor, the last
repayment in a market could revert on underflow.

### `supplyCollateral` — [`:303-320`](morpho-blue/src/Morpho.sol#L303-L320)

Notable for what it **omits**: no interest accrual, with the comment *"Don't
accrue interest because it's not required and it saves gas"*
([`:311`](morpho-blue/src/Morpho.sol#L311)). Adding collateral cannot make a
position unhealthy and does not affect the rate, so the accrual is pure cost.
Callback then pull, same as `supply`.

### `withdrawCollateral` — [`:323-342`](morpho-blue/src/Morpho.sol#L323-L342)

Does accrue, because removing collateral can make a position unhealthy and the
health check must run against current debt. Authorization required, health
checked after the write ([`:337`](morpho-blue/src/Morpho.sol#L337)).

### `flashLoan` — [`:422-432`](morpho-blue/src/Morpho.sol#L422-L432)

Eleven lines, and **zero fee**:

```solidity
function flashLoan(address token, uint256 assets, bytes calldata data) external {
    require(assets != 0, ErrorsLib.ZERO_ASSETS);
    emit EventsLib.FlashLoan(msg.sender, token, assets);
    IERC20(token).safeTransfer(msg.sender, assets);
    IMorphoFlashLoanCallback(msg.sender).onMorphoFlashLoan(assets, data);
    IERC20(token).safeTransferFrom(msg.sender, address(this), assets);
}
```

It is not per-market — it lends any token the contract holds, across all markets.
There is no explicit repayment check: the final `safeTransferFrom` reverts if the
borrower cannot pay, and that is the whole enforcement. Contrast with Aave's
`FlashLoanLogic`, which handles premiums, a protocol share, and the mode-2 path
that converts a flash loan into a debt position.

### `setAuthorization` / `setAuthorizationWithSig` — [`:437`](morpho-blue/src/Morpho.sol#L437), [`:446`](morpho-blue/src/Morpho.sol#L446)

Authorization is **global, not per-market**: `isAuthorized[authorizer][authorized]`
grants control of *every* position that address holds, on every market. This is a
deliberate simplification with real teeth — see §8.

The signature path checks deadline, then consumes the nonce with a post-increment
inside the comparison ([`:449`](morpho-blue/src/Morpho.sol#L449)):

```solidity
require(authorization.nonce == nonce[authorization.authorizer]++, INVALID_NONCE);
```

The comment above it is worth reading: the "already set" check is deliberately
skipped *because the nonce increment is a desired side effect*
([`:447`](morpho-blue/src/Morpho.sol#L447)) — it lets a signer burn a nonce to
invalidate an outstanding signature.

### `accrueInterest` / `_accrueInterest` — [`:474`](morpho-blue/src/Morpho.sol#L474), [`:483-509`](morpho-blue/src/Morpho.sol#L483-L509)

The whole interest engine:

```solidity
uint256 elapsed = block.timestamp - market[id].lastUpdate;
if (elapsed == 0) return;

if (marketParams.irm != address(0)) {
    uint256 borrowRate = IIrm(marketParams.irm).borrowRate(marketParams, market[id]);
    uint256 interest = market[id].totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
    market[id].totalBorrowAssets += interest.toUint128();
    market[id].totalSupplyAssets += interest.toUint128();
    ...
}
market[id].lastUpdate = uint128(block.timestamp);
```

Three things follow from this that are worth stating plainly.

First, **there are no indexes**. Aave maintains `liquidityIndex` and
`variableBorrowIndex` in ray, and every balance is a scaled value multiplied by
one of them. Morpho instead grows `totalBorrowAssets` and `totalSupplyAssets`
directly, and share price emerges from the ratio of assets to shares. Fewer moving
parts, and the share/asset ratio is the index.

Second, **suppliers and borrowers see the same accrual**. The exact `interest`
added to borrowers is added to suppliers. Aave splits these: suppliers accrue
linearly, borrowers compound. Here there is one number.

Third, the **fee is taken as shares, not assets**
([`:494-502`](morpho-blue/src/Morpho.sol#L494-L502)):

```solidity
uint256 feeAmount = interest.wMulDown(market[id].fee);
feeShares = feeAmount.toSharesDown(market[id].totalSupplyAssets - feeAmount, market[id].totalSupplyShares);
position[id][feeRecipient].supplyShares += feeShares;
market[id].totalSupplyShares += feeShares.toUint128();
```

The `- feeAmount` in the denominator is the subtle part, and the comment explains
it: `totalSupplyAssets` has *already* been increased by the full interest
including the fee, so the conversion must use the pre-fee total to avoid the
recipient's shares diluting themselves. Aave's equivalent is `_accrueToTreasury`,
which mints scaled aTokens to the treasury on the same principle.

### `_isHealthy` — [`:515-539`](morpho-blue/src/Morpho.sol#L515-L539)

Two overloads. The outer one short-circuits for zero debt and fetches the price;
the inner one takes the price as an argument so `liquidate` can fetch it once and
reuse it. The core is four lines:

```solidity
uint256 borrowed = uint256(position[id][borrower].borrowShares)
    .toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
uint256 maxBorrow = uint256(position[id][borrower].collateral)
    .mulDivDown(collateralPrice, ORACLE_PRICE_SCALE)
    .wMulDown(marketParams.lltv);
return maxBorrow >= borrowed;
```

Debt rounds **up**, collateral value rounds **down**, `lltv` multiplication
rounds **down**. Every rounding decision is against the borrower. The docstring
says so explicitly ([`:526`](morpho-blue/src/Morpho.sol#L526)): *"Rounds in favor
of the protocol, so one might not be able to borrow exactly `maxBorrow` but one
unit less."*

### `extSloads` — [`:544-556`](morpho-blue/src/Morpho.sol#L544-L556)

Raw `sload` of arbitrary slots, batched. Because Morpho has no getter for every
derived quantity, off-chain consumers and periphery libraries compute slot
addresses themselves — see
[`morpho-blue/src/libraries/periphery/MorphoStorageLib.sol`](morpho-blue/src/libraries/periphery/MorphoStorageLib.sol).
This is the same trick as Uniswap v4's `Extsload`: pay for storage layout
knowledge off-chain, save bytecode on-chain.

---
