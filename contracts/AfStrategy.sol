// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IAfETH.sol";
import "./interfaces/frax/IFrxETHMinter.sol";
import "./interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/uniswap/ISwapRouter.sol";
import "./interfaces/curve/ICrvEthPool.sol";
import "./interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "./interfaces/rocketpool/RocketStorageInterface.sol";
import "./interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "./interfaces/lido/IWStETH.sol";
import "./interfaces/lido/IstETH.sol";
import "./Vault.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./constants.sol";
import "hardhat/console.sol";

contract AfStrategy is Ownable {
    event StakingPaused(bool paused);
    event UnstakingPaused(bool paused);

    AggregatorV3Interface private constant CHAIN_LINK_ETH_FEED =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
    RocketStorageInterface private constant ROCKET_STORAGE =
        RocketStorageInterface(rocketStorageAddress);
    ISwapRouter private constant SWAP_ROUTER =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address public afETH;
    uint256 private numberOfDerivatives = 3;

    uint256 private constant ROCKET_POOL_LIMIT = 5000000000000000000000; // TODO: make changeable by owner
    bool public pauseStaking = false;
    bool public pauseUnstaking = false;

    function rethAddress() public view returns(address) {
        return ROCKET_STORAGE.getAddress(keccak256(abi.encodePacked("contract.address", "rocketTokenRETH")));
    }

    constructor(address _afETH) {
        afETH = _afETH;
    }

    // Eth value of all derivatives in this contract if they were redeemed
    function underlyingValue() public view returns(uint256) {
        uint256 totalSfrxEthValue = ethPerSfrxAmount(IERC20(sfrxEthAddress).balanceOf(address(this)));
        uint256 totalRethValue = ethPerRethAmount(IERC20(rethAddress()).balanceOf(address(this)));
        uint256 totalWstEthValue = ethPerWstAmount(IERC20(wstETH).balanceOf(address(this)));
        return totalSfrxEthValue + totalRethValue + totalWstEthValue;
    }

    function calculatePrice(uint256 uv, uint256 totalSupply) public pure returns(uint256) {
        return  ( 10 ** 18 * uv / totalSupply);
    }

    // special case for getting a price estimate before a deposit has been made
    function startingPrice() public view returns (uint256) {
        uint256 fakeTotalSfrxEthValue = ethPerSfrxAmount(10 ** 18);
        uint256 fakeTotalRethValue = ethPerRethAmount(10 ** 18);
        uint256 fakeTotalSstEthValue = ethPerWstAmount(10 ** 18);
        uint256 fakeUnderlyingValue = fakeTotalSfrxEthValue + fakeTotalRethValue + fakeTotalSstEthValue;
        uint256 fakeTotalSupply = 3 * 10 ** 18;
        return calculatePrice(fakeUnderlyingValue, fakeTotalSupply);
    }

    function price() public view returns(uint256) {
        uint256 totalSupply = IAfETH(afETH).totalSupply();
        if(totalSupply == 0) return startingPrice();
        return calculatePrice(underlyingValue(), totalSupply);
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN/CLOSE POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function stake() public payable {
        require(pauseStaking == false, "staking is paused");

        uint256 ethPerDerivative = msg.value / numberOfDerivatives;

        uint256 preDepositPrice = price();

        uint256 sfrxAmount = depositSfrax(ethPerDerivative);
        uint256 rethAmount = depositREth(ethPerDerivative);
        uint256 wstAmount = depositWstEth(ethPerDerivative);

        uint256 totalStakeValueEth = ethPerSfrxAmount(sfrxAmount) + ethPerRethAmount(rethAmount) + ethPerWstAmount(wstAmount);

        uint256 mintAmount = (totalStakeValueEth * 10 ** 18) / preDepositPrice;

        IAfETH(afETH).mint(msg.sender, mintAmount);
    }

    function unstake(uint256 safEthAmount) public {
        require(pauseUnstaking == false, "unstaking is paused");

        uint256 sfrxBalance = IERC20(sfrxEthAddress).balanceOf(address(this));
        uint256 rethBalance = IERC20(rethAddress()).balanceOf(address(this));
        uint256 wstBalance = IERC20(wstETH).balanceOf(address(this));

        uint256 safEthTotalSupply = IAfETH(afETH).totalSupply();

        // unstake percent of pool that user owns equally from all derivatives
        uint256 sfrxAmount = (sfrxBalance * safEthAmount) / safEthTotalSupply;
        uint256 rethAmount = (rethBalance * safEthAmount) / safEthTotalSupply;
        uint256 wstAmount = (wstBalance * safEthAmount) / safEthTotalSupply;

        uint256 ethAmountBefore = address(this).balance;

        withdrawREth(rethAmount);
        withdrawWstEth(wstAmount);
        withdrawSfrax(sfrxAmount);
        IAfETH(afETH).burn(msg.sender, safEthAmount);

        uint256 ethAmountAfter = address(this).balance;
        uint256 ethAmountToWithdraw = ethAmountAfter - ethAmountBefore;
        // solhint-disable-next-line
        address(msg.sender).call{value: ethAmountToWithdraw}("");
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY METHODS
    //////////////////////////////////////////////////////////////*/

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn
    ) public returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(SWAP_ROUTER), amountIn);
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });
        amountOut = SWAP_ROUTER.exactInputSingle(params);
    }

    // utilize Lido's wstETH shortcut by sending ETH to its fallback function
    // send ETH and bypass stETH, recieve wstETH for BAL pool
    function depositWstEth(uint256 amount)
        public
        payable
        returns (uint256 wstEthMintAmount)
    {
        uint256 wstEthBalancePre = IWStETH(wstETH).balanceOf(address(this));
          // solhint-disable-next-line
        (bool sent, ) = wstETH.call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wstEthBalancePost = IWStETH(wstETH).balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalancePost - wstEthBalancePre;
        return (wstEthAmount);
    }

    function depositSfrax(uint256 amount) public payable returns (uint256) {
        IFrxETHMinter frxETHMinterContract = IFrxETHMinter(frxEthMinterAddress);
        uint256 sfrxBalancePre = IERC20(sfrxEthAddress).balanceOf(
            address(this)
        );
        frxETHMinterContract.submitAndDeposit{value: amount}(address(this));
        uint256 sfrxBalancePost = IERC20(sfrxEthAddress).balanceOf(
            address(this)
        );
        return sfrxBalancePost - sfrxBalancePre;
    }

    function depositREth(uint256 amount)
        public
        payable
        returns (uint256 rEthAmount)
    {
        // Per RocketPool Docs query deposit pool address each time it is used
        address rocketDepositPoolAddress = ROCKET_STORAGE.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );
        bool canDeposit = rocketDepositPool.getBalance() + amount <=
            ROCKET_POOL_LIMIT;
        if (!canDeposit) {
            IWETH(wETH).deposit{value: amount}();
            uint256 amountSwapped = swapExactInputSingleHop(
                wETH,
                rethAddress(),
                500,
                amount
            );
            return amountSwapped;
        } else {
            address rocketTokenRETHAddress = ROCKET_STORAGE.getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            );
            RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
                rocketTokenRETHAddress
            );
            uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
            rocketDepositPool.deposit{value: amount}();
            uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
            require(rethBalance2 > rethBalance1, "No rETH was minted");
            uint256 rethMinted = rethBalance2 - rethBalance1;
            return (rethMinted);
        }
    }

    function withdrawREth(uint256 _amount) public {
        address rETH = rethAddress();
        RocketTokenRETHInterface(rETH).burn(_amount);
    }

    function withdrawWstEth(uint256 _amount) public {
        IWStETH(wstETH).unwrap(_amount); // TODO: not using right amount of wstETH
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        // convert stETH to ETH
        ICrvEthPool(lidoCrvPool).exchange(1, 0, stEthBal, 0);        
    }

    function withdrawSfrax(uint256 amount) public {
        IsFrxEth(sfrxEthAddress).redeem(amount, address(this), address(this));
        uint256 frxEthBalance = IERC20(frxEthAddress).balanceOf(address(this));
        IsFrxEth(frxEthAddress).approve(frxEthCrvPoolAddress, frxEthBalance);
        // TODO figure out if we want a min receive amount and what it should be
        // Currently set to 0. It "works" but may not be ideal long term
        ICrvEthPool(frxEthCrvPoolAddress).exchange(1, 0, frxEthBalance, 0);
    }

    /*//////////////////////////////////////////////////////////////
                        PRICE HELPER METHODS
    //////////////////////////////////////////////////////////////*/

    // how much eth to receive for a given amount of sfrx (wei)
    function ethPerSfrxAmount(uint256 amount) public view returns (uint256) {
        if(amount == 0) return 0;
        uint256 frxAmount = IsFrxEth(sfrxEthAddress).convertToAssets(amount);
        return ICrvEthPool(frxEthCrvPoolAddress).get_dy(0, 1, frxAmount);
    }

    // how much eth to receive for a given amount of reth (wei)
    function ethPerRethAmount(uint256 amount) public view returns (uint256) {
        if(amount == 0) return 0;
        return RocketTokenRETHInterface(rethAddress()).getEthValue(amount);
    }

    // eth per wstEth (wei)
    function ethPerWstAmount(uint256 amount) public view returns (uint256) {
        if(amount == 0) return 0;
        return IWStETH(wstETH).getStETHByWstETH(amount);
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER METHODS
    //////////////////////////////////////////////////////////////*/

    function setPauseStaking(bool _pause) public onlyOwner {
        pauseStaking = _pause;
        emit StakingPaused(_pause);
    }

    function setPauseuntaking(bool _pause) public onlyOwner {
        pauseUnstaking = _pause;
        emit UnstakingPaused(_pause);
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
