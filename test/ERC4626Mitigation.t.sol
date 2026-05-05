// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../src/MockERC20.sol";
import {SafeVirtualOffsetVault} from "../src/SafeVirtualOffsetVault.sol";

contract ERC4626MitigationTest is Test {
    MockERC20 internal asset;
    SafeVirtualOffsetVault internal vault;

    address internal attacker = makeAddr("attacker");
    address internal victim = makeAddr("victim");

    uint256 internal constant ATTACKER_SEED = 1;
    uint256 internal constant DONATION = 100e18;
    uint256 internal constant VICTIM_DEPOSIT = 100e18;

    function setUp() public {
        asset = new MockERC20("Mock Asset", "MOCK", 18);
        vault = new SafeVirtualOffsetVault(asset);

        asset.mint(attacker, ATTACKER_SEED + DONATION);
        asset.mint(victim, VICTIM_DEPOSIT);

        vm.prank(attacker);
        asset.approve(address(vault), type(uint256).max);

        vm.prank(victim);
        asset.approve(address(vault), type(uint256).max);
    }

    function test_virtualOffsetPreventsZeroShareVictimDeposit() public {
        // 1. Attacker makes the first tiny deposit.
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(ATTACKER_SEED, attacker);

        assertGt(attackerShares, 0, "attacker should receive nonzero shares");
        assertEq(vault.totalAssets(), ATTACKER_SEED, "vault should contain attacker seed");

        // 2. Attacker donates directly to the vault.
        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        assertEq(vault.totalAssets(), ATTACKER_SEED + DONATION, "vault should include direct donation");

        // 3. Victim deposit should still mint nonzero shares.
        uint256 victimPreviewShares = vault.previewDeposit(VICTIM_DEPOSIT);

        assertGt(victimPreviewShares, 0, "virtual offset should prevent zero-share preview");

        vm.prank(victim);
        uint256 victimShares = vault.deposit(VICTIM_DEPOSIT, victim);

        assertGt(victimShares, 0, "victim should receive nonzero shares");
        assertEq(victimShares, victimPreviewShares, "deposit should match preview");

        assertGt(vault.balanceOf(victim), 0, "victim should own shares");
    }

    function test_virtualOffsetPreventsAttackerFromRedeemingAllAssets() public {
        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        vm.prank(victim);
        uint256 victimShares = vault.deposit(VICTIM_DEPOSIT, victim);

        uint256 vaultAssetsBeforeRedeem = asset.balanceOf(address(vault));

        assertEq(
            vaultAssetsBeforeRedeem,
            ATTACKER_SEED + DONATION + VICTIM_DEPOSIT,
            "vault should contain seed, donation, and victim deposit"
        );

        vm.prank(attacker);
        uint256 attackerRedeemed = vault.redeem(attackerShares, attacker, attacker);

        assertLt(attackerRedeemed, vaultAssetsBeforeRedeem, "attacker should not redeem all vault assets");
        assertGt(asset.balanceOf(address(vault)), 0, "vault should retain assets after attacker redemption");
        assertGt(vault.balanceOf(victim), 0, "victim should still own shares");
        assertEq(vault.balanceOf(victim), victimShares, "victim shares should remain unchanged");
    }

    function test_virtualOffsetBoundsAttackerProfit() public {
        uint256 attackerInitialBalance = asset.balanceOf(attacker);

        vm.prank(attacker);
        uint256 attackerShares = vault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        vm.prank(victim);
        vault.deposit(VICTIM_DEPOSIT, victim);

        vm.prank(attacker);
        vault.redeem(attackerShares, attacker, attacker);

        uint256 attackerFinalBalance = asset.balanceOf(attacker);

        assertLe(
            attackerFinalBalance,
            attackerInitialBalance,
            "attacker should not profit under virtual offset mitigation"
        );
    }

    function test_previewDepositNonZeroAfterDonation() public {
        vm.prank(attacker);
        vault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(vault), DONATION);

        uint256 victimPreviewShares = vault.previewDeposit(VICTIM_DEPOSIT);

        assertGt(victimPreviewShares, 0, "victim preview should be nonzero after donation");
    }

    function test_virtualOffsetStillLetsNormalDepositsMintShares() public {
        vm.prank(victim);
        uint256 victimShares = vault.deposit(VICTIM_DEPOSIT, victim);

        assertGt(victimShares, 0, "normal deposit should mint shares");
        assertEq(vault.balanceOf(victim), victimShares, "victim should receive minted shares");
        assertEq(vault.totalAssets(), VICTIM_DEPOSIT, "vault should contain victim assets");
    }
}