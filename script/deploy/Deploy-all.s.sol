// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPermit2, Permit2Deployer} from '../../src/briefcase/deployers/permit2/Permit2Deployer.sol';

import {FeeOnTransferDetectorDeployer} from
    '../../src/briefcase/deployers/util-contracts/FeeOnTransferDetectorDeployer.sol';
import {UniswapV2FactoryDeployer} from '../../src/briefcase/deployers/v2-core/UniswapV2FactoryDeployer.sol';
import {UniswapV2Router02Deployer} from '../../src/briefcase/deployers/v2-periphery/UniswapV2Router02Deployer.sol';
import {
    IUniswapV3Factory,
    UniswapV3FactoryDeployer
} from '../../src/briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol';
import {NonfungiblePositionManagerDeployer} from
    '../../src/briefcase/deployers/v3-periphery/NonfungiblePositionManagerDeployer.sol';
import {NonfungibleTokenPositionDescriptorDeployer} from
    '../../src/briefcase/deployers/v3-periphery/NonfungibleTokenPositionDescriptorDeployer.sol';
import {NonfungibleTokenPositionDescriptorDeployer} from
    '../../src/briefcase/deployers/v3-periphery/NonfungibleTokenPositionDescriptorDeployer.sol';
import {QuoterV2Deployer} from '../../src/briefcase/deployers/v3-periphery/QuoterV2Deployer.sol';
import {SwapRouterDeployer} from '../../src/briefcase/deployers/v3-periphery/SwapRouterDeployer.sol';
import {TickLensDeployer} from '../../src/briefcase/deployers/v3-periphery/TickLensDeployer.sol';
import {UniswapInterfaceMulticallDeployer} from
    '../../src/briefcase/deployers/v3-periphery/UniswapInterfaceMulticallDeployer.sol';
import {V3MigratorDeployer} from '../../src/briefcase/deployers/v3-periphery/V3MigratorDeployer.sol';
import {QuoterDeployer} from '../../src/briefcase/deployers/view-quoter-v3/QuoterDeployer.sol';
import {TransparentUpgradeableProxy} from
    'src/pkgs/v4-core/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';
import {console2} from 'forge-std/console2.sol';

contract Deploy is Script {
    using stdJson for string;

    function run() public {
        string memory config =
            vm.readFile(string.concat('./script/deploy/tasks/', vm.toString(block.chainid), '/task-pending.json'));

        vm.startBroadcast();

        getPermit2(config);

        address v2Factory = deployV2Contracts(config);

        address v3Factory = deployV3Contracts(config);

        deployViewQuoterV3(config, v3Factory);

        deployUtilsContracts(config, v2Factory);

        vm.stopBroadcast();

        uint256 timestamp = vm.getBlockTimestamp();
        string memory output_filename = string.concat(
            './script/deploy/tasks/', vm.toString(block.chainid), '/task-', vm.toString(timestamp), '.json'
        );
        vm.writeFile(output_filename, config);
    }

    function deployV2Contracts(string memory config) private returns (address v2Factory) {
        bool deployV2 = config.readBool('.protocols.v2.deploy');
        if (!deployV2) {
            return address(0);
        }

        bool deployUniswapV2Factory = config.readBool('.protocols.v2.contracts.UniswapV2Factory.deploy');
        bool deployUniswapV2Router02 = config.readBool('.protocols.v2.contracts.UniswapV2Router02.deploy');

        // Params
        address feeToSetter;
        address weth;

        if (deployUniswapV2Factory) {
            feeToSetter = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.params.feeToSetter.value');
            console2.log('deploying Uniswap v2 Factory');
            v2Factory = address(UniswapV2FactoryDeployer.deploy(feeToSetter));
        }

        if (deployUniswapV2Router02) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployUniswapV2Factory) {
                v2Factory = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.address');
            }

            console2.log('deploying Uniswap v2 Router 02');
            UniswapV2Router02Deployer.deploy(v2Factory, weth);
        }
    }

    function deployV3Contracts(string memory config) private returns (address v3Factory) {
        bool deployV3 = config.readBool('.protocols.v3.deploy');
        if (!deployV3) {
            return address(0);
        }
        bool deployUniswapV3Factory = config.readBool('.protocols.v3.contracts.UniswapV3Factory.deploy');
        bool deployUniswapInterfaceMulticall =
            config.readBool('.protocols.v3.contracts.UniswapInterfaceMulticall.deploy');
        bool deployQuoterV2 = config.readBool('.protocols.v3.contracts.QuoterV2.deploy');
        bool deployTickLens = config.readBool('.protocols.v3.contracts.TickLens.deploy');
        bool deployNonfungibleTokenPositionDescriptor =
            config.readBool('.protocols.v3.contracts.NonfungibleTokenPositionDescriptor.deploy');
        bool deployNonfungiblePositonManager =
            config.readBool('.protocols.v3.contracts.NonfungiblePositonManager.deploy');
        bool deployV3Migrator = config.readBool('.protocols.v3.contracts.V3Migrator.deploy');
        bool deploySwapRouter = config.readBool('.protocols.v3.contracts.SwapRouter.deploy');

        // Params
        address nftDescriptor;
        address weth;
        address nonfungiblePositionManager;

        if (deployUniswapV3Factory) {
            address initialOwner =
                config.readAddress('.protocols.v3.contracts.UniswapV3Factory.params.initialOwner.value');
            console2.log('deploying Uniswap v3 Factory');
            IUniswapV3Factory v3Factory_ = UniswapV3FactoryDeployer.deploy();
            v3Factory_.enableFeeAmount(100, 1);
            v3Factory_.setOwner(initialOwner);
            v3Factory = address(v3Factory_);
        }

        if (deployUniswapInterfaceMulticall) {
            console2.log('deploying Uniswap Interface Multicall');
            UniswapInterfaceMulticallDeployer.deploy();
        }

        if (deployQuoterV2) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            console2.log('deploying Quoter V2');
            QuoterV2Deployer.deploy(v3Factory, weth);
        }

        if (deployTickLens) {
            console2.log('deploying Tick Lens');
            TickLensDeployer.deploy();
        }

        if (deployNonfungibleTokenPositionDescriptor) {
            weth = config.readAddress('.dependencies.weth.value');
            string memory nativeCurrencyLabel = config.readString(
                '.protocols.v3.contracts.NonfungibleTokenPositionDescriptor.params.nativeCurrencyLabel.value'
            );
            bytes32 nativeCurrencyLabelBytes;
            assembly {
                nativeCurrencyLabelBytes := mload(add(nativeCurrencyLabel, 32))
            }
            address proxyAdminOwner = config.readAddress(
                '.protocols.v3.contracts.NonfungibleTokenPositionDescriptor.params.proxyAdminOwner.value'
            );
            address nftDescriptorImplementation =
                address(NonfungibleTokenPositionDescriptorDeployer.deploy(weth, nativeCurrencyLabelBytes));
            nftDescriptor = address(new TransparentUpgradeableProxy(nftDescriptorImplementation, proxyAdminOwner, ''));
        }

        if (deployNonfungiblePositonManager) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployNonfungibleTokenPositionDescriptor) {
                nftDescriptor = config.readAddress('.protocols.v3.contracts.NonfungibleTokenPositionDescriptor.address');
            }
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            console2.log('deploying Nonfungible Position Manager');
            NonfungiblePositionManagerDeployer.deploy(v3Factory, weth, nftDescriptor);
        }

        if (deployV3Migrator) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            if (!deployNonfungiblePositonManager) {
                nonfungiblePositionManager =
                    config.readAddress('.protocols.v3.contracts.NonfungiblePositonManager.address');
            }
            console2.log('deploying V3 Migrator');
            V3MigratorDeployer.deploy(v3Factory, weth, nonfungiblePositionManager);
        }

        if (deploySwapRouter) {
            weth = config.readAddress('.dependencies.weth.value');
            if (!deployUniswapV3Factory) {
                console2.log('deploying Swap Router');
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
        console2.log('deploying Permit2');
        (bool result,) = deterministicProxy.call(abi.encodePacked(salt, Permit2Deployer.initcode()));
        require(result, 'Failed to deploy permit2');
        address computedAddress =
            computeAddress(deterministicProxy, salt, keccak256(abi.encodePacked(Permit2Deployer.initcode())));
        console2.log('Computed address:', computedAddress);
        return computedAddress;
    }

    function deployViewQuoterV3(string memory config, address v3Factory) private {
        bool deployViewQuoter = config.readBool('.protocols.view-quoter-v3.deploy');
        if (!deployViewQuoter) {
            return;
        }
        if (v3Factory == address(0)) {
            v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
        }
        console2.log('deploying View Quoter v3');
        QuoterDeployer.deploy(v3Factory);
    }

    function deployUtilsContracts(string memory config, address v2Factory) private {
        bool deployUtils = config.readBool('.protocols.util-contracts.deploy');
        if (!deployUtils) {
            return;
        }
        if (v2Factory == address(0)) {
            v2Factory = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.address');
        }
        console2.log('deploying Fee On Transfer Detector');
        FeeOnTransferDetectorDeployer.deploy(v2Factory);
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
