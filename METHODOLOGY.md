# Methodology

## 1. Objective

This repository is a focused case study of ERC4626-style donation inflation attacks.

The objective is to isolate one accounting mechanism:

```text
low share supply + direct donation + floor rounding
```

and show how it can create unfair ownership allocation even when the vault remains solvent in a raw-balance sense.

This is not a full ERC4626 implementation and not a production vault audit framework. It is a minimal, reproducible security research artifact.

---

## 2. Research Question

The central question is:

```text
Can a vault hold the correct asset balance while assigning the ownership claim to the wrong user?
```

This case study answers yes.

The vulnerable vault allows an attacker to:

```text
1. seed an empty vault with a tiny deposit
2. donate assets directly to the vault
3. force a later depositor to mint zero or unfairly low shares
4. redeem the vault assets through the attacker's existing shares
```

The important distinction is:

```text
asset solvency != ownership fairness
```

---

## 3. Modeling Approach

The artifact uses a minimal model instead of a production ERC4626 implementation.

The model includes:

```text
- MockERC20
- VulnerableVault
- SafeVirtualOffsetVault
- Foundry tests
- mechanism notes
- threat model
- case study write-up
```

The contracts are intentionally small so that the share-accounting mechanism is visible.

The goal is not to optimize for feature completeness. The goal is to make the failure mode easy to inspect, test, and reason about.

---

## 4. Vulnerable Vault Construction

`VulnerableVault` implements a simplified ERC4626-style conversion formula:

```solidity
shares = assets * totalSupply / totalAssets();
```

When the vault is empty:

```solidity
if (totalSupply == 0) {
    shares = assets;
}
```

The vulnerable design choice is that `totalAssets()` reads the live ERC20 balance:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

This means direct ERC20 transfers to the vault affect the conversion rate even though no new shares are minted.

The vulnerable model intentionally allows this behavior so the donation inflation mechanism can be reproduced.

---

## 5. Attack Reproduction

The basic attack path is:

```text
1. Attacker deposits 1 wei into an empty vault.
2. Attacker receives 1 share.
3. Attacker donates 100e18 assets directly to the vault.
4. Victim deposits 100e18 assets.
5. Victim receives 0 shares due to floor rounding.
6. Attacker redeems the only share and receives all vault assets.
```

The critical state after donation is:

```text
totalSupply = 1
totalAssets = donation + 1
```

The victim share calculation becomes:

```text
shares = victimDeposit * totalSupply / totalAssets
shares = 100e18 * 1 / (100e18 + 1)
shares = 0
```

This demonstrates that the victim can contribute assets while receiving no ownership claim.

---

## 6. Threshold Analysis

The tests do not only reproduce the exploit. They also analyze the threshold condition.

Given:

```solidity
shares = assets * totalSupply / totalAssets;
```

a depositor must satisfy:

```text
assets >= ceil(totalAssets / totalSupply)
```

to mint at least one share.

When:

```text
totalSupply = 1
totalAssets = donation + 1
```

the minimum deposit required to mint one share is:

```text
donation + 1
```

Any smaller deposit rounds down to zero shares.

This threshold framing is important because it shows the attack is not magic. It is a direct result of extreme asset/share ratio formation under integer floor rounding.

---

## 7. Partial Dilution Analysis

Zero-share minting is the extreme case.

The case study also includes a partial dilution scenario where the victim receives nonzero shares but materially fewer than in a no-donation baseline.

This matters because real-world cases may not always produce zero shares.

The broader risk is:

```text
donation-induced exchange-rate distortion can unfairly reduce later depositor ownership
```

not only:

```text
victim receives exactly zero shares
```

The tests compare:

```text
baseline deposit without donation
vs.
deposit after donation
```

and verify that donation lowers the victim's minted shares.

---

## 8. Mitigation Comparison

The repository includes `SafeVirtualOffsetVault`, a minimal virtual-offset mitigation.

It uses:

```solidity
shares = assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
```

with:

```solidity
VIRTUAL_ASSETS = 1;
VIRTUAL_SHARES = 1e18;
```

This mitigation does not ignore donations.

`SafeVirtualOffsetVault` still uses:

```solidity
totalAssets = assetToken.balanceOf(address(this));
```

So direct donations still affect the exchange rate.

The mitigation works by raising effective supply:

```text
effectiveSupply = totalSupply + VIRTUAL_SHARES
```

This prevents the first depositor from cheaply controlling the entire effective ownership base.

The tests verify that under the same attack setup:

```text
- victim previewDeposit is nonzero
- victim deposit mints nonzero shares
- attacker cannot redeem all vault assets
- attacker profit is bounded
```

---

## 9. What the Tests Prove

The test suite proves the following points.

### Vulnerable attack reproduction

```text
- direct donation raises exchange rate without minting shares
- previewDeposit returns zero after donation
- victim deposit mints zero shares
- attacker redeems all vault assets
- zero-share threshold behavior is reproducible
```

### Mechanism analysis

```text
- minimum assets required to mint one share increases after donation
- direct donation creates an extreme asset/share ratio
- the vault can be solvent while victim ownership is zero
- partial dilution exists even when victim shares are nonzero
- virtual offset does not ignore donation
- virtual offset raises effective supply under low real supply
```

### Mitigation behavior

```text
- virtual offset prevents the zero-share victim deposit in the tested scenario
- attacker cannot redeem the full vault balance
- attacker profit is bounded
- normal deposits still mint shares
```

Current expected result:

```text
15 tests passed
0 failed
0 skipped
```

---

## 10. What the Tests Do Not Prove

The tests do not prove that the mitigation is sufficient for all production deployments.

They do not model:

```text
- malicious ERC20 behavior
- fee-on-transfer tokens
- rebasing tokens
- ERC777 hooks
- reentrancy
- strategy profit and loss reporting
- management fees
- performance fees
- withdrawal queues
- lending collateralization
- oracle manipulation
- governance-controlled configuration changes
```

The tests also do not prove that a specific virtual offset is correct for every asset or every expected deposit size.

They only show that the chosen virtual offset mitigates the demonstrated low-supply donation attack in this controlled model.

---

## 11. Design Alternatives Considered

### Reject zero-share deposits

A minimal protection is:

```solidity
require(shares > 0, "ZERO_SHARES");
```

This prevents the worst case where assets are accepted and no shares are minted.

However, it does not solve partial dilution or donation-sensitive exchange-rate manipulation.

### Add minSharesOut

A stronger user-facing protection is a minimum shares-out parameter.

Example:

```text
deposit(assets, receiver, minSharesOut)
```

This allows users or integrators to reject deposits when the exchange rate has moved against them.

### Use virtual assets and virtual shares

Virtual offset raises the effective supply and reduces first-depositor dominance.

This is the mitigation implemented in this repository.

### Use internal asset accounting

Internal accounting tracks accounted assets separately from raw token balance.

This can prevent direct donations from changing share price.

However, it introduces new questions around surplus tokens, sweeping rights, reconciliation, and governance assumptions.

---

## 12. Review Method

The review method used in this repository is:

```text
1. Build the smallest vulnerable model.
2. Reproduce the attack with a deterministic Foundry test.
3. Derive the mathematical threshold condition.
4. Add mechanism-level tests that explain why the attack works.
5. Add a mitigation model.
6. Test the same attack path against the mitigation.
7. Document the threat model, limitations, and audit checklist.
```

This sequence keeps the artifact grounded in executable evidence while also explaining the accounting mechanism.

---

## 13. Final Methodology Summary

This repository studies an ERC4626 accounting failure through a minimal model.

The main result is:

```text
A vault can be solvent in assets while unfair in ownership allocation.
```

The methodology is intentionally narrow:

```text
minimal code
deterministic tests
mechanism analysis
mitigation comparison
clear limitations
```

The goal is to build reusable intuition for reviewing ERC4626-style vaults and other share-based accounting systems.