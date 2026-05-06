# Case Study: ERC4626 Donation Inflation and Share-Accounting Fairness

## 1. Overview

This case study demonstrates a minimal ERC4626-style donation inflation attack.

The vulnerable vault remains solvent in a raw asset-balance sense, but the ownership claim over those assets is misallocated.

The core failure is:

```text
The victim deposits assets but receives zero shares.
The attacker owns the only share and redeems the victim's assets.
```

This is a share-accounting fairness problem, not a missing-balance problem.

---

## 2. Why This Case Study Matters

ERC4626-style vaults convert between assets and shares.

This conversion looks simple:

```solidity
shares = assets * totalSupply / totalAssets;
```

But the conversion can become dangerous when:

```text
- totalSupply is very small
- totalAssets is inflated by direct donation
- integer division floors down
- deposit does not enforce minimum shares received
```

In that state, a user can transfer valuable assets into the vault and receive no ownership claim.

This case study isolates that failure mode.

---

## 3. Contracts in This Repo

### MockERC20

A minimal ERC20 token used for testing.

It avoids external dependencies and keeps the artifact self-contained.

### VulnerableVault

A minimal ERC4626-style vault that is intentionally vulnerable.

It uses live-balance accounting:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

It mints shares using:

```solidity
shares = assets * totalSupply / totalAssets();
```

This makes the vault sensitive to direct token donations.

### SafeVirtualOffsetVault

A minimal mitigation vault using virtual assets and virtual shares.

It uses:

```solidity
shares = assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
```

This does not ignore direct donations, but it bounds their impact when real share supply is very low.

---

## 4. The Vulnerable Mechanism

The attack begins with an empty vault.

The attacker deposits a tiny amount:

```text
attacker deposit = 1 wei
attacker shares  = 1
totalSupply      = 1
totalAssets      = 1
```

This first deposit is not itself wrong.

The problem starts when the attacker transfers assets directly to the vault:

```text
donation = 100e18
```

The vault now has:

```text
totalSupply = 1
totalAssets = 100e18 + 1
```

The attacker still owns the only share.

The exchange rate has been distorted because assets increased without new shares being minted.

---

## 5. Victim Deposit and Zero Shares

The victim deposits:

```text
victimDeposit = 100e18
```

The vault computes:

```text
shares = victimDeposit * totalSupply / totalAssets
shares = 100e18 * 1 / (100e18 + 1)
shares = 0
```

The victim transfers assets to the vault but receives zero shares.

After the victim deposit:

```text
vault assets = attacker seed + attacker donation + victim deposit
totalSupply  = 1
attacker owns 1 share
victim owns 0 shares
```

The attacker then redeems the only share and receives the full vault balance.

---

## 6. Minimum Deposit Threshold

The key threshold is the minimum asset amount required to mint one share.

Given:

```solidity
shares = assets * totalSupply / totalAssets;
```

To mint at least one share:

```text
assets >= ceil(totalAssets / totalSupply)
```

After the attacker's donation:

```text
totalSupply = 1
totalAssets = donation + 1
```

So:

```text
minAssetsForOneShare = donation + 1
```

Any deposit below this threshold rounds down to zero shares.

This is the core mechanism behind the attack.

---

## 7. Solvent but Unfair

The vault is not missing assets.

After the victim deposits, the assets are inside the vault.

The problem is that the victim has no ownership claim:

```text
vault asset balance > 0
victim shares = 0
attacker shares = 1
```

The vault is solvent in the raw-balance sense, but unfair in ownership allocation.

This distinction is important.

Many accounting bugs in DeFi are not simple insolvency bugs. They are claim-assignment bugs:

```text
The assets exist.
The wrong party owns the claim.
```

---

## 8. Partial Dilution Is the General Case

Zero-share minting is the extreme case.

A broader version of the same problem is partial dilution.

For example, suppose:

```text
attackerSeed = 1e18
donation = 100e18
victimDeposit = 100e18
```

Without donation, the victim would receive:

```text
victimShares = 100e18
```

With donation:

```text
totalSupply = 1e18
totalAssets = 101e18

victimShares = 100e18 * 1e18 / 101e18
             ≈ 0.990099e18
```

The victim receives nonzero shares, but far fewer than in the no-donation baseline.

This shows that zero-share deposits are only one boundary case.

The broader risk is donation-induced ownership distortion.

---

## 9. Virtual Offset Mitigation

The mitigation vault uses:

```solidity
VIRTUAL_ASSETS = 1;
VIRTUAL_SHARES = 1e18;
```

and conversion math:

```solidity
shares = assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
```

This makes the vault behave as if there is already a large effective share supply:

```text
effectiveSupply = totalSupply + VIRTUAL_SHARES
```

So the first depositor cannot cheaply dominate the entire effective supply.

Under the same attack setup:

```text
attacker seed deposit
attacker direct donation
victim deposit
```

the victim receives nonzero shares, and the attacker cannot redeem all vault assets.

---

## 10. What Virtual Offset Does Not Do

Virtual offset does not prevent donations from entering `totalAssets()`.

In this repo, `SafeVirtualOffsetVault` still uses:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

So donation still changes the exchange rate.

The correct interpretation is:

```text
Virtual offset does not make the vault donation-proof.
It makes the low-supply donation attack economically bounded.
```

This distinction matters for audits.

A reviewer should not simply see virtual shares and assume donation risk is gone.

The question is whether the virtual offset is large enough to protect expected deposits under realistic low-supply conditions.

---

## 11. Alternative Mitigation: Internal Accounting

Another defense is internal accounting.

Instead of using raw token balance as `totalAssets()`:

```solidity
return assetToken.balanceOf(address(this));
```

the vault can track its own accounted assets:

```solidity
uint256 public accountedAssets;
```

and return:

```solidity
return accountedAssets;
```

Direct donations would not affect share price because they would not increase accounted assets.

This is a stronger defense against donation-driven exchange-rate manipulation.

However, it introduces new design questions:

```text
- What happens to extra tokens sent directly to the vault?
- Can they be swept?
- Who can sweep them?
- Are surplus tokens treated as protocol revenue?
- Could sweeping create governance risk?
- How does the vault reconcile accounted balance and raw balance?
```

So internal accounting reduces donation sensitivity but requires explicit surplus-token policy.

---

## 12. Lessons for Auditors

This case study suggests several review lessons.

### Lesson 1: Empty Vaults Are Special

The initial deposit path often has custom behavior:

```solidity
if (totalSupply == 0) {
    shares = assets;
}
```

This path must be reviewed carefully.

### Lesson 2: Low Share Supply Is a Risk Zone

Even if the vault is no longer empty, a very small `totalSupply` can be dangerous.

The relevant question is:

```text
How large must a later deposit be to mint at least one share?
```

### Lesson 3: Direct Donations Can Change Exchange Rate

If `totalAssets()` reads raw token balance, unsolicited transfers can change the exchange rate.

The reviewer should test direct transfers to the vault.

### Lesson 4: Preview Is Not Enough

`previewDeposit()` may correctly return zero shares.

That does not make the system safe.

The vault or integrator must prevent users from accepting zero-share deposits.

### Lesson 5: Solvency and Fairness Are Different

A vault can hold enough assets but still allocate claims incorrectly.

The reviewer should check both:

```text
asset balance correctness
ownership claim correctness
```

### Lesson 6: Mitigation Must Be Precisely Understood

Virtual offset is not the same as internal accounting.

Virtual offset bounds low-supply donation extraction.

Internal accounting can ignore unsolicited donations for share-price purposes.

They solve related but different problems.

---

## 13. Tests Included

This repo includes three groups of tests.

### Vulnerable Reproduction Tests

File:

```text
test/ERC4626Inflation.t.sol
```

These tests show:

```text
- direct donation raises exchange rate without minting shares
- previewDeposit returns zero after donation
- victim deposit mints zero shares
- attacker redeems all vault assets
- the zero-share threshold
```

### Mechanism Analysis Tests

File:

```text
test/ERC4626InflationAnalysis.t.sol
```

These tests show:

```text
- the minimum assets required to mint one share
- the extreme asset/share ratio after donation
- the solvent-but-unfair state
- partial dilution
- virtual offset still reacts to donation
- virtual offset raises effective supply
```

### Mitigation Tests

File:

```text
test/ERC4626Mitigation.t.sol
```

These tests show:

```text
- virtual offset prevents zero-share victim deposits
- attacker cannot redeem all vault assets
- attacker profit is bounded
- previewDeposit remains nonzero after donation
- normal deposits still work
```

Current expected test result:

```text
15 tests passed
0 failed
0 skipped
```

---

## 14. Practical Audit Checklist

When reviewing ERC4626-style vaults, check:

```text
1. Does totalAssets() use raw token balance?
2. Can assets be transferred directly into the vault?
3. What happens when totalSupply == 0?
4. What happens when totalSupply is very small?
5. Can previewDeposit return zero for a positive asset amount?
6. Does deposit reject zero-share mints?
7. Is there a user-controlled minSharesOut?
8. Can direct donation change share price before another user's deposit?
9. Are virtual assets / virtual shares used?
10. Are virtual offsets large enough?
11. Is internal accounting used?
12. If internal accounting is used, how are surplus tokens handled?
13. Are low-supply states covered by tests?
14. Are donation states covered by tests?
15. Are both zero-share and partial-dilution cases tested?
```

---

## 15. Relation to Production Vaults

Production ERC4626 vaults are more complex than this toy model.

They may include:

```text
- strategy reports
- profit locking
- loss accounting
- fees
- withdrawal queues
- debt allocation
- shutdown modes
- role-based management
```

However, the same accounting principle applies:

```text
A vault must preserve fair ownership claims across user cohorts.
```

The low-supply donation attack is a minimal example of that principle failing.

In production systems, the same type of issue can appear through more complex paths:

```text
- profit timing
- loss timing
- stale accounting
- fee crystallization
- strategy report ordering
- donation or reward accounting
```

The minimal case helps build intuition for those larger systems.

---

## 16. Final Takeaway

The attack is not about assets disappearing from the vault.

The attack is about ownership claims being assigned incorrectly.

The vulnerable vault allows this state:

```text
victim contributes assets
victim receives no shares
attacker owns all shares
attacker redeems all assets
```

The key insight is:

```text
Solvency protects asset presence.
Share accounting protects ownership fairness.
Both are required.
```