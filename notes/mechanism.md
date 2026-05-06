# Mechanism: ERC4626 Inflation / Donation Attack

## 1. Summary

This note explains a minimal ERC4626-style donation inflation attack.

The core issue is not that the first depositor receives shares in an empty vault. That is expected behavior. The issue appears when the vault has very low share supply and allows direct token donations to increase `totalAssets()` without minting new shares.

This creates an extreme asset/share ratio. A later depositor may deposit a positive amount of assets but receive zero shares due to integer floor rounding.

The vault can remain solvent in a raw-balance sense while allocating ownership claims unfairly.

Core lesson:

```text
Vault solvency alone is not enough.
The accounting system must also preserve fair ownership claims.
```

---

## 2. Minimal ERC4626 Share Math

A simplified ERC4626-style vault converts assets into shares using:

```solidity
shares = assets * totalSupply / totalAssets;
```

For the first deposit into an empty vault, the vault usually mints shares 1:1:

```solidity
if (totalSupply == 0) {
    shares = assets;
}
```

So if the first user deposits `1 wei` of assets, receiving `1 share` is not itself a bug.

The dangerous condition appears only after the asset/share ratio is manipulated.

---

## 3. The Vulnerable Design

In `VulnerableVault`, `totalAssets()` reads the live ERC20 balance:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

This means anyone can transfer assets directly to the vault without calling `deposit()`:

```solidity
asset.transfer(address(vault), donation);
```

That direct transfer increases `totalAssets()` but does not increase `totalSupply`.

So the vault state can move from:

```text
totalSupply = 1
totalAssets = 1
```

to:

```text
totalSupply = 1
totalAssets = donation + 1
```

The attacker still owns the only share, but that one share now represents a claim on the entire vault balance.

---

## 4. Attack Flow

The minimal attack has four steps.

### Step 1: Attacker seeds the empty vault

The attacker deposits `1 wei`:

```text
attacker deposit = 1
attacker shares  = 1
totalSupply      = 1
totalAssets      = 1
```

This step is normal by itself.

### Step 2: Attacker donates assets directly

The attacker transfers assets directly to the vault:

```text
donation = 100e18
```

The vault state becomes:

```text
totalSupply = 1
totalAssets = 100e18 + 1
```

No new shares are minted.

### Step 3: Victim deposits

The victim deposits:

```text
victimDeposit = 100e18
```

The vault computes shares as:

```text
shares = victimDeposit * totalSupply / totalAssets
shares = 100e18 * 1 / (100e18 + 1)
shares = 0
```

Because Solidity integer division floors down, the victim receives zero shares.

### Step 4: Attacker redeems

After the victim deposit, the vault holds:

```text
attacker seed + attacker donation + victim deposit
```

But share ownership is:

```text
attacker shares = 1
victim shares   = 0
totalSupply     = 1
```

The attacker redeems the only share and receives all vault assets.

---

## 5. Minimum Assets Required to Mint One Share

The zero-share condition can be expressed as a threshold problem.

Given:

```solidity
shares = assets * totalSupply / totalAssets;
```

To mint at least one share:

```text
assets * totalSupply / totalAssets >= 1
```

So approximately:

```text
assets >= ceil(totalAssets / totalSupply)
```

After the attacker creates this state:

```text
totalSupply = 1
totalAssets = donation + 1
```

the minimum deposit required to mint one share becomes:

```text
minAssetsForOneShare = donation + 1
```

Therefore, if:

```text
victimDeposit < donation + 1
```

then:

```text
victimShares = 0
```

This is the key mechanism. The attacker makes the vault’s asset/share ratio so extreme that normal-sized deposits round down to zero shares.

---

## 6. The First Depositor Is Not the Bug

The first depositor receiving one share for one wei is not the root problem.

The root problem is the combination of:

```text
low initial share supply
+ live-balance totalAssets()
+ direct donation sensitivity
+ floor rounding on deposit
+ no minimum shares-out protection
```

The first depositor only becomes dangerous because the protocol allows the exchange rate to be moved without minting new shares.

A more precise description is:

```text
The vault permits an extreme asset/share ratio under low share supply.
```

or:

```text
The vault allows donation-induced exchange-rate distortion before later deposits.
```

---

## 7. Solvent but Unfair

This attack is not primarily an insolvency bug.

The victim’s assets are inside the vault after deposit. The raw ERC20 balance is present. The vault is solvent in the narrow sense that it holds the assets.

The failure is in ownership allocation.

After the victim deposits:

```text
vault asset balance > 0
victim shares = 0
attacker owns 100% of totalSupply
```

So the asset exists, but the victim has no ownership claim on it.

This is why ERC4626 donation inflation is best understood as a share-accounting fairness failure:

```text
Assets are present, but the wrong party owns the claim.
```

---

## 8. Zero-Share Minting vs Partial Dilution

Zero-share minting is the most extreme version of the issue.

A more general version is partial dilution, where the victim receives nonzero shares but materially fewer than they would have received without the donation.

For example, without donation:

```text
attackerSeed = 1e18
victimDeposit = 100e18

victimShares = 100e18
```

With donation:

```text
attackerSeed = 1e18
donation = 100e18
victimDeposit = 100e18

totalSupply = 1e18
totalAssets = 101e18

victimShares = 100e18 * 1e18 / 101e18
             ≈ 0.990099e18
```

The victim receives nonzero shares, but far fewer than the no-donation baseline.

This distinction matters because not every real-world case will produce zero shares. The broader audit question is whether donation or exchange-rate manipulation can cause unfair share allocation.

---

## 9. What Virtual Offset Mitigates

`SafeVirtualOffsetVault` uses virtual assets and virtual shares:

```solidity
shares = assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
```

and:

```solidity
assets = shares * (totalAssets() + VIRTUAL_ASSETS) / (totalSupply + VIRTUAL_SHARES);
```

This does not stop direct donations from increasing `totalAssets()`.

The vault still reads live token balance:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

So donation still moves the exchange rate.

The mitigation is more specific:

```text
Virtual offset reduces the economic impact of low-supply donation inflation.
```

It does this by making the conversion math behave as if the vault already has a large effective share base.

In the toy implementation:

```solidity
VIRTUAL_ASSETS = 1;
VIRTUAL_SHARES = 1e18;
```

So even when real supply is tiny, the conversion formula uses:

```text
effectiveSupply = totalSupply + 1e18
```

This prevents the first depositor from cheaply controlling the entire effective ownership base.

---

## 10. What Virtual Offset Does Not Mitigate

Virtual offset should not be described as fully preventing donation inflation.

It does not:

```text
- reject direct donations
- ignore unsolicited token transfers
- keep exchange rate unchanged after donation
- isolate accounted assets from raw token balance
```

It only bounds the exploitability of the donation under low real share supply.

A more precise statement is:

```text
Virtual offset does not prevent donations from increasing totalAssets.
It reduces the profitability and zero-share impact of first-depositor donation inflation.
```

---

## 11. Internal Accounting as an Alternative Design

A different mitigation is internal asset accounting.

Instead of:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

the vault can track accounted assets internally:

```solidity
uint256 public accountedAssets;

function totalAssets() public view returns (uint256) {
    return accountedAssets;
}
```

Then `deposit()` increases `accountedAssets`, and `redeem()` decreases it.

Direct donations would increase the raw ERC20 balance but not the vault’s accounting value.

This design can prevent unsolicited donations from changing share price, but it introduces its own operational questions:

```text
- What happens to excess tokens sent directly to the vault?
- Can they be swept?
- Who can sweep them?
- Can sweeping create governance or trust assumptions?
- How does the vault reconcile raw balance and accounted balance?
```

So internal accounting is stronger against donation-driven exchange-rate manipulation, but it requires explicit handling of surplus assets.

---

## 12. Relation to Production ERC4626 Systems

This case study isolates the low-supply donation-inflation problem.

Production ERC4626 systems, such as Yearn-style tokenized strategies, must solve a broader family of share-accounting fairness problems, including:

```text
- first-depositor dominance
- donation sensitivity
- profit-locking fairness
- loss socialization
- fee accounting
- preview/deposit consistency
- withdrawal fairness
- strategy report timing
```

The toy vaults in this repo intentionally exclude these production concerns.

The point is to isolate one mechanism:

```text
low share supply + direct donation + floor rounding
```

and show why vault solvency is not enough.

The core lesson also applies to more complex systems:

```text
A vault can have enough assets while still assigning the ownership claim to the wrong cohort of users.
```

---

## 13. Audit Checklist

When reviewing ERC4626-style vaults, check:

```text
1. Does totalAssets() read raw token balance?
2. Can users transfer assets directly to the vault?
3. What happens when totalSupply is very small?
4. Can a first depositor create an extremely thin share supply?
5. Can donation increase assets without minting shares?
6. Can previewDeposit() return zero for a positive deposit?
7. Does deposit() allow minting zero shares?
8. Does the protocol enforce minSharesOut?
9. Are virtual assets / virtual shares used?
10. Are virtual offsets large enough for the asset decimals and expected deposit sizes?
11. Does the vault use internal asset accounting?
12. If internal accounting is used, how are unsolicited tokens handled?
13. Are integrations relying on previewDeposit without slippage protection?
14. Are empty-vault and low-supply states explicitly tested?
15. Are donation and rounding effects included in fuzz or invariant tests?
```

---

## 14. Tests Supporting This Mechanism

This repo includes tests for three layers.

### Vulnerable attack reproduction

```text
test/ERC4626Inflation.t.sol
```

Covers:

```text
- direct donation raises exchange rate without minting shares
- previewDeposit returns zero after donation
- victim deposit mints zero shares
- attacker redeems all vault assets
- zero-share threshold behavior
```

### Mechanism analysis

```text
test/ERC4626InflationAnalysis.t.sol
```

Covers:

```text
- minimum assets required to mint one share after donation
- extreme asset/share ratio formation
- solvent-but-unfair ownership allocation
- partial dilution with nonzero victim shares
- virtual offset does not ignore donation but bounds the effect
- virtual offset raises effective supply under low real supply
```

### Mitigation behavior

```text
test/ERC4626Mitigation.t.sol
```

Covers:

```text
- virtual offset prevents zero-share victim deposit
- attacker cannot redeem all assets
- attacker profit is bounded
- previewDeposit remains nonzero after donation
- normal deposits still mint shares
```

---

## 15. Final Takeaway

The vulnerable vault fails because direct donation can create an extreme asset/share ratio while share supply is very low.

The important observation is:

```text
The first depositor receiving one share is not the bug.
The bug is allowing that one-share supply to become the denominator for a donation-inflated asset base.
```

The attack turns a solvent vault into an unfair vault:

```text
The assets are present.
The ownership claim is wrong.
```

That is the central accounting risk this case study demonstrates.