// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/Iderivative.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/curve/ICrvEthPool.sol";
import "../../interfaces/frax/IFrxETHMinter.sol";
import "hardhat/console.sol";
import "../../interfaces/lido/IWStETH.sol";

contract WstEth is IDERIVATIVE, Initializable, OwnableUpgradeable {
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant lidoCrvPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant stEthToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // This replaces the constructor for upgradeable contracts
    function initialize() public initializer {
        _transferOwnership(msg.sender);
    }

    function withdraw(uint256 amount) public onlyOwner {
        IWStETH(wstETH).unwrap(amount);
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        // TODO figure out if we want a min receive amount and what it should be
        // Currently set to 0. It "works" but may not be ideal long term
        ICrvEthPool(lidoCrvPool).exchange(1, 0, stEthBal, 0);      
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    function deposit() public onlyOwner payable returns (uint256) {
        uint256 wstEthBalancePre = IWStETH(wstETH).balanceOf(address(this));
          // solhint-disable-next-line
        (bool sent, ) = wstETH.call{value: msg.value}("");
        require(sent, "Failed to send Ether");
        uint256 wstEthBalancePost = IWStETH(wstETH).balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalancePost - wstEthBalancePre;
        return (wstEthAmount);
    }

    function ethPerDerivative(uint256 amount) public view returns (uint256) {
        if(amount == 0) return 0;
        return IWStETH(wstETH).getStETHByWstETH(amount);
    }

    function totalEthValue() public view returns (uint256) {
        return ethPerDerivative(balance());
    }

    function balance() public view returns (uint256){
       return IERC20(wstETH).balanceOf(address(this));
    }

    receive() external payable {}
}

