// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MockERC20} from "./MockERC20.sol";

/// @notice Minimal ERC4626-style vault intentionally vulnerable to donation inflation.
/// @dev This is not a full ERC4626 implementation. It is a focused case-study contract.
contract VulnerableVault {
    MockERC20 public immutable assetToken;

    string public name;
    string public symbol;
    uint8 public immutable decimals;

    uint256 public totalSupply;

    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    event Transfer(address indexed from, address indexed to, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 amount);
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed caller,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );

    constructor(MockERC20 asset_) {
        assetToken = asset_;

        name = "Vulnerable ERC4626 Vault Share";
        symbol = "vSHARE";
        decimals = asset_.decimals();
    }

    function asset() external view returns (address) {
        return address(assetToken);
    }

    /// @notice Vulnerable behavior: totalAssets reads the live token balance.
    /// @dev Direct donations increase totalAssets without minting new shares.
    function totalAssets() public view returns (uint256) {
        return assetToken.balanceOf(address(this));
    }

    function convertToShares(uint256 assets) public view returns (uint256 shares) {
        uint256 supply = totalSupply;

        if (supply == 0) {
            shares = assets;
        } else {
            shares = assets * supply / totalAssets();
        }
    }

    function convertToAssets(uint256 shares) public view returns (uint256 assets) {
        uint256 supply = totalSupply;

        if (supply == 0) {
            assets = shares;
        } else {
            assets = shares * totalAssets() / supply;
        }
    }

    function previewDeposit(uint256 assets) external view returns (uint256 shares) {
        shares = convertToShares(assets);
    }

    function previewRedeem(uint256 shares) external view returns (uint256 assets) {
        assets = convertToAssets(shares);
    }

    function deposit(uint256 assets, address receiver) external returns (uint256 shares) {
        require(receiver != address(0), "ZERO_RECEIVER");
        require(assets > 0, "ZERO_ASSETS");

        shares = convertToShares(assets);

        require(assetToken.transferFrom(msg.sender, address(this), assets), "TRANSFER_FROM_FAILED");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);
    }

    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets) {
        require(receiver != address(0), "ZERO_RECEIVER");
        require(shares > 0, "ZERO_SHARES");

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max) {
                require(allowed >= shares, "INSUFFICIENT_ALLOWANCE");
                allowance[owner][msg.sender] = allowed - shares;
            }
        }

        assets = convertToAssets(shares);

        _burn(owner, shares);

        require(assetToken.transfer(receiver, assets), "TRANSFER_FAILED");

        emit Withdraw(msg.sender, receiver, owner, assets, shares);
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        _transferShares(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];

        if (allowed != type(uint256).max) {
            require(allowed >= amount, "INSUFFICIENT_ALLOWANCE");
            allowance[from][msg.sender] = allowed - amount;
        }

        _transferShares(from, to, amount);
        return true;
    }

    function _mint(address to, uint256 amount) internal {
        totalSupply += amount;
        balanceOf[to] += amount;

        emit Transfer(address(0), to, amount);
    }

    function _burn(address from, uint256 amount) internal {
        require(balanceOf[from] >= amount, "INSUFFICIENT_SHARES");

        balanceOf[from] -= amount;
        totalSupply -= amount;

        emit Transfer(from, address(0), amount);
    }

    function _transferShares(address from, address to, uint256 amount) internal {
        require(to != address(0), "ZERO_ADDRESS");
        require(balanceOf[from] >= amount, "INSUFFICIENT_SHARES");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;

        emit Transfer(from, to, amount);
    }
}