# Threat Model: ERC4626 Inflation / Donation Attack

## 1. Scope

This threat model covers a minimal ERC4626-style vault case study focused on donation-induced share-accounting distortion.

The artifact models three core components:

```text
1. A mock ERC20 asset
2. A vulnerable ERC4626-style vault
3. A virtual-offset mitigation vault
```

The purpose is not to audit a production vault. The purpose is to isolate one mechanism:

```text
low share supply + direct donation + floor rounding
```

and show how a vault can remain solvent while allocating ownership claims unfairly.

---

## 2. System Components

### MockERC20

`MockERC20` is a simple ERC20 test token used as the vault asset.

It supports:

```text
- mint
- transfer
- transferFrom
- approve
- balanceOf
- allowance
```

It is intentionally simple and does not model non-standard ERC20 behavior.

### VulnerableVault

`VulnerableVault` is a minimal ERC4626-style vault.

It intentionally uses live-balance accounting:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

It converts assets to shares using:

```solidity
shares = assets * totalSupply / totalAssets();
```

When `totalSupply == 0`, it mints shares 1:1:

```solidity
shares = assets;
```

This design is intentionally vulnerable to low-supply donation inflation.

### SafeVirtualOffsetVault

`SafeVirtualOffsetVault` uses virtual assets and virtual shares:

```solidity
shares = assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
```

It still reads live token balance for `totalAssets()`.

Therefore, it does not ignore direct donations. Instead, it bounds the economic effect of donation inflation under low real share supply.

---

## 3. Actors

### Attacker

The attacker can:

```text
- deposit into an empty vault
- receive the first shares
- transfer assets directly to the vault
- observe or anticipate victim deposits
- redeem shares after victim deposits
```

The attacker is not assumed to have admin privileges.

The attacker does not need to compromise the token or vault.

### Victim Depositor

The victim can:

```text
- approve the vault
- deposit assets
- rely on previewDeposit or the vault's deposit behavior
```

In the vulnerable scenario, the victim deposits after the attacker has created an extreme asset/share ratio.

### Integrator

An integrator may route user deposits into the vault.

The integrator may be vulnerable if it:

```text
- does not enforce minSharesOut
- does not reject zero-share deposits
- assumes positive asset deposits always mint positive shares
- relies on previewDeposit without slippage or state-change protection
```

### Vault Contract

The vault is responsible for:

```text
- converting assets to shares
- converting shares to assets
- minting and burning shares
- maintaining fair ownership claims
```

The vulnerable vault is technically solvent but fails to preserve fair ownership allocation.

---

## 4. Assets to Protect

### Depositor Assets

Depositor assets should not be transferred into the vault without receiving an appropriate ownership claim.

The central failure mode is:

```text
victim deposits assets
victim receives zero shares
attacker owns the only shares
```

### Share Ownership Claims

Vault shares represent claims on vault assets.

The system must protect the relationship between:

```text
assets contributed
shares minted
claim on future redemption
```

The attack breaks this relationship.

### Preview / Deposit Consistency

`previewDeposit(assets)` should accurately describe the expected shares minted by `deposit(assets, receiver)` under the same state.

This case study shows that preview may correctly return zero shares, but the vault still allows the victim deposit to proceed.

That is dangerous because correctness of preview alone is not sufficient.

### Low-Supply Accounting Safety

The empty-vault and low-supply states are special risk zones.

The vault should protect against:

```text
- first depositor dominance
- extreme exchange-rate formation
- direct donation sensitivity
- rounding-to-zero share mints
```

---

## 5. Trust Assumptions

This case study assumes:

```text
- the ERC20 token behaves normally
- token transfers do not reenter
- there are no transfer fees
- the attacker has no admin privileges
- the victim has approved the vault
- the vault uses integer arithmetic with floor rounding
```

The vulnerable behavior does not depend on:

```text
- malicious ERC20 behavior
- oracle manipulation
- admin misconfiguration
- governance attack
- reentrancy
- flash loans
```

The attack only requires ordinary ERC20 transfers and vault deposits.

---

## 6. Attacker Capabilities

The attacker can perform the following sequence:

```text
1. Deposit a minimal amount into an empty vault.
2. Receive the first shares.
3. Donate assets directly to the vault.
4. Wait for or front-run a victim deposit.
5. Redeem the only shares after the victim receives zero shares.
```

The critical capability is direct donation:

```solidity
asset.transfer(address(vault), donation);
```

This changes the vault's raw token balance without calling `deposit()` and without minting shares.

---

## 7. Non-Goals

This artifact does not model:

```text
- malicious ERC20 tokens
- fee-on-transfer tokens
- rebasing tokens
- ERC777 hooks
- reentrancy
- oracle manipulation
- strategy accounting
- profit locking
- performance fees
- management fees
- withdrawal queues
- multi-asset vaults
- lending collateralization
- governance attacks
```

These are important production concerns, but they are intentionally excluded to keep the mechanism isolated.

---

## 8. Security Properties

### Property 1: Positive Deposits Should Not Mint Zero Shares

A positive deposit should not silently mint zero ownership.

In the vulnerable vault, this property fails.

Example:

```text
totalSupply = 1
totalAssets = 100e18 + 1
victimDeposit = 100e18

victimShares = 100e18 * 1 / (100e18 + 1)
victimShares = 0
```

The victim transfers assets but receives no claim.

### Property 2: Direct Donations Should Not Create Extractable Ownership Distortion

A direct donation should not allow an existing shareholder to extract later depositor funds.

In the vulnerable vault, donation increases `totalAssets()` but not `totalSupply`.

This turns the first share into a claim on a much larger asset base.

### Property 3: Vault Solvency Is Not Enough

A vault can hold all assets and still be economically unsafe.

The vulnerable vault remains solvent in the raw-balance sense:

```text
vault asset balance > 0
```

But the ownership allocation is wrong:

```text
victim shares = 0
attacker owns 100% of totalSupply
```

The security property should be stronger than solvency:

```text
Depositors must receive fair ownership claims for contributed assets.
```

### Property 4: Mitigation Should Bound Low-Supply Donation Effects

A mitigation does not necessarily need to reject all donations.

But it should prevent cheap first-depositor dominance.

`SafeVirtualOffsetVault` does this by introducing:

```text
effectiveSupply = totalSupply + VIRTUAL_SHARES
effectiveAssets = totalAssets + VIRTUAL_ASSETS
```

This makes the first depositor unable to cheaply control the whole effective share base.

---

## 9. Attack Preconditions

The vulnerable attack requires:

```text
1. The vault is empty or has very low totalSupply.
2. The first depositor can mint a very small number of shares.
3. totalAssets() reads raw token balance.
4. Direct token transfers to the vault are possible.
5. The victim deposits after the donation.
6. deposit() allows zero-share minting.
7. There is no minSharesOut check.
```

The attack does not require the attacker to steal from the vault directly.

The attacker only manipulates the exchange rate before the victim's deposit.

---

## 10. Attack Impact

The impact is ownership misallocation.

In the zero-share case:

```text
victim loses deposited assets
victim receives no shares
attacker redeems all vault assets
```

The attacker profit is approximately the victim deposit, assuming the attacker can recover the seed and donation through redemption.

In the partial-dilution case:

```text
victim receives nonzero shares
victim receives materially fewer shares than in the no-donation baseline
attacker captures a larger share of vault ownership than economically fair
```

Zero-share minting is the extreme version. Partial dilution is the broader class.

---

## 11. Mitigation Model

### Virtual Offset

Virtual offset uses virtual assets and virtual shares in conversion math.

It reduces the impact of low-supply donation inflation.

It does not prevent direct donations from increasing live token balance.

Correct statement:

```text
Virtual offset does not ignore donation.
It bounds the effect of donation under low real share supply.
```

### Internal Asset Accounting

Internal accounting is a stronger defense against donation-sensitive exchange rates.

Instead of reading raw token balance:

```solidity
totalAssets = asset.balanceOf(address(this));
```

the vault tracks:

```solidity
accountedAssets
```

Direct donations increase raw token balance but do not change `accountedAssets`.

This prevents unsolicited token transfers from changing share price.

However, it introduces operational questions:

```text
- who owns surplus tokens?
- can surplus be swept?
- who can sweep?
- can sweeping create trust assumptions?
- how should accounted assets reconcile with raw balance?
```

### Minimum Shares-Out

Deposits should include a user-provided minimum shares-out check.

For example:

```text
deposit(assets, receiver, minSharesOut)
```

This protects users and integrators from accepting a stale or manipulated exchange rate.

### Reject Zero-Share Deposits

A minimal safety check is:

```solidity
require(shares > 0, "ZERO_SHARES");
```

This prevents the worst case where assets are accepted but no ownership claim is minted.

However, it does not fully solve partial dilution or donation-sensitive exchange-rate manipulation.

---

## 12. Review Checklist

When reviewing an ERC4626-style vault, ask:

```text
1. What happens when totalSupply == 0?
2. What happens when totalSupply is very small?
3. Does totalAssets() read live token balance?
4. Can users transfer assets directly to the vault?
5. Does direct donation change the exchange rate?
6. Can donation happen before a victim deposit?
7. Can previewDeposit return zero for positive assets?
8. Does deposit allow zero-share minting?
9. Is there a minSharesOut parameter?
10. Are virtual assets or virtual shares used?
11. Are virtual offsets calibrated to token decimals and expected deposit sizes?
12. Is internal accounting used?
13. If internal accounting is used, how are surplus tokens handled?
14. Are low-supply states covered by tests?
15. Are donation states covered by tests?
16. Are partial dilution cases tested, not only zero-share cases?
```

---

## 13. Test Mapping

This threat model is supported by the following tests.

### Vulnerable attack path

```text
test/ERC4626Inflation.t.sol
```

Covers:

```text
- direct donation raises exchange rate without minting shares
- previewDeposit returns zero after donation
- victim deposit mints zero shares
- attacker redeems all assets
- zero-share threshold
```

### Mechanism analysis

```text
test/ERC4626InflationAnalysis.t.sol
```

Covers:

```text
- minimum assets required to mint one share
- extreme asset/share ratio formation
- solvent-but-unfair accounting state
- partial dilution
- virtual offset not ignoring donation
- virtual offset raising effective supply
```

### Mitigation behavior

```text
test/ERC4626Mitigation.t.sol
```

Covers:

```text
- virtual offset prevents zero-share deposit
- attacker cannot redeem all vault assets
- attacker profit is bounded
- previewDeposit remains nonzero
- normal deposits still mint shares
```

---

## 14. Final Threat Model Summary

The primary threat is not insolvency.

The primary threat is unfair ownership allocation caused by donation-induced exchange-rate distortion under low share supply.

The vulnerable vault allows this state:

```text
asset balance exists
victim contributed assets
victim owns no shares
attacker owns the only claim
```

The central security requirement is:

```text
A vault must protect both asset solvency and ownership fairness.
```