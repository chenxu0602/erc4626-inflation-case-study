# Roadmap

## 1. Current Status

This repository currently contains a focused ERC4626 donation inflation case study.

Completed components:

```text
- minimal mock ERC20
- vulnerable ERC4626-style vault
- virtual-offset mitigation vault
- vulnerable attack reproduction tests
- mechanism analysis tests
- mitigation tests
- mechanism notes
- threat model
- case study write-up
- methodology
- limitations
```

Current expected test result:

```text
15 tests passed
0 failed
0 skipped
```

---

## 2. Completed Milestones

### Milestone 1: Vulnerable Vault

Status: completed

Files:

```text
src/MockERC20.sol
src/VulnerableVault.sol
test/ERC4626Inflation.t.sol
```

Implemented:

```text
- minimal ERC20 asset
- minimal ERC4626-style vulnerable vault
- live-balance totalAssets()
- first-depositor share minting
- direct donation attack path
```

Tested:

```text
- direct donation raises exchange rate without minting shares
- previewDeposit returns zero after donation
- victim deposit mints zero shares
- attacker redeems all vault assets
- zero-share threshold behavior
```

---

### Milestone 2: Virtual Offset Mitigation

Status: completed

Files:

```text
src/SafeVirtualOffsetVault.sol
test/ERC4626Mitigation.t.sol
```

Implemented:

```text
- virtual assets
- virtual shares
- effective supply conversion math
```

Tested:

```text
- victim receives nonzero shares under attack setup
- attacker cannot redeem all assets
- attacker profit is bounded
- previewDeposit remains nonzero
- normal deposits still work
```

---

### Milestone 3: Mechanism Analysis Tests

Status: completed

File:

```text
test/ERC4626InflationAnalysis.t.sol
```

Tested:

```text
- minimum assets required to mint one share after donation
- extreme asset/share ratio formation
- solvent-but-unfair ownership allocation
- partial dilution
- virtual offset does not ignore donation
- virtual offset raises effective supply under low real supply
```

---

### Milestone 4: Documentation

Status: completed or in progress

Files:

```text
notes/mechanism.md
notes/threat-model.md
notes/case-study.md
METHODOLOGY.md
LIMITATIONS.md
ROADMAP.md
README.md
```

Purpose:

```text
- explain the mechanism
- define the threat model
- document assumptions and limitations
- map tests to security properties
- provide an audit checklist
```

---

## 3. Near-Term Improvements

### 3.1 README Polish

Priority: high

Improve the root `README.md` so that it clearly communicates:

```text
- the purpose of the repo
- the vulnerable mechanism
- the test suite structure
- the mitigation model
- how to run the tests
- the key takeaway
```

Suggested sections:

```text
- Overview
- Core Mechanism
- Repository Structure
- Tests
- Results
- Security Lesson
- Limitations
```

---

### 3.2 Internal Accounting Vault

Priority: medium

Add a third vault model:

```text
src/InternalAccountingVault.sol
test/ERC4626InternalAccounting.t.sol
```

Purpose:

```text
Compare virtual offset with internal accounting.
```

Expected behavior:

```text
- direct donations increase raw token balance
- direct donations do not increase accountedAssets
- share conversion uses accountedAssets
- donation does not distort share price
```

Potential test cases:

```text
- directDonationDoesNotChangeTotalAssets()
- victimDepositNotDilutedByDonation()
- rawBalanceCanExceedAccountedAssets()
- surplusTokenHandlingRequiresExplicitPolicy()
```

This would make the mitigation comparison stronger:

```text
VulnerableVault:
    donation changes exchange rate and attack succeeds

SafeVirtualOffsetVault:
    donation changes exchange rate but attack is bounded

InternalAccountingVault:
    donation does not change accounting exchange rate
```

---

### 3.3 MinSharesOut Deposit Wrapper

Priority: medium

Add a simple wrapper or alternate deposit function:

```text
depositWithMinSharesOut(uint256 assets, address receiver, uint256 minSharesOut)
```

Purpose:

```text
Demonstrate user-side slippage protection for ERC4626 deposits.
```

Expected behavior:

```text
- deposit reverts if shares < minSharesOut
- zero-share deposit is rejected
- victim can protect against stale or manipulated exchange rate
```

Potential test cases:

```text
- depositRevertsWhenMinSharesOutNotMet()
- depositSucceedsWhenMinSharesOutMet()
- minSharesOutProtectsVictimAfterDonation()
```

---

### 3.4 Reject Zero-Share Deposits

Priority: medium

Add a minimal guarded vault variant or patch:

```solidity
require(shares > 0, "ZERO_SHARES");
```

Purpose:

```text
Show that rejecting zero-share deposits prevents the worst-case loss but does not fully solve partial dilution.
```

Potential test cases:

```text
- zeroShareDepositReverts()
- partialDilutionStillPossible()
```

This would clarify the difference between:

```text
zero-share protection
```

and:

```text
full donation-inflation mitigation
```

---

### 3.5 Fuzz Tests

Priority: medium

Add fuzz tests around:

```text
attackerSeed
donation
victimDeposit
virtualShares
virtualAssets
```

Possible properties:

```text
- vulnerable vault can produce zero-share deposits under low supply
- virtual offset keeps victim shares nonzero above chosen deposit threshold
- attacker profit is bounded for selected parameter ranges
- previewDeposit matches deposit under unchanged state
```

Example invariant-style questions:

```text
When can previewDeposit(assets) == 0?
How large must donation be to zero out a given victim deposit?
How does virtual offset change the attacker's cost curve?
```

---

### 3.6 Python / Jupyter Parameter Sweep

Priority: optional

Add a small Python analysis layer only after the Solidity artifact is complete.

Possible files:

```text
notebooks/01_erc4626_inflation_threshold.ipynb
scripts/plot_inflation_threshold.py
```

Possible figures:

```text
Figure 1: Minimum assets required to mint one share after donation
Figure 2: Zero-share region across donation and victim deposit sizes
Figure 3: Attacker final balance under vulnerable vs virtual-offset vault
Figure 4: Victim shares under different virtual share parameters
```

If added, initialize Python tooling separately:

```bash
uv init --bare
uv add numpy pandas matplotlib
```

This should remain optional. The current artifact is already complete as a Foundry-based case study.

---

## 4. Medium-Term Extensions

### 4.1 Historical Exploit Mapping

Priority: optional

Add a short note connecting this toy mechanism to known ERC4626 inflation / donation discussions.

Potential file:

```text
notes/historical-context.md
```

This should cite external sources if used in a public article.

Suggested topics:

```text
- ERC4626 inflation attack pattern
- virtual offset mitigation
- first-depositor attack
- donation-sensitive exchange rates
```

---

### 4.2 Production Vault Comparison

Priority: optional

Add a conceptual comparison to production vault systems.

Potential file:

```text
notes/production-vault-comparison.md
```

Possible topics:

```text
- Yearn-style tokenized strategies
- profit locking
- loss socialization
- fee accounting
- preview/deposit consistency
- donation handling
```

The goal would not be to audit Yearn or any production vault, but to explain how the toy mechanism relates to broader share-accounting fairness.

---

### 4.3 Report-Style PDF

Priority: optional

Create a report-style artifact for portfolio or client-facing use.

Potential structure:

```text
1. Executive Summary
2. Scope and Assumptions
3. Attack Mechanism
4. Proof of Concept
5. Mitigation Comparison
6. Review Checklist
7. Limitations
8. Appendix: Test Mapping
```

This could later be rendered as a PDF.

---

### 4.4 Medium Article

Priority: optional

Possible title:

```text
Solvent but Unfair: An ERC4626 Donation Inflation Case Study
```

Possible subtitle:

```text
How low share supply, direct donations, and floor rounding can misallocate vault ownership claims.
```

Suggested article structure:

```text
- why ERC4626 share accounting matters
- first depositor is not the bug
- donation creates extreme asset/share ratio
- victim zero-share deposit
- solvent but unfair
- virtual offset mitigation
- audit checklist
```

---

## 5. Non-Priorities

The following are intentionally not priorities for this repository:

```text
- building a production ERC4626 implementation
- implementing a full vault framework
- adding complex strategy accounting
- modeling malicious ERC20 tokens
- modeling reentrancy
- modeling oracle risk
- modeling governance/admin control
- adding frontend or deployment scripts
- optimizing gas
```

The repo should remain focused.

Its value comes from clarity, not feature completeness.

---

## 6. Suggested Next Steps

Immediate next steps:

```text
1. Finalize README.md.
2. Run forge test -vvv.
3. Commit the completed artifact.
4. Push to GitHub.
5. Optionally write a short LinkedIn/X post.
```

Optional next implementation step:

```text
Add InternalAccountingVault as a third comparison model.
```

Optional next content step:

```text
Draft a Medium article based on notes/mechanism.md and notes/case-study.md.
```

---

## 7. Long-Term Artifact Positioning

This repository can serve as one entry in a broader DeFi financial-security portfolio.

It demonstrates:

```text
- share-accounting reasoning
- ERC4626 mechanism analysis
- attack reproduction with Foundry
- mitigation comparison
- solvency vs ownership fairness distinction
- audit checklist construction
```

It fits well alongside future case studies on:

```text
- oracle manipulation
- reward accounting bugs
- read-only reentrancy
- lending solvency accounting
- liquidation edge cases
- AMM invariant manipulation
```

---

## 8. Final Roadmap Summary

The core artifact is already complete:

```text
vulnerable model
attack reproduction
mechanism analysis
virtual-offset mitigation
documentation
```

Future work should only be added if it strengthens the central message:

```text
A vault can be solvent while assigning ownership unfairly.
```

Do not let the repo become a general-purpose ERC4626 library.

Keep it small, focused, and audit-oriented.