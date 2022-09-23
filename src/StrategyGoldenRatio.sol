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
import "./tokens/grBundle1155.sol";
//import "./tokens/grETH.sol";
import "./interfaces/curve/ICrvEthPool.sol";
import "./interfaces/curve/ICurvePool.sol";
import "./interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "./interfaces/rocketpool/RocketStorageInterface.sol";
import "./interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "./interfaces/lido/IWStETH.sol";
import "./interfaces/IController.sol";
// balancer Vault interface: https://github.com/balancer-labs/balancer-v2-monorepo/blob/weighted-deployment/contracts/vault/interfaces/IVault.sol
import "./interfaces/balancer/IVault.sol";
import "./interfaces/IgrETH.sol";

contract StrategyGoldenRatio is ERC1155Holder {
    // Contract Addresses
    address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant want = address(WETH9);
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant CvxLockerV2 = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    address constant wStEthToken = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
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
    grCVX1155 private cvxNft = new grCVX1155();
    grBundle1155 private bundleNft = new grBundle1155();
    IWStETH private wstEth = IWStETH(payable(wStEthToken));
    ICurvePool private curve = ICurvePool(deployCurvePool);

    ISwapRouter constant router =
        ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address currentDepositor;

    address grETH;
    address pool;

    uint256 currentCvxNftId;
    // 1155 IDs can't have same ID
    uint256 currentBundleNftId = 10;

    uint256 totalGrEthBalance;

    // balancer pool things
    address private wstEthBalPool = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
    IVault balancer = IVault(wstEthBalPool);
    bytes32 balPoolId =
        0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;

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

    mapping(address => uint256) cvxNfts;

    mapping(uint256 => uint256) cvxNftLockedBalances;

    // user address to Bundle NFT ID
    mapping(address => uint256) bundleNfts;

    // bundle NFT ID to BAL LP token balance
    mapping(uint256 => uint256) bundleNFtBalances;

    constructor(
        address token,
        address _controller,
        address _rocketStorageAddress
    ) {
        governance = msg.sender;
        strategist = msg.sender;
        controller = _controller;
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
        grETH = token;
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
        uint256 mintedCvx1155 = cvxNft.balanceOf(address(this), newCvxNftId);
        return mintedCvx1155;
    }

    // mint params: uint256 cvxId, uint256 cvxAmount, uint256 balId, uint256 balAmount, address recipient

    function mintBundleNft(
        uint256 cvxNftId,
        uint256 cvxAmount,
        uint256 balPoolTokens
    ) public returns (uint256 balance) {
        uint256 newBundleNftId = ++currentBundleNftId;
        bundleNft.mint(
            cvxNftId,
            cvxAmount,
            newBundleNftId,
            balPoolTokens,
            address(this)
        );
        bundleNfts[currentDepositor] = newBundleNftId;
        bundleNFtBalances[newBundleNftId] = balPoolTokens;
        uint256 mintedBundle1155 = bundleNft.balanceOf(
            address(this),
            newBundleNftId
        );
        return mintedBundle1155;
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
        //_assets = [wStEthToken, balPoolEthAddress];
        //uint256[] memory _amounts;
        //_amounts = [uint256(amount), 0];
        uint256 joinKind = 1;
        bytes memory userDataEncoded = abi.encode(joinKind, _amounts);
        // update joinpool struct
        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest(
            _assets,
            _amounts,
            userDataEncoded,
            false
        );
        wstEth.approve(wstEthBalPool, amount);
        // join pool params: bytes32 poolId, address sender, address recipient, JoinPoolRequest memory request
        balancer.joinPool(balPoolId, address(this), address(this), request);
        return (
            ERC20(0x32296969Ef14EB0c6d29669C550D4a0449130230).balanceOf(
                address(this)
            )
        );
    }

    function mintGrEth(uint256 amount) public {
        IgrETH grEthToken = IgrETH(grETH);
        grEthToken.mint(address(this), amount);
    }

    function burn(uint256 amount) public {
        IgrETH grEthToken = IgrETH(grETH);
        grEthToken.burn(address(this), amount);
    }

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

    function deposit(address sender, uint256 assets) public payable {
        address pool = deployGrPool(grETH);
        currentDepositor = sender;
        // unwrap WETH to ETH in strategy
        weth.withdraw(assets);
        // swap 16WETH for CVX, lock, and mint CVX NFT
        uint256 cvxAmountOut = swapCvx(assets - 32e18);
        uint256 amountCvxLocked = lockCvx(cvxAmountOut);
        uint256 cvxNftBalance = mintCvxNft(amountCvxLocked);
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

    // Need method to withdraw funds and burn CVX NFT
    // OR withdraw funds and maintain NFT, transfer to user's wallet
    function withdraw() public {
        withdrawCRVPool(pool, 32e18);
        burn(16e18);
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

    function getPool() public view returns (address) {
        return (pool);
    }

    receive() external payable {}
}
