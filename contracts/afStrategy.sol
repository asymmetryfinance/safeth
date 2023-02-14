// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IAfETH.sol";
import "./interfaces/frax/IFrxETHMinter.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/uniswap/ISwapRouter.sol";
import "./interfaces/curve/ICrvEthPool.sol";
import "./interfaces/rocketpool/RocketDepositPoolInterface.sol";
import "./interfaces/rocketpool/RocketStorageInterface.sol";
import "./interfaces/rocketpool/RocketTokenRETHInterface.sol";
import "./interfaces/lido/IWStETH.sol";
import "./interfaces/lido/IstETH.sol";
import "./interfaces/balancer/IVault.sol";
import "./interfaces/balancer/IBalancerHelpers.sol";
import "./Vault.sol";
import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "./constants.sol";
import "hardhat/console.sol";

contract AfStrategy is Ownable {
    event StakingPaused(bool paused);
    event UnstakingPaused(bool paused);
    event SetVault(address token, address vault);

    struct Position {
        uint256 positionID;
        uint256 rEthBalance;
        uint256 wstEthBalance;
        uint256 sfraxBalance;
        uint256 balancerBalance;
        uint256 afETHBalance;
        uint256 createdAt;
    }

    // ERC-4626 Vaults of each derivative (token address => vault address)
    mapping(address => address) public vaults;

    // map user address to Position struct
    mapping(address => Position) public positions;
    uint256 private currentPositionId;

    AggregatorV3Interface constant chainLinkEthFeed =
        AggregatorV3Interface(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);

    RocketStorageInterface rocketStorage;

    ISwapRouter constant swapRouter =
        ISwapRouter(0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45);

    address public afETH;
    uint256 private numberOfDerivatives = 3;

    // balancer pool things
    address private afBalancerPool = 0xBA12222222228d8Ba445958a75a0704d566BF2C8; // Temporarily using wstETH pool
    bytes32 balPoolId =
        0x32296969ef14eb0c6d29669c550d4a0449130230000200000000000000000080;
    address private balancerHelpers =
        0x5aDDCCa35b7A0D07C74063c48700C8590E87864E;

    uint256 private constant ROCKET_POOL_LIMIT = 5000000000000000000000; // TODO: make changeable by owner
    bool public pauseStaking = false;
    bool public pauseUnstaking = false;

    constructor(address _afETH, address _rocketStorageAddress) {
        rocketStorage = RocketStorageInterface(_rocketStorageAddress);
        afETH = _afETH;
    }

    /*//////////////////////////////////////////////////////////////
                        OPEN/CLOSE POSITION LOGIC
    //////////////////////////////////////////////////////////////*/

    function stake() public payable {
        require(pauseStaking == false, "staking is paused");

        uint256 ethAmount = msg.value;

        uint256 wstEthMinted = depositWstEth(ethAmount / numberOfDerivatives);
        Vault(vaults[wstETH]).deposit(wstEthMinted, address(this));

        uint256 rEthMinted = depositREth(ethAmount / numberOfDerivatives);
        Vault(vaults[rETH]).deposit(rEthMinted, address(this));

        uint256 sfraxMinted = depositSfrax(ethAmount / numberOfDerivatives);
        Vault(vaults[sfrax]).deposit(sfraxMinted, address(this));

        // TODO: Deploy and deposit balancer tokens of the 4626 vaults
        //uint256 balLpAmount = depositBalTokens(wstEthMinted);

        // TODO: After depositing to the balancer pool, mint a bundle NFT
        // uint256 bundleNftId = mintBundleNft(
        //     currentCvxNftId,
        //     amountCvxLocked,
        //     balLpAmount
        // );

        mintAfEth(ethAmount);

        // storage of individual balances associated w/ user deposit
        // TODO: This calculation doesn't update when afETH is transferred between wallets
        // TODO: This will not be correct when user stakes multiple times
        uint256 newPositionID = ++currentPositionId;
        positions[msg.sender] = Position({
            positionID: newPositionID,
            rEthBalance: rEthMinted,
            wstEthBalance: wstEthMinted,
            sfraxBalance: sfraxMinted,
            balancerBalance: 0, // TODO: add bal lp amount
            afETHBalance: ethAmount,
            createdAt: block.timestamp
        });
    }

    // must transfer amount out tokens to vault
    function unstake() public {
        require(pauseUnstaking == false, "unstaking is paused");

        // TODO: add option to not unstake all
        uint256 afEthBalance = IERC20(afETH).balanceOf(msg.sender);
        burnAfEth(afEthBalance);

        // TODO: Reintegrate Balancer with 4626 vaults
        // burnBundleNFT(msg.sender);
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

    function depositSfrax(uint256 amount) public payable returns (uint256) {
        address frxEthMinterAddress = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;
        IFrxETHMinter frxETHMinterContract = IFrxETHMinter(frxEthMinterAddress);
        uint256 sfrxBalancePre = IERC20(sfrax).balanceOf(address(this));
        frxETHMinterContract.submitAndDeposit{value: amount}(address(this));
        uint256 sfrxBalancePost = IERC20(sfrax).balanceOf(address(this));
        return sfrxBalancePost - sfrxBalancePre;
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
        uint256 amount = positions[msg.sender].rEthBalance;
        positions[msg.sender].rEthBalance = 0;
        rocketTokenRETH.burn(amount);
        uint256 rethBalance2 = rocketTokenRETH.balanceOf(address(this));
        require(rethBalance1 > rethBalance2, "No rETH was burned");
        uint256 rethBurned = rethBalance1 - rethBalance2;
    }

    function withdrawWstEth(uint256 _amount) public {
        positions[msg.sender].wstEthBalance = 0;
        IWStETH(wstETH).unwrap(_amount); // TODO: not using right amount of wstETH
        uint256 stEthBal = IERC20(stEthToken).balanceOf(address(this));
        IERC20(stEthToken).approve(lidoCrvPool, stEthBal);
        // convert stETH to ETH
        console.log("Eth before swapping steth to eth:", address(this).balance);
        ICrvEthPool(lidoCrvPool).exchange(1, 0, stEthBal, 0);
        console.log("Eth after swapping steth to eth:", address(this).balance);
    }

    function withdrawBalTokens() public returns (uint256 wstETH2Unwrap) {
        // bal lp amount
        uint256 amount = positions[msg.sender].balancerBalance;
        address[] memory _assets = new address[](2);
        uint256[] memory _amounts = new uint256[](2);
        _assets[0] = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        _assets[1] = 0x0000000000000000000000000000000000000000;
        // account for slippage from Balancer withdrawal
        _amounts[0] = (positions[msg.sender].wstEthBalance * 99) / 100;
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
        positions[msg.sender].balancerBalance = 0;
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

    /*//////////////////////////////////////////////////////////////
                        TOKEN METHODS
    //////////////////////////////////////////////////////////////*/

    /// @notice get ETH price data from Chainlink, may not be needed if we can get ratio from contracts for rETH and sfrxETH
    function getEthPriceData() public view returns (uint256) {
        (, int256 price, , , ) = chainLinkEthFeed.latestRoundData();
        if (price < 0) {
            price = 0;
        }
        uint8 decimals = chainLinkEthFeed.decimals();
        return uint256(price) * 10**(decimals + 2); // Need to remove decimals and send price with the precision including decimals
    }

    function mintAfEth(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.mint(address(this), amount);
    }

    function burnAfEth(uint256 amount) private {
        IAfETH afEthToken = IAfETH(afETH);
        afEthToken.burn(address(this), amount);
        positions[msg.sender].afETHBalance = 0;
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

    function getName() external pure returns (string memory) {
        return "AsymmetryFinance Strategy";
    }

    /*//////////////////////////////////////////////////////////////
                            FALLBACK
    //////////////////////////////////////////////////////////////*/

    receive() external payable {}
}
