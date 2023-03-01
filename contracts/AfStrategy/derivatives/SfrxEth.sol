// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/Iderivative.sol";
import "../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/curve/ICrvEthPool.sol";
import "../../interfaces/frax/IFrxETHMinter.sol";
import "hardhat/console.sol";

contract SfrxEth is IDERIVATIVE, Initializable, OwnableUpgradeable {
    address public constant sfrxEthAddress =
        0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant frxEthAddress =
        0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant frxEthCrvPoolAddress =
        0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address public constant frxEthMinterAddress =
        0xbAFA44EFE7901E04E39Dad13167D089C559c1138;

    uint256 public maxSlippage;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // This replaces the constructor for upgradeable contracts
    function initialize() public initializer {
        _transferOwnership(msg.sender);
        maxSlippage = ( 5 * 10 ** 16); // 5%
    }

    function setMaxSlippage(uint slippage) public onlyOwner {
        maxSlippage = slippage;
    }

    function withdraw(uint256 amount) public onlyOwner {
        IsFrxEth(sfrxEthAddress).redeem(amount, address(this), address(this));
        uint256 frxEthBalance = IERC20(frxEthAddress).balanceOf(address(this));
        IsFrxEth(frxEthAddress).approve(frxEthCrvPoolAddress, frxEthBalance);
        // TODO figure out if we want a min receive amount and what it should be
        // Currently set to 0. It "works" but may not be ideal long term
        ICrvEthPool(frxEthCrvPoolAddress).exchange(1, 0, frxEthBalance, 0);
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    function deposit() public payable onlyOwner returns (uint256) {
        IFrxETHMinter frxETHMinterContract = IFrxETHMinter(frxEthMinterAddress);
        uint256 sfrxBalancePre = IERC20(sfrxEthAddress).balanceOf(
            address(this)
        );
        frxETHMinterContract.submitAndDeposit{value: msg.value}(address(this));
        uint256 sfrxBalancePost = IERC20(sfrxEthAddress).balanceOf(
            address(this)
        );
        return sfrxBalancePost - sfrxBalancePre;
    }

    function ethPerDerivative(uint256 amount) public view returns (uint256) {
        if (amount == 0) return 0;
        uint256 frxAmount = IsFrxEth(sfrxEthAddress).convertToAssets(amount);
        return ICrvEthPool(frxEthCrvPoolAddress).get_dy(0, 1, frxAmount);
    }

    function totalEthValue() public view returns (uint256) {
        return ethPerDerivative(balance());
    }

    function balance() public view returns (uint256) {
        return IERC20(sfrxEthAddress).balanceOf(address(this));
    }

    receive() external payable {}
}
