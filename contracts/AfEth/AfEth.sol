// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/token/ERC1155/utils/ERC1155Holder.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../interfaces/uniswap/ISwapRouter.sol";
import "../interfaces/IWETH.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/ICvxLockerV2.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "./interfaces/IAf1155.sol";
import "hardhat/console.sol";

contract AfEth is
    Initializable,
    ERC20Upgradeable,
    ERC1155Holder,
    OwnableUpgradeable
{
    struct Position {
        uint256 positionID;
        uint256 curveBalances; // crv Pool LP amount
        uint256 convexBalances; // CVX locked amount amount
        uint256 cvxNFTID;
        uint256 bundleNFTID;
        uint256 afETH; // amount safETH minted to user
        uint256 createdAt; // block.timestamp
    }

    // curve emissions based on year
    mapping(uint256 => uint256) private emissionsPerYear;
    // map user address to Position struct
    mapping(address => Position) public positions;

    AggregatorV3Interface constant chainLinkEthFeed =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419); // TODO: what if these are updated or discontinued?
    AggregatorV3Interface constant chainLinkCvxFeed =
        AggregatorV3Interface(0xd962fC30A72A84cE50161031391756Bf2876Af5D);
    AggregatorV3Interface constant chainLinkCrvFeed =
        AggregatorV3Interface(0xCd627aA160A6fA45Eb793D19Ef54f5062F20f33f);

    ISwapRouter constant swapRouter =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address constant veCRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address constant vlCVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    address constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 currentPositionId;
    uint256 currentCvxNftId;
    uint256 currentBundleNftId;
    address afETH;
    address CVXNFT;
    address bundleNFT;
    address crvPool;

    // As recommended by https://docs.openzeppelin.com/upgrades-plugins/1.x/writing-upgradeable
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
        @notice - Function to initialize values for the contracts
        @dev - This replaces the constructor for upgradeable contracts
        @param _tokenName - name of erc20
        @param _tokenSymbol - symbol of erc20
    */
    function initialize(
        address _token,
        address _cvxNft,
        address _bundleNft,
        address _crvPool,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external initializer {
        ERC20Upgradeable.__ERC20_init(_tokenName, _tokenSymbol);

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

    function stake() public payable {
        uint256 ratio = getAsymmetryRatio();
        uint256 cvxAmount = (msg.value * ratio) / 10000;
        uint256 ethAmount = (msg.value - cvxAmount) / 2;

        uint256 cvxAmountReceived = swapCvx(cvxAmount);
        uint256 amountCvxLocked = lockCvx(cvxAmountReceived);
        (uint256 cvxNftBalance, uint256 _cvxNFTID) = mintCvxNft(
            msg.sender,
            amountCvxLocked
        );

        uint256 afEthAmount = ethAmount;
        _mint(address(this), afEthAmount);
        uint256 crvLpAmount = addAfEthCrvLiquidity(
            crvPool,
            ethAmount,
            afEthAmount
        );

        // TODO: mint a bundle NFT
        // uint256 bundleNftId = mintBundleNft(
        //     currentCvxNftId,
        //     amountCvxLocked,
        //     balLpAmount
        // );

        // storage of individual balances associated w/ user deposit
        // TODO: This calculation doesn't update when afETH is transferred between wallets
        uint256 newPositionID = ++currentPositionId;
        positions[msg.sender] = Position({
            positionID: newPositionID,
            curveBalances: crvLpAmount,
            convexBalances: amountCvxLocked,
            cvxNFTID: _cvxNFTID,
            bundleNFTID: 0, //bundleNftId,
            afETH: afEthAmount,
            createdAt: block.timestamp
        });
    }

    function getCvxPriceData() public view returns (uint256) {
        (, int256 price, , , ) = chainLinkCvxFeed.latestRoundData();
        if (price < 0) {
            price = 0;
        }
        uint8 decimals = chainLinkCvxFeed.decimals();
        return uint256(price) * 10 ** (decimals + 2); // Need to remove decimals and send price with the precision including decimals
    }

    function getCrvPriceData() public view returns (uint256) {
        (, int256 price, , , ) = chainLinkCrvFeed.latestRoundData();
        if (price < 0) {
            price = 0;
        }
        uint8 decimals = chainLinkCrvFeed.decimals();
        return uint256(price) * 10 ** (decimals + 2); // Need to remove decimals and send price with the precision including decimals
    }

    function getAsymmetryRatio() public view returns (uint256 ratio) {
        uint256 crvPrice = getCrvPriceData();
        uint256 cvxPrice = getCvxPriceData();
        uint256 cvxSupply = IERC20(CVX).totalSupply();
        uint256 tvl = 10000000; // TODO: Should be ETH/afETH pool tvl
        uint256 apy = 1500;
        uint256 offset = 30;

        // 1597471200 - represents Aug 15th 2020 when curve was initialized
        // 31556926 - represents 1 year including leap years
        uint256 emissionYear = ((block.timestamp - 1597471200) / 31556926) + 1; // which year the emission schedule is on
        uint256 crvPerDay = emissionsPerYear[emissionYear] / 365;

        uint256 yearly_minted_crv_per_cvx = ((crvPerDay * 10 ** offset) /
            cvxSupply) *
            365 *
            uint256(crvPrice);

        uint256 cvx_amount = ((((apy + 10000) * (tvl / 10000)) - tvl) *
            10 ** offset) / yearly_minted_crv_per_cvx;

        uint256 allocationPercentage = (((((cvx_amount * uint256(cvxPrice)) /
            10 ** 18) * 10000) /
            (tvl + ((cvx_amount * uint256(cvxPrice)) / 10 ** 18))) * 10000) /
            10000;

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

    // strat has afETH, deposit in CRV pool
    function addAfEthCrvLiquidity(
        address _pool,
        uint256 _ethAmount,
        uint256 _afEthAmount
    ) public returns (uint256 mint) {
        require(_ethAmount <= address(this).balance, "Not Enough ETH");

        IWETH(wETH).deposit{value: _ethAmount}();
        IWETH(wETH).approve(_pool, _ethAmount);

        // IAfETH afEthToken = IAfETH(afETH);
        // afEthToken.approve(_pool, _afEthAmount);

        uint256[2] memory _amounts = [_afEthAmount, _ethAmount];
        uint256 poolTokensMinted = ICrvEthPool(_pool).add_liquidity(
            _amounts,
            uint256(100000),
            false
        );
        return (poolTokensMinted);
    }

    function withdrawCRVPool(address _pool, uint256 _amount) public {
        address afETHPool = _pool;
        uint256[2] memory min_amounts;
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        positions[msg.sender].curveBalances = 0;
        ICrvEthPool(afETHPool).remove_liquidity(_amount, min_amounts);
    }

    function mintCvxNft(
        address sender,
        uint256 _amountLocked
    ) private returns (uint256 balance, uint256 nftId) {
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
        // IAfBundle1155(bundleNFT).mint(
        //     cvxNftId,
        //     cvxAmount,
        //     newBundleNftId,
        //     balPoolTokens,
        //     address(this)
        // );
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
        amounts[1] = positions[user].convexBalances;
        // IAfBundle1155(bundleNFT).burnBatch(address(this), ids, amounts);
    }
}
