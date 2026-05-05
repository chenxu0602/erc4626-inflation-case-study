# ERC4626 Inflation Case Study

Toy reproduction and security case study of ERC4626 inflation / donation attacks, share-accounting edge cases, and virtual asset/share mitigations.

This repository studies how ERC4626-style vault share accounting can be manipulated when an attacker controls the first deposit and donates assets directly to the vault before a victim deposits.

This is not a full protocol audit. It is a focused security research artifact.

## Core mental model

```text
assets -> shares -> exchange rate -> preview/deposit/redeem behavior
```

The main review question is not only whether the ERC4626 interface is implemented, but whether share minting and redemption remain fair under edge cases such as:

- empty vault initialization
- first depositor advantage
- direct asset donation
- rounding down in `convertToShares`
- preview/deposit mismatch
- virtual assets / virtual shares mitigations

## Why this repo exists

ERC4626 vaults appear simple, but their accounting can be fragile near zero supply.

A common inflation pattern is:

```text
1. Attacker deposits a tiny amount into an empty vault.
2. Attacker receives the first shares.
3. Attacker donates assets directly to the vault.
4. The vault exchange rate becomes artificially high.
5. Victim deposits assets.
6. Due to rounding, victim receives zero or too few shares.
7. Attacker redeems shares and captures value.
```

The bug class is not usually a broken transfer. It is an accounting interpretation problem:

```text
direct asset balance increase != fair share ownership increase
```

This repo isolates that mechanism with small Foundry tests.

## Current scope

Planned coverage:

- vulnerable ERC4626-style vault
- attacker first-deposit / donation setup
- victim zero-share or under-minted-share deposit
- attacker redemption after donation
- virtual asset/share mitigation
- rounding and preview behavior
- minimal threat model and case study notes

## Repository structure

```text
.
├── src/
│   ├── VulnerableVault.sol
│   ├── SafeVirtualOffsetVault.sol
│   └── MockERC20.sol
├── test/
│   ├── ERC4626Inflation.t.sol
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

## Planned contracts

### `VulnerableVault.sol`

A minimal ERC4626-style vault that intentionally models unsafe share accounting near zero supply.

Expected vulnerable behavior:

```text
empty vault
-> attacker deposits 1 wei
-> attacker donates assets directly
-> victim deposit mints 0 or too few shares
-> attacker redeems inflated share value
```

### `SafeVirtualOffsetVault.sol`

A safer vault variant using virtual assets / virtual shares to reduce first-depositor inflation.

Expected mitigation behavior:

```text
empty vault
-> attacker deposits tiny amount
-> attacker donates assets
-> victim deposit still mints meaningful shares
-> attacker cannot capture the victim's deposit through share inflation
```

### `MockERC20.sol`

Minimal ERC20 test token used by the vault tests.

## Planned test themes

### Inflation attack

The main attack test should demonstrate:

- attacker can seed an empty vault with a tiny deposit;
- attacker can donate assets directly to the vault;
- victim deposit receives zero or unfairly low shares;
- attacker redemption captures value that should have belonged to the victim.

### Preview behavior

The preview tests should examine:

- `previewDeposit`
- `convertToShares`
- rounding-down behavior
- whether a preview can return zero shares for nonzero assets
- whether integrators should reject zero-share deposits

### Mitigation behavior

The mitigation tests should demonstrate:

- virtual assets / virtual shares reduce donation-driven exchange-rate manipulation;
- victim receives nonzero shares under the same attack setup;
- attacker profit is eliminated or bounded;
- safe behavior is achieved without relying on trusted intervention.

## Run tests

```bash
forge test
```

For traces:

```bash
forge test -vvv
```

## Review map

| Layer | Main question |
|---|---|
| Empty-vault initialization | Can the first depositor control the initial exchange rate? |
| Share minting | Can a nonzero deposit mint zero or unfairly low shares? |
| Donation handling | Can direct asset transfers change exchange rate without minting shares? |
| Preview semantics | Do `previewDeposit` and actual deposit behavior expose dangerous rounding? |
| Redemption | Can attacker redeem donated/victim assets through inflated share ownership? |
| Mitigation | Do virtual assets/shares bound or remove the attack? |

## Security interpretation

ERC4626 inflation attacks are a good example of a broader DeFi accounting lesson:

```text
A vault can be technically solvent while share allocation is economically unfair.
```

The issue is usually not that assets disappear from the vault. The issue is that the ownership claim over those assets can be manipulated.

That makes this bug class especially relevant for:

- yield vaults
- lending collateral vaults
- LP wrappers
- strategy vaults
- tokenized real-world asset vaults
- protocols integrating ERC4626 shares as collateral or accounting units

## Relationship to other work

This repository is designed to complement:

- [`curve-stableswap-lab`](https://github.com/chenxu0602/curve-stableswap-lab)
  - AMM accounting, StableSwap NG semantics, LP oracle risk, and read-only reentrancy.
- `protocol-security-lab`
  - broader DeFi security review notes and practice artifacts.

Together, the two case studies cover two recurring DeFi financial-security themes:

```text
Curve StableSwap:
  balances -> rates -> xp -> invariant / LP price

ERC4626 vaults:
  assets -> shares -> exchange rate -> ownership claim
```

## Status

Research artifact in progress.

Initial setup:

- Foundry project initialized
- notes / roadmap / limitations structure created
- vulnerable and safe vault contracts pending
- attack and mitigation tests pending

## Planned milestones

### Phase 1 — Minimal vulnerable vault

- implement `MockERC20`
- implement `VulnerableVault`
- write first-deposit / donation / victim-deposit test
- demonstrate zero-share or under-minted victim deposit

### Phase 2 — Attack accounting

- add attacker redemption path
- quantify victim loss and attacker gain
- document the accounting transition step by step

### Phase 3 — Mitigation

- implement `SafeVirtualOffsetVault`
- add virtual assets / virtual shares
- show victim receives fairer shares
- show attacker profit is eliminated or bounded

### Phase 4 — Case study notes

- write `notes/mechanism.md`
- write `notes/threat-model.md`
- write `notes/case-study.md`
- add final review checklist for ERC4626 integrations

## Disclaimer

This repository is not a full audit of any live protocol and does not prove the absence of vulnerabilities in ERC4626 implementations.

It is a focused educational and security research artifact intended to clarify the ERC4626 inflation / donation attack class and related share-accounting mitigations.
