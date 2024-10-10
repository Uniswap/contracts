// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {
    IUniswapV3Factory, UniswapV3FactoryDeployer
} from '../../autogen/deployers/v3-core/UniswapV3FactoryDeployer.sol';

import {IPermit2, Permit2Deployer} from '../../autogen/deployers/permit2/Permit2Deployer.sol';
import {
    IUniswapV2Factory, UniswapV2FactoryDeployer
} from '../../autogen/deployers/v2-core/UniswapV2FactoryDeployer.sol';
import {
    IUniswapV2Router02,
    UniswapV2Router02Deployer
} from '../../autogen/deployers/v2-periphery/UniswapV2Router02Deployer.sol';
import {
    INonfungiblePositionManager,
    NonfungiblePositionManagerDeployer
} from '../../autogen/deployers/v3-periphery/NonfungiblePositionManagerDeployer.sol';

import {ISwapRouter, SwapRouterDeployer} from '../../autogen/deployers/v3-periphery/SwapRouterDeployer.sol';
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
        bool deployPermit2 = config.readBool('.permit2.deploy');

        vm.startBroadcast(deployerPrivateKey);
        if (deployV2) {
            deployV2Contracts(config);
        }

        if (deployV3) {
            deployV3Contracts(config);
        }

        if (deployPermit2) {
            deployPermit2Contracts(config);
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
        bool deploySwapRouter = config.readBool('.v3.SwapRouter.deploy');

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
            NonfungiblePositionManagerDeployer.deploy(v3Factory, weth9, tokenDescriptor);
        }

        if (deploySwapRouter) {
            weth9 = config.readAddress('.external_dependencies.weth9');
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.v3.SwapRouter.params.factory');
            }
            SwapRouterDeployer.deploy(v3Factory, weth9);
        }
    }

    function deployPermit2Contracts(string memory config) private {
        bytes32 salt = bytes32(config.readUint('.permit2.params.salt'));
        Permit2Deployer.deploy(salt);
    }
}
