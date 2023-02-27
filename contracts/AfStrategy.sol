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
import "./interfaces/balancer/IBalancerVault.sol";
import "./interfaces/balancer/IBalancerHelpers.sol";
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
    uint256 internal numberOfDerivatives = 3;

    bytes32 public balPoolId;

    uint256 private constant ROCKET_POOL_LIMIT = 5000000000000000000000; // TODO: make changeable by owner
    bool public pauseStaking = false;
    bool public pauseUnstaking = false;

    constructor(address _afETH, bytes32 _balPoolId) {
        afETH = _afETH;
        balPoolId = _balPoolId;
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN/CLOSE POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function stake() public payable {
        require(pauseStaking == false, "staking is paused");

        uint256 ethAmount = msg.value;

        uint256 wstEthMinted = depositWstEth(ethAmount / numberOfDerivatives);
        uint256 rEthMinted = depositREth(ethAmount / numberOfDerivatives);
        uint256 sfraxMinted = depositSfrax(ethAmount / numberOfDerivatives);

        uint256 balLpAmount = depositBalTokens(
            wstEthMinted,
            sfraxMinted,
            rEthMinted
        );
        mintAfEth(balLpAmount);
    }

    // must transfer amount out tokens to vault
    function unstake() public {
        require(pauseUnstaking == false, "unstaking is paused");
        // TODO: add option to not unstake all
        
        uint256 afEthBalance = IERC20(afETH).balanceOf(msg.sender);
        burnAfEth(afEthBalance);

        // uint256 wstETH2Unwrap = withdrawBalTokens();
        // withdrawREth();
        // withdrawWstEth(wstETH2Unwrap);
        IWETH(wETH).withdraw(IWETH(wETH).balanceOf(address(this))); // TODO: this seems broken don't give random users the balance of this contract
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
                getRETHAddress(),
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
            //rocketBalances[currentDepositor] += rethMinted;
            return (rethMinted);
        }
    }

    function depositBalTokens(
        uint256 _wstEthAmount,
        uint256 _sFraxEthAmount,
        uint256 _rEthAmount
    ) internal returns (uint256 lpAmount) {
        address[] memory _assets = new address[](3);
        uint256[] memory _amounts = new uint256[](3);
        address rEthAddress = getRETHAddress();

        _assets[0] = wstETH;
        _assets[1] = sfrxEthAddress;
        _assets[2] = rEthAddress;
        _amounts[0] = _wstEthAmount;
        _amounts[1] = _sFraxEthAmount;
        _amounts[2] = _rEthAmount;

        uint256 joinKind = 1;
        bytes memory userDataEncoded = abi.encode(joinKind, _amounts);
        IBalancerVault.JoinPoolRequest memory request = IBalancerVault
            .JoinPoolRequest(_assets, _amounts, userDataEncoded, false);

        IWStETH(wstETH).approve(balancerVault, _wstEthAmount);
        IsFrxEth(sfrxEthAddress).approve(balancerVault, _sFraxEthAmount);
        IERC20(rEthAddress).approve(balancerVault, _rEthAmount);

        IBalancerVault(balancerVault).joinPool(
            balPoolId,
            address(this),
            address(this),
            request
        );
        return (
            ERC20(0x32296969Ef14EB0c6d29669C550D4a0449130230).balanceOf(
                address(this)
            )
        );
    }

    function withdrawREth(uint256 _amount) public {
        address rETH = getRETHAddress();
        uint256 rethBalance1 = RocketTokenRETHInterface(rETH).balanceOf(
            address(this)
        );
        RocketTokenRETHInterface(rETH).burn(_amount);
        uint256 rethBalance2 = RocketTokenRETHInterface(rETH).balanceOf(
            address(this)
        );
        require(rethBalance1 > rethBalance2, "No rETH was burned");
    }

    function withdrawWstEth(uint256 _amount) public {
        IWStETH(wstETH).unwrap(_amount); // TODO: not using right amount of wstETH
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        // convert stETH to ETH
        console.log("Eth before swapping steth to eth:", address(this).balance);
        ICrvEthPool(lidoCrvPool).exchange(1, 0, stEthBal, 0);
        console.log("Eth after swapping steth to eth:", address(this).balance);
    }

    function withdrawSfrax(uint256 amount) public {
        IsFrxEth(sfrxEthAddress).redeem(amount, address(this), address(this));
        uint256 frxEthBalance = IERC20(frxEthAddress).balanceOf(address(this));
        IsFrxEth(frxEthAddress).approve(frxEthCrvPoolAddress, frxEthBalance);
        // TODO figure out if we want a min receive amount and what it should be
        // Currently set to 0. It "works" but may not be ideal long term
        ICrvEthPool(frxEthCrvPoolAddress).exchange(1, 0, frxEthBalance, 0);
    }

    function withdrawBalTokens() public returns (uint256 wstETH2Unwrap) {
        // bal lp amount
        uint256 amount = 0; // TODO: Previous code - positions[msg.sender].balancerBalance;
        address[] memory _assets = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _assets[0] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        _assets[1] = 0x0000000000000000000000000000000000000000;
        // account for slippage from Balancer withdrawal
        _amounts[0] = 0; // TODO: Previous code - (positions[msg.sender].wstEthBalance * 99) / 100;
        _amounts[1] = 0;
        uint256 exitKind = 0;
        uint256 exitTokenIndex = 0;
        bytes memory userDataEncoded = abi.encode(
            exitKind,
            amount,
            exitTokenIndex
        );
        IBalancerVault.ExitPoolRequest memory request = IBalancerVault
            .ExitPoolRequest(_assets, _amounts, userDataEncoded, false);
        // (uint256 balIn, uint256[] memory amountsOut) = IBalancerHelpers(balancerHelpers).queryExit(balPoolId,address(this),address(this),request);
        uint256 wBalance1 = IWStETH(wstETH).balanceOf(address(this));

        IBalancerVault(balancerVault).exitPool(
            balPoolId,
            address(this),
            address(this),
            request
        );
        uint256 wBalance2 = IWStETH(wstETH).balanceOf(address(this));
        require(wBalance2 > wBalance1, "No wstETH was withdrawn");
        uint256 wstETHWithdrawn = wBalance2 - wBalance1;
        return (wstETHWithdrawn);
    }

    /*//////////////////////////////////////////////////////////////
                        HELPER METHODS
    //////////////////////////////////////////////////////////////*/

    function getRETHAddress() public view returns (address) {
        return
            ROCKET_STORAGE.getAddress(
                keccak256(
                    abi.encodePacked("contract.address", "rocketTokenRETH")
                )
            );
    }

    // eth per sfrxEth (wei)
    function sfrxEthPrice(uint256 amount) public view returns (uint256) {
        uint256 frxAmount = IsFrxEth(sfrxEthAddress).convertToAssets(amount);
        return ICrvEthPool(frxEthCrvPoolAddress).get_dy(0, 1, frxAmount);
    }

    // eth per reth (wei)
    function rethPrice(uint256 amount) public view returns (uint256) {
        return RocketTokenRETHInterface(getRETHAddress()).getEthValue(amount);
    }

    /// @notice get ETH price data from Chainlink, may not be needed if we can get ratio from contracts for rETH and sfrxETH
    function getEthPriceData() public view returns (uint256) {
        (, int256 price, , , ) = CHAIN_LINK_ETH_FEED.latestRoundData();
        if (price < 0) {
            price = 0;
        }
        uint8 decimals = CHAIN_LINK_ETH_FEED.decimals();
        // 10**(decimals) gives the number in dollar form $10.03
        // because solidity is only integers we need to add two to get price data including cents
        return uint256(price) * 10**(decimals + 2);
    }

    function mintAfEth(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.mint(address(this), amount);
    }

    function burnAfEth(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.burn(address(this), amount);
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
