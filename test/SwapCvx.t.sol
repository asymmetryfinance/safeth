// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";

import "../src/SwapCvx.sol";
import "../src/interfaces/convex/ILockedCvx.sol";

address constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
address constant CvxLockerV2 = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;

interface ICvxLockerV2 {
    function lock(
        address _account,
        uint256 _amount,
        uint256 _spendRatio
    ) external;
}

contract SwapCvxTest is ERC1155("grCVXNFT"), Test {
    IWETH private weth = IWETH(WETH9);
    IERC20 private cvx = IERC20(CVX);
    ICvxLockerV2 constant locker = ICvxLockerV2(CvxLockerV2);
    ILockedCvx constant lockedCvx = ILockedCvx(CvxLockerV2);

    SwapCvx private swap = new SwapCvx();

    function setUp() public {}

    function mint(uint256 id, uint256 amount) public {
        _mint(msg.sender, id, amount, "");
    }

    function testSwapAndLock() public {
        weth.deposit{value: 1e18}();
        weth.approve(address(swap), 1e18);

        uint amountOut = swap.swapExactInputSingleHop(WETH9, CVX, 10000, 1e18);

        //uint256 amountInCVX = amountOut / 1e18;
        console.log("CVX Swapped:", amountOut);

        // lock up CVX as vlCVX
        IERC20(CVX).approve(CvxLockerV2, amountOut);
        locker.lock(msg.sender, amountOut, 0);
        //console.log("address w/ locked balance:", msg.sender);
        console.log("Locked balance:", lockedCvx.lockedBalanceOf(msg.sender));
        mint(1, amountOut);
        console.log("1155 minted amount of CVX:", balanceOf(msg.sender, 1));
    }
}
