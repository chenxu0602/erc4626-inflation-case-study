## Relation to Production ERC4626 Systems

This case study isolates the low-supply donation-inflation problem. Production vaults such as Yearn-style tokenized strategies must solve a broader family of share-accounting fairness problems: first-depositor dominance, donation sensitivity, profit-locking fairness, loss socialization, fee accounting, and preview/deposit consistency.

The core lesson is the same: vault solvency alone is not enough. The accounting system must also preserve fair ownership claims across time and across user cohorts.

The exploit is not caused by the first depositor receiving one share for one wei of assets. That initial exchange rate is reasonable in an empty vault.

The problem appears after a direct donation changes the asset/share ratio without minting new shares. The vault moves from:

- `totalSupply = 1`
- `totalAssets = 1`

to:

- `totalSupply = 1`
- `totalAssets = donation + 1`

At that point, the minimum asset amount required to mint one share becomes approximately `donation + 1`.

Any deposit smaller than that threshold rounds down to zero shares.