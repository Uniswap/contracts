// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    IUniswapV2Factory, IUniswapV2Router01, IUniswapV2Router02, V2Deployer
} from '../../src/deployers/V2Deployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';

struct Config {
    V2Config v2Config;
}

struct V2Config {
    V2Chain[] chains;
    bool deployFactory;
    bool deployRouter01;
    bool deployRouter02;
}

struct V2Chain {
    bool deploy;
    string id;
    string name;
    V2Parameters parameters;
}

struct V2Parameters {
    address feeToSetter;
    address v2Factory;
    address weth;
}

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        string memory configFile = vm.readFile('./script/deploy/config.json');
        bytes memory configData = vm.parseJson(configFile);
        Config memory config = abi.decode(configData, (Config));

        bool deployV2Factory = config.v2Config.deployFactory;
        bool deployRouter01 = config.v2Config.deployRouter01;
        bool deployRouter02 = config.v2Config.deployRouter02;
        bool deployV2 = deployV2Factory || deployRouter01 || deployRouter02;

        if (deployV2) {
            deployV2Contracts(config);
        }
    }

    function deployV2Contracts(Config memory config) private {
        V2Chain[] memory v2Chains = config.v2Config.chains;
        for (uint256 i = 0; i < v2Chains.length; i++) {
            V2Chain memory chain = v2Chains[i];
            if (chain.deploy) {
                address feeToSetter = chain.parameters.feeToSetter;
                address v2FactoryAddress = chain.parameters.v2Factory;
                address wethAddress = chain.parameters.weth;
                vm.createSelectFork(vm.rpcUrl(chain.name));

                uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');
                vm.startBroadcast(deployerPrivateKey);

                if (config.v2Config.deployFactory) {
                    IUniswapV2Factory v2Factory = V2Deployer.deployUniswapV2Factory(feeToSetter);
                    v2FactoryAddress = address(v2Factory);
                }
                if (config.v2Config.deployRouter01) {
                    IUniswapV2Router01 v2Router01 = V2Deployer.deployUniswapV2Router01(v2FactoryAddress, wethAddress);
                }
                if (config.v2Config.deployRouter02) {
                    IUniswapV2Router02 v2Router02 = V2Deployer.deployUniswapV2Router02(v2FactoryAddress, wethAddress);
                }
            }
        }
    }
}
