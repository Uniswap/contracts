# Contributing

- [Install](#install)
- [Pre-commit Hooks](#pre-commit-hooks)
- [Requirements for merge](#requirements-for-merge)
- [Adding a new repository](#adding-a-new-repository)
- [Adding a deployer](#adding-a-deployer)

## Install

Follow these steps to set up your local environment for development:

- [Install foundry](https://book.getfoundry.sh/getting-started/installation)
- Install dependencies: `forge install`
- [Install pre-commit](https://pre-commit.com/#installation)
- Install pre commit hooks: `pre-commit install`

## Pre-commit Hooks

Follow the [installation steps](#install) to enable pre-commit hooks. To ensure consistency in our formatting `pre-commit` is used to check whether code was formatted properly and the documentation is up to date. Whenever a commit does not meet the checks implemented by pre-commit, the commit will fail and the pre-commit checks will modify the files to make the commits pass. Include these changes in your commit for the next commit attempt to succeed. On pull requests the CI checks whether all pre-commit hooks were run correctly.
This repo includes the following pre-commit hooks that are defined in the `.pre-commit-config.yaml`:

- `mixed-line-ending`: This hook ensures that all files have the same line endings (LF).
- `format`: This hook uses `forge fmt` to format all Solidity files.
- `prettier`: All remaining files are formatted using prettier.

## Requirements for merge

In order for a PR to be merged, it must pass the following requirements:

- All commits within the PR must be signed
- CI must pass (tests, linting, etc.)
- New features must be merged with associated tests
- Bug fixes must have a corresponding test that fails without the fix
- The PR must be approved by at least one maintainer
  - The PR must be approved by 2+ maintainers if the PR is a new feature or > 100 LOC changed

## Adding a new repository

### 1. Add the repository to packages

Run `git submodule add https://github.com/Uniswap/<repository-name> src/pkgs/<repository-name>`

### 2. Add compilation settings to foundry.toml

In the `foundry.toml` file, first create a profile with the compiler settings.

```
additional_compiler_profiles = [
  ...
  { name = "<repository-name>", optimizer_runs = <optimizer-runs>, via_ir = <via_ir>, ... },
]
```

Next, add the compilation restrictions to use the new profile. Compilation restrictions define what compiler profiles can be used to compile individual files. The restrictions should be defined in a way so that the main contracts used for deployments from the new repository can only be compiled with the newly added profile from this step to ensure consistent deployments.

```
compilation_restrictions = [
  ...
  { paths = "src/pkgs/<repository-name>/src/**", version = "<version>", optimizer_runs = <optimizer-runs>, via_ir = <via_ir>, evm_version = <evm_version> },
]
```

The `version` should be fixed (e.g., `=0.8.29`) to ensure that foundry does not compile the package with a different version.

Should other packages depend on interfaces of the new package, to ensure that the interfaces can also be compiled with other versions, the path should exclude interfaces from the compilation restrictions. E.g., `paths = "src/pkgs/<repository-name>/src/**/[!i]*.sol"`

Should the package include libraries other packages depend on, multiple compilation restrictions should be added to ensure that the compilation restrictions do not interfere with the compilation restrictions of other packages. E.g.,

```
{ paths = "src/pkgs/<repository-name>/src/**/libraries/**", version = "<0.9.0", optimizer_runs = <optimizer_runs>, via_ir = <via_ir> },
{ paths = "src/pkgs/<repository-name>/src/*.sol", version = "0.8.26", ... },
```

### 3. Add foundry remappings for dependencies

In the remappings.txt file, add the remappings for the dependencies of the new package.

```
src/pkgs/<repository-name>:dependency1=src/pkgs/<repository-name>/lib/dependency1
src/pkgs/<repository-name>:dependency2=src/pkgs/<repository-name>/lib/dependency2
```

### 4. Generate briefcase files

Run `./script/util/create_briefcase.sh` to generate the briefcase files for the new package.

## Adding a deployer

### 1. Create a new deployer

Create a new deployer in the `src/briefcase/deployers` folder.

The file should be located in the directory of the package of the contract. The name of the file should be the name of the contract with the `Deployer.sol` suffix:

`src/briefcase/deployers/<package-name>/<contract-name>Deployer.sol`

The structure of the file should be as follows:

```solidity
// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import {<ContractInterface>} from '../../protocols/<package-name>/interfaces/<ContractInterface>.sol';

library <ContractName>Deployer {
    function deploy(address <arg1>, uint256 <arg2>) internal returns (<ContractInterface> contract) {
        bytes memory args = abi.encode(<arg1>, <arg2>);
        bytes memory initcode_ = abi.encodePacked(initcode(), args);
        assembly {
            contract := create(0, add(initcode_, 32), mload(initcode_))
        }
    }

    /**
     * @dev autogenerated - run `./script/util/create_briefcase.sh` to generate current initcode
     *
     * @notice This initcode is generated from the following contract:
     * - Source Contract: src/pkgs/<package-name>/src/<contract-name>.sol
     */
    function initcode() internal pure returns (bytes memory) {
        return hex'';
    }
}
```

The deploy function can run arbitrary logic to deploy the contract, e.g., deploying via create, create2, using a factory, or a proxy. The deployer function should return the address and interface of the deployed contract so it can be called in subsequent steps.

After creating the deployer file, it's important to update the `Source Contract` path in the comment above the `initcode` function. This ensures that the correct contract is used for the initcode.

Finally, run `./script/util/create_briefcase.sh` to generate the initcode for the deployer and populate the bytecode in the initcode function.

### 2. Add the contract to the task template

Modify the `script/deploy/tasks/task_template.json` file to add the new contract to the task template. The contract can either be added to a new protocol or to an existing protocol where appropriate.

#### Adding a new protocol

```json
"protocols": {
  ...,
  "<protocol-name>": {
    "name": "Permit 2", // The name that will be displayed in the deploy-cli for that protocol
    "deploy": false, // deploy is false by default
    "contracts": {
      ... // contracts that can be deployed for that protocol
    },
  }
}
```

#### Adding a new contract to an existing protocol

```json
contracts: {
  "<contract-name>": {
    "deploy": false, // deploy is false by default
    "address": null, // address is null by default
    "params": {
      ... // parameters for the contract deployment
    },
    "lookup": {
      ... // optional, lookup information for the contract
    },
    "dependencies": [
      ... // optional, dependencies for the contract
    ]
  }
}
```

**Params**

The params object allows the deployer tool to pass arguments to the deployment.

```json
"params": {
  "<arg-name>": {
    "type": "<type>", // e.g., uint256, address, bool, etc.
    "name": "<name>", // optional, if provided it will be displayed to the user instead of the arg-name
    "value": "<value>", // optional, if provided it will be prompted to the user as a default value
    "pointer": "protocols.<protocol-name>.contracts.<contract-name>" // optional, if provided it will be used to resolve the value at runtime
  }
}
```

If a value is provided, it will be displayed to the user as a default value, the user can then press enter to use the default value or provide a new value.

A pointer allows to dynamically resolve the value of the argument at runtime. This is primarily used to resolve the address of contracts that are deployed in the same run in prior steps. For example, when deploying Uniswap v2, the address of the Uniswap v2 factory needs to be resolved at runtime within the deployment of the Uniswap v2 router. If the v2 factory is deployed in the same run, the pointer would then point to the address of the newly deployed factory. If the v2 factory is not deployed, the user will be prompted to provide the address of the factory.

**Lookup**

The lookup object allows the deployer tool to find past deployments of the contract in the deployment logs located in `deployments/json/<chain-id>.json`. If a contract has been found there, the deployer tool will display the address to the user as a quick selection option for convenience. For example, when deploying the UniversalRouter, where Permit2 is a constructor argument, the lookup object can provide the location of past Permit2 deployments to the user for that chain.

It can either point at the address of the latest deployment of the contract or a point in time it was used as a constructor argument in the past.

```json
"lookup": {
  "latest": "<contract-name>",
  "history": [<other-contract>.input.constructor.params.<param-name>]
}
```

**Dependencies**

The dependencies array specifies other external contracts that are required to deploy the current contract but are not deployable by the deployer tool (e.g., WETH).

### 3. Add the deployer to the deployment script

Add the deployer to the deployment script used by the deploy-cli.

`script/deploy/Deploy-all.s.sol`

```solidity
function deploy<ProtocolName>() private {
    if (!config.readBoolOr('.protocols.<protocol-name>.deploy', false)) return;

    console.log('deploying <ContractName>');
    <ContractName>Deployer.deploy(<params>);
}
```

Create a new protocol section in the config file, create a new function in the deployment script that will deploy the contracts for that protocol. This function should then be called from the `run` function in the deployment script.

Within the protocol section the to be deployed contract is defined in, read the arguments for that contract from the config file and pass them to the deployer library for that contract.

Should the contract have dependencies that need to be resolved at runtime (e.g., the factory when deploying a router), ensure that the dependency contracts are deployed before the current contract.
