// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "hardhat/console.sol";
// AF Interfaces
import "./interfaces/IWETH.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/ICvxLockerV2.sol";
import "./tokens/afCVX1155.sol";
import "./tokens/afBundle1155.sol";
import "./interfaces/IAfETH.sol";
import "./interfaces/IAf1155.sol";
// OZ
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
// Uniswap
import "./interfaces/uniswap/ISwapRouter.sol";
// Curve
import "./interfaces/curve/ICrvEthPool.sol";
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

import "./Vault.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract AsymmetryStrategy is ERC1155Holder, Ownable {
    using Strings for uint256;
    event StakingPaused(bool paused);
    event UnstakingPaused(bool paused);
    event SetVault(address token, address vault);

    struct Position {
        uint256 positionID;
        address userAddress;
        uint256 rocketBalances; // rETH
        uint256 lidoBalances; // wstETH
        uint256 curveBalances; // crv Pool LP amount
        uint256 convexBalances; // CVX locked amount amount
        uint256 balancerBalances; // bal LP amount
        uint256 cvxNFTID;
        uint256 bundleNFTID;
        uint256 afETH; // amount afETH minted to user
        uint256 createdAt; // block.timestamp
    }

    // curve emissions based on year
    mapping(uint256 => uint256) private emissionsPerYear;

    // ERC-4626 Vaults of each derivative (token address => vault address)
    mapping(address => address) public vaults;

    // map user address to Position struct
    mapping(address => Position) public positions;
    uint256 currentPositionId;

    // Contract Addresses
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant rETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;
    address constant veCRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address constant vlCVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    address constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address constant stEthToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant lidoCrvPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    AggregatorV3Interface constant chainLinkEthFeed =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // TODO: what if this is updated or discontinued?
    AggregatorV3Interface constant chainLinkCvxFeed =
        AggregatorV3Interface(0xd962fC30A72A84cE50161031391756Bf2876Af5D);
    AggregatorV3Interface constant chainLinkCrvFeed =
        AggregatorV3Interface(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);

    RocketStorageInterface rocketStorage;

    ISwapRouter constant swapRouter =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address afETH;
    address pool;
    address CVXNFT;
    address bundleNFT;
    // cvx NFT ID starts at 0
    uint256 currentCvxNftId;
    // Bundle NFT ID starts at 100 // TODO: why?
    uint256 currentBundleNftId = 100;
    uint256 numberOfDerivatives = 2;
    address crvPool;

    // balancer pool things
    address private afBalancerPool = 0xBA12222222228d8Ba445958a75a0704d566BF2C8; // Temporarily using wstETH pool
    bytes32 balPoolId =
        0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;
    address private balancerHelpers =
        0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;

    uint256 constant ROCKET_POOL_LIMIT = 5000000000000000000000; // TODO: make changeable by owner
    bool pauseStaking = false;
    bool pauseUnstaking = false;

    constructor(
        address _token,
        address _rocketStorageAddress,
        address _cvxNft,
        address _bundleNft,
        address _crvPool
    ) {
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
        afETH = _token;
        CVXNFT = _cvxNft;
        bundleNFT = _bundleNft;
        crvPool = _crvPool;

        // emissions of CRV per year
        emissionsPerYear[1] = 274815283;
        emissionsPerYear[2] = 231091186;
        emissionsPerYear[3] = 194323750;
        emissionsPerYear[4] = 163406144;
        emissionsPerYear[5] = 137407641;
        emissionsPerYear[6] = 115545593;
        emissionsPerYear[7] = 97161875;
        emissionsPerYear[8] = 81703072;
        emissionsPerYear[9] = 68703820;
        emissionsPerYear[10] = 57772796;
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN/CLOSE POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function stake() public payable {
        require(pauseStaking == false, "staking is paused");

        uint256 ratio = getAsymmetryRatio();
        uint256 cvxAmount = (msg.value * ratio) / 10000;
        uint256 ethAmount = (msg.value - cvxAmount) / 2; // will split half of remaining eth into derivatives

        uint256 cvxAmountReceived = swapCvx(cvxAmount);
        uint256 amountCvxLocked = lockCvx(cvxAmountReceived);
        (uint256 cvxNftBalance, uint256 _cvxNFTID) = mintCvxNft(
            msg.sender,
            amountCvxLocked
        );
        uint256 wstEthMinted = depositWstEth(ethAmount / numberOfDerivatives);
        Vault(vaults[wstETH]).deposit(wstEthMinted, address(this));

        uint256 rEthMinted = depositREth(ethAmount / numberOfDerivatives);
        Vault(vaults[rETH]).deposit(rEthMinted, address(this));

        // TODO: Deploy and deposit balancer tokens of the 4626 vaults
        //uint256 balLpAmount = depositBalTokens(wstEthMinted);

        // TODO: After depositing to the balancer pool, mint a bundle NFT
        // uint256 bundleNftId = mintBundleNft(
        //     currentCvxNftId,
        //     amountCvxLocked,
        //     balLpAmount
        // );

        uint256 afEthAmount = ethAmount + 1;
        mintAfEth(afEthAmount);
        console.log('afETh', afEthAmount);
        console.log('ethAmount', ethAmount);
        console.log('cvxAmount', cvxAmount);

        // console.log('eth bal', address(this).balance);
        // console.log('afETH bal', IERC20(afETH).balanceOf(address(this)));
        console.log('crvPool', crvPool);
        uint256 crvLpAmount = addAfEthCrvLiquidity(crvPool, ethAmount, afEthAmount);
        require(
            positions[msg.sender].userAddress != msg.sender,
            "User already has position."
        );
        uint256 newPositionID = ++currentPositionId;

        // storage of individual balances associated w/ user deposit
        // TODO: This calculation doesn't update when afETH is transferred between wallets
        positions[msg.sender] = Position({
            positionID: newPositionID,
            userAddress: msg.sender, // TODO: why??
            rocketBalances: rEthMinted,
            lidoBalances: wstEthMinted,
            curveBalances: crvLpAmount,
            convexBalances: amountCvxLocked,
            balancerBalances: 0, //balLpAmount,
            cvxNFTID: _cvxNFTID,
            bundleNFTID: 0, //bundleNftId,
            afETH: ethAmount,
            createdAt: block.timestamp
        });
    }

    // add support for CVX burn or keep and transfer NFT to user
    // must transfer amount out tokens to vault
    function unstake(bool _instantWithdraw) public {
        require(pauseUnstaking == false, "unstaking is paused");

        uint256 afEthBalance = IERC20(afETH).balanceOf(msg.sender);
        withdrawCVXNft(_instantWithdraw);
        withdrawCRVPool(pool, 32e18);
        burnAfEth(afEthBalance);
        burnBundleNFT(msg.sender);
        uint256 wstETH2Unwrap = withdrawBalTokens();
        withdrawREth();
        withdrawWstEth(wstETH2Unwrap);
        IWETH(wETH).withdraw(IWETH(wETH).balanceOf(address(this))); // TODO: this seems broken

        // address vault = IController(controller).getVault(wETH);
        // (bool sent, ) = address(vault).call{value: address(this).balance}("");
        // require(sent, "Failed to send Ether");
    }

    /*//////////////////////////////////////////////////////////////
                        STRATEGY METHODS
    //////////////////////////////////////////////////////////////*/

    function getAsymmetryRatio() public view returns (uint256 ratio) {
        int256 crvPrice = getCrvPriceData();
        int256 cvxPrice = getCvxPriceData();
        uint256 cvxSupply = IERC20(CVX).totalSupply();
        uint256 tvl = 10000000; // TODO: Should be ETH/afETH pool tvl
        uint256 apy = 1500;
        uint256 offset = 30;

        // 1597471200 - represents Aug 15th 2020 when curve was initialized
        // 31556926 - represents 1 year including leap years
        uint256 emissionYear = ((block.timestamp - 1597471200) / 31556926) + 1; // which year the emission schedule is on
        uint256 crvPerDay = emissionsPerYear[emissionYear] / 365;

        uint256 yearly_minted_crv_per_cvx = ((crvPerDay * 10**offset) /
            cvxSupply) *
            365 *
            uint(crvPrice);

        uint256 cvx_amount = ((((apy + 10000) * (tvl / 10000)) - tvl) *
            10**offset) / yearly_minted_crv_per_cvx;

        uint256 allocationPercentage = (((((cvx_amount * uint(cvxPrice)) /
            10**18) * 10000) /
            (tvl + ((cvx_amount * uint(cvxPrice)) / 10**18))) * 10000) / 10000;

        return allocationPercentage;
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn
    ) public returns (uint256 amountOut) {
        IERC20(tokenIn).approve(address(swapRouter), amountIn);
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
        amountOut = swapRouter.exactInputSingle(params);
    }

    function swapCvx(uint256 amount) internal returns (uint256 amountOut) {
        IWETH(wETH).deposit{value: amount}();
        uint256 amountSwapped = swapExactInputSingleHop(
            wETH,
            CVX,
            10000,
            amount
        );
        return amountSwapped;
    }

    function lockCvx(uint256 _amountOut) public returns (uint256 amount) {
        uint256 amountOut = _amountOut;
        IERC20(CVX).approve(vlCVX, amountOut);
        ICvxLockerV2(vlCVX).lock(address(this), amountOut, 0);
        uint256 lockedCvxAmount = ILockedCvx(vlCVX).lockedBalanceOf(
            address(this)
        );
        return lockedCvxAmount;
    }

    // utilize Lido's wstETH shortcut by sending ETH to its fallback function
    // send ETH and bypass stETH, recieve wstETH for BAL pool
    function depositWstEth(uint256 amount)
        public
        payable
        returns (uint256 wstEthMintAmount)
    {
        uint256 wstEthBalancePre = IWStETH(wstETH).balanceOf(address(this));
        (bool sent, ) = wstETH.call{value: amount}("");
        require(sent, "Failed to send Ether");
        uint256 wstEthBalancePost = IWStETH(wstETH).balanceOf(address(this));
        uint256 wstEthAmount = wstEthBalancePost - wstEthBalancePre;
        return (wstEthAmount);
    }

    function depositREth(uint256 amount)
        public
        payable
        returns (uint256 rEthAmount)
    {
        // Per RocketPool Docs query deposit pool address each time it is used
        address rocketDepositPoolAddress = rocketStorage.getAddress(
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
                rETH,
                500,
                amount
            );
            return amountSwapped;
        } else {
            address rocketTokenRETHAddress = rocketStorage.getAddress(
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
        IWStETH(wstETH).approve(afBalancerPool, amount);
        IVault(afBalancerPool).joinPool(
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

    function withdrawREth() public {
        address rocketTokenRETHAddress = rocketStorage.getAddress(
            keccak256(abi.encodePacked("contract.address", "rocketTokenRETH"))
        );
        RocketTokenRETHInterface rocketTokenRETH = RocketTokenRETHInterface(
            rocketTokenRETHAddress
        );
        uint256 rethBalance1 = rocketTokenRETH.balanceOf(address(this));
        uint256 amount = positions[msg.sender].rocketBalances;
        positions[msg.sender].rocketBalances = 0;
        rocketTokenRETH.burn(amount);
        uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
        require(rethBalance1 > rethBalance2, "No rETH was burned");
        uint256 rethBurned = rethBalance1 - rethBalance2;
    }

    function withdrawWstEth(uint256 _amount) public {
        positions[msg.sender].lidoBalances = 0;
        IWStETH(wstETH).unwrap(_amount);
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        // convert stETH to ETH
        console.log("Eth before swapping steth to eth:", address(this).balance);
        ICrvEthPool(lidoCrvPool).exchange(1, 0, stEthBal, 0);
        console.log("Eth after swapping steth to eth:", address(this).balance);
    }

    // deploy new curve pool, add liquidity
    // strat has afETH, deposit in CRV pool
    function addAfEthCrvLiquidity(address _pool, uint256 _ethAmount, uint256 _afEthAmount)
        public
        returns (uint256 mint)
    {
        require(_ethAmount <= address(this).balance, "Not Enough ETH");

        IWETH(wETH).deposit{value: _ethAmount}();
        IWETH(wETH).approve(_pool, _ethAmount);
        
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.approve(_pool, _afEthAmount);

        uint256[2] memory _amounts = [_afEthAmount, _ethAmount];
        ICrvEthPool(_pool).add_liquidity(_amounts, 0, true, msg.sender);

        return (100);
    }

    function withdrawBalTokens() public returns (uint256 wstETH2Unwrap) {
        // bal lp amount
        uint256 amount = positions[msg.sender].balancerBalances;
        address[] memory _assets = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _assets[0] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        _assets[1] = 0x0000000000000000000000000000000000000000;
        // account for slippage from Balancer withdrawal
        _amounts[0] = (positions[msg.sender].lidoBalances * 99) / 100;
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
        // (uint256 balIn, uint256[] memory amountsOut) = IBalancerHelpers(balancerHelpers).queryExit(balPoolId,address(this),address(this),request);
        uint256 wBalance1 = IWStETH(wstETH).balanceOf(address(this));
        positions[msg.sender].balancerBalances = 0;
        IVault(afBalancerPool).exitPool(
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

    function withdrawCRVPool(address pool, uint256 _amount) public {
        address afETHPool = pool;
        uint256[2] memory min_amounts;
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        positions[msg.sender].curveBalances = 0;
        uint256[2] memory returnAmt = ICrvEthPool(afETHPool).remove_liquidity(
            _amount,
            min_amounts
        );
    }

    /*//////////////////////////////////////////////////////////////
                        TOKEN METHODS
    //////////////////////////////////////////////////////////////*/

    function getCvxPriceData() public view returns (int256) {
        (, int price, , , ) = chainLinkCvxFeed.latestRoundData();
        uint8 decimals = chainLinkCvxFeed.decimals();
        console.log("dec", decimals);
        // TODO: clean this up find a better solution
        return price * 10**10;
    }

    function getCrvPriceData() public view returns (int256) {
        (, int price, , , ) = chainLinkCrvFeed.latestRoundData();
        uint8 decimals = chainLinkCrvFeed.decimals();
        console.log("dec crv", decimals);

        return price * 10**10;
    }

    function mintCvxNft(address sender, uint256 _amountLocked)
        private
        returns (uint256 balance, uint256 nftId)
    {
        uint256 amountLocked = _amountLocked;
        uint256 newCvxNftId = ++currentCvxNftId;
        IAfCVX1155(CVXNFT).mint(newCvxNftId, amountLocked, address(this));
        positions[sender].cvxNFTID = newCvxNftId;
        uint256 mintedCvx1155 = IAfCVX1155(CVXNFT).balanceOf(
            address(this),
            newCvxNftId
        );
        return (mintedCvx1155, newCvxNftId);
    }

    function mintBundleNft(
        uint256 cvxNftId,
        uint256 cvxAmount,
        uint256 balPoolTokens
    ) private returns (uint256 id) {
        uint256 newBundleNftId = ++currentBundleNftId;
        IAfBundle1155(bundleNFT).mint(
            cvxNftId,
            cvxAmount,
            newBundleNftId,
            balPoolTokens,
            address(this)
        );
        // positions[currentDepositor] = newBundleNftId;
        // bundleNFtBalances[newBundleNftId] = balPoolTokens;
        return (newBundleNftId);
    }

    // user selection in front-end:
    // True - user is transferred the 1155 NFT holding their CVX deposit
    // until CVX lockup period is over (16 weeks plus days to thursday 0000 UTC)
    // False - user pays fee to unlock their CVX and burn their NFT
    function withdrawCVXNft(bool _instantWithdraw) private {
        if (_instantWithdraw == true) {
            // TODO: start withdraw vlCVX
            IAfCVX1155(CVXNFT).safeTransferFrom(
                address(this),
                msg.sender,
                positions[msg.sender].cvxNFTID,
                positions[msg.sender].convexBalances,
                ""
            );
            console.log(
                "user balance of CVX NFT:",
                IAfCVX1155(CVXNFT).balanceOf(
                    msg.sender,
                    positions[msg.sender].cvxNFTID
                )
            );
        } else {
            console.log("instant withdraw: ", _instantWithdraw);
            // fees: 119 days - 1% per day to max 12% fee: 88 days to min fee
            // 119 - 88 = 31
            // block.timestamp - positions[createdAt] = time locked
            // 1 day = 86400 seconds
            // burn NFT
            // swap CVX for ETH
            // transfer ETH to user minus fee for unlock
            // fee schedule:
            //
        }
    }

    function burnBundleNFT(address user) private {
        uint256[2] memory ids;
        uint256[2] memory amounts;
        ids[0] = positions[user].bundleNFTID;
        ids[1] = positions[user].cvxNFTID;
        amounts[0] = positions[user].balancerBalances;
        amounts[1] = positions[user].convexBalances;
        IAfBundle1155(bundleNFT).burnBatch(address(this), ids, amounts);
    }

    function mintAfEth(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.mint(address(this), amount);
    }

    // burn afETH
    function burnAfEth(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.burn(address(this), amount);
        positions[msg.sender].afETH = 0;
    }

    /*//////////////////////////////////////////////////////////////
                        OWNER METHODS
    //////////////////////////////////////////////////////////////*/

    function setVault(address _token, address _vault) public onlyOwner {
        vaults[_token] = _vault;
        emit SetVault(_token, _vault);
        IERC20(_token).approve(_vault, type(uint256).max);
    }

    function setPauseStaking(bool _pause) public onlyOwner {
        pauseStaking = _pause;
        emit StakingPaused(_pause);
    }

    function setPauseuntaking(bool _pause) public onlyOwner {
        pauseUnstaking = _pause;
        emit UnstakingPaused(_pause);
    }

    /*//////////////////////////////////////////////////////////////
                        VIEW METHODS
    //////////////////////////////////////////////////////////////*/

    function getPool() public view returns (address) {
        return (pool);
    }

    function getName() external pure returns (string memory) {
        return "AsymmetryFinance Strategy";
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
