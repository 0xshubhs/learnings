# Lido Deep Dive

A code-first walkthrough of Lido on Ethereum, written against the source cloned
in `lido/core` (lidofinance/core, `package.json` version `3.0.2`).

One thing to know before you start: **this tree is ahead of its own version
label.** `Lido.sol` contains
[`finalizeUpgrade_v4`](core/contracts/0.4.24/Lido.sol#L296) and
[`_migrateStorage_v3_to_v4`](core/contracts/0.4.24/Lido.sol#L311), so what you
are reading is v4-in-progress code carrying a v3 tag. Where I say "v3" below I
mean the stVaults generation; where the code says v4 I flag it.

You have met Lido once already in this repo without going near it. LI.FI ships a
`LidoWrapper` whose entire job is converting stETH to wstETH and back, documented
in `lifi/LIBRARIES-PERIPHERY-COMPLETE-REFERENCE.md`. That wrapper exists because
of a single design decision inside `StETH.sol`, and section 1 is about why.

Every `path:line` below was checked with `grep -n` against these files.

---

## 0. What liquid staking actually solves

**The problem.** Ethereum proof-of-stake wants validators. A validator costs
exactly 32 ETH, runs software that must stay online, and until the Shanghai
upgrade could not be exited at all. Three separate barriers: capital, operations,
and liquidity.

**The trade.** Lido pools deposits of any size, hands the operational burden to
vetted node operators, and gives the depositor a token that stays liquid. The
depositor keeps exposure to staking yield without ever touching 32 ETH or a
validator client.

**Who holds what.** This split is the whole security model, and it is worth
getting straight before any code:

```
     staker                node operator              the protocol
       |                        |                          |
   holds stETH            holds the validator        holds the withdrawal
   (a claim on the        signing keys               credentials (0x01/0x02
    pool, transferable)   (can attest, propose,       pointing at the
       |                   and get slashed)           WithdrawalVault)
       |                        |                          |
   can sell or             cannot move                 controls where
   redeem via the          user funds                  exited ETH lands
   withdrawal queue
```

The node operator can lose money through slashing, but cannot steal it. The
withdrawal credentials point at protocol-controlled contracts, so exited stake
returns to Lido regardless of who ran the validator. That asymmetry is what makes
delegating to strangers tolerable.

**A worked example.** Suppose the pool holds 1,000 ETH against 1,000 shares, so
one share is worth 1 ETH.

```
you submit 10 ETH
  shares minted = 10 * (1000 shares / 1000 ETH) = 10 shares
  your balanceOf = 10 stETH        pool: 1010 ETH / 1010 shares

validators earn 10 ETH over some period; the oracle reports it
  protocol fee is 10% of rewards = 1 ETH, minted as new shares to
  operators + treasury (section 3 derives the exact formula)
  pool becomes 1010 ETH but ~1010.99 shares

your shares are unchanged at 10
  your balanceOf = 10 * (1010 / 1010.99) ~= 10.089 stETH
```

Your share count never moved. Your balance did. That is a rebase, and it happens
without a transfer, without your involvement, and without your consent.

**Then you withdraw.** You request a withdrawal, receive an NFT representing your
place in a queue, wait for the protocol to accumulate enough ETH (from the
buffer, from rewards, or from actually exiting validators), and then claim.
Section 4 covers why this cannot be instant.

---

## 1. stETH: a rebasing token, in code

This is the conceptual heart of Lido, and it is the most transferable idea in
this document, because you have already seen it three times under other names.

### 1.1 Balances are derived, not stored

Nowhere does Lido store your stETH balance. It stores your **shares**, and
computes the balance on read:

```solidity
function balanceOf(address _account) external view returns (uint256) {
    return getPooledEthByShares(_sharesOf(_account));
}
```

[`core/contracts/0.4.24/StETH.sol:177-179`](core/contracts/0.4.24/StETH.sol#L177-L179)

`totalSupply` is the same trick, returning the pool's total ether rather than a
stored counter ([`StETH.sol:158-160`](core/contracts/0.4.24/StETH.sol#L158-L160)).

The two conversions are plain proportions:

```solidity
function getSharesByPooledEth(uint256 _ethAmount) public view returns (uint256) {
    require(_ethAmount < UINT128_MAX, "ETH_TOO_LARGE");
    return (_ethAmount
        * _getShareRateDenominator()) // denominator in shares
        / _getShareRateNumerator();   // numerator in ether
}
```

[`StETH.sol:317-322`](core/contracts/0.4.24/StETH.sol#L317-L322), with the
inverse at [`:329-334`](core/contracts/0.4.24/StETH.sol#L329-L334) and a
round-up variant at [`:342-349`](core/contracts/0.4.24/StETH.sol#L342-L349).
Both round down by default; the round-up variant exists so that
`getSharesByPooledEth(getPooledEthBySharesRoundUp(1))` returns 1 rather than 0
for any share rate at or above 0.5.

### 1.2 Why the numerator is not what you would guess

In the base contract, the share rate is simply total ether over total shares
([`StETH.sol:410-421`](core/contracts/0.4.24/StETH.sol#L410-L421)). `Lido.sol`
overrides both halves, and the override is the interesting part:

```solidity
function _getShareRateNumerator() internal view returns (uint256) {
    return _getInternalEther();
}

function _getShareRateDenominator() internal view returns (uint256) {
    (uint256 totalShares, uint256 externalShares) = _getTotalAndExternalShares();
    uint256 internalShares = totalShares - externalShares; // never 0 because of the stone in the elevator
    return internalShares;
}
```

[`core/contracts/0.4.24/Lido.sol:1296-1307`](core/contracts/0.4.24/Lido.sol#L1296-L1307)

The rate is **internal** ether over **internal** shares, not totals over totals.
"External" shares are those minted against stVaults (section 6), and their ether
value is itself derived from the internal rate at
[`Lido.sol:1284-1289`](core/contracts/0.4.24/Lido.sol#L1284-L1289). Using totals
would divide by a number that was itself produced by a division, losing precision
twice. The comment at [`:1291-1295`](core/contracts/0.4.24/Lido.sol#L1291-L1295)
says exactly this.

Note the aside in that snippet: `internalShares` is "never 0 because of the stone
in the elevator". That is Lido's first-depositor defence, and it is the crudest
and clearest one in this entire repo:

```solidity
function _bootstrapInitialHolder() internal {
    uint256 balance = address(this).balance;
    assert(balance != 0);

    if (_getTotalShares() == 0) {
        _setBufferedEther(balance);
        emit Submitted(INITIAL_TOKEN_HOLDER, balance, 0);
        _mintInitialShares(balance);
    }
}
```

[`Lido.sol:1459-1471`](core/contracts/0.4.24/Lido.sol#L1459-L1471), called once
from `initialize` at [`:277`](core/contracts/0.4.24/Lido.sol#L277) with the
comment `// stone in the elevator`. `INITIAL_TOKEN_HOLDER` is
`0xdead` ([`StETH.sol:56`](core/contracts/0.4.24/StETH.sol#L56)). The protocol
permanently burns the first deposit so the share supply can never return to zero
and the rate can never be manipulated from an empty pool.

Compare the three answers to the same attack you have now seen:

| Protocol | Defence |
|---|---|
| Uniswap V2 | burns `MINIMUM_LIQUIDITY` to address zero on first mint |
| Morpho Blue | never reads `balanceOf` for accounting, so donations are simply lost |
| Lido | burns the entire first deposit to `0xdead` |

### 1.3 Minting on deposit

`submit` is a two-line wrapper ([`Lido.sol:508-510`](core/contracts/0.4.24/Lido.sol#L508-L510))
over `_submit`:

```solidity
function _submit(address _referral) internal returns (uint256) {
    require(msg.value != 0, "ZERO_DEPOSIT");

    _decreaseStakingLimit(msg.value);

    uint256 sharesAmount = getSharesByPooledEth(msg.value);

    _mintShares(msg.sender, sharesAmount);

    _setBufferedEther(_getBufferedEther() + msg.value);
    emit Submitted(msg.sender, msg.value, _referral);

    _emitTransferAfterMintingShares(msg.sender, sharesAmount);
    return sharesAmount;
}
```

[`Lido.sol:1253-1267`](core/contracts/0.4.24/Lido.sol#L1253-L1267)

Read the ordering carefully. `getSharesByPooledEth` is called **after**
`msg.value` has already landed in `address(this).balance`, but the share rate
reads `_getBufferedEther()`, a stored value that has not yet been updated. So the
conversion uses the pre-deposit rate, which is correct. If the rate read live
balances instead, your own deposit would dilute the price you paid.

The rate limiter at `_decreaseStakingLimit` is a separate mechanism, a leaky
bucket defined in `StakeLimitUtils.sol`, that caps how much ETH can enter per
block so the protocol cannot be flooded faster than it can deploy stake.

### 1.4 Why rebasing breaks composability

Every integration that stores a stETH balance is wrong the moment a rebase lands.
Concretely:

- An AMM pool holding stETH sees its reserves change without a swap, so
  `x*y=k` accounting and any cached reserve is stale. Uniswap V2's `sync`/`skim`
  exist partly for this class of token.
- A lending market that recorded "user supplied 10 stETH" now owes a different
  amount than it recorded.
- Any contract doing `balanceBefore`/`balanceAfter` diffing can attribute a
  rebase to a transfer.
- On L2s, bridging a rebasing token means the bridge must replicate the rebase.

`transferShares` ([`StETH.sol:365`](core/contracts/0.4.24/StETH.sol#L365)) exists
precisely so that integrations can move the underlying unit rather than the
derived one, but most ERC-20 infrastructure does not know it exists.

### 1.5 wstETH: the fix is to stop deriving

`WstETH` wraps shares directly and lets the balance stay put:

```solidity
function wrap(uint256 _stETHAmount) external returns (uint256) {
    require(_stETHAmount > 0, "wstETH: can't wrap zero stETH");
    uint256 wstETHAmount = stETH.getSharesByPooledEth(_stETHAmount);
    _mint(msg.sender, wstETHAmount);
    stETH.transferFrom(msg.sender, address(this), _stETHAmount);
    return wstETHAmount;
}
```

[`core/contracts/0.6.12/WstETH.sol:53-59`](core/contracts/0.6.12/WstETH.sol#L53-L59),
with `unwrap` at [`:69-75`](core/contracts/0.6.12/WstETH.sol#L69-L75).

Your wstETH balance is a plain stored ERC-20 number that never changes on its
own. The yield shows up as `stEthPerToken()`
([`:107`](core/contracts/0.6.12/WstETH.sol#L107)) rising instead. Same economics,
ordinary token semantics. There is also a `receive()` at
[`:80`](core/contracts/0.6.12/WstETH.sol#L80) that stakes and wraps in one step.

This is exactly what LI.FI's `LidoWrapper` is calling. An aggregator routing
through stETH needs the non-rebasing form to make its balance-diff accounting
safe, so it converts at the edges.

### 1.6 The pattern, named

You have now seen this four times:

| Protocol | Stored unit | Derived unit | Conversion rate |
|---|---|---|---|
| Aave v3 | `scaledBalance` | `balanceOf` | `liquidityIndex` |
| Curve | LP token balance | claim on pool | `D / totalSupply` (virtual price) |
| Morpho Blue | `supplyShares` | assets | `totalSupplyAssets / totalSupplyShares` |
| Lido | shares | `balanceOf` stETH | internal ether / internal shares |

The rule is identical in all four: **never store a balance that yield will
change; store an immutable unit and a global rate, and multiply on read.** The
only thing Lido does differently is expose the derived number as the token's
`balanceOf` rather than keeping it behind a view function, and that single
choice is what forces wstETH to exist.

Aave made the opposite call with aTokens, which also rebase, and then shipped
`StataTokenV2` as its own non-rebasing wrapper. Same problem, same fix, two
protocols.

---

## 2. The deposit path

Your ETH does not go to a validator when you call `submit`. It sits in a buffer
until someone assembles a deposit, and the gap between those two events is where
the interesting security problem lives.

```
  user
   |  submit{value}                                   Lido.sol:508
   v
 Lido  ------------------------------ buffered ether stored, shares minted
   ^                                                  Lido.sol:1253-1267
   |  withdrawDepositableEther                        Lido.sol:869
   |
 StakingRouter.deposit  <---- only callable by the DSM   StakingRouter.sol:942
   |      |
   |      |  obtainDepositData(maxDepositsCount)     -> a staking module
   |      v                                             returns pubkeys+sigs
   |  makeBeaconChainDeposits32ETH                      StakingRouter.sol:985
   v
 beacon chain deposit contract
   ^
   |  depositBufferedEther(blockNumber, blockHash,      DepositSecurityModule
   |                       depositRoot, moduleId,       .sol:460
   |                       nonce, guardianSignatures)
 anyone (a bot), carrying a guardian quorum
```

### 2.1 Buffering

`_submit` adds to `bufferedEther` and stops
([`Lido.sol:1263`](core/contracts/0.4.24/Lido.sol#L1263)). Buffered ether serves
two masters: it is the pool of capital waiting to be staked, and it is the first
place withdrawals are paid from. v3 splits it explicitly through
`_getBufferedEtherAllocation` ([`Lido.sol:605`](core/contracts/0.4.24/Lido.sol#L605))
into a deposits reserve and a withdrawals reserve, with
`getDepositableEther` ([`:823`](core/contracts/0.4.24/Lido.sol#L823)) reporting
only the portion that may actually be staked.

### 2.2 The attack the DSM exists to stop

This is the part worth understanding properly, because it is a genuinely subtle
vulnerability and the mitigation is unusual.

A node operator submits validator public keys and, crucially, **signatures over
their own deposit data**. The beacon chain deposit contract does not verify that
a deposit's withdrawal credentials match any earlier deposit for the same public
key. It only checks the BLS signature over the message the depositor supplies.

So: a malicious operator can pre-deposit 1 ETH for a public key, setting the
withdrawal credentials to **their own address**. Later, Lido deposits 32 ETH for
that same public key with Lido's withdrawal credentials. The beacon chain honours
the *first* credentials it ever saw for that key. Lido's 32 ETH is now withdrawable
by the attacker. This is the "deposit front-running" attack, and it was disclosed
against Lido in 2021.

The fix cannot be purely on-chain, because the EVM cannot see the beacon chain
deposit history for a key. So Lido added an off-chain guardian committee that
watches the deposit contract and signs an attestation that a given deposit is
safe to make right now.

### 2.3 The guardian attestation

```solidity
function depositBufferedEther(
    uint256 blockNumber,
    bytes32 blockHash,
    bytes32 depositRoot,
    uint256 stakingModuleId,
    uint256 nonce,
    Signature[] calldata sortedGuardianSignatures
) external {
    bytes32 onchainDepositRoot = DEPOSIT_CONTRACT.get_deposit_root();
    if (depositRoot != onchainDepositRoot) revert DepositRootChanged();

    uint256 onchainNonce = STAKING_ROUTER.getStakingModuleNonce(stakingModuleId);
    if (nonce != onchainNonce) revert ModuleNonceChanged();
    ...
```

[`core/contracts/0.8.9/DepositSecurityModule.sol:460-488`](core/contracts/0.8.9/DepositSecurityModule.sol#L460-L488)

Every check exists for a reason:

| Check | Line | Defends against |
|---|---|---|
| `depositRoot` matches on-chain | [`:468`](core/contracts/0.8.9/DepositSecurityModule.sol#L470) | any new deposit landing between signing and execution, including the attacker's |
| module `nonce` matches | [`:474`](core/contracts/0.8.9/DepositSecurityModule.sol#L474) | the key set changing after guardians vetted it |
| quorum of signatures | [`:477`](core/contracts/0.8.9/DepositSecurityModule.sol#L477) | a single compromised guardian |
| min deposit block distance | [`:478`](core/contracts/0.8.9/DepositSecurityModule.sol#L478) | rapid repeated deposits outrunning guardian review |
| `blockhash(blockNumber) == blockHash` | [`:479`](core/contracts/0.8.9/DepositSecurityModule.sol#L479) | reorgs, and signatures older than 256 blocks |
| `isDepositsPaused` | [`:480`](core/contracts/0.8.9/DepositSecurityModule.sol#L480) | the emergency stop |

The deposit root check is the load-bearing one. `get_deposit_root()` is a
Merkle root over *every* deposit ever made to the beacon deposit contract. If the
attacker front-runs with their 1 ETH pre-deposit, the root changes, and the
guardian signatures no longer validate. The transaction reverts rather than
handing over 32 ETH.

Signatures are checked in `_verifyAttestSignatures`
([`:490-520`](core/contracts/0.8.9/DepositSecurityModule.sol#L490-L520)) over the
packed message `ATTEST_MESSAGE_PREFIX | blockNumber | blockHash | depositRoot |
stakingModuleId | nonce`. Note the ascending-address sort requirement at
[`:515`](core/contracts/0.8.9/DepositSecurityModule.sol#L515): it makes duplicate
signatures from one guardian impossible to sneak past the quorum count, in one
comparison rather than a nested loop.

A single guardian can also pause deposits unilaterally via `pauseDeposits`
([`:368`](core/contracts/0.8.9/DepositSecurityModule.sol#L368)), with only one
signature required. Asymmetric on purpose: stopping is cheap, starting needs
quorum.

### 2.4 Handing off to the module

`StakingRouter.deposit` is gated to the DSM alone
([`StakingRouter.sol:943`](core/contracts/0.8.25/sr/StakingRouter.sol#L943)) and
does the actual work:

```solidity
(bytes memory publicKeysBatch, bytes memory signaturesBatch) =
    IStakingModule(stakingModuleAddress).obtainDepositData(maxDepositsCount, _depositCalldata);
...
/// @dev Update the local state of the contract to prevent a reentrancy attack
/// even though the staking modules are trusted contracts.
_updateModuleLastDepositState(_stakingModuleId, depositsValue);
...
LIDO.withdrawDepositableEther(depositsValue, actualDepositsCount);
BeaconChainDepositor.makeBeaconChainDeposits32ETH(...);
```

[`StakingRouter.sol:961-991`](core/contracts/0.8.25/sr/StakingRouter.sol#L961-L991)

Three details worth noticing. The module may return **fewer** keys than asked
for, so the ETH pulled from Lido is computed from `actualDepositsCount` rather
than the request ([`:971-973`](core/contracts/0.8.25/sr/StakingRouter.sol#L971-L973)).
State is updated before the external call even though modules are trusted
([`:975-976`](core/contracts/0.8.25/sr/StakingRouter.sol#L975-L976)), the same
checks-effects-interactions discipline Morpho relies on. And the function closes
with a hard assertion that its own balance is unchanged
([`:996`](core/contracts/0.8.25/sr/StakingRouter.sol#L996)):

```solidity
assert(etherBalanceBeforeDeposits == etherBalanceAfterDeposits);
```

Every wei pulled from Lido must reach the deposit contract. Nothing may stick to
the router.

---

## 3. The oracle and the rebase

Ethereum's execution layer cannot see the beacon chain. Validator balances live
in a state the EVM has no access to, so the number that drives every stETH
balance has to be *told* to the protocol. That makes the oracle the single most
consequential trust assumption in Lido, and the machinery around it is
correspondingly paranoid.

### 3.1 Frames, quorum, and getting to one number

`HashConsensus` runs the vote. Time is chopped into **frames** of
`epochsPerFrame` epochs ([`FrameConfig`](core/contracts/0.8.9/oracle/HashConsensus.sol#L123)),
and each frame has one **reference slot**: the last slot of the previous frame.
Every oracle member independently reads beacon state as of that exact slot, so
they are all describing the same instant.

Members then submit a **hash** of their report, not the report itself
([`submitReport`](core/contracts/0.8.9/oracle/HashConsensus.sol#L609)). The
contract tallies support per distinct hash:

```solidity
if (support >= _quorum) {
    _consensusReached(frame, report, varIndex, support);
} else if (prevConsensusLost) {
    _consensusNotReached(frame);
}
```

[`HashConsensus.sol:945-949`](core/contracts/0.8.9/oracle/HashConsensus.sol#L945-L949)

Two subtleties most descriptions miss. A member may **change their vote** within
a frame: the code decrements the old variant's support first
([`:922`](core/contracts/0.8.9/oracle/HashConsensus.sol#L922)), and if that drops
it below quorum, consensus is actively *lost* again rather than silently
retained. And submitting the identical hash twice reverts with
`DuplicateReport` ([`:919`](core/contracts/0.8.9/oracle/HashConsensus.sol#L919)),
which is what stops one member counting twice toward quorum.

Only once a hash has quorum may anyone submit the matching data to
`AccountingOracle.submitReportData`
([`AccountingOracle.sol:360`](core/contracts/0.8.9/oracle/AccountingOracle.sol#L360)),
which checks the data against the agreed hash. Hash first, data second: the vote
is cheap, and no member can be front-run into revealing their numbers early.

### 3.2 Where the rebase actually happens

Contrary to what older write-ups say, `handleOracleReport` is **not** in
`Lido.sol` any more. It lives in
[`Accounting.sol:137`](core/contracts/0.8.9/Accounting.sol#L137), a v3 contract
that orchestrates the whole report and calls back into Lido for the pieces that
touch token state.

The ordering in `_applyOracleReportContext`
([`Accounting.sol:360-427`](core/contracts/0.8.9/Accounting.sol#L360-L427)) is
deliberate and worth reading as a sequence:

```
1  _sanityChecks(...)                          revert the whole report if wrong
2  burner.requestBurnShares(withdrawalQueue)   queue WQ shares for burning
3  LIDO.processClStateUpdate(...)              write new CL balances
4  vaultHub / internalizeExternalBadDebt       absorb stVault bad debt, if any
5  burner.commitSharesToBurn(...)              actually burn -> share rate rises
6  LIDO.collectRewardsAndProcessWithdrawals()  pull EL rewards, finalize WQ
7  LIDO.mintShares(fees)  + _distributeFee()   dilute -> share rate settles
8  _notifyRebaseObserver(...)
9  LIDO.emitTokenRebase(...)                   announce pre/post numbers
```

Step 7 carries an explicit comment in the source:

```solidity
if (_update.sharesToMintAsFees > 0) {
    // this is a final action that changes share rate.
    // so all transfers after this mint will reflect the actual postShareRate
    LIDO.mintShares(address(this), _update.sharesToMintAsFees);
```

[`Accounting.sol:403-406`](core/contracts/0.8.9/Accounting.sol#L403-L406)

Fee minting is last among rate-changing operations precisely so that the
`_distributeFee` transfers that follow move the correct amount of value. Get that
order wrong and operators are paid at a stale rate.

### 3.3 The fee formula

This is the piece worth deriving, because it is the same shape you met in
Uniswap V2's `_mintFee` and it is not obvious on first read.

Lido takes a fee on rewards. It could take it in ether, but the ether is on the
beacon chain and cannot be moved. So instead it **mints new shares** to
operators and the treasury, diluting existing holders by exactly the value the
fee would have been.

```solidity
uint256 totalRewards = unifiedClBalance - _update.principalClBalance + _update.elRewardsVaultTransfer;
uint256 feeEther = (totalRewards * _totalFee) / _feePrecisionPoints;
sharesToMintAsFees = (feeEther * _internalSharesBeforeFees) / (_update.postInternalEther - feeEther);
```

[`Accounting.sol:322-331`](core/contracts/0.8.9/Accounting.sol#L322-L331)

Why that denominator? Let `S` be shares before, `E` the post-rebase ether, and
`f` the fee in ether. We want to mint `x` new shares whose value is exactly `f`
at the **post-mint** rate:

```
    x / (S + x)  =  f / E          (the fee's share of the pool equals its value)
    xE = f(S + x)
    x(E - f) = fS
    x = fS / (E - f)
```

which is the line above verbatim. Subtracting `f` in the denominator is what makes
the fee come out of the rewards rather than out of existing holders' principal.

One more guard sits above it:

```solidity
if (unifiedClBalance > _update.principalClBalance) {
```

[`Accounting.sol:322`](core/contracts/0.8.9/Accounting.sol#L322). No fee is
charged on a report where the consensus layer balance did not grow. Lido does not
take a cut of a loss.

### 3.4 The sanity checker

`OracleReportSanityChecker` is 1,588 lines of "this number cannot possibly be
right". Its `LimitsList` struct
([`:58-130`](core/contracts/0.8.9/sanity_checks/OracleReportSanityChecker.sol#L58-L129))
is the most compact description of what Lido is afraid of:

| Limit | Guards against |
|---|---|
| `exitedEthAmountPerDayLimit` | an oracle claiming an implausible mass exit |
| `appearedEthAmountPerDayLimit` | fabricated deposits appearing from nowhere |
| `annualBalanceIncreaseBPLimit` | a report inflating rewards beyond physical staking yield |
| `maxCLBalanceDecreaseBP` | a report fabricating catastrophic slashing |
| `maxPositiveTokenRebase` | a single report spiking the share rate; smooths MEV spikes |
| `simulatedShareRateDeviationBPLimit` | the submitted rate disagreeing with the recomputed one |
| `requestTimestampMargin` | finalizing withdrawal requests that are too fresh |
| `clBalanceOraclesErrorUpperBPLimit` | disagreement with an independent second-opinion oracle |
| `maxItemsPerExtraDataTransaction` | gas-griefing via oversized extra data |

The economically interesting one is `maxPositiveTokenRebase`. Without it, a single
large MEV block would spike the rate in one report, letting anyone who deposited
moments earlier capture a disproportionate share. Capping the positive rebase and
smearing the excess across later reports removes that timing game. The limiter
itself lives in
[`PositiveTokenRebaseLimiter.sol`](core/contracts/0.8.9/lib/PositiveTokenRebaseLimiter.sol#L1).

Note that these are **not** guarantees the report is honest. They are bounds on
how much damage a dishonest quorum can do in one report. A malicious quorum
reporting a small lie repeatedly is still a malicious quorum; section 7 returns
to this.

---

## 4. Withdrawals

### 4.1 Why there is a queue at all

The protocol cannot pay you instantly because most of its ether is not liquid. It
is 32-ETH chunks locked in validators, and getting it back means asking the
beacon chain to exit them. That takes time bounded by the network's exit churn
limit, not by anything Lido controls.

So withdrawals are a **queue**, paid from whatever the protocol can assemble:
buffered ether that has not been staked, incoming execution-layer rewards, and
ether from validators that have actually exited into the `WithdrawalVault`.

### 4.2 Requesting

`requestWithdrawals` ([`WithdrawalQueue.sol:125`](core/contracts/0.8.9/WithdrawalQueue.sol#L125))
takes an array of amounts, with variants for wstETH
([`:144`](core/contracts/0.8.9/WithdrawalQueue.sol#L144)) and permit-based
approval ([`:171`](core/contracts/0.8.9/WithdrawalQueue.sol#L171),
[`:186`](core/contracts/0.8.9/WithdrawalQueue.sol#L186)). Each request is bounded:

```solidity
uint256 public constant MIN_STETH_WITHDRAWAL_AMOUNT = 100;
uint256 public constant MAX_STETH_WITHDRAWAL_AMOUNT = 1000 * 1e18;
```

[`:52`](core/contracts/0.8.9/WithdrawalQueue.sol#L52) and
[`:57`](core/contracts/0.8.9/WithdrawalQueue.sol#L57). The cap is why large exits
arrive as many requests: it bounds the work of finalizing any single one.

Your stETH is transferred to the queue contract and you receive an **ERC-721**
(`WithdrawalQueueERC721`), which makes an in-flight withdrawal transferable and
tradeable. Someone wanting out faster can sell the NFT rather than wait.

### 4.3 The cumulative-sum trick

The request struct stores running totals, not per-request amounts:

```solidity
struct WithdrawalRequest {
    uint128 cumulativeStETH;
    uint128 cumulativeShares;
    address owner;
    uint40 timestamp;
    bool claimed;
    uint40 reportTimestamp;
}
```

[`WithdrawalQueueBase.sol:46-59`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L46-L59)

Any single request's amount is the difference between its cumulative and the
previous one's. That means finalizing a *batch* of requests costs a subtraction
rather than a loop, and `_calcBatch` reads exactly two entries no matter how many
requests sit between them. This is the same prefix-sum idea as Liquity's `L_ETH`
accumulator and Uniswap's fee growth: store running totals, take differences.

### 4.4 Finalization and the discount

The oracle decides which batches to finalize and Lido sends the ether. The
subtle part is what happens if the share rate **fell** between your request and
its finalization.

Your request locked a number of shares. If stETH lost value in the meantime, the
protocol must not pay you the higher pre-loss amount, because that would hand
your loss to everyone else. `Checkpoint` records the rate cap in force for a range
of requests:

```solidity
struct Checkpoint {
    uint256 fromRequestId;
    uint256 maxShareRate;
}
```

[`WithdrawalQueueBase.sol:62-65`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L62-L65)

and the claim applies it:

```solidity
if (batchShareRate > checkpoint.maxShareRate) {
    eth = shares * checkpoint.maxShareRate / E27_PRECISION_BASE;
}
```

[`:508-510`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L508-L510)

You are paid at `min(rate at request, rate at finalization)`. Note the direction:
a *positive* rebase between request and finalization does not benefit you either,
since your shares were already locked. Queued withdrawals stop earning.

The `_hint` parameter threaded through claiming
([`:484-504`](core/contracts/0.8.9/WithdrawalQueueBase.sol#L484-L504)) is a
binary-search index into the checkpoint array, supplied off-chain so the contract
does not pay to search. The checks around it are all bounds assertions that the
supplied hint really does bracket the request.

### 4.5 Bunker mode

If the protocol is losing money, for example through mass slashing, honouring
withdrawals at face value first-come-first-served would let early exiters escape
whole while stragglers absorb everything. **Bunker mode**
([`WithdrawalQueue.sol:328-338`](core/contracts/0.8.9/WithdrawalQueue.sol#L328-L338))
is the oracle-triggered switch that pauses finalization so losses can be shared
rather than raced.

It is the same insight as Liquity's Recovery Mode: under stress, the protocol
changes the rules to stop a bank run, at the cost of predictability for
individual users. Compare
`liquity/LIQUITY-DEEP-DIVE.md`, which describes v2 removing Recovery Mode
entirely by capping liquidation penalties instead.

---
