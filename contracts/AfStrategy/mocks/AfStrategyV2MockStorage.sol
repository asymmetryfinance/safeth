// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../../interfaces/rocketpool/RocketStorageInterface.sol";
import "../../interfaces/uniswap/ISwapRouter.sol";

// Upgradeability Rules:
// DO NOT change existing variable names or types
// DO NOT change order of variables
// DO NOT remove any variables
// ONLY add new variables at the end
contract AfStrategyV2MockStorage {
    // Constant values CAN be modified on upgrade
    uint256 public constant numberOfDerivatives = 3;
    address public constant wETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public constant veCRV = 0x5f3b5DfEb7B28CDbD7FAba78963EE202a494e2A2;
    address public constant vlCVX = 0x72a19342e8F1838460eBFCCEf09F6585e32db86E;
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant stEthToken = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant lidoCrvPool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant sfrxEthAddress = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address public constant frxEthAddress = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address public constant frxEthCrvPoolAddress = 0xa1F8A6807c402E4A15ef4EBa36528A3FED24E577;
    address public constant frxEthMinterAddress = 0xbAFA44EFE7901E04E39Dad13167D089C559c1138;
    address public constant rocketStorageAddress = 0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46;
    address public constant uniswapRouter = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
    uint256 public constant ROCKET_POOL_LIMIT = 5000000000000000000000;

    address public afETH;
    bool public pauseStaking;
    bool public pauseUnstaking;

    bool public newFunctionCalled;
}