// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/IDerivative.sol";
import "../../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../interfaces/ankr/AnkrStaker.sol";
import "hardhat/console.sol";

contract Ankr is IDerivative, Initializable, OwnableUpgradeable {

    address ankrEthAddress = 0xE95A203B1a91a908F9B9CE46459d101078c2c3cb;
    address ankrStakerAddress = 0x84db6eE82b7Cf3b47E8F19270abdE5718B936670;

    uint256 public maxSlippage;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // This replaces the constructor for upgradeable contracts
    function initialize() public initializer {
        _transferOwnership(msg.sender);
        maxSlippage = (5 * 10 ** 16); // 5%
    }

    function setMaxSlippage(uint slippage) public onlyOwner {
        maxSlippage = slippage;
    }

    function withdraw(uint256 amount) public onlyOwner {
        (bool sent, ) = address(msg.sender).call{value: address(this).balance}(
            ""
        );
        require(sent, "Failed to send Ether");
    }

    function deposit() public payable onlyOwner returns (uint256) {
        uint256 ankrBalancePre = IERC20(ankrEthAddress).balanceOf(
            address(this)
        );
        AnkrStaker(ankrStakerAddress).stakeAndClaimAethC{value: msg.value}(address(this));
        uint256 ankrBalancePost = IERC20(ankrEthAddress).balanceOf(
            address(this)
        );
        return ankrBalancePost - ankrBalancePre;
    }

    function ethPerDerivative() public view returns (uint256) {
        return 0;
    }

    function totalEthValue() public view returns (uint256) {
        return (ethPerDerivative() * balance()) / 10 ** 18;
    }

    function balance() public view returns (uint256) {
        return IERC20(ankrEthAddress).balanceOf(address(this));
    }

    receive() external payable {}
}
