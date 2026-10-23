## Uniswap Contracts Monorepo

This repo contains all Uniswap contracts. It is used to configure and execute deployments, as well as compile and update the briefcase repo/package.

#### Table of Contents

- [Setup](#setup)
- [Deployment](#deployment)
- [Docs](#docs)
- [Contributing](#contributing)

## Setup

Follow these steps to set up your local environment:

- [Install foundryup](https://book.getfoundry.sh/getting-started/installation)
- Fetch submodules: `git submodule update --init --recursive`
- Install dependencies: `forge install`
- Build contracts: `forge build`

## Deployment

- Follow the [setup](#setup) instructions
- Make sure node `>18.0` is installed
- Install `just` and `cargo`
- Install deploy-cli, `cd script/cli` and either
  - run `just install` to install the cli to your local bin and run `deploy-cli`
  - or run `just build` to build the cli, copy it to the project root, and run `./deploy-cli` from the project root

### Ethereum L1 after the Amsterdam upgrade

Amsterdam (Glamsterdam) adds state gas for deployed code (EIP-8037, 1,530 gas per byte). A large contract then needs more than 2^24 (16,777,216) gas to deploy. For example, a PoolManager deployment (24,009 bytes of code) uses 37,435,950 gas.

deploy-cli broadcasts with `forge script --broadcast --skip-simulation`. forge then gets the gas limit of each transaction from `eth_estimateGas` on the RPC node, multiplied by 1.3. This works on Amsterdam when the RPC node runs Amsterdam. A PoolManager-only task with forge 1.5.0 got a gas limit of 49,427,194 and deployed on a mainnet fork with Amsterdam rules. Geth 1.17.8 and reth 2.7 and 2.8 on Sepolia give the same gas used (37,435,950) for this transaction.

The dry run before the broadcast uses pre-Amsterdam gas rules. Its "Estimated total gas used for script" and "Estimated amount required" lines are too low (7,256,884 gas for the PoolManager task). Fund the deployer for the real cost. Do not broadcast `Deploy-all.s.sol` without `--skip-simulation`. forge then uses the simulated gas as the gas limit, and the deployment reverts on chain. `--gas-limit` does not help. In `forge script` it sets the block gas limit of the local simulation.

`Deploy-all.s.sol` expects the deterministic deployment proxy (`0x4e59b44847b379578588920cA78FbF26c0B4956C`) on the chain. If the proxy is missing, the script broadcasts a pre-signed transaction with a fixed gas limit of 100,000. On a chain with the Amsterdam gas rules this transaction needs 314,525 gas and fails. The proxy exists on Ethereum mainnet and Sepolia.

Check Amsterdam gas numbers from anvil before you use them. anvil 1.8.6 with `--hardfork amsterdam` and no `--fork-url` keeps the pre-Amsterdam gas rules. In fork mode it applies them, but `eth_estimateGas` for a create transaction without a `from` address returns a value that is too low.

## Contributing

If you want to contribute to this project, please check [CONTRIBUTING.md](CONTRIBUTING.md) first.
