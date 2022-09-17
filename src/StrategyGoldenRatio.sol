// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
import "uniswap/interfaces/ISwapRouter.sol";
import {TransferHelper} from "uniswap/libraries/TransferHelper.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/ICvxLockerV2.sol";
import "./tokens/grCVX1155.sol";
import "./interfaces/curve/ICrvEthPool.sol";
import {ICurve} from "./interfaces/curve/ICurve.sol";
import "./interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "./interfaces/rocketpool/RocketStorageInterface.sol";
import "./interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "./interfaces/lido/IWStETH.sol";
import "./interfaces/IController.sol";

contract StrategyGoldenRatio is ERC1155Holder {
    // Contract Addresses
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant want = address(WETH9);
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CvxLockerV2 = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    // address for ETH/stETH crv pool
    address private constant stEthCrvPool =
        0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    // address for ETH/stETH crv LP token
    address private constant lpToken =
        0x06325440D014e39736583c165C2963BA99fAf14E;
    address constant wStEthToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    RocketStorageInterface rocketStorage = RocketStorageInterface(address(0));

    address public governance;
    address public controller;
    address public strategist;

    // Init
    IWETH private weth = IWETH(WETH9);
    IERC20 private cvx = IERC20(CVX);
    IERC20 private reth = IERC20(RETH);
    ICvxLockerV2 constant locker = ICvxLockerV2(CvxLockerV2);
    ILockedCvx constant lockedCvx = ILockedCvx(CvxLockerV2);
    grCVX1155 private cvxNft = new grCVX1155();
    IWStETH private wstEth = IWStETH(payable(wStEthToken));

    ISwapRouter constant router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address currentDepositor;

    uint256 currentCvxNftId;

    // Mapping of rETH balance to sender
    mapping(address => uint256) rocketBalances;

    // Mapping of stETH balance to sender
    mapping(address => uint256) lidoBalances;

    // Mapping of CRV balance to sender
    mapping(address => uint256) curveBalances;

    // Mapping of CVX balance to sender
    mapping(address => uint256) convexBalances;

    // Mapping of BAL balance to sender
    mapping(address => uint256) balancerBalances;

    mapping(address => uint256) cvxNfts;

    mapping(uint256 => uint256) cvxNftLockedBalances;

    constructor(address _controller, address _rocketStorageAddress) {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
    }

    function getName() external pure returns (string memory) {
        return "StrategyGoldenRatio";
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint amountIn
    ) public returns (uint amountOut) {
        // no need to transfer weth; weth already in contract
        //TransferHelper.safeTransferFrom(tokenIn,msg.sender,address(this),amountIn);
        TransferHelper.safeApprove(tokenIn, address(router), amountIn);

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter
            .ExactInputSingleParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                fee: poolFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: amountIn,
                amountOutMinimum: 1,
                sqrtPriceLimitX96: 0
            });
        amountOut = router.exactInputSingle(params);
    }

    // strat has WETH, withdraw to ETH and deposit in pool
    function addCrvLiquidity(uint256 amount) public returns (uint256 mint) {
        uint256[2] memory _amounts;
        _amounts = [uint256(amount), 0];
        require(_amounts[0] == 16e18, "Invalid Deposit");
        uint256 mintAmt = ICrvEthPool(stEthCrvPool).add_liquidity{
            value: _amounts[0]
        }(_amounts, 0);
        uint256 lpMinted = IERC20(lpToken).balanceOf(address(this));
        return (lpMinted);
    }

    function swapCvx(uint256 amount) public returns (uint256 amountOut) {
        weth.deposit{value: amount}();
        weth.approve(address(controller), amount);
        uint256 amountSwapped = swapExactInputSingleHop(
            WETH9,
            CVX,
            10000,
            amount
        );
        return amountSwapped;
    }

    function lockCvx(uint _amountOut) public returns (uint256 amount) {
        uint amountOut = _amountOut;
        cvx.approve(CvxLockerV2, amountOut);
        locker.lock(address(this), amountOut, 0);
        uint256 lockedCvxAmount = lockedCvx.lockedBalanceOf(address(this));
        return lockedCvxAmount;
    }

    function mintCvxNft(uint _amountLocked) public returns (uint256 balance) {
        uint amountLocked = _amountLocked;
        uint256 newCvxNftId = ++currentCvxNftId;
        cvxNft.mint(newCvxNftId, amountLocked, address(this));
        cvxNfts[currentDepositor] = newCvxNftId;
        cvxNftLockedBalances[newCvxNftId] = amountLocked;
        uint256 minted1155 = cvxNft.balanceOf(address(this), newCvxNftId);
        return minted1155;
    }

    // utilize Lido's wstETH shortcut by sending ETH to its fallback function
    // send ETH and bypass stETH, recieve wstETH for BAL pool
    function depositWstEth(uint256 amount)
        public
        payable
        returns (uint256 wstEthAmount)
    {
        require(amount == 8e18, "Invalid Deposit");
        uint256 wstEthBalance1 = wstEth.balanceOf(address(this));
        (bool sent, ) = address(wstEth).call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wstEthBalance2 = wstEth.balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalance2 - wstEthBalance1;
        return (wstEthAmount);
    }

    function depositREth(uint256 amount)
        public
        payable
        returns (uint256 rEthAmount)
    {
        require(amount == 8e18, "Invalid Deposit");
        // Per RocketPool Docs query deposit pool address each time it is used
        address rocketDepositPoolAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketDepositPool"))
        );
        RocketDepositPoolInterface rocketDepositPool = RocketDepositPoolInterface(
                rocketDepositPoolAddress
            );
        address rocketTokenRETHAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
            rocketTokenRETHAddress
        );
        uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
        rocketDepositPool.deposit{value: amount}();
        uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
        console.log("REth balance of this strat", rethBalance2);
        require(rethBalance2 > rethBalance1, "No rETH was minted");
        uint256 rethMinted = rethBalance2 - rethBalance1;
        rocketBalances[currentDepositor] += rethMinted;
    }

    //function depositCvx() public returns (uint256 balance) {}

    function depositBalTokens() public {}

    function mintBundleNft() public {}

    function mintGrEth() public {}

    // put it all together
    function deposit(address sender, uint256 assets) public payable {
        currentDepositor = sender;
        // unwrap WETH to ETH in strategy
        weth.withdraw(assets);
        // deposit in 16 ETH in CRV pool
        uint256 crvDeposit = addCrvLiquidity(assets - 32e18);
        // swap 16WETH for CVX, lock, and mint CVX NFT
        uint256 cvxAmountOut = swapCvx(assets - 32e18);
        uint256 amountCvxLocked = lockCvx(cvxAmountOut);
        //console.log("this address locked cvx:", amountCvxLocked);
        uint256 cvxNftBalance = mintCvxNft(amountCvxLocked);
        // stake 8ETH in rETH and 8ETH in stETH
        uint256 wstEthMinted = depositWstEth(assets - 40e18);
        uint256 rEthMinted = depositREth(assets - 40e18);
        // deposit liquid staked ether derivatives in BAL pool
        // mint bundle NFT w/ BAL LP token + CVX NFT
        // mint grETH from bundle NFT
        // deposit grETH in CRV pool
    }

    function withdraw() public {
        // deposit() in reverse
    }

    // Withdraw all funds, normally used when migrating strategies
    function withdrawAll() external returns (uint256 balance) {
        require(msg.sender == controller, "!controller");
        _withdrawAll();

        balance = IERC20(want).balanceOf(address(this));

        address _vault = IController(controller).vaults(address(want));
        require(_vault != address(0), "!vault"); // additional protection so we don't burn the funds
        IERC20(want).transfer(_vault, balance);
    }

    function _withdrawAll() internal {
        uint256 amount;
    }

    receive() external payable {}
}
