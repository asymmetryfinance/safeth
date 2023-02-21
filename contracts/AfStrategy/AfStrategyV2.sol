// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IAfETH.sol";
import "../interfaces/frax/IFrxETHMinter.sol";
import "../interfaces/frax/IsFrxEth.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "../interfaces/rocketpool/RocketStorageInterface.sol";
import "../interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "../interfaces/lido/IWStETH.sol";
import "../interfaces/lido/IstETH.sol";
import "hardhat/console.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// This is an ugradeable contract - variable order matters
// https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
contract AfStrategyV2 is OwnableUpgradeable {
    event StakingPaused(bool paused);
    event UnstakingPaused(bool paused);

    RocketStorageInterface private ROCKET_STORAGE;
    ISwapRouter private SWAP_ROUTER;

    address public afETH;
    uint256 private numberOfDerivatives;

    uint256 private ROCKET_POOL_LIMIT;
    bool public pauseStaking;
    bool public pauseUnstaking;

    address public wETH;
    address public CVX;
    address public veCRV;
    address public vlCVX;
    address public wstETH;
    address public stEthToken;
    address public lidoCrvPool;
    address public sfrxEthAddress;
    address public frxEthAddress;
    address public frxEthCrvPoolAddress;
    address public frxEthMinterAddress;
    address public rocketStorageAddress;
    address public uniswapRouter;

    bool public newFunctionCalled;

    function newFunction() public {
        newFunctionCalled = true;
    }

    function rethAddress() public view returns(address) {
        return ROCKET_STORAGE.getAddress(keccak256(abi.encodePacked("contract.address", "rocketTokenRETH")));
    }

    function initialize(address _afETH) public initializer {
        wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
        veCRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
        vlCVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
        wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        stEthToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        lidoCrvPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
        sfrxEthAddress = 0xac3E018457B222d93114458476f3E3416Abbe38F;
        frxEthAddress = 0x5E8422345238F34275888049021821E8E08CAa1f;
        frxEthCrvPoolAddress = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
        frxEthMinterAddress = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;
        rocketStorageAddress = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
        uniswapRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        afETH = _afETH;
        numberOfDerivatives = 3;
        SWAP_ROUTER = ISwapRouter(uniswapRouter);
        ROCKET_STORAGE =
        RocketStorageInterface(rocketStorageAddress);
        ROCKET_POOL_LIMIT = 5000000000000000000000;
        newFunctionCalled = false;
    }

    function calculatePrice(uint256 underlyingValue, uint256 totalSupply) public pure returns(uint256) {
        return  ( 10 ** 18 * underlyingValue / totalSupply);
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
        // get underlying value
        uint256 totalSfrxEthValue = ethPerSfrxAmount(IERC20(sfrxEthAddress).balanceOf(address(this)));
        uint256 totalRethValue = ethPerRethAmount(IERC20(rethAddress()).balanceOf(address(this)));
        uint256 totalWstEthValue = ethPerWstAmount(IERC20(wstETH).balanceOf(address(this)));
        uint256 underlyingValue = totalSfrxEthValue + totalRethValue + totalWstEthValue;

        uint256 totalSupply = IAfETH(afETH).totalSupply();
        if(totalSupply == 0) return startingPrice();
        return calculatePrice(underlyingValue, totalSupply);
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
    function depositWstEth(uint256 amount) private
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

    function depositSfrax(uint256 amount) private returns (uint256) {
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
        private
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

    function withdrawWstEth(uint256 _amount) private {
        IWStETH(wstETH).unwrap(_amount);
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        // TODO figure out if we want a min receive amount and what it should be
        // Currently set to 0. It "works" but may not be ideal long term
        ICrvEthPool(lidoCrvPool).exchange(1, 0, stEthBal, 0);        
    }

    function withdrawSfrax(uint256 amount) private {
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
