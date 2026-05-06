# Limitations

## 1. Toy Model Only

This repository is a focused educational and research artifact.

It is not a production-ready ERC4626 implementation.

The contracts are intentionally minimal so that the donation inflation mechanism is easy to inspect.

The repo should be understood as:

```text
a mechanism case study
```

not:

```text
a complete vault library
```

---

## 2. Not a Full ERC4626 Implementation

The vaults in this repository only implement the functions needed for the case study.

They do not implement the full ERC4626 surface.

Missing or simplified areas include:

```text
- maxDeposit
- maxMint
- maxWithdraw
- maxRedeem
- mint
- withdraw
- full ERC4626 compliance edge cases
- complete metadata compatibility
- production-grade access patterns
```

The goal is not standards completeness.

The goal is to isolate the asset/share conversion risk.

---

## 3. Simplified ERC20 Assumptions

`MockERC20` is intentionally simple.

It does not model:

```text
- fee-on-transfer tokens
- rebasing tokens
- ERC777 hooks
- callback-based tokens
- blacklists
- paused transfers
- non-standard return values
- tokens with unusual decimals behavior
```

Production ERC4626 vaults may need to handle or explicitly reject these token behaviors.

This case study assumes a standard ERC20-like token.

---

## 4. No Reentrancy Modeling

The contracts do not include reentrancy guards.

The tests do not model reentrant token callbacks or malicious receiver behavior.

This is intentional.

The case study focuses only on:

```text
direct donation + low share supply + floor rounding
```

Reentrancy is an important production concern, but it is outside this artifact's scope.

---

## 5. No Oracle or External Price Modeling

This repository does not use price oracles.

It does not model:

```text
- oracle manipulation
- stale prices
- TWAP manipulation
- external price feeds
- cross-asset valuation
```

The vault uses a single asset and a single share token.

The issue is purely internal share accounting.

---

## 6. No Strategy Accounting

Production vaults often allocate funds to external strategies.

This repo does not model:

```text
- strategy debt
- strategy reports
- profit locking
- loss reporting
- withdrawal queues
- emergency shutdown
- unrealized PnL
- locked profit decay
```

Those mechanisms create additional share-accounting complexity.

This case study isolates a smaller issue: donation-induced exchange-rate distortion.

---

## 7. No Fee Accounting

The vaults do not implement:

```text
- management fees
- performance fees
- withdrawal fees
- deposit fees
- protocol fees
```

Fee logic can interact with share accounting and rounding.

Those interactions are intentionally excluded.

---

## 8. No Governance or Admin Model

The contracts do not include governance roles or admin-controlled configuration.

There is no model for:

```text
- pausing
- upgrades
- parameter changes
- role-based access control
- admin rescue functions
- emergency withdrawal
```

This is intentional.

The demonstrated attack does not depend on privileged roles.

It is triggered through ordinary deposit and ERC20 transfer behavior.

---

## 9. Virtual Offset Is Not Donation Isolation

`SafeVirtualOffsetVault` should not be interpreted as fully donation-proof.

It still uses live-balance accounting:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

Therefore, direct donations still increase `totalAssets()` and still move the exchange rate.

The virtual offset mitigation only bounds the low-supply donation attack by increasing effective supply:

```text
effectiveSupply = totalSupply + VIRTUAL_SHARES
```

Correct interpretation:

```text
Virtual offset reduces first-depositor donation extraction.
It does not ignore unsolicited donations.
```

---

## 10. Virtual Offset Calibration Is Not Universal

The toy mitigation uses:

```solidity
VIRTUAL_ASSETS = 1;
VIRTUAL_SHARES = 1e18;
```

These constants are chosen for clarity in this case study.

They are not presented as universally correct.

In a production vault, virtual offset parameters should consider:

```text
- asset decimals
- share decimals
- expected minimum deposit size
- expected TVL range
- acceptable rounding loss
- integration assumptions
- economic cost of attack
```

The tests only show that the chosen constants mitigate the demonstrated scenario.

---

## 11. No Full Fuzz or Invariant Campaign

The repo currently uses deterministic tests.

It does not include a full fuzzing or invariant-testing campaign.

Possible future invariants could include:

```text
- positive deposits should not mint zero shares under protected vaults
- attacker profit should be bounded under chosen virtual offset
- donation should not allow a first depositor to capture later depositor assets
- previewDeposit and deposit should remain consistent under fixed state
```

The current tests are sufficient for a focused case study but not a complete verification effort.

---

## 12. Internal Accounting Not Implemented

The notes discuss internal asset accounting as an alternative design.

However, the repository currently does not implement an `InternalAccountingVault`.

Such a vault would track:

```solidity
accountedAssets
```

instead of using:

```solidity
asset.balanceOf(address(this))
```

This could demonstrate a stronger donation-isolation model.

It is listed as a possible extension, not part of the current implementation.

---

## 13. No Production Integration Assumptions

The case study does not model external integrators.

It does not include:

```text
- routers
- aggregators
- front ends
- zap contracts
- strategy allocators
- lending integrations
- oracle consumers
```

In practice, integrators may add protections such as:

```text
- minSharesOut
- preview checks
- slippage limits
- deposit caps
- initialization guards
```

Those integration-level mitigations are discussed but not implemented.

---

## 14. No Mempool or MEV Simulation

The attack can be framed as a front-running or ordering problem, but this repo does not simulate mempool behavior.

It does not model:

```text
- transaction ordering
- private mempools
- sandwiching
- backrunning
- bundle submission
- probabilistic victim arrival
```

The tests assume a deterministic sequence of transactions.

This is enough to demonstrate the accounting mechanism but not enough to quantify realistic MEV feasibility.

---

## 15. No Claim About All ERC4626 Vaults

This artifact should not be read as a claim that all ERC4626 vaults are vulnerable.

The risk depends on implementation details, including:

```text
- totalAssets accounting
- initial share behavior
- zero-share handling
- virtual offset design
- internal accounting
- deposit slippage protection
- integration constraints
```

The repository demonstrates one vulnerable pattern and one mitigation pattern.

---

## 16. What This Artifact Is Useful For

This repository is useful for:

```text
- understanding ERC4626 donation inflation mechanics
- testing low-supply share-accounting behavior
- explaining solvent-but-unfair vault states
- comparing vulnerable and virtual-offset conversion math
- building audit checklists for share-based vaults
- creating a public proof-of-work security case study
```

It is especially useful as a minimal model for reasoning about:

```text
assets -> shares -> ownership claims
```

---

## 17. What This Artifact Is Not Useful For

This repository is not sufficient for:

```text
- deploying a production vault
- proving full ERC4626 compliance
- evaluating all Yearn-style strategy accounting risks
- modeling malicious tokens
- modeling reentrancy
- proving universal virtual offset safety
- replacing a full audit
```

---

## 18. Final Limitation Summary

The artifact is deliberately narrow.

It demonstrates one important accounting lesson:

```text
A vault can hold the assets while assigning the ownership claim unfairly.
```

The tests and notes are designed to make that mechanism clear, not to exhaustively cover every ERC4626 or vault-security issue.