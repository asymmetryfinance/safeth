# include .env file and export its env vars
# (-include to ignore error if it does not exist)
-include .env

# deps
update:; forge update

# Build & test
# change ETH_RPC_URL to another one (e.g., FTM_RPC_URL) for different chains
FORK_URL := ${ETH_RPC_URL} 
build  :; forge build
test  :; forge test
trace  :; forge test -vvv
# tests with forks
test-fork   :; forge test -vv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
trace-fork   :; forge test -vvv --fork-url ${FORK_URL} --etherscan-api-key ${ETHERSCAN_API_KEY}
test-contract :; forge test -vv --fork-url ${FORK_URL} --match-contract $(contract) --etherscan-api-key ${ETHERSCAN_API_KEY}
trace-contract :; forge test -vvv --fork-url ${FORK_URL} --match-contract $(contract) --etherscan-api-key ${ETHERSCAN_API_KEY}
test-mainnet-fork :; forge test --fork-url $(RPC_URL_MAINNET) --match-contract StETH4626.*Test -vvv
test-vault-fork :; forge test --fork-url $(MAINNET_RPC_URL) --match-contract Vault -vvv
test-strat-fork :; forge test --fork-url $(MAINNET_RPC_URL) --match-contract Strategy -vvv
test-gr-fork :; forge test --fork-url $(MAINNET_RPC_URL) --match-contract GoldenRatio -vvv
test-warden-fork :; forge test --fork-url $(MAINNET_RPC_URL) --match-contract Warden -vvv
# fork mainnnet
anvil :; anvil --fork-url $(MAINNET_RPC_URL) --chain-id 69420
clean  :; forge clean
snapshot :; forge snapshot

