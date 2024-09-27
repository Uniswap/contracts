// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IUniswapV2Factory, UniswapV2FactoryDeployer} from '../../src/deployers/v2-core/UniswapV2FactoryDeployer.sol';
import {
    IUniswapV2Router02,
    UniswapV2Router02Deployer
} from '../../src/deployers/v2-periphery/UniswapV2Router02Deployer.sol';
import {IUniswapV3Factory, UniswapV3FactoryDeployer} from '../../src/deployers/v3-core/UniswapV3FactoryDeployer.sol';
import {
    INonfungiblePositionManager,
    NonfungiblePositionManagerDeployer
} from '../../src/deployers/v3-periphery/NonfungiblePositionManagerDeployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint('PRIVATE_KEY');

        string memory config =
            vm.readFile(string.concat('./script/deploy/tasks/', vm.toString(block.chainid), '/task_deploy_config.json'));

        bool deployV2 = config.readBool('.v2.deploy');
        bool deployV3 = config.readBool('.v3.deploy');

        vm.startBroadcast(deployerPrivateKey);
        if (deployV2) {
            deployV2Contracts(config);
        }

        if (deployV3) {
            deployV3Contracts(config);
        }
        vm.stopBroadcast();

        uint256 timestamp = vm.getBlockTimestamp();
        string memory output_filename =
            string.concat('./script/deploy/tasks/', vm.toString(block.chainid), '/', vm.toString(timestamp), '.json');
        vm.writeFile(output_filename, config);
    }

    function deployV2Contracts(string memory config) private {
        bool deployUniswapV2Factory = config.readBool('.v2.UniswapV2Factory.deploy');
        bool deployUniswapV2Router02 = config.readBool('.v2.UniswapV2Router02.deploy');

        // Params
        address v2Factory;
        address feeToSetter;
        address weth;

        if (deployUniswapV2Factory) {
            feeToSetter = config.readAddress('.v2.UniswapV2Factory.params.feeToSetter');
            v2Factory = address(UniswapV2FactoryDeployer.deploy(feeToSetter));
        }

        if (deployUniswapV2Router02) {
            weth = config.readAddress('.external_dependencies.weth');
            if (!deployUniswapV2Factory) {
                v2Factory = config.readAddress('.v2.UniswapV2Router02.params.factory');
            }

            UniswapV2Router02Deployer.deploy(v2Factory, weth);
        }
    }

    function deployV3Contracts(string memory config) private {
        bool deployUniswapV3Factory = config.readBool('.v3.UniswapV3Factory.deploy');
        bool deployNonfungiblePositonManager = config.readBool('.v3.NonfungiblePositonManager.deploy');

        // Params
        address v3Factory;
        address tokenDescriptor;
        address weth9;
        if (deployUniswapV3Factory) {
            v3Factory = address(UniswapV3FactoryDeployer.deploy());
        }

        if (deployNonfungiblePositonManager) {
            weth9 = config.readAddress('.external_dependencies.weth9');
            tokenDescriptor = config.readAddress('.v3.NonfungiblePositonManager.params.tokenDescriptor');
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.v3.NonfungiblePositonManager.params.factory');
            }
            NonfungiblePositonManagerDeployer.deploy(factory, weth9, tokenDescriptor);
        }
    }
}
