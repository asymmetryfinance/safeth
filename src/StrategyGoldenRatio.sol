// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/console.sol";
// GR Interfaces
import "./interfaces/IController.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/ICvxLockerV2.sol";
import "./tokens/grCVX1155.sol";
import "./tokens/grBundle1155.sol";
import "./interfaces/IgrETH.sol";
import "./interfaces/Igr1155.sol";
// OZ
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
// Uniswap
import "uniswap/interfaces/ISwapRouter.sol";
import {TransferHelper} from "uniswap/libraries/TransferHelper.sol";
// Curve
import "./interfaces/curve/ICrvEthPool.sol";
import "./interfaces/curve/ICurvePool.sol";
// RocketPool
import "./interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "./interfaces/rocketpool/RocketStorageInterface.sol";
import "./interfaces/rocketpool/RocketTokenRETHInterface.sol";
// Lido
import "./interfaces/lido/IWStETH.sol";
import "./interfaces/lido/IstETH.sol";
// Balancer
// balancer Vault interface: https://github.com/balancer-labs/balancer-v2-monorepo/blob/weighted-deployment/contracts/vault/interfaces/IVault.sol
import "./interfaces/balancer/IVault.sol";
import "./interfaces/balancer/IBalancerHelpers.sol";

contract StrategyGoldenRatio is ERC1155Holder {
    // Contract Addresses
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant want = address(WETH9);
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CvxLockerV2 = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    address constant wStEthToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant stEthToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant lidoCrvPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant balPoolEthAddress =
        0x0000000000000000000000000000000000000000;
    RocketStorageInterface rocketStorage = RocketStorageInterface(address(0));
    address constant deployCurvePool =
        0xB9fC157394Af804a3578134A6585C0dc9cc990d4;

    address public governance;
    address public controller;
    address public strategist;

    // Init
    IWETH private weth = IWETH(WETH9);
    IERC20 private cvx = IERC20(CVX);
    IERC20 private reth = IERC20(RETH);
    ICvxLockerV2 constant locker = ICvxLockerV2(CvxLockerV2);
    ILockedCvx constant lockedCvx = ILockedCvx(CvxLockerV2);
    IWStETH private wstEth = IWStETH(payable(wStEthToken));
    ICrvEthPool private lidoPool = ICrvEthPool(lidoCrvPool);
    ICurvePool private curve = ICurvePool(deployCurvePool);

    ISwapRouter constant router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address currentDepositor;
    address currentWithdrawer;

    address grETH;
    address pool;
    address CVXNFT;
    address bundleNFT;

    uint256 currentCvxNftId;
    // 1155 IDs can't have same ID
    uint256 currentBundleNftId = 10;

    uint256 totalGrEthBalance;

    // balancer pool things
    address private wstEthBalPool = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IVault balancer = IVault(wstEthBalPool);
    bytes32 balPoolId =
        0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;
    address private balancerHelpers =
        0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;
    IBalancerHelpers helper = IBalancerHelpers(balancerHelpers);

    // Internal Storage of balances across strategy protocols
    // Includes CRV, CVX, rETH, wstETH, BAL BPT, NFTs

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

    // Mapping of CVXNFT ID to sender
    mapping(address => uint256) cvxNfts;

    // Mapping of CVX Locked Balance to NFT ID
    mapping(uint256 => uint256) cvxNftLockedBalances;

    // user address to Bundle NFT ID
    mapping(address => uint256) bundleNfts;

    // bundle NFT ID to BAL LP token balance
    mapping(uint256 => uint256) bundleNFtBalances;

    constructor(
        address token,
        address _controller,
        address _rocketStorageAddress,
        address cvxNft,
        address bundleNft
    ) {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
        grETH = token;
        CVXNFT = cvxNft;
        bundleNFT = bundleNft;
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

    function deposit(address sender, uint256 assets) public payable {
        address pool = deployGrPool(grETH);
        // may put us at risk for exploits. need a way to internally track values by msg.sender to the vault
        // however msg.sender for strat functions is vault, msg.sender to vault is user address
        // same issue in withdraw(...) setting currentWithdrawer = sender;
        currentDepositor = sender;
        // unwrap WETH to ETH in strategy
        weth.withdraw(assets);
        // swap 16WETH for CVX, lock, and mint CVX NFT
        uint256 cvxAmountOut = swapCvx(assets - 32e18);
        uint256 amountCvxLocked = lockCvx(cvxAmountOut);
        uint256 cvxNftBalance = mintCvxNft(sender, amountCvxLocked);
        // stake 8ETH in rETH and 8ETH in wstETH
        uint256 wstEthMinted = depositWstEth(assets - 40e18);
        uint256 rEthMinted = depositREth(assets - 40e18);
        // deposit wstETH and rETH derivatives in BAL pool
        uint256 lpAmount = depositBalTokens(wstEthMinted);
        // mint bundle NFT w/ BAL LP token + CVX NFT
        uint256 bundleNftBalance = mintBundleNft(
            currentCvxNftId,
            amountCvxLocked,
            lpAmount
        );
        mintGrEth(16e18);
        addGrEthCrvLiquidity(pool, 16e18);
        // mint grETH from bundle NFT
        // deposit grETH in CRV pool
    }

    // add support for CVX burn or keep and transfer NFT to user
    function withdraw(address sender) public {
        currentWithdrawer = sender;
        withdrawCRVPool(pool, 32e18);
        burn(16e18);
        burnBundleNFT(sender);
        withdrawBalTokens();
        withdrawREth();
        withdrawWstEth();
        weth.withdraw(weth.balanceOf(address(this)));
        //uint256 lockedCvxAmount = lockedCvx.lockedBalanceOf(address(this));
        //console.log("CVX lp after withdraw:", lockedCvxAmount);
        address vault = IController(controller).getVault(WETH9);
        (bool sent, ) = address(vault).call{value: address(this).balance}("");
        require(sent, "Failed to send Ether");
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY METHODS
    //////////////////////////////////////////////////////////////*/

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

    // utilize Lido's wstETH shortcut by sending ETH to its fallback function
    // send ETH and bypass stETH, recieve wstETH for BAL pool
    function depositWstEth(uint256 amount)
        public
        payable
        returns (uint256 wstEthMintAmount)
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
        require(rethBalance2 > rethBalance1, "No rETH was minted");
        uint256 rethMinted = rethBalance2 - rethBalance1;
        rocketBalances[currentDepositor] += rethMinted;
        return (rethMinted);
    }

    function depositBalTokens(uint256 amount)
        public
        returns (uint256 lpAmount)
    {
        address[] memory _assets = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _assets[0] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        _assets[1] = 0x0000000000000000000000000000000000000000;
        _amounts[0] = amount;
        _amounts[1] = 0;
        uint256 joinKind = 1;
        bytes memory userDataEncoded = abi.encode(joinKind, _amounts);
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            _assets,
            _amounts,
            userDataEncoded,
            false
        );
        wstEth.approve(wstEthBalPool, amount);
        balancer.joinPool(balPoolId, address(this), address(this), request);
        return (
            ERC20(0x32296969Ef14EB0c6d29669C550D4a0449130230).balanceOf(
                address(this)
            )
        );
    }

    function withdrawWstEth() public {
        uint256 amount = wstEth.balanceOf(address(this));
        wstEth.unwrap(amount);
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        lidoPool.exchange(1, 0, stEthBal, 0);
    }

    function withdrawREth() public {
        address rocketTokenRETHAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
            rocketTokenRETHAddress
        );
        uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
        uint256 amount = rocketBalances[currentWithdrawer];
        rocketTokenRETH.burn(amount);
        uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
        //require(rethBalance1 > rethBalance2, "No rETH was burned");
        uint256 rethBurned = rethBalance1 - rethBalance2;
        rocketBalances[currentWithdrawer] -= rethBurned;
    }

    // deploy new curve pool, add liquidity
    // strat has grETH, deposit in CRV pool
    function addGrEthCrvLiquidity(address pool, uint256 amount)
        public
        returns (uint256 mint)
    {
        address grETHPool = pool;
        uint256[2] memory _amounts;
        weth.deposit{value: amount}();
        weth.approve(grETHPool, amount);
        _amounts = [uint256(amount), amount];
        require(_amounts[0] == 16e18, "Invalid Deposit");
        IgrETH grEthToken = IgrETH(grETH);
        grEthToken.approve(grETHPool, amount);
        uint256 mintAmt = ICrvEthPool(grETHPool).add_liquidity(_amounts, 0);
        return (mintAmt);
    }

    function withdrawBalTokens() public {
        uint256 amount = ERC20(0x32296969Ef14EB0c6d29669C550D4a0449130230)
            .balanceOf(address(this));
        address[] memory _assets = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _assets[0] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        _assets[1] = 0x0000000000000000000000000000000000000000;
        _amounts[0] = 7056977990962131012;
        _amounts[1] = 0;
        uint256 exitKind = 0;
        uint256 exitTokenIndex = 0;
        bytes memory userDataEncoded = abi.encode(
            exitKind,
            amount,
            exitTokenIndex
        );
        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest(
            _assets,
            _amounts,
            userDataEncoded,
            false
        );
        (uint256 balIn, uint256[] memory amountsOut) = helper.queryExit(
            balPoolId,
            address(this),
            address(this),
            request
        );
        balancer.exitPool(balPoolId, address(this), address(this), request);
    }

    function withdrawCRVPool(address pool, uint256 _amount) public {
        address grETHPool = pool;
        uint256[2] memory min_amounts;
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        uint256[2] memory returnAmt = ICrvEthPool(grETHPool).remove_liquidity(
            _amount,
            min_amounts
        );
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN METHODS
    //////////////////////////////////////////////////////////////*/

    function deployGrPool(address grEth) public returns (address) {
        string memory name = "Golden Ratio ETH";
        string memory symbol = "grETH";
        address[4] memory coins;
        coins = [
            grEth,
            0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            0x0000000000000000000000000000000000000000,
            0x0000000000000000000000000000000000000000
        ];
        uint256 _A = 1000;
        uint256 fee = 4000000;
        uint256 asset_type = 1;
        uint256 implementation_idx = 1;
        address deployedPool = curve.deploy_plain_pool(
            name,
            symbol,
            coins,
            _A,
            fee,
            asset_type,
            implementation_idx
        );
        pool = deployedPool;
        return (deployedPool);
    }

    function mintCvxNft(address sender, uint _amountLocked)
        public
        returns (uint256 balance)
    {
        uint amountLocked = _amountLocked;
        uint256 newCvxNftId = ++currentCvxNftId;
        IgrCVX1155(CVXNFT).mint(newCvxNftId, amountLocked, address(this));
        cvxNfts[sender] = newCvxNftId;
        cvxNftLockedBalances[newCvxNftId] = amountLocked;
        uint256 mintedCvx1155 = IgrCVX1155(CVXNFT).balanceOf(
            address(this),
            newCvxNftId
        );
        return mintedCvx1155;
    }

    function mintBundleNft(
        uint256 cvxNftId,
        uint256 cvxAmount,
        uint256 balPoolTokens
    ) public returns (uint256 balance) {
        uint256 newBundleNftId = ++currentBundleNftId;
        IgrBundle1155(bundleNFT).mint(
            cvxNftId,
            cvxAmount,
            newBundleNftId,
            balPoolTokens,
            address(this)
        );
        bundleNfts[currentDepositor] = newBundleNftId;
        bundleNFtBalances[newBundleNftId] = balPoolTokens;
        uint256 mintedBundle1155 = IgrBundle1155(bundleNFT).balanceOf(
            address(this),
            newBundleNftId
        );
        return mintedBundle1155;
    }

    function burnBundleNFT(address user) public {
        uint256[2] memory ids;
        uint256[2] memory amounts;
        //uint256[2] memory amounts;
        ids[0] = bundleNfts[user];
        ids[1] = cvxNfts[user];
        amounts[0] = bundleNFtBalances[ids[0]];
        amounts[1] = cvxNftLockedBalances[ids[1]];
        IgrBundle1155(bundleNFT).burnBatch(address(this), ids, amounts);
    }

    function mintGrEth(uint256 amount) public {
        IgrETH grEthToken = IgrETH(grETH);
        grEthToken.mint(address(this), amount);
    }

    // burn GRETH
    function burn(uint256 amount) public {
        IgrETH grEthToken = IgrETH(grETH);
        grEthToken.burn(address(this), amount);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    function getPool() public view returns (address) {
        return (pool);
    }

    function getName() external pure returns (string memory) {
        return "StrategyGoldenRatio";
    }

    receive() external payable {}
}
