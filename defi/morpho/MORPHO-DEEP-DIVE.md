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

## 3. The accounting

### Shares and the virtual offset

All four conversions live in 18 lines
([`morpho-blue/src/libraries/SharesMathLib.sol:27-44`](morpho-blue/src/libraries/SharesMathLib.sol#L27-L44)),
and every one of them adds a constant to both sides of the ratio:

```solidity
uint256 internal constant VIRTUAL_SHARES = 1e6;
uint256 internal constant VIRTUAL_ASSETS = 1;

function toSharesDown(uint256 assets, uint256 totalAssets, uint256 totalShares) internal pure returns (uint256) {
    return assets.mulDivDown(totalShares + VIRTUAL_SHARES, totalAssets + VIRTUAL_ASSETS);
}
```

**Why this defeats the donation attack.** The classic first-depositor exploit
against a naive vault runs like this. The attacker deposits 1 wei and receives
1 share, so the pool is `1 asset / 1 share`. They then *donate* 10,000 tokens
directly to the contract, making it `10,001 assets / 1 share`. A victim
depositing 10,000 tokens now computes `10,000 * 1 / 10,001 = 0` shares by
integer division, and the attacker redeems their single share for everything.

The attack needs the share price to be movable to an arbitrary height from a
starting point of one. The virtual offset makes that impossible. Redo the
arithmetic with `VIRTUAL_SHARES = 1e6` and `VIRTUAL_ASSETS = 1`: the empty market
starts at `(0 + 1) assets / (0 + 1e6) shares`, so the very first depositor
receives a million shares per asset, not one. After the same 10,000-token
donation the ratio is `10,001 / (1e6 + 1e6)`, and the victim's 10,000 tokens
still buy `10,000 * 2e6 / 10,001 ≈ 1.999e6` shares. The attacker's slice of the
pool is unchanged. The offset costs the attacker a factor of `1e6` in capital to
move the price one step, which makes the attack strictly unprofitable rather than
merely harder.

Two consequences the source is candid about
([`SharesMathLib.sol:17-19`](morpho-blue/src/libraries/SharesMathLib.sol#L17-L19)):
the virtual shares can never be redeemed, and the assets backing virtual *borrow*
shares "behave like unrealizable bad debt". Both are rounding dust, deliberately
stranded.

**Compare with Aave.** Aave solves the same class of problem differently, with
`virtualUnderlyingBalance`
([`DataTypes.sol:73`](../aave/aave-v3-origin/src/contracts/protocol/libraries/types/DataTypes.sol#L73)),
a tracked balance that ignores direct token donations entirely. Aave's approach
is to make the contract blind to gifts; Morpho's is to make gifts economically
pointless. Aave's needs a storage slot per reserve and bookkeeping on every
transfer path; Morpho's needs two `constant`s and costs nothing.

### `wTaylorCompounded` — continuous compounding on a budget

[`morpho-blue/src/libraries/MathLib.sol:38-44`](morpho-blue/src/libraries/MathLib.sol#L38-L44):

```solidity
function wTaylorCompounded(uint256 x, uint256 n) internal pure returns (uint256) {
    uint256 firstTerm = x * n;
    uint256 secondTerm = mulDivDown(firstTerm, firstTerm, 2 * WAD);
    uint256 thirdTerm = mulDivDown(secondTerm, firstTerm, 3 * WAD);

    return firstTerm + secondTerm + thirdTerm;
}
```

**The derivation.** Continuously compounded growth over `n` seconds at rate `x`
per second is `e^(xn)`, and the *interest* is `e^(xn) − 1`. Expanding the
exponential:

```
e^z − 1 = z + z²/2! + z³/3! + z⁴/4! + …      where z = x·n
```

The function keeps the first three terms. `firstTerm` is `z`, `secondTerm` is
`z²/2` (computed as `z·z/2` in WAD), `thirdTerm` is `z³/6` (computed as
`(z²/2)·z/3`, since `(z²/2)/3 = z³/6`). Truncation is downward at each `mulDivDown`,
so the result always *understates* interest — in the borrower's favour, which is
the safe direction for an approximation that could otherwise let debt exceed
what the model justifies.

**Error bound.** The tail is `Σ(k≥4) z^k/k! < z⁴/4! · 1/(1−z/5)` for `z < 5`. At
a 100% APR rate accruing over a full day, `z = 1.0 · (1/365) ≈ 0.00274`, and the
first omitted term is `z⁴/24 ≈ 2.3e-12` — twelve decimal places down, utterly
negligible. Even at an extreme `z = 0.5` (a position untouched long enough to
accrue 50% in one accrual), the error is `0.5⁴/24 ≈ 0.26%`, still an
understatement. The approximation degrades gracefully precisely because every
omitted term is positive.

**Compare with Aave.** Aave's `calculateCompoundedInterest`
([`MathUtils.sol:79-84`](../aave/aave-v3-origin/src/contracts/protocol/libraries/math/MathUtils.sol#L79-L84))
does the same job with the same number of terms, written as a nested Horner form:

```solidity
uint256 x = (rate * exp) / SECONDS_PER_YEAR;
return WadRayMath.RAY + x + x.rayMul(x / 2 + x.rayMul(x / 6));
```

Expand it: `1 + x + x·(x/2 + x·(x/6)) = 1 + x + x²/2 + x³/6`. Identical
mathematics. Two differences worth noting. Aave returns the *ratio* (`RAY + …`)
because it multiplies an index by it; Morpho returns the *interest fraction*
because it multiplies a balance by it. And Aave divides the annual rate by
`SECONDS_PER_YEAR` inside the function, whereas Morpho's IRM already returns a
per-second rate. Aave's own comment
([`MathUtils.sol:62-70`](../aave/aave-v3-origin/src/contracts/protocol/libraries/math/MathUtils.sol#L62-L70))
is unusually frank that the polynomial diverges badly at absurd inputs, and
explains why they accept it.

### The market id

[`MarketParamsLib.sol:13`](morpho-blue/src/libraries/MarketParamsLib.sol#L13)
hard-codes `MARKET_PARAMS_BYTES_LENGTH = 5 * 32`, then hashes exactly that many
bytes from the struct's memory pointer. Because `MarketParams` is five
word-sized fields with no dynamic types, its memory layout is exactly 160
contiguous bytes and the assembly `keccak256(marketParams, 160)` is safe. Add a
sixth field and the constant silently becomes wrong — which is a good argument
for why this struct will never gain a field.

### Struct layout

[`IMorpho.sol:16-33`](morpho-blue/src/interfaces/IMorpho.sol#L16-L33):

| Struct | Field | Type | Slots |
|---|---|---|---|
| `Position` | `supplyShares` | `uint256` | slot 0 (full) |
| | `borrowShares` | `uint128` | slot 1, low half |
| | `collateral` | `uint128` | slot 1, high half |
| `Market` | `totalSupplyAssets` | `uint128` | slot 0, low |
| | `totalSupplyShares` | `uint128` | slot 0, high |
| | `totalBorrowAssets` | `uint128` | slot 1, low |
| | `totalBorrowShares` | `uint128` | slot 1, high |
| | `lastUpdate` | `uint128` | slot 2, low |
| | `fee` | `uint128` | slot 2, high |

A `Position` is two slots; a whole `Market` is three. Every read in
`_accrueInterest` or `_isHealthy` touches at most those three. `supplyShares` is
the only `uint256` — because supply shares carry the `1e6` virtual multiplier and
can grow large, whereas borrow shares are bounded by `uint128` casts via
`toUint128` ([`UtilsLib.sol:27-30`](morpho-blue/src/libraries/UtilsLib.sol#L27-L30)),
which reverts rather than truncating.

Contrast with Aave's `ReserveData`, which is a dozen fields plus a packed
configuration word plus two external token contracts holding the actual balances.

---

## 4. The callback pattern

Four of Morpho's functions hand control to `msg.sender` **before** pulling
tokens, and one hands it over before demanding repayment. The interfaces are all
in [`morpho-blue/src/interfaces/IMorphoCallbacks.sol`](morpho-blue/src/interfaces/IMorphoCallbacks.sol):

| Callback | Fired by | Line | Fired before |
|---|---|---|---|
| `onMorphoSupply` | `supply` | [`Morpho.sol:192`](morpho-blue/src/Morpho.sol#L192) | `safeTransferFrom` of loan token |
| `onMorphoRepay` | `repay` | [`Morpho.sol:293`](morpho-blue/src/Morpho.sol#L293) | `safeTransferFrom` of loan token |
| `onMorphoSupplyCollateral` | `supplyCollateral` | [`Morpho.sol:317`](morpho-blue/src/Morpho.sol#L317) | `safeTransferFrom` of collateral |
| `onMorphoLiquidate` | `liquidate` | [`Morpho.sol:412`](morpho-blue/src/Morpho.sol#L412) | `safeTransferFrom` of repayment |
| `onMorphoFlashLoan` | `flashLoan` | [`Morpho.sol:429`](morpho-blue/src/Morpho.sol#L429) | `safeTransferFrom` of repayment |

Each is gated on `if (data.length > 0)`, so the cost is one `CALLDATASIZE` check
when unused.

**Why the ordering is the whole trick.** State is already written when the
callback fires. So inside `onMorphoSupplyCollateral` your collateral is already
credited, which means you can already borrow against it — and you can use the
borrowed funds to acquire the very collateral you are about to be charged for.
That is one-transaction leverage with no flash loan and no intermediary:

```
User calls supplyCollateral(market, 5 WETH, user, data)
  |
  |-- position.collateral += 5 WETH          (credited already)
  |-- emit SupplyCollateral
  |-- onMorphoSupplyCollateral(5 WETH, data) --> back in user's contract
  |     |-- Morpho.borrow(market, 9000 USDC, 0, user, user)
  |     |     `-- health check passes: collateral is already there
  |     |-- swap 9000 USDC -> 3 WETH on a DEX
  |     `-- (user now holds the WETH needed to settle)
  |
  `-- safeTransferFrom(user, Morpho, 5 WETH)  <-- settles with 2 own + 3 bought
```

Deleveraging is the mirror image through `onMorphoRepay`: your debt is already
reduced when the callback fires, so you can withdraw the freed collateral, sell
it, and use the proceeds to fund the repayment that is about to be pulled.

A collateral swap is the same shape again: `supplyCollateral` the new asset,
inside the callback `withdrawCollateral` the old one and sell it.

**What this replaces.** Aave needs a *contract per operation*. In
`aave/v2-protocol/contracts/adapters/` there is a `BaseUniswapAdapter`, a
`UniswapLiquiditySwapAdapter`, a `UniswapRepayAdapter`, a
`FlashLiquidationAdapter`, a `ParaSwapLiquiditySwapAdapter` — hundreds of lines
each, every one a bespoke flash-loan choreography with its own approval handling
and its own audit surface. Aave v2 also had flash-loan "mode 1/2", which lets a
flash loan terminate as a debt position instead of being repaid, precisely
because the callback alone was not expressive enough.

Morpho needs none of them. There is one generic hook per operation, and the
periphery becomes optional convenience rather than required plumbing. The
bundlers repo is exactly that convenience layer, and it is thin: `MorphoBundler`
implements all four callbacks by simply re-entering its own multicall
([`morpho-blue-bundlers/src/MorphoBundler.sol:261-266`](morpho-blue-bundlers/src/MorphoBundler.sol#L261-L266)),
so a callback body is just "more bundled actions".

**The safety argument.** Handing control to `msg.sender` mid-function is the
pattern that makes reentrancy dangerous, and Morpho has no `nonReentrant`
modifier anywhere. §8 works through why that is sound here.

---

## 5. Where the removed complexity went

Nothing disappeared. It moved to places where you can decline it.

### MetaMorpho: curation as a market, not a vote

[`metamorpho/src/MetaMorpho.sol`](metamorpho/src/MetaMorpho.sol) is 911 lines —
longer than Morpho itself — and it is an ERC-4626 vault that spreads deposits
across Blue markets. This is where "which markets are safe?" gets answered.

**Four roles**, deliberately unequal
([`:67-73`](metamorpho/src/MetaMorpho.sol#L67-L73)):

| Role | Storage | Can do |
|---|---|---|
| `owner` | (from `Ownable`) | Set every other role, set fee and timelock |
| `curator` | [`:67`](metamorpho/src/MetaMorpho.sol#L67) | Submit caps, submit market removals |
| allocators | [`:70`](metamorpho/src/MetaMorpho.sol#L70) | Reorder queues, `reallocate` between approved markets |
| `guardian` | [`:73`](metamorpho/src/MetaMorpho.sol#L73) | **Revoke** pending changes during the timelock |

The asymmetry is the design. Adding risk is slow and vetoable; removing risk is
instant. `submitCap` ([`:273`](metamorpho/src/MetaMorpho.sol#L273)) only queues a
`PendingUint192`; it takes effect via `acceptCap`
([`:470`](metamorpho/src/MetaMorpho.sol#L470)) behind the `afterTimelock`
modifier ([`:176`](metamorpho/src/MetaMorpho.sol#L176)). The timelock is bounded
to between 1 day and 2 weeks
([`metamorpho/src/libraries/ConstantsLib.sol:10-13`](metamorpho/src/libraries/ConstantsLib.sol#L10-L13)).
Meanwhile an allocator can pull funds out of a market immediately, and the
guardian can kill a pending cap increase with no delay.

**Two queues**, both capped at 30 entries
([`ConstantsLib.sol:16`](metamorpho/src/libraries/ConstantsLib.sol#L16)):
`supplyQueue` is the order deposits fill markets
([`:100`](metamorpho/src/MetaMorpho.sol#L100)), `withdrawQueue` is the order
withdrawals drain them ([`:103`](metamorpho/src/MetaMorpho.sol#L103)).
`_supplyMorpho` ([`:775-804`](metamorpho/src/MetaMorpho.sol#L775-L804)) walks the
supply queue filling each market up to its `cap`, and reverts `AllCapsReached` if
the deposit does not fit. Both loops wrap the Morpho call in `try/catch` — *"Using
try/catch to skip markets that revert"* — so one broken market cannot brick the
whole vault.

`totalAssets` ([`:589-593`](metamorpho/src/MetaMorpho.sol#L589-L593)) is a plain
loop over the withdraw queue summing `expectedSupplyAssets`. That is why the
queue length is capped at 30: it bounds the gas of every ERC-4626 view.

The vault fee is taken as shares on interest only, with the same pre-fee
denominator trick as Morpho's market fee
([`:898-911`](metamorpho/src/MetaMorpho.sol#L898-L911)), and is capped at 50%
([`ConstantsLib.sol:19`](metamorpho/src/libraries/ConstantsLib.sol#L19)).

**The governance point.** In Aave, if you dislike a risk parameter your recourse
is to win a DAO vote. In Morpho, your recourse is to withdraw from this curator's
vault and deposit in another. Curation becomes a competitive market with exit
rather than a political process with voice. Whether that is better depends on
whether depositors actually evaluate curators — see §7.

### Oracles: the market's trust anchor, chosen at creation

[`morpho-blue/src/interfaces/IOracle.sol:14`](morpho-blue/src/interfaces/IOracle.sol#L14)
is the entire oracle contract requirement:

```solidity
function price() external view returns (uint256);
```

One function, returning the price of one collateral token in loan tokens, scaled
by `1e36`. No `latestRoundData`, no staleness field, no round id. Whatever
sanity-checking exists must live inside the oracle, because core will not do it.
The interface docstring is blunt about ownership of that risk
([`IOracle.sol:8`](morpho-blue/src/interfaces/IOracle.sol#L8)): *"It is the
user's responsibility to select markets with safe oracles."*

`MorphoChainlinkOracleV2` ([`morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol:151-156`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol#L151-L156))
is the reference implementation, and it is a *composition* engine: up to two
Chainlink feeds on the base side, two on the quote side, plus an optional
ERC-4626 vault on each side to handle share-price assets.

```solidity
function price() external view returns (uint256) {
    return SCALE_FACTOR.mulDiv(
        BASE_VAULT.getAssets(BASE_VAULT_CONVERSION_SAMPLE) * BASE_FEED_1.getPrice() * BASE_FEED_2.getPrice(),
        QUOTE_VAULT.getAssets(QUOTE_VAULT_CONVERSION_SAMPLE) * QUOTE_FEED_1.getPrice() * QUOTE_FEED_2.getPrice()
    );
}
```

All the decimal reconciliation is folded into `SCALE_FACTOR`, computed once in
the constructor. The derivation is spelled out in a 25-line comment
([`:113-137`](morpho-blue-oracles/src/morpho-chainlink/MorphoChainlinkOracleV2.sol#L113-L137))
ending at
`SCALE_FACTOR = 1e(36 + dQ1 + fpQ1 + fpQ2 − dB1 − fpB1 − fpB2)`. Doing this at
deploy time rather than per call is why `price()` is four multiplications.

The wstETH adapter
([`morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol:26-29`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L26-L29))
is a nice illustration of what "oracle" can mean here — it is not a price feed at
all, it is Lido's own exchange rate dressed as one:

```solidity
function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
    return (0, int256(ST_ETH.getPooledEthByShares(1 ether)), 0, 0, 0);
}
```

It returns zero for `roundId`, `startedAt`, `updatedAt` and `answeredInRound`.
Any consumer checking staleness would reject it; Morpho does not check, so it
works. That is the trade in miniature.

### The IRM: pluggable, and allowed to have state

[`morpho-blue/src/interfaces/IIrm.sol:13-18`](morpho-blue/src/interfaces/IIrm.sol#L13-L18)
requires two functions: `borrowRate` (non-view, may write) and `borrowRateView`
(view). Morpho calls the mutating one from `_accrueInterest`
([`Morpho.sol:488`](morpho-blue/src/Morpho.sol#L488)) and once at market creation
([`:163`](morpho-blue/src/Morpho.sol#L163)) so a stateful model can initialise.

The interface is deliberately permissive: the IRM receives the full `Market`
struct and may keep its own history, which is how Morpho's adaptive-curve model
targets a utilisation over time rather than reading it off a fixed kink. What an
IRM may *not* do is re-enter Morpho — that is listed as a market-creation
assumption ([`IMorpho.sol:113`](morpho-blue/src/interfaces/IMorpho.sol#L113)),
not enforced in code.

Aave's equivalent is a single blessed strategy contract per reserve
([`DefaultReserveInterestRateStrategyV2.sol:124`](../aave/aave-v3-origin/src/contracts/misc/DefaultReserveInterestRateStrategyV2.sol#L124)),
swappable by the risk admin. Morpho's is fixed per market but freely chosen at
creation from the owner's whitelist.

### Bundlers: the UX layer

[`morpho-blue-bundlers/src/BaseBundler.sol:51-59`](morpho-blue-bundlers/src/BaseBundler.sol#L51-L59)
is a `multicall` that records the initiator for the duration of the call:

```solidity
function multicall(bytes[] memory data) external payable {
    require(_initiator == UNSET_INITIATOR, ErrorsLib.ALREADY_INITIATED);
    _initiator = msg.sender;
    _multicall(data);
    _initiator = UNSET_INITIATOR;
}
```

The `protected` modifier ([`:31`](morpho-blue-bundlers/src/BaseBundler.sol#L31))
then rejects any call arriving outside that window, which is what stops someone
calling an individual bundler action directly with someone else's approvals.
`MorphoBundler` layers permit, supply, borrow, repay and flash-loan actions on
top, and the migration bundlers move whole positions out of Aave v2, Aave v3,
Compound v2 and Compound v3 in one transaction
([`morpho-blue-bundlers/src/migration/`](morpho-blue-bundlers/src/migration/)).

---

## 6. Liquidation

The whole function is [`Morpho.sol:347-417`](morpho-blue/src/Morpho.sol#L347-L417),
about seventy lines. Aave's `executeLiquidationCall` starts at
[`LiquidationLogic.sol:166`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L166)
and runs past line 460, with a second helper at
[`:583`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L583)
and a deficit routine at
[`:76`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L76).

### The incentive factor

[`Morpho.sol:365-369`](morpho-blue/src/Morpho.sol#L365-L369):

```solidity
// The liquidation incentive factor is min(maxLiquidationIncentiveFactor, 1/(1 - cursor*(1 - lltv))).
uint256 liquidationIncentiveFactor = UtilsLib.min(
    MAX_LIQUIDATION_INCENTIVE_FACTOR,
    WAD.wDivDown(WAD - LIQUIDATION_CURSOR.wMulDown(WAD - marketParams.lltv))
);
```

With `LIQUIDATION_CURSOR = 0.3e18` and `MAX_LIQUIDATION_INCENTIVE_FACTOR = 1.15e18`
([`ConstantsLib.sol:11-14`](morpho-blue/src/libraries/ConstantsLib.sol#L11-L14)),
the LIF is a **pure function of LLTV**. Nobody sets it:

| `lltv` | `1 − lltv` | LIF | Liquidator margin |
|---|---|---|---|
| 0.98 | 0.02 | 1.0060 | 0.60% |
| 0.945 | 0.055 | 1.0168 | 1.68% |
| 0.86 | 0.14 | 1.0438 | 4.38% |
| 0.77 | 0.23 | 1.0742 | 7.42% |
| 0.625 | 0.375 | 1.1268 → capped **1.15** | 15% |
| 0.30 | 0.70 | 1.2658 → capped **1.15** | 15% |

The shape is right: a riskier market (lower LLTV, bigger gap to insolvency) pays
a bigger bounty, because the collateral it holds is more volatile and the
liquidator's inventory risk is larger. The cap stops the bounty from eating the
borrower alive in very low-LLTV markets.

Aave instead stores a per-asset `liquidationBonus` in the config bitmap
([`ReserveConfiguration.sol:15`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/ReserveConfiguration.sol#L15))
that the risk admin tunes, and then takes a cut of it for the protocol via
`liquidationProtocolFee`
([`LiquidationLogic.sol:614-622`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L614-L622)).
Morpho derives the number and keeps none of it.

### Direction: seize-exact or repay-exact

Same XOR pattern as everywhere else
([`:356`](morpho-blue/src/Morpho.sol#L356)) — specify `seizedAssets` or
`repaidShares`, never both. The two branches invert each other
([`:371-380`](morpho-blue/src/Morpho.sol#L371-L380)):

```solidity
if (seizedAssets > 0) {
    uint256 seizedAssetsQuoted = seizedAssets.mulDivUp(collateralPrice, ORACLE_PRICE_SCALE);
    repaidShares = seizedAssetsQuoted.wDivUp(liquidationIncentiveFactor)
        .toSharesUp(market[id].totalBorrowAssets, market[id].totalBorrowShares);
} else {
    seizedAssets = repaidShares.toAssetsDown(market[id].totalBorrowAssets, market[id].totalBorrowShares)
        .wMulDown(liquidationIncentiveFactor)
        .mulDivDown(ORACLE_PRICE_SCALE, collateralPrice);
}
```

Every rounding favours the protocol: seize-exact rounds the repayment *up*,
repay-exact rounds the seizure *down*.

**There is no close factor.** A liquidator may repay the entire debt in one call.
Aave caps a single liquidation at 50% unless the health factor is below
`CLOSE_FACTOR_HF_THRESHOLD = 0.95e18`
([`LiquidationLogic.sol:43`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L43),
[`:49`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L49)),
and further insists the leftovers exceed `MIN_LEFTOVER_BASE`
([`:64`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L64))
to avoid stranding dust positions.

Why can Morpho skip all that? Because a close factor protects a borrower whose
*whole cross-collateral portfolio* would otherwise be sold to cover one bad leg.
A Morpho position is one collateral against one debt in one isolated market;
there is nothing else to protect. Partial liquidation is still possible, it is
just not mandated.

### Bad debt, socialised in eight lines

[`Morpho.sol:392-403`](morpho-blue/src/Morpho.sol#L392-L403):

```solidity
if (position[id][borrower].collateral == 0) {
    badDebtShares = position[id][borrower].borrowShares;
    badDebtAssets = UtilsLib.min(
        market[id].totalBorrowAssets,
        badDebtShares.toAssetsUp(market[id].totalBorrowAssets, market[id].totalBorrowShares)
    );

    market[id].totalBorrowAssets -= badDebtAssets.toUint128();
    market[id].totalSupplyAssets -= badDebtAssets.toUint128();
    market[id].totalBorrowShares -= badDebtShares.toUint128();
    position[id][borrower].borrowShares = 0;
}
```

The trigger is simply "collateral hit zero and debt remains". The loss is written
off *immediately*, in the same transaction, by reducing `totalSupplyAssets`.
Every supplier in that market takes a proportional haircut instantly — their
share count is unchanged, but each share is now worth less.

Aave cannot do this, because its suppliers are pooled across the whole market and
an instant write-down would be a bank run trigger. So it books the shortfall into
`reserve.deficit`
([`LiquidationLogic.sol:538`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L538))
and covers it later out of treasury or Umbrella via `executeEliminateDeficit`
([`:76`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L76),
[`:119`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L119)).
That is a whole subsystem — accrual, tracking, an elimination path, a funding
source — that exists because losses cannot be localised. Morpho's isolation makes
the write-down cheap enough to do inline.

### Call ordering

[`:410-414`](morpho-blue/src/Morpho.sol#L410-L414) — collateral goes out
**first**, then the callback, then the repayment is pulled:

```solidity
IERC20(marketParams.collateralToken).safeTransfer(msg.sender, seizedAssets);
if (data.length > 0) IMorphoLiquidateCallback(msg.sender).onMorphoLiquidate(repaidAssets, data);
IERC20(marketParams.loanToken).safeTransferFrom(msg.sender, address(this), repaidAssets);
```

So a liquidator needs **no capital**: receive the WETH, sell it inside the
callback, repay the USDC from the proceeds. Aave's equivalent is the separate
`FlashLiquidationAdapter` contract.

### Worked example, continuing §0

Bob: 10 WETH collateral, 24,000 USDC debt, ETH at $2,700, `lltv = 0.86`,
LIF = 1.0438.

**Partial.** Liquidator repays 10,000 USDC. Seized =
`10,000 × 1.0438 × 1e36 / 2.7e24 = 3.866 WETH` ($10,438). Bob keeps 6.134 WETH
($16,562) against 14,000 USDC debt; `maxBorrow = 6.134 × 2700 × 0.86 = 14,243`,
so he is healthy again by a hair.

**Full.** Liquidator repays all 24,000. Seized =
`24,000 × 1.0438 × 1e36 / 2.7e24 = 9.278 WETH` ($25,051). Bob keeps 0.722 WETH.
No bad debt, because collateral did not reach zero.

**Insolvent.** Now suppose ETH gapped to $2,300 before anyone acted. Bob's 10 WETH
is worth $23,000 against 24,000 debt. A liquidator seizing everything gets
$23,000 of WETH for `23,000 / 1.0438 = 22,035` USDC repaid — still profitable.
Collateral is now zero with 1,965 USDC of debt outstanding, so the branch above
fires: `totalBorrowAssets` and `totalSupplyAssets` both drop by 1,965, and the
market's suppliers eat it immediately. If Alice was the only supplier of
100,000 USDC, her position is now worth 98,035.

---

## 7. What this design costs

The minimalism is not free. Five things Aave gives you that Morpho does not, and
they are real.

### Capital fragmentation

One market is one collateral against one loan asset. WETH/USDC at `lltv = 0.86`
and WETH/USDC at `lltv = 0.945` are **different markets with different ids and
separate liquidity**. Aave has one USDC reserve that every collateral type
borrows from.

The practical consequence: a supplier who wants WETH/USDC exposure must pick a
specific LLTV, and their capital sits idle if borrowers concentrate elsewhere.
MetaMorpho exists mostly to paper over this — its `supplyQueue`
([`metamorpho/src/MetaMorpho.sol:100`](metamorpho/src/MetaMorpho.sol#L100)) is
literally a manual answer to "which of these fragmented markets should my money
be in today". Aave solves the same problem structurally, for free, by not
fragmenting.

### No cross-collateral positions

In Aave a user posts WETH, wstETH and WBTC, and borrows USDC against the combined
value; `calculateUserAccountData`
([`GenericLogic.sol:65`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/GenericLogic.sol#L65))
loops over every reserve the user has touched and produces one health factor.

Morpho's `_isHealthy` ([`Morpho.sol:515`](morpho-blue/src/Morpho.sol#L515)) reads
one collateral balance in one market. To replicate the Aave position you open
three separate markets, each independently liquidatable. You lose the
diversification benefit entirely: a WBTC crash liquidates your WBTC market even
though your other two are massively over-collateralised.

This is the sharpest trade in the whole design. Isolation is what makes
permissionless listing safe and bad debt cheap to socialise, and it is exactly
what costs the borrower cross-margining.

### No e-mode

Aave's e-mode raises LTV for correlated pairs — wstETH against WETH at 93% rather
than 80% — via `EModeConfiguration`
([`aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/EModeConfiguration.sol`](../aave/aave-v3-origin/src/contracts/protocol/libraries/configuration/EModeConfiguration.sol)).
Morpho's equivalent is simply *a market created at a high LLTV*, which is
arguably cleaner. But the owner must have enabled that LLTV first
([`Morpho.sol:113`](morpho-blue/src/Morpho.sol#L113)), and the LIF formula then
mechanically shrinks the liquidation bounty at high LLTV — 0.6% at `lltv = 0.98`,
per the table in §6. Thin bounties mean liquidators may not show up in a fast
market. Aave decouples the two knobs; Morpho ties them together by design.

### No supply or borrow caps

Aave enforces `supplyCap` and `borrowCap` from the config bitmap in
`validateSupply` and `validateBorrow`
([`ValidationLogic.sol`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/ValidationLogic.sol)).
Morpho has none: a market accepts unbounded deposits.

The cap moved up a layer. MetaMorpho's per-market `cap`
([`metamorpho/src/MetaMorpho.sol:273`](metamorpho/src/MetaMorpho.sol#L273))
limits how much *that vault* will put in, but nothing limits the market itself.
For a direct supplier there is no protection at all against a market growing
past the depth its oracle and liquidator set can support.

### No pause, no freeze, no emergency anything

There is no admin function to halt a market. Aave has `setReservePause` and
`setReserveFreeze` in `PoolConfigurator`, and a whole guardian role to use them.
Morpho's owner can do exactly four things
([`Morpho.sol:95-145`](morpho-blue/src/Morpho.sol#L95-L145)): transfer ownership,
*enable* an IRM, *enable* an LLTV, and set the fee (capped at 25%) and its
recipient. Note what is missing: there is no `disableIrm`, no `disableLltv`.
Enabling is monotonic — once an LLTV is allowed, anyone can create markets at it
forever.

If an oracle breaks, nobody can stop the market. Suppliers can withdraw whatever
liquidity is not borrowed, and that is the entire remedy. This is a deliberate
choice — immutability is the product — but it means the failure mode is *loss*
rather than *pause*.

### The scoreboard

| | Aave v3 | Morpho Blue |
|---|---|---|
| Listing | DAO vote | permissionless |
| Cross-collateral | yes | no |
| e-mode | yes | via high-LLTV markets |
| Caps | supply + borrow | none in core |
| Pause / freeze | yes | none |
| Bad debt | deficit + Umbrella | instant socialisation |
| Close factor | 50% or 100% | none |
| Rate model | admin-swappable per reserve | fixed per market, chosen at creation |
| Oracle validation | in `AaveOracle` | entirely in the oracle contract |
| Upgradeable | yes, proxies throughout | no |
| Core size | ~10,000 lines | 557 lines |

Read that table twice. Almost every "no" in the right column is a feature that
was moved rather than deleted — to MetaMorpho, to the oracle contract, to the
IRM, or to the user's own judgement. The genuine deletions are cross-collateral,
caps, and the pause switch.

---

## 8. Security notes

### Why there is no reentrancy guard

`grep -rn "nonReentrant\|ReentrancyGuard" morpho-blue/src/` returns nothing. Yet
five functions hand control to `msg.sender` mid-execution (§4). Three properties
make that sound, and it is worth being precise because copying the pattern
without them is dangerous.

**One. State is written before the callback, never after.** Look at the shape of
every callback site — `supply` at
[`:186-192`](morpho-blue/src/Morpho.sol#L186-L192) updates
`position.supplyShares`, `market.totalSupplyShares` and `market.totalSupplyAssets`,
emits, *then* calls out. A reentrant call therefore observes fully consistent
state. This is checks-effects-interactions applied strictly, and it is the whole
defence.

**Two. The only thing after the callback is a transfer of a pre-computed amount.**
Nothing is recomputed from state that reentrancy could have moved. In `supply`
the trailing line pulls exactly the `assets` decided before the callback fired.

**Three. Health is checked at the end of the functions that can worsen it.**
`borrow` ([`:264`](morpho-blue/src/Morpho.sol#L264)) and `withdrawCollateral`
([`:341`](morpho-blue/src/Morpho.sol#L341)) both assert `_isHealthy` *after* all
state changes, and `borrow`/`withdraw` additionally assert
`totalBorrowAssets <= totalSupplyAssets`. So a reentrant borrow-inside-a-callback
still has to leave the position healthy when the outer frame finishes.

The lesson generalises badly, though: this works because Morpho's post-callback
work is trivial. Aave's `executeLiquidationCall` does substantial work after its
external calls and needs its guards.

### The assumptions Morpho does not check

[`IMorpho.sol:104-125`](morpho-blue/src/interfaces/IMorpho.sol#L104-L125) is the
most important comment block in the codebase. It lists what must be true of a
market's token, IRM and oracle for the protocol to behave, and **none of it is
enforced in code**:

- Tokens must not re-enter, must not have transfer fees, must not have burn
  functions that reduce Morpho's balance.
- The IRM must not re-enter Morpho.
- The oracle must return correctly scaled prices, and — the subtle one — *"the
  oracle price should not be able to change instantly such that the new price is
  less than the old price multiplied by LLTV·LIF"*.

That last condition is the solvency criterion. If a price can gap by more than
the buffer between LLTV and full collateralisation, liquidators cannot act in
time and bad debt is created. Morpho states it and delegates it. The same comment
warns that if the loan asset is a vault that can receive donations, its shares
must not be priced by AUM — precisely the manipulation the virtual-shares offset
protects Morpho's *own* accounting against, reappearing one layer out.

**The practical takeaway.** In Aave, "is this asset safe?" was answered by
governance before you arrived. In Morpho, it is answered by whoever created the
market, and you inherit their judgement silently. `id` is a hash — two markets
that look identical in a UI can differ in oracle. Always resolve the full
`MarketParams`.

### Oracle risk is total and unmitigated

`price()` is one unvalidated `view` call. There is no staleness check, no
circuit breaker, no fallback, no deviation bound — not in core, and not
necessarily in the oracle either. The wstETH adapter in §5 returns literal zeros
for every Chainlink freshness field
([`WstEthStEthExchangeRateChainlinkAdapter.sol:26-29`](morpho-blue-oracles/src/wsteth-exchange-rate-adapter/WstEthStEthExchangeRateChainlinkAdapter.sol#L26-L29))
and Morpho accepts it happily.

Compare Aave, which at least routes everything through `AaveOracle` with a
fallback oracle. Even that is weaker than people assume — Aave **v2**'s oracle
calls `latestAnswer()` with no staleness check at all
([`aave/v2-protocol/contracts/misc/AaveOracle.sol:96`](../aave/v2-protocol/contracts/misc/AaveOracle.sol#L96)),
a finding from the v2 reference in this repo. So the honest framing is that
Morpho makes explicit a risk Aave partially obscures.

### Immutability cuts both ways

No proxy, no upgrade path, no pause. A bug in `Morpho.sol` cannot be patched, and
funds cannot be frozen while you think. The mitigations are the formal
verification in [`morpho-blue/certora/`](morpho-blue/certora/) and the fact that
557 lines is small enough to actually verify. But the risk is asymmetric: Aave's
upgradeability is itself a risk (a compromised admin can drain), whereas Morpho's
immutability is a risk only in the tail.

### Authorization and the signature path

`setAuthorization` ([`:437`](morpho-blue/src/Morpho.sol#L437)) grants another
address full power over your position — borrow, withdraw, withdraw collateral.
It is all-or-nothing, with no per-action or per-market scoping. The signature
variant ([`:446-460`](morpho-blue/src/Morpho.sol#L446-L460)) checks deadline and
a per-authorizer nonce, so replay is handled, but a signed authorization is a
blank cheque over every market you hold.

### Where the residual risk actually sits

Not in `Morpho.sol`. It sits in the market parameters, and therefore in
MetaMorpho's curators, who choose markets on depositors' behalf. The role split
(§5) is well designed — adding risk is timelocked and vetoable, removing it is
instant — but a curator can still allocate to a market with a bad oracle, and the
timelock only delays it by 1 to 14 days
([`metamorpho/src/libraries/ConstantsLib.sol:10-13`](metamorpho/src/libraries/ConstantsLib.sol#L10-L13)).
"Governance-minimised" describes the core accurately; it does not describe the
system a depositor actually faces.

---

## 9. Exercises to trace yourself

These assume you have the Aave references open alongside, since the point of
reading Morpho is the comparison.

1. **The virtual offset, by hand.** Open
   [`SharesMathLib.sol:27-44`](morpho-blue/src/libraries/SharesMathLib.sol#L27-L44).
   Run the first-depositor attack numerically on a market with
   `VIRTUAL_SHARES = 1e6`: attacker supplies 1 wei, donates 10,000e6 USDC by
   calling `supply` again (note: a direct token transfer does *nothing* here —
   why?), victim supplies 10,000e6. Compute both parties' final asset claims.
   Then redo it with the offset removed and confirm the victim gets zero shares.

2. **Why `- feeAmount`.** In `_accrueInterest`
   ([`:494-502`](morpho-blue/src/Morpho.sol#L494-L502)) the fee conversion uses
   `totalSupplyAssets - feeAmount` as the denominator. Work out, with numbers,
   what the fee recipient would receive if it used `totalSupplyAssets`, and
   explain who pays the difference. Then find Aave's equivalent in
   `_accrueToTreasury`
   ([`ReserveLogic.sol`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/ReserveLogic.sol))
   and identify the same adjustment.

3. **The Taylor error.** Implement `wTaylorCompounded`
   ([`MathLib.sol:38-44`](morpho-blue/src/libraries/MathLib.sol#L38-L44)) in
   Python and compare it against `math.exp(x*n) - 1` for `z` from 0.001 to 1.0.
   At what `z` does the error exceed 1%? Now find the elapsed time that produces
   that `z` at a 50% APR, and decide whether it is reachable in practice.

4. **Rounding direction audit.** List every rounding call in `_isHealthy`
   ([`:515-539`](morpho-blue/src/Morpho.sol#L515-L539)) and in the two liquidation
   branches ([`:371-380`](morpho-blue/src/Morpho.sol#L371-L380)). For each, state
   who loses the dust. Find one where reversing the direction would let someone
   extract value, and describe the attack.

5. **Build leverage on paper.** Using only `supplyCollateral` with a callback
   (§4), write the exact sequence that takes 2 WETH of your own into a 5 WETH
   position against USDC debt. State the health factor at the moment
   `onMorphoSupplyCollateral` fires and explain why the borrow inside it
   succeeds. Then find the Aave v2 contract that exists solely to do this
   (`aave/v2-protocol/contracts/adapters/`) and count its lines.

6. **The LIF table.** Reproduce the table in §6 from
   [`:365-369`](morpho-blue/src/Morpho.sol#L365-L369). At what `lltv` does the
   cap first bind? Then argue whether a 0.6% bounty at `lltv = 0.98` is enough to
   attract liquidators during a 20% hourly drawdown, and what that implies about
   who should use high-LLTV markets.

7. **Bad debt, both ways.** Trace
   [`:392-403`](morpho-blue/src/Morpho.sol#L392-L403) and then Aave's
   `_burnBadDebt` / deficit path
   ([`LiquidationLogic.sol:538`](../aave/aave-v3-origin/src/contracts/protocol/libraries/logic/LiquidationLogic.sol#L538)).
   Write down what a supplier sees in each system in the block the loss occurs,
   and in the block after. Which one would you rather be in, and does the answer
   change if you are the *last* supplier to withdraw?

8. **MetaMorpho's queue.** Read `_withdrawMorpho`
   ([`metamorpho/src/MetaMorpho.sol:807`](metamorpho/src/MetaMorpho.sol#L807))
   and `totalAssets`
   ([`:589-593`](metamorpho/src/MetaMorpho.sol#L589-L593)). Construct a state
   where a depositor cannot withdraw despite `totalAssets` being large, and
   identify which role could have prevented it and which could fix it fastest.

9. **The unenforced assumptions.** Take the list at
   [`IMorpho.sol:104-125`](morpho-blue/src/interfaces/IMorpho.sol#L104-L125) and
   for each item construct the concrete failure. Start with the fee-on-transfer
   one, which is the easiest to reason about, then do the oracle gap condition
   `newPrice < oldPrice · LLTV · LIF`.

10. **Reproduce the size claim.** Run
    `find morpho-blue/src -name '*.sol' -not -path '*/mocks/*' | xargs wc -l` and
    compare against
    `find ../aave/aave-v3-origin/src/contracts/protocol -name '*.sol' | xargs wc -l`.
    Then argue which comparison is fair, given that MetaMorpho, the oracle
    contracts and the bundlers are all doing work that lives inside Aave's number.

---

## Where to go next

- [`MORPHO-COMPLETE-REFERENCE.md`](MORPHO-COMPLETE-REFERENCE.md) — every contract
  and every function across all four repos, with selector tables, storage
  layouts and the full error list.
- [`../liquity/LIQUITY-DEEP-DIVE.md`](../liquity/LIQUITY-DEEP-DIVE.md) — the
  other minimalist design in this repo. Liquity removes governance entirely
  rather than minimising it, and replaces liquidation auctions with a stability
  pool. Read it directly after this one; the two make different bets on the same
  intuition.
- [`../aave/AAVE-DEEP-DIVE.md`](../aave/AAVE-DEEP-DIVE.md) — the maximalist
  counterpart referenced throughout.
