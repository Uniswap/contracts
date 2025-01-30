## Uniswap Contracts Monorepo

This repo contains all Uniswap contracts. It is used to configure and execute deployments, as well as compile and update the briefcase repo/package.

#### Table of Contents

- [Setup](#setup)
- [Deployment](#deployment)
- [Docs](#docs)
- [Contributing](#contributing)

## Setup

Follow these steps to set up your local environment:

- [Install foundry](https://book.getfoundry.sh/getting-started/installation)
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

## Contributing

If you want to contribute to this project, please check [CONTRIBUTING.md](CONTRIBUTING.md) first.
