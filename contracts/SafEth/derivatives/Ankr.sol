// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import "../../interfaces/IDerivative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/ankr/AnkrStaker.sol";
import "../../interfaces/ankr/AnkrEth.sol";
import "../../interfaces/curve/IAnkrEthEthPool.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Storage.sol";
import "./DerivativeBase.sol";

/// @title Derivative contract for ankr
/// @author Asymmetry Finance

contract Ankr is DerivativeBase {
    address public constant ANKR_ETH_ADDRESS =
        0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address public constant ANKR_STAKER_ADDRESS =
        0x84db6eE82b7Cf3b47E8F19270abdE5718B936670;
    address public constant ANKR_ETH_POOL =
        0xA96A65c051bF88B4095Ee1f2451C2A9d43F53Ae2;

    uint256 public maxSlippage;
    uint256 public underlyingBalance;

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _owner - owner of the contract which should be SafEth.sol
    */
    function initialize(address _owner) public initializer {
        super.init(_owner);
        maxSlippage = (1 * 1e16); // 1%
    }

    /**
        @notice - Return derivative name
    */
    function name() external pure returns (string memory) {
        return "AnkrEth";
    }

    /**
        @notice - Owner only function to set max slippage for derivative
        @param _slippage - Amount of slippage to set in wei
    */
    function setMaxSlippage(uint256 _slippage) public onlyManager {
        maxSlippage = _slippage;
    }

    /**
        @notice - Convert derivative into ETH
     */
    function withdraw(uint256 _amount) public onlyOwner {
        IERC20(ANKR_ETH_ADDRESS).approve(ANKR_ETH_POOL, _amount);
        uint256 balancePre = address(this).balance;
        IAnkrEthEthPool(ANKR_ETH_POOL).exchange(1, 0, _amount, 0);
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
        @notice - Owner only function to Deposit into derivative
        @dev - Owner is set to SafEth contract
     */
    function deposit() public payable onlyOwner returns (uint256) {
        uint256 ankrBalancePre = IERC20(ANKR_ETH_ADDRESS).balanceOf(
            address(this)
        );
        AnkrStaker(ANKR_STAKER_ADDRESS).stakeAndClaimAethC{value: msg.value}();
        uint256 received = IERC20(ANKR_ETH_ADDRESS).balanceOf(address(this)) -
            ankrBalancePre;
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
        return AnkrEth(ANKR_ETH_ADDRESS).sharesToBonds(1e18);
    }

    /**
        @notice - Total derivative balance
     */
    function balance() external view returns (uint256) {
        return underlyingBalance;
    }
}
