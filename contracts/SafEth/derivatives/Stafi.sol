// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/rocketpool/RocketStorageInterface.sol";
import "../../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../../interfaces/rocketpool/RocketSwapRouterInterface.sol";
import "../../interfaces/balancer/IVault.sol";
import "../../interfaces/IWETH.sol";
import "../../interfaces/stafi/IStafi.sol";
import "../../interfaces/stafi/IStafiUserDeposit.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./DerivativeBase.sol";

/// @title Derivative contract for Stafi
/// @author Asymmetry Finance

contract Stafi is DerivativeBase {
    address public constant STAFI_TOKEN =
        0x9559Aaa82d9649C7A7b220E7c461d2E74c9a3593;
    address public constant STAFI_USER_DEPOSIT =
        0xc12dfb80d80d564DB9b180AbF61a252eE6355058;
    address private constant W_ETH_ADDRESS =
        0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public maxSlippage;
    uint256 public underlyingBalance;

    IVault public constant BALANCER_VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which should be SafEth.sol
    */
    function initialize(address _owner) external initializer {
        super.init(_owner);
        maxSlippage = (1 * 1e16); // 1%
    }

    /**
        @notice - Return derivative name
    */
    function name() external pure returns (string memory) {
        return "Stafi";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
        @param _slippage - new slippage amount in wei
    */
    function setMaxSlippage(uint256 _slippage) external onlyManager {
        maxSlippage = _slippage;
    }

    /**
        @notice - Convert derivative into ETH
        @param _amount - amount of stafi to convert
     */
    function withdraw(uint256 _amount) external onlyOwner {
        IVault.SingleSwap memory swap;
        swap
            .poolId = 0xb08885e6026bab4333a80024ec25a1a3e1ff2b8a000200000000000000000445;
        swap.kind = IVault.SwapKind.GIVEN_IN;
        swap.assetIn = address(STAFI_TOKEN);
        swap.assetOut = address(0x0000000000000000000000000000000000000000);
        swap.amount = _amount;
        IVault.FundManagement memory fundManagement;
        fundManagement.sender = address(this);
        fundManagement.recipient = address(this);
        fundManagement.fromInternalBalance = false;
        fundManagement.toInternalBalance = false;
        IERC20(STAFI_TOKEN).approve(address(BALANCER_VAULT), _amount);
        uint256 balancePre = address(this).balance;
        BALANCER_VAULT.swap(swap, fundManagement, 0, block.timestamp);
        underlyingBalance = super.finalChecks(
            ethPerDerivative(true),
            _amount,
            maxSlippage,
            address(this).balance - balancePre,
            false,
            underlyingBalance
        );
    }

    /**
        @notice - Deposit into stafi derivative
     */
    function deposit() external payable onlyOwner returns (uint256) {
        uint256 stafiBalancePre = IStafi(STAFI_TOKEN).balanceOf(address(this));
        IVault.SingleSwap memory swap;
        swap
            .poolId = 0xb08885e6026bab4333a80024ec25a1a3e1ff2b8a000200000000000000000445;
        swap.kind = IVault.SwapKind.GIVEN_IN;
        swap.assetIn = address(W_ETH_ADDRESS);
        swap.assetOut = address(STAFI_TOKEN);
        swap.amount = msg.value;
        IVault.FundManagement memory fundManagement;
        fundManagement.sender = address(this);
        fundManagement.recipient = address(this);
        fundManagement.fromInternalBalance = false;
        IWETH(W_ETH_ADDRESS).deposit{value: msg.value}();
        IERC20(W_ETH_ADDRESS).approve(address(BALANCER_VAULT), msg.value);
        BALANCER_VAULT.swap(swap, fundManagement, 0, block.timestamp);
        uint256 received = IStafi(STAFI_TOKEN).balanceOf(address(this)) -
            stafiBalancePre;
        underlyingBalance = super.finalChecks(
            ethPerDerivative(true),
            msg.value,
            maxSlippage,
            received,
            true,
            underlyingBalance
        );
        return received;
    }

    /**
        @notice - Get price of derivative in terms of ETH
     */
    function ethPerDerivative(bool) public view returns (uint256) {
        return IStafi(STAFI_TOKEN).getExchangeRate();
    }

    /**
        @notice - Total derivative balance
     */
    function balance() external view returns (uint256) {
        return underlyingBalance;
    }
}
