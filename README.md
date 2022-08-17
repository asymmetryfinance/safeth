# Project Golden Ratio • ![solidity](https://img.shields.io/badge/solidity-^0.8.13-lightgrey)

## To Do

Interfaces for deposits:

1. Curve: I3CRVZap, ICurve, ISwapRouter
2. Convex: IBooster (deposit contract for LP tokens), IBaseRewardPool (Main reward contract for all LP pools)
3. Chainlink: AggregatorV3Interface
4. Lido: ILido: submit(address) returns (uint256)
5. RocketPool: RocketStorageInterface, RocketDepositPoolInterface, RocketETHTokenInterface

## About

## Development

Fundamentals:

1. Deposit funds into contract: 48ETH -> 16 ETH to CVX; 16 ETH to Curve LP; 16 ETH to liquid staking to BPT Index

**Setup**

```bash
forge install
```

**Building**

```bash
forge build
```

**Testing**

```bash
forge test
```

### First time with Forge/Foundry?

See the official Foundry installation [instructions](https://github.com/foundry-rs/foundry/blob/master/README.md#installation).

Then, install the [foundry](https://github.com/foundry-rs/foundry) toolchain installer (`foundryup`) with:

```bash
curl -L https://foundry.paradigm.xyz | bash
```

Now that you've installed the `foundryup` binary,
anytime you need to get the latest `forge` or `cast` binaries,
you can run `foundryup`.

So, simply execute:

```bash
foundryup
```

## License

## Acknowledgements

- [foundry](https://github.com/foundry-rs/foundry)
- [solmate](https://github.com/Rari-Capital/solmate)
- [forge-std](https://github.com/brockelmore/forge-std)
