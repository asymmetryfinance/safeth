// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/curve/IFrxEthEthPool.sol";
import "../../interfaces/frax/IFrxETHMinter.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "./DerivativeBase.sol";

/// @title Derivative contract for sfrxETH
/// @author Asymmetry Finance
contract SfrxEth is DerivativeBase {
    address private constant SFRX_ETH_ADDRESS =
        0xac3E018457B222d93114458476f3E3416Abbe38F;
    address private constant FRX_ETH_ADDRESS =
        0x5E8422345238F34275888049021821E8E08CAa1f;
    address private constant FRX_ETH_CRV_POOL_ADDRESS =
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address private constant FRX_ETH_MINTER_ADDRESS =
        0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    uint256 public maxSlippage;
    uint256 public underlyingBalance;
    uint256 public depegSlippage;

    error FrxDepegged();
    event DepegSlippageSet(uint256 depegSlippage);

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
    function name() public pure returns (string memory) {
        return "Frax";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
    */
    function setMaxSlippage(uint256 _slippage) external onlyManager {
        maxSlippage = _slippage;
    }

    /**
        @notice - Owner only function to Convert derivative into ETH
        @dev - Owner is set to SafEth contract
        @param _amount - Amount to withdraw
     */
    function withdraw(uint256 _amount) external onlyOwner {
        uint256 frxEthBalanceBefore = IERC20(FRX_ETH_ADDRESS).balanceOf(
            address(this)
        );
        IsFrxEth(SFRX_ETH_ADDRESS).redeem(
            _amount,
            address(this),
            address(this)
        );
        uint256 frxEthBalanceAfter = IERC20(FRX_ETH_ADDRESS).balanceOf(
            address(this)
        );
        uint256 frxEthReceived = frxEthBalanceAfter - frxEthBalanceBefore;
        IsFrxEth(FRX_ETH_ADDRESS).approve(
            FRX_ETH_CRV_POOL_ADDRESS,
            frxEthReceived
        );
        uint256 ethBalanceBefore = address(this).balance;
        IFrxEthEthPool(FRX_ETH_CRV_POOL_ADDRESS).exchange(
            1,
            0,
            frxEthReceived,
            0
        );
        underlyingBalance = super.finalChecks(
            ethPerDerivative(true),
            _amount,
            maxSlippage,
            address(this).balance - ethBalanceBefore,
            false,
            underlyingBalance
        );
    }

    /**
        @notice - Owner only function to Deposit into derivative
        @dev - Owner is set to SafEth contract
     */
    function deposit() external payable onlyOwner returns (uint256) {
        IFrxETHMinter frxETHMinterContract = IFrxETHMinter(
            FRX_ETH_MINTER_ADDRESS
        );
        uint256 sfrxBalancePre = IERC20(SFRX_ETH_ADDRESS).balanceOf(
            address(this)
        );
        frxETHMinterContract.submitAndDeposit{value: msg.value}(address(this));
        uint256 received = IERC20(SFRX_ETH_ADDRESS).balanceOf(address(this)) -
            sfrxBalancePre;
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
    function ethPerDerivative(bool _validate) public view returns (uint256) {
        // There is no chainlink price fees for frxEth
        // We making the assumption that frxEth is always priced 1-1 with eth
        // revert if the curve oracle price suggests otherwise
        // Theory is its very hard for attacker to manipulate price away from 1-1 for any long period of time
        // and if its depegged attack probably cant maniulate it back to 1-1
        uint256 oraclePrice = IFrxEthEthPool(FRX_ETH_CRV_POOL_ADDRESS)
            .price_oracle();
        uint256 priceDifference;
        if (oraclePrice > 1e18) priceDifference = oraclePrice - 1e18;
        else priceDifference = 1e18 - oraclePrice;

        uint256 depeg = depegSlippage > 0 ? depegSlippage : 4e15; // base depeg slippage
        if (_validate && priceDifference > depeg) revert FrxDepegged();

        uint256 frxEthAmount = IsFrxEth(SFRX_ETH_ADDRESS).convertToAssets(1e18);
        return ((frxEthAmount * oraclePrice) / 10 ** 18);
    }

    /**
        @notice - Total derivative balance
     */
    function balance() public view returns (uint256) {
        return underlyingBalance;
    }

    /**
        @notice - Set depeg slippage
        @dev - This will revert if crv pool is depegged past the slippage amount
        @param _depegSlippage - Slippage amount to revert at
     */
    function setDepegSlippage(uint256 _depegSlippage) external onlyManager {
        depegSlippage = _depegSlippage;
        emit DepegSlippageSet(_depegSlippage);
    }
}
