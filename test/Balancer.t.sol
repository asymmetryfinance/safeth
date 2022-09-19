// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
//import "../src/interfaces/balancer/IWeightedPoolFactory.sol";
import "../src/interfaces/balancer/IInvestmentPoolFactory.sol";
import "../src/interfaces/IERC20.sol";
import "forge-std/console.sol";
import "../src/interfaces/balancer/IBasePool.sol";
import "../src/interfaces/balancer/IVault.sol";

// contracts
address constant VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;
//address constant WeightedPoolFactory = 0x8E9aa87E45e92bad84D5F8DD1bff34Fb92637dE9;
address constant InvestmentPoolFactory = 0x48767F9F868a4A7b86A90736632F6E44C2df7fa9;
address constant ZERO_ADDRESS = 0x0000000000000000000000000000000000000000;
address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
address constant RETH = 0xae78736Cd615f374D3085123A210448E74Fc6393;

contract BalancerTest is Test {
    // IWeightedPoolFactory constant factory = IWeightedPoolFactory(WeightedPoolFactory);
    IInvestmentPoolFactory constant investmentFactory =
        IInvestmentPoolFactory(InvestmentPoolFactory);
    IVault constant vault = IVault(VAULT);
    // Pool Creation Args
    IERC20 private stETH = IERC20(STETH);
    IERC20 private rETH = IERC20(RETH);
    IERC20[] public tokens = [rETH, stETH];
    string constant NAME = "grETH Test Pool";
    string constant SYMBOL = "50stETH-50rETH";
    uint256 constant swapFeePercentage = 5e15; // 0.5%
    bool constant swapEnabledOnStart = false;
    uint256 managementSwapFeePercentage = 5e15;

    uint256[] public weights = [50e16, 50e16];

    function setUp() public {}
    /*
    function testDeployPool() public {
        address owner = msg.sender;

        address poolAddress = investmentFactory.create(
            NAME,
            SYMBOL,
            tokens,
            weights,
            swapFeePercentage,
            owner,
            swapEnabledOnStart,
            managementSwapFeePercentage
        );
        emit log_named_address("Created Pool Address:", poolAddress);
        IBasePool pool = IBasePool(poolAddress);
        bytes32 poolID = pool.getPoolId();
        emit log_named_bytes32("PoolID", poolID);
        address testPoolAddress = vault.getPool(poolID);
        emit log_named_address("Test Pool Address:", testPoolAddress);
    }
*/
}
