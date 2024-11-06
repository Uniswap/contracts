// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPermit2, Permit2Deployer} from '../../src/briefcase/deployers/permit2/Permit2Deployer.sol';
import {
    IUniswapV2Factory,
    UniswapV2FactoryDeployer
} from '../../src/briefcase/deployers/v2-core/UniswapV2FactoryDeployer.sol';
import {
    IUniswapV2Router02,
    UniswapV2Router02Deployer
} from '../../src/briefcase/deployers/v2-periphery/UniswapV2Router02Deployer.sol';
import {
    IUniswapV3Factory,
    UniswapV3FactoryDeployer
} from '../../src/briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol';

import {NFTDescriptorDeployer} from '../../src/briefcase/deployers/v3-periphery/NFTDescriptorDeployer.sol';
import {
    INonfungiblePositionManager,
    NonfungiblePositionManagerDeployer
} from '../../src/briefcase/deployers/v3-periphery/NonfungiblePositionManagerDeployer.sol';
import {ISwapRouter, SwapRouterDeployer} from '../../src/briefcase/deployers/v3-periphery/SwapRouterDeployer.sol';
import {UniswapInterfaceMulticallDeployer} from
    '../../src/briefcase/deployers/v3-periphery/UniswapInterfaceMulticallDeployer.sol';
import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        string memory config =
            vm.readFile(string.concat('./script/deploy/tasks/', vm.toString(block.chainid), '/task-pending.json'));

        bool deployV2 = config.readBool('.protocols.v2.deploy');
        bool deployV3 = config.readBool('.protocols.v3.deploy');

        vm.startBroadcast();

        address permit2 = getPermit2(config);

        if (deployV2) {
            deployV2Contracts(config);
        }

        if (deployV3) {
            deployV3Contracts(config);
        }

        vm.stopBroadcast();

        uint256 timestamp = vm.getBlockTimestamp();
        string memory output_filename = string.concat(
            './script/deploy/tasks/', vm.toString(block.chainid), '/task-', vm.toString(timestamp), '.json'
        );
        vm.writeFile(output_filename, config);
    }

    function deployV2Contracts(string memory config) private {
        bool deployUniswapV2Factory = config.readBool('.protocols.v2.contracts.UniswapV2Factory.deploy');
        bool deployUniswapV2Router02 = config.readBool('.protocols.v2.contracts.UniswapV2Router02.deploy');

        // Params
        address v2Factory;
        address feeToSetter;
        address weth;

        if (deployUniswapV2Factory) {
            feeToSetter = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.params.feeToSetter.value');
            v2Factory = address(UniswapV2FactoryDeployer.deploy(feeToSetter));
        }

        if (deployUniswapV2Router02) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployUniswapV2Factory) {
                v2Factory = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.address');
            }

            UniswapV2Router02Deployer.deploy(v2Factory, weth);
        }
    }

    function deployV3Contracts(string memory config) private {
        bool deployUniswapV3Factory = config.readBool('.protocols.v3.contracts.UniswapV3Factory.deploy');
        bool deployUniswapInterfaceMulticall =
            config.readBool('.protocols.v3.contracts.UniswapInterfaceMulticall.deploy');
        bool deployNFTDescriptor = config.readBool('.protocols.v3.contracts.NFTDescriptor.deploy');
        bool deployNonfungiblePositonManager =
            config.readBool('.protocols.v3.contracts.NonfungiblePositonManager.deploy');
        bool deploySwapRouter = config.readBool('.protocols.v3.contracts.SwapRouter.deploy');

        // Params
        address v3Factory;
        address nftDescriptor;
        address weth;
        if (deployUniswapV3Factory) {
            address initialOwner =
                config.readAddress('.protocols.v3.contracts.UniswapV3Factory.params.initialOwner.value');
            v3Factory = (new v3FactoryDeployer()).deploy(initialOwner);
        }

        if (deployUniswapInterfaceMulticall) {
            UniswapInterfaceMulticallDeployer.deploy();
        }

        if (deployNFTDescriptor) {
            nftDescriptor = NFTDescriptorDeployer.deploy();
        }

        if (deployNonfungiblePositonManager) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployNFTDescriptor) {
                nftDescriptor = config.readAddress('.protocols.v3.contracts.NFTDescriptor.address');
            }
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            NonfungiblePositionManagerDeployer.deploy(v3Factory, weth, nftDescriptor);
        }

        if (deploySwapRouter) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            SwapRouterDeployer.deploy(v3Factory, weth);
        }
    }

    function getPermit2(string memory config) private returns (address) {
        bool deployPermit2 = config.readBool('.protocols.permit2.deploy');
        if (!deployPermit2) {
            return config.readAddress('.protocols.permit2.contracts.permit2.address');
        }

        address deterministicProxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        if (deterministicProxy.code.length == 0) {
            console2.log('Deterministic deployment proxy not deployed, deploying');
            address deployerSigner = 0x3fAB184622Dc19b6109349B94811493BF2a45362;
            if (deployerSigner.balance < 0.01 ether) {
                console2.log('Deployer signer balance is less than 0.01 ether, funding...');
                // fund the deployer signer to deploy the deterministic proxy
                (bool success,) = deployerSigner.call{value: 0.01 ether - deployerSigner.balance}('');
                require(success, 'Failed to fund deployer signer');
            }
            // send the deployment transaction from the deployer signer:
            vm.broadcastRawTransaction(
                hex'f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222'
            );
        }

        bytes32 salt = config.readBytes32('.protocols.permit2.contracts.permit2.params.salt.value');
        (bool result,) = deterministicProxy.call(abi.encodePacked(salt, Permit2Deployer.initcode()));
        require(result, 'Failed to deploy permit2');
        address computedAddress =
            computeAddress(deterministicProxy, salt, keccak256(abi.encodePacked(Permit2Deployer.initcode())));
        console2.log('Computed address:', computedAddress);
        return computedAddress;
    }
}

function computeAddress(address deployer, bytes32 salt, bytes32 creationCodeHash) pure returns (address addr) {
    assembly {
        let ptr := mload(0x40)

        mstore(add(ptr, 0x40), creationCodeHash)
        mstore(add(ptr, 0x20), salt)
        mstore(ptr, deployer)
        let start := add(ptr, 0x0b)
        mstore8(start, 0xff)
        addr := keccak256(start, 85)
    }
}

contract v3FactoryDeployer {
    bool deployed;

    function deploy(address initialOwner) external returns (address) {
        require(!deployed);
        deployed = true;
        IUniswapV3Factory factory = UniswapV3FactoryDeployer.deploy();
        factory.enableFeeAmount(100, 1);
        factory.setOwner(initialOwner);
        return address(factory);
    }
}
