# Open Issues and bugs

## Foundry run-latest.json issues

- Nested smart contract deployments are not recorded

  - **Description**: When a contract is deployed and deploys another contract in the constructor, the second deployment does not show up in the `additionalContracts` array.
  - **Impact**: When deploying a transparent proxy, the [forge-chronicles](./lib/forge-chronicles) library relies on the `additionalContracts` array to fetch the deployed `ProxyAdmin` contract. This functionality doesn't seem to work right now and thus the `ProxyAdmin` contract is not recorded in the deployment logs.
  - **Expected behavior**: The `additionalContracts` array should contain all the deployed contracts, including the nested ones.
  - **Workaround**: Generate the deployment logs manually after the deployment is complete using the `deploy-cli`.

- Linked external libraries make bytecode not recognizable
  - **Description**: When a contract has a linked external library, the bytecode is not matched correctly by foundry and `contractName` is `null`.
  - **Impact**: Contracts deployed in this repo don't have deployment logs generated automatically.
    - _Example_: [NonfungibleTokenPositionDescriptor](./src/briefcase/deployers/v3-periphery/NonfungibleTokenPositionDescriptorDeployer.sol)
  - **Expected behavior**: Foundry should be able to recognize that the placeholders in the bytecode have been replaced by the actual library address and match the bytecode correctly to the contract name.
  - **Workaround**: Generate the deployment logs manually after the deployment is complete using the `deploy-cli`.
