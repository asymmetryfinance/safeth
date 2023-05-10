# [Asymmetry Finance](https://www.asymmetry.finance/) • ![solidity](https://img.shields.io/badge/solidity-0.8.19-lightgrey)

## About

SafEth is a smart contract suite that enables a user to diversify their ETH into staked derivatives.
Currently the supported staked derivatives are [wstETH](https://lido.fi/), [rETH](https://rocketpool.net/), and [sfrxETH](https://docs.frax.finance/frax-ether/frxeth-and-sfrxeth).

The goal of SafEth is to help decentralize the liquid staked derivatives on the Ethereum blockchain. This is done by enabling and easy access to diversification of derivatives.

In the future, SafEth will be used in conjunction with other smart contracts to allow the staking of SafEth to gain higher yield.

## Contracts

- SafEth - 0x6732Efaf6f39926346BeF8b821a04B6361C4F3e5
- RocketPool - 0x7B6633c0cD81dC338688A528c0A3f346561F5cA3
- Frax - 0x36Ce17a5c81E74dC111547f5DFFbf40b8BF6B20A
- Lido - 0x972A53e3A9114f61b98921Fb5B86C517e8F23Fad

## Architecture

[Architecture Diagram](assets/SafEth-Architecture.drawio)

## Local Development

To use the correct node version run

```
nvm use
```

To install dependencies and compile run

```
yarn && yarn compile
```

## Testing

### Hardhat

For testing on hardhat simply run:

```
yarn test
```

Or for complete coverage:

```
yarn coverage
```

### Local Node

Run the following command to spin up your local node

```
yarn local:node
```

In another terminal run this command to deploy the contracts to your local node

```
yarn deploy --network localhost
```

Once deployed you can interact with your local contracts through Ethernal or scripts/tests
