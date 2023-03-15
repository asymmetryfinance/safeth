# [Asymmetry Finance](https://www.asymmetry.finance/) • ![solidity](https://img.shields.io/badge/solidity-^0.8.13-lightgrey)

## About

SafEth is a smart contract suite that enables a user to diversify their ETH into staked derivatives.
Currently the supported staked derivatives are [wstETH](https://lido.fi/), [rETH](https://rocketpool.net/), and [sfrxETH](https://docs.frax.finance/frax-ether/frxeth-and-sfrxeth).


The goal of SafEth is to help decentralize the liquid staked derivatives on the Ethereum blockchain.  This is done by enabling and easy access to diversification of derivatives.

In the future, SafEth will be used in conjunction with other smart contracts to allow the staking of SafEth to gain higher yield. 

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
