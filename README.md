# ERC4626 Inflation Case Study

A focused security case study of ERC4626-style donation inflation, share-accounting edge cases, and virtual asset/share mitigation.

This repository demonstrates how a vault can remain solvent in raw asset balance while assigning ownership claims unfairly under low-supply donation inflation.

Core lesson:

```text
A vault can hold the assets and still assign the ownership claim to the wrong party.
```

This is not a full protocol audit and not a production ERC4626 implementation. It is a compact research artifact built with Foundry.

---

## Core Mental Model

```text
assets -> shares -> exchange rate -> preview/deposit/redeem behavior
```

The main review question is not only whether the ERC4626 interface exists, but whether share minting and redemption remain fair under edge cases such as:

```text
- empty vault initialization
- low share supply
- first depositor dominance
- direct asset donation
- floor rounding in convertToShares
- zero-share deposits
- partial dilution
- virtual asset/share mitigation
```

---

## Why This Repo Exists

ERC4626-style vault accounting can be fragile near zero supply.

A common donation inflation pattern is:

```text
1. Attacker deposits a tiny amount into an empty vault.
2. Attacker receives the first shares.
3. Attacker donates assets directly to the vault.
4. The asset/share ratio becomes extremely high.
5. Victim deposits assets.
6. Due to floor rounding, victim receives zero or too few shares.
7. Attacker redeems shares and captures value.
```

The bug class is not usually a broken transfer.

It is an ownership accounting failure:

```text
direct asset balance increase != fair share ownership increase
```

---

## Key Insight

The first depositor receiving one share for one wei is not the bug.

The bug is allowing that one-share supply to become the denominator for a donation-inflated asset base.

After the attacker deposits `1 wei` and donates `100e18`, the vault can enter this state:

```text
totalSupply = 1
totalAssets = 100e18 + 1
```

A victim depositing `100e18` receives:

```text
shares = 100e18 * 1 / (100e18 + 1)
shares = 0
```

The vault is solvent because the assets are present.

But ownership is unfair because the victim owns no shares.

---

## Repository Structure

```text
.
├── src/
│   ├── MockERC20.sol
│   ├── VulnerableVault.sol
│   └── SafeVirtualOffsetVault.sol
├── test/
│   ├── ERC4626Inflation.t.sol
│   ├── ERC4626InflationAnalysis.t.sol
│   └── ERC4626Mitigation.t.sol
├── notes/
│   ├── mechanism.md
│   ├── threat-model.md
│   └── case-study.md
├── outputs/
│   └── traces/
├── METHODOLOGY.md
├── LIMITATIONS.md
├── ROADMAP.md
├── foundry.toml
└── README.md
```

---

## Contracts

### `MockERC20.sol`

Minimal ERC20 token used for deterministic Foundry tests.

It intentionally avoids external dependencies so the case study remains self-contained.

### `VulnerableVault.sol`

A minimal ERC4626-style vault that intentionally models unsafe share accounting near low supply.

The vulnerable design uses live-balance accounting:

```solidity
function totalAssets() public view returns (uint256) {
    return assetToken.balanceOf(address(this));
}
```

and converts assets to shares with:

```solidity
shares = assets * totalSupply / totalAssets();
```

This allows direct donations to increase `totalAssets()` without minting new shares.

### `SafeVirtualOffsetVault.sol`

A minimal mitigation vault using virtual assets and virtual shares:

```solidity
shares = assets * (totalSupply + VIRTUAL_SHARES) / (totalAssets() + VIRTUAL_ASSETS);
```

This does not ignore donations.

It still reads live token balance for `totalAssets()`.

The mitigation works by raising effective supply under low real supply, making first-depositor donation extraction economically bounded.

---

## Test Suite

### Vulnerable Attack Tests

File:

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

### Mechanism Analysis Tests

File:

```text
test/ERC4626InflationAnalysis.t.sol
```

Covers:

```text
- minimum assets required to mint one share after donation
- extreme asset/share ratio formation
- solvent-but-unfair ownership allocation
- partial dilution with nonzero victim shares
- virtual offset does not ignore donation
- virtual offset raises effective supply under low real supply
```

### Mitigation Tests

File:

```text
test/ERC4626Mitigation.t.sol
```

Covers:

```text
- virtual offset prevents zero-share victim deposit
- attacker cannot redeem all vault assets
- attacker profit is bounded
- previewDeposit remains nonzero after donation
- normal deposits still mint shares
```

---

## Run Tests

```bash
forge test
```

Verbose:

```bash
forge test -vvv
```

Expected result:

```text
Ran 3 test suites:
15 tests passed
0 failed
0 skipped
```

---

## Review Map

| Layer | Main Question |
|---|---|
| Empty-vault initialization | Can the first depositor create an extremely thin share supply? |
| Share minting | Can a nonzero deposit mint zero or unfairly low shares? |
| Donation handling | Can direct transfers change the exchange rate without minting shares? |
| Preview semantics | Can `previewDeposit` expose zero-share behavior before deposit? |
| Redemption | Can attacker redeem donated/victim assets through inflated ownership? |
| Partial dilution | Can a victim receive nonzero but materially unfair shares? |
| Mitigation | Does virtual offset bound low-supply donation extraction? |

---

## Security Interpretation

ERC4626 donation inflation is a good example of a broader DeFi accounting lesson:

```text
Solvency protects asset presence.
Share accounting protects ownership fairness.
Both are required.
```

The issue is usually not that assets disappear from the vault.

The issue is that the ownership claim over those assets can be manipulated.

This bug class is especially relevant for:

```text
- yield vaults
- lending collateral vaults
- LP wrappers
- strategy vaults
- tokenized real-world asset vaults
- protocols integrating ERC4626 shares as collateral or accounting units
```

---

## Mitigation Notes

This repository compares two mitigation directions conceptually.

### Virtual Offset

Implemented in `SafeVirtualOffsetVault`.

Virtual offset:

```text
- does not reject donations
- does not ignore live token balance
- does not make the vault fully donation-proof
- does raise effective supply
- does bound first-depositor donation extraction
```

### Internal Accounting

Discussed in the notes but not implemented.

Internal accounting would track `accountedAssets` separately from raw token balance.

This can prevent direct donations from changing share price, but introduces surplus-token handling questions:

```text
- who owns unsolicited tokens?
- can they be swept?
- who can sweep them?
- how does the vault reconcile raw balance and accounted balance?
```

---

## Documentation

Additional notes:

```text
notes/mechanism.md      - detailed mechanism explanation
notes/threat-model.md   - scoped threat model and assumptions
notes/case-study.md     - narrative case study and audit lessons
METHODOLOGY.md          - research method and test design
LIMITATIONS.md          - explicit scope boundaries
ROADMAP.md              - completed work and optional extensions
```

---

## Relationship to Other Work

This repository complements:

- [`curve-stableswap-lab`](https://github.com/chenxu0602/curve-stableswap-lab)
  - AMM accounting, StableSwap NG semantics, LP oracle risk, and read-only reentrancy.
- `protocol-security-lab`
  - broader DeFi security review notes and practice artifacts.

Together, the case studies cover two recurring DeFi financial-security themes:

```text
Curve StableSwap:
  balances -> rates -> xp -> invariant / LP price

ERC4626 vaults:
  assets -> shares -> exchange rate -> ownership claim
```

---

## Status

Current status:

```text
- vulnerable vault implemented
- attack reproduction tests passing
- virtual-offset mitigation implemented
- mechanism analysis tests passing
- mitigation tests passing
- notes and methodology files completed
```

Current test result:

```text
15 tests passed
0 failed
0 skipped
```

Optional future extensions are tracked in `ROADMAP.md`.

---

## Disclaimer

This repository is not a full audit of any live protocol.

It does not prove the absence of vulnerabilities in ERC4626 implementations.

It is a focused educational and security research artifact intended to clarify the ERC4626 inflation / donation attack class and related share-accounting mitigations.