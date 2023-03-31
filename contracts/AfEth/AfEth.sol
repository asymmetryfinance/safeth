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
import "../interfaces/ISnapshotDelegationRegistry.sol";
import "./interfaces/convex/ILockedCvx.sol";
import "./interfaces/convex/IClaimZap.sol";
import "../interfaces/curve/ICvxCrvCrvPool.sol";
import "../interfaces/curve/IFxsEthPool.sol";
import "../interfaces/curve/ICrvEthPool.sol";
import "../interfaces/curve/ICvxFxsFxsPool.sol";
import "../interfaces/curve/IAfEthPool.sol";
import "./interfaces/IAf1155.sol";
import "./interfaces/ISafEth.sol";
import "hardhat/console.sol";

contract AfEth is
    Initializable,
    ERC20Upgradeable,
    ERC1155Holder,
    OwnableUpgradeable
{
    event UpdateCrvPool(address indexed newCrvPool, address oldCrvPool);

    // curve emissions based on year
    mapping(uint256 => uint256) private emissionsPerYear;

    mapping(address => uint256) public nftIds;
    uint256 nftId = 0;

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

    address constant cvxClaimZap = 0x3f29cB4111CbdA8081642DA1f75B3c12DECf2516;

    address constant cvxCrv = 0x62B9c7356A2Dc64a1969e19C23e4f579F9810Aa7;
    address constant fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address constant crv = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address constant cvxFxs = 0xFEEf77d3f69374f66429C91d732A244f074bdf74;

    address public constant FXS_ETH_CRV_POOL_ADDRESS =
        0x941Eb6F616114e4Ecaa85377945EA306002612FE;
    address public constant CVXFXS_FXS_CRV_POOL_ADDRESS =
        0xd658A338613198204DCa1143Ac3F01A722b5d94A;
    address public constant CVXCRV_CRV_CRV_POOL_ADDRESS =
        0x9D0464996170c6B9e75eED71c68B99dDEDf279e8;
    address public constant CRV_ETH_CRV_POOL_ADDRESS =
        0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    address public constant SNAPSHOT_DELEGATE_REGISTRY =
        0x469788fE6E9E9681C6ebF3bF78e7Fd26Fc015446;

    address afETH;
    address CVXNFT;
    address bundleNFT;
    address crvPool;
    address safEth;

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
        address _cvxNft,
        address _bundleNft,
        address _safEth,
        string memory _tokenName,
        string memory _tokenSymbol
    ) external initializer {
        ERC20Upgradeable.__ERC20_init(_tokenName, _tokenSymbol);
        _transferOwnership(msg.sender);

        CVXNFT = _cvxNft;
        bundleNFT = _bundleNft;
        safEth = _safEth;

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

        // Assumes AfEth contract owns the vote locked convex
        // This will need to be done elseware if other contracts own or wrap the vote locked convex
        bytes32 vlCvxVoteDelegationId = 0x6376782e65746800000000000000000000000000000000000000000000000000;
        ISnapshotDelegationRegistry(SNAPSHOT_DELEGATE_REGISTRY).setDelegate(
            vlCvxVoteDelegationId,
            owner()
        );
    }

    function stake() external payable {
        uint256 ratio = getAsymmetryRatio(150000000000000000); // TODO: make apr changeable
        uint256 cvxAmount = (msg.value * ratio) / 10 ** 18;
        uint256 ethAmount = (msg.value - cvxAmount) / 2;

        uint256 cvxAmountReceived = swapCvx(cvxAmount);
        uint256 amountCvxLocked = lockCvx(cvxAmountReceived);

        (uint256 cvxNftBalance, uint256 cvxNFTID) = mintCvxNft(
            msg.sender,
            amountCvxLocked
        );

        // TODO: return mint amount from stake function
        ISafEth(safEth).stake{value: ethAmount}();
        uint256 afEthAmount = ethAmount;

        _mint(address(this), afEthAmount);

        uint256 crvLpAmount = addAfEthCrvLiquidity(
            crvPool,
            ethAmount,
            afEthAmount
        );

        mintBundleNft(crvLpAmount, cvxNFTID);

        // storage of individual balances associated w/ user deposit
        // This calculation doesn't update when afETH is transferred between wallets
        // if we can not need this that'd be great, Maybe the bundle nft can handle the acounting from this
        uint256 newPositionID = ++currentPositionId;
        // positions[msg.sender] = Position({
        //     positionID: newPositionID,
        //     curveBalances: crvLpAmount,
        //     convexBalances: cvxNftBalance,
        //     cvxNFTID: cvxNFTID,
        //     bundleNFTID: 0, // maybe not needed yet,
        //     afETH: afEthAmount,
        //     createdAt: block.timestamp
        // });
    }

    function unstake(bool _instantWithdraw) external payable {
        // TODO: add option to not unstake all
        uint256 afEthBalance = IERC20(afETH).balanceOf(msg.sender);
        withdrawCVXNft(_instantWithdraw, _id);
        withdrawCRVPool(crvPool, 100000);
        _burn(msg.sender, afEthBalance);

        burnBundleNFT(msg.sender);
        IWETH(wETH).withdraw(IWETH(wETH).balanceOf(address(this))); // TODO: this seems broken
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

    function getAsymmetryRatio(
        uint256 apy
    ) public view returns (uint256 ratio) {
        uint256 cvxPrice = getCvxPriceData();
        uint256 crvPrice = getCrvPriceData();
        uint256 emissionYear = ((block.timestamp - 1597471200) / 31556926) + 1; // which year the emission schedule is on
        uint256 totalUsdEmissionsPerYear = (emissionsPerYear[emissionYear] *
            crvPrice);
        uint256 cvxAmount = (((apy) * IERC20(CVX).totalSupply()) /
            totalUsdEmissionsPerYear);
        uint256 cvxAmountUsdValue = (cvxAmount * uint256(cvxPrice));
        return
            (cvxAmountUsdValue) / (10 ** 18 + (cvxAmountUsdValue / 10 ** 18));
    }

    function swapExactInputSingleHop(
        address tokenIn,
        address tokenOut,
        uint24 poolFee,
        uint256 amountIn
    ) private returns (uint256 amountOut) {
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

    function swapCvx(uint256 amount) private returns (uint256 amountOut) {
        IWETH(wETH).deposit{value: amount}();
        uint256 amountSwapped = swapExactInputSingleHop(
            wETH,
            CVX,
            10000,
            amount
        );
        return amountSwapped;
    }

    function lockCvx(uint256 _amountToLock) private returns (uint256 amount) {
        uint256 amountToLock = _amountToLock;
        IERC20(CVX).approve(vlCVX, amountToLock);
        ILockedCvx(vlCVX).lock(address(this), amountToLock, 0);
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
    ) private returns (uint256 mintAmount) {
        require(_ethAmount <= address(this).balance, "Not Enough ETH");

        IWETH(wETH).deposit{value: _ethAmount}();
        IWETH(wETH).approve(_pool, _ethAmount);
        _approve(address(this), _pool, _afEthAmount);

        uint256[2] memory _amounts = [_afEthAmount, _ethAmount];
        uint256 poolTokensMinted = IAfEthPool(_pool).add_liquidity(
            _amounts,
            uint256(100000),
            false
        );
        return (poolTokensMinted);
    }

    function withdrawCRVPool(
        address _pool,
        uint256 _amount
    ) private returns (uint256) {
        uint256[2] memory min_amounts;
        // TODO: update min amounts
        min_amounts[0] = 0;
        min_amounts[1] = 0;
        // positions[msg.sender].curveBalances = 0;
        IAfEthPool(_pool).remove_liquidity(_amount, min_amounts);
    }

    function mintBundleNft(uint256 _amount, uint256 _id) private {
        IAfBundle1155(bundleNFT).mint(msg.sender, _amount, _id);
        nftId++;
    }

    function burnBundleNFT(
        address _from,
        uint256 _id,
        uint256 _amount
    ) private {
        // uint256[2] memory ids;
        // uint256[2] memory amounts;
        // ids[0] = positions[user].bundleNFTID;
        // ids[1] = positions[user].cvxNFTID;
        // amounts[1] = positions[user].convexBalances;
        IAfBundle1155(bundleNFT).burn(_from, _id, _amount);
    }

    function mintCvxNft(
        address sender,
        uint256 _amountLocked
    ) private returns (uint256 _balance, uint256 _id) {
        uint256 amountLocked = _amountLocked;

        IAfCVX1155(CVXNFT).mint(address(this), nftId, amountLocked);
        // positions[sender].cvxNFTID = newCvxNftId;
        return (amountLocked, nftId);
    }

    // user selection in front-end:
    // True - user is transferred the 1155 NFT holding their CVX deposit
    // until CVX lockup period is over (16 weeks plus days to thursday 0000 UTC)
    // False - user pays fee to unlock their CVX and burn their NFT
    function withdrawCVXNft(bool _instantWithdraw, uint256 _cvxNFTID) private {
        if (_instantWithdraw == false) {
            // TODO: start withdraw vlCVX
            IAfCVX1155(CVXNFT).safeTransferFrom(
                address(this),
                msg.sender,
                _cvxNFTID,
                // positions[msg.sender].convexBalances,
                ""
            );
            console.log(
                "user balance of CVX NFT:",
                IAfCVX1155(CVXNFT).balanceOf(
                    msg.sender,
                    // positions[msg.sender].cvxNFTID
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

    function updateCrvPool(address _crvPool) public onlyOwner {
        emit UpdateCrvPool(_crvPool, crvPool);
        crvPool = _crvPool;
    }

    function claimRewards(uint256 _maxSlippage) public onlyOwner {
        address[] memory emptyArray;
        IClaimZap(cvxClaimZap).claimRewards(
            emptyArray,
            emptyArray,
            emptyArray,
            emptyArray,
            0,
            0,
            0,
            0,
            8
        );
        // cvxFxs -> fxs
        uint256 cvxFxsBalance = IERC20(cvxFxs).balanceOf(address(this));
        if (cvxFxsBalance > 0) {
            uint256 oraclePrice = ICvxFxsFxsPool(CVXFXS_FXS_CRV_POOL_ADDRESS)
                .get_dy(1, 0, 10 ** 18);
            uint256 minOut = (((oraclePrice * cvxFxsBalance) / 10 ** 18) *
                (10 ** 18 - _maxSlippage)) / 10 ** 18;

            IERC20(cvxFxs).approve(CVXFXS_FXS_CRV_POOL_ADDRESS, cvxFxsBalance);
            ICvxFxsFxsPool(CVXFXS_FXS_CRV_POOL_ADDRESS).exchange(
                1,
                0,
                cvxFxsBalance,
                minOut
            );
        }

        // fxs -> eth
        uint256 fxsBalance = IERC20(fxs).balanceOf(address(this));
        if (fxsBalance > 0) {
            uint256 oraclePrice = IFxsEthPool(FXS_ETH_CRV_POOL_ADDRESS).get_dy(
                1,
                0,
                10 ** 18
            );
            uint256 minOut = (((oraclePrice * fxsBalance) / 10 ** 18) *
                (10 ** 18 - _maxSlippage)) / 10 ** 18;

            IERC20(fxs).approve(FXS_ETH_CRV_POOL_ADDRESS, fxsBalance);

            IERC20(fxs).allowance(address(this), FXS_ETH_CRV_POOL_ADDRESS);

            IFxsEthPool(FXS_ETH_CRV_POOL_ADDRESS).exchange_underlying(
                1,
                0,
                fxsBalance,
                minOut
            );
        }
        // cvxCrv -> crv
        uint256 cvxCrvBalance = IERC20(cvxCrv).balanceOf(address(this));
        if (cvxCrvBalance > 0) {
            uint256 oraclePrice = ICvxCrvCrvPool(CVXCRV_CRV_CRV_POOL_ADDRESS)
                .get_dy(1, 0, 10 ** 18);
            uint256 minOut = (((oraclePrice * cvxCrvBalance) / 10 ** 18) *
                (10 ** 18 - _maxSlippage)) / 10 ** 18;
            IERC20(cvxCrv).approve(CVXCRV_CRV_CRV_POOL_ADDRESS, cvxCrvBalance);
            ICvxCrvCrvPool(CVXCRV_CRV_CRV_POOL_ADDRESS).exchange(
                1,
                0,
                cvxCrvBalance,
                minOut
            );
        }

        // crv -> eth
        uint256 crvBalance = IERC20(crv).balanceOf(address(this));
        if (crvBalance > 0) {
            uint256 oraclePrice = ICrvEthPool(CRV_ETH_CRV_POOL_ADDRESS).get_dy(
                1,
                0,
                10 ** 18
            );
            uint256 minOut = (((oraclePrice * crvBalance) / 10 ** 18) *
                (10 ** 18 - _maxSlippage)) / 10 ** 18;

            IERC20(crv).approve(CRV_ETH_CRV_POOL_ADDRESS, crvBalance);
            ICrvEthPool(CRV_ETH_CRV_POOL_ADDRESS).exchange_underlying(
                1,
                0,
                crvBalance,
                minOut
            );
        }

        return;
    }

    // TODO make this function private once we figure out a solution for unlocking
    function unlockCvx() public {
        ILockedCvx(vlCVX).processExpiredLocks(false);
    }
}
