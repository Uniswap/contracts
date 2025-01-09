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

- Make sure node `>18.0` is installed
- Follow the [setup](#setup) instructions
- run `./deploy-cli` to generate deployment tasks and execute them

## Contributing

If you want to contribute to this project, please check [CONTRIBUTING.md](CONTRIBUTING.md) first.
