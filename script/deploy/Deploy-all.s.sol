// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IPermit2, Permit2Deployer} from '../../src/briefcase/deployers/permit2/Permit2Deployer.sol';

import {SwapRouter02Deployer} from '../../src/briefcase/deployers/swap-router-contracts/SwapRouter02Deployer.sol';

import {UniversalRouterDeployer} from '../../src/briefcase/deployers/universal-router/UniversalRouterDeployer.sol';
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
    'lib/v4-core/lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol';

import {PoolManagerDeployer} from '../../src/briefcase/deployers/v4-core/PoolManagerDeployer.sol';

import {PositionDescriptorDeployer} from '../../src/briefcase/deployers/v4-periphery/PositionDescriptorDeployer.sol';
import {PositionManagerDeployer} from '../../src/briefcase/deployers/v4-periphery/PositionManagerDeployer.sol';

import {StateViewDeployer} from '../../src/briefcase/deployers/v4-periphery/StateViewDeployer.sol';
import {V4QuoterDeployer} from '../../src/briefcase/deployers/v4-periphery/V4QuoterDeployer.sol';

import {Script, console2 as console, stdJson} from 'forge-std/Script.sol';
import {VmSafe} from 'forge-std/Vm.sol';

contract Deploy is Script {
    using stdJson for string;

    address _weth;
    string config;

    address permit2;
    address v2Factory;
    address v3Factory;
    address nonfungiblePositionManager;
    address poolManager;
    address positionManager;

    function run() public {
        config = vm.readFile(string.concat('./script/deploy/tasks/', vm.toString(block.chainid), '/task-pending.json'));

        vm.startBroadcast();

        deployPermit2();

        deployV2Contracts();

        deployV3Contracts();

        deployV4Contracts();

        deployViewQuoterV3();

        deploySwapRouters();

        deployUtilsContracts();

        deployUniversalRouter();

        vm.stopBroadcast();

        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast) && config.readBool('.rename')) {
            uint256 timestamp = vm.getBlockTimestamp();
            string memory output_filename = string.concat(
                './script/deploy/tasks/', vm.toString(block.chainid), '/task-', vm.toString(timestamp), '.json'
            );
            vm.writeFile(output_filename, config);
        }
    }

    function deployV2Contracts() private {
        if (!config.readBool('.protocols.v2.deploy')) return;

        bool deployUniswapV2Factory = config.readBool('.protocols.v2.contracts.UniswapV2Factory.deploy');
        bool deployUniswapV2Router02 = config.readBool('.protocols.v2.contracts.UniswapV2Router02.deploy');

        // Params
        address feeToSetter;

        if (deployUniswapV2Factory) {
            feeToSetter = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.params.feeToSetter.value');
            console.log('deploying Uniswap v2 Factory');
            v2Factory = address(UniswapV2FactoryDeployer.deploy(feeToSetter));
        }

        if (deployUniswapV2Router02) {
            if (!deployUniswapV2Factory) {
                v2Factory = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.address');
            }

            console.log('deploying Uniswap v2 Router 02');
            UniswapV2Router02Deployer.deploy(v2Factory, weth());
        }
    }

    function deployV3Contracts() private {
        if (!config.readBool('.protocols.v3.deploy')) return;

        bool deployUniswapV3Factory = config.readBool('.protocols.v3.contracts.UniswapV3Factory.deploy');
        bool deployUniswapInterfaceMulticall =
            config.readBool('.protocols.v3.contracts.UniswapInterfaceMulticall.deploy');
        bool deployQuoterV2 = config.readBool('.protocols.v3.contracts.QuoterV2.deploy');
        bool deployTickLens = config.readBool('.protocols.v3.contracts.TickLens.deploy');
        bool deployNonfungibleTokenPositionDescriptor =
            config.readBool('.protocols.v3.contracts.NonfungibleTokenPositionDescriptor.deploy');
        bool deployNonfungiblePositionManager =
            config.readBool('.protocols.v3.contracts.NonfungiblePositionManager.deploy');
        bool deployV3Migrator = config.readBool('.protocols.v3.contracts.V3Migrator.deploy');
        bool deploySwapRouter = config.readBool('.protocols.v3.contracts.SwapRouter.deploy');

        // Params
        address nftDescriptor;

        if (deployUniswapV3Factory) {
            address initialOwner =
                config.readAddress('.protocols.v3.contracts.UniswapV3Factory.params.initialOwner.value');
            console.log('deploying Uniswap v3 Factory');
            IUniswapV3Factory v3Factory_ = UniswapV3FactoryDeployer.deploy();
            v3Factory_.enableFeeAmount(100, 1);
            v3Factory_.setOwner(initialOwner);
            v3Factory = address(v3Factory_);
        }

        if (deployUniswapInterfaceMulticall) {
            console.log('deploying Uniswap Interface Multicall');
            UniswapInterfaceMulticallDeployer.deploy();
        }

        if (deployQuoterV2) {
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            console.log('deploying Quoter V2');
            QuoterV2Deployer.deploy(v3Factory, weth());
        }

        if (deployTickLens) {
            console.log('deploying Tick Lens');
            TickLensDeployer.deploy();
        }

        if (deployNonfungibleTokenPositionDescriptor) {
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
                address(NonfungibleTokenPositionDescriptorDeployer.deploy(weth(), nativeCurrencyLabelBytes));
            nftDescriptor = address(new TransparentUpgradeableProxy(nftDescriptorImplementation, proxyAdminOwner, ''));
        }

        if (deployNonfungiblePositionManager) {
            if (!deployNonfungibleTokenPositionDescriptor) {
                nftDescriptor = config.readAddress('.protocols.v3.contracts.NonfungibleTokenPositionDescriptor.address');
            }
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            console.log('deploying Nonfungible Position Manager');
            nonfungiblePositionManager =
                address(NonfungiblePositionManagerDeployer.deploy(v3Factory, weth(), nftDescriptor));
        }

        if (deployV3Migrator) {
            if (!deployUniswapV3Factory) {
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            if (!deployNonfungiblePositionManager) {
                nonfungiblePositionManager =
                    config.readAddress('.protocols.v3.contracts.NonfungiblePositionManager.address');
            }
            console.log('deploying V3 Migrator');
            V3MigratorDeployer.deploy(v3Factory, weth(), nonfungiblePositionManager);
        }

        if (deploySwapRouter) {
            if (!deployUniswapV3Factory) {
                console.log('deploying Swap Router');
                v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
            }
            SwapRouterDeployer.deploy(v3Factory, weth());
        }
    }

    function deployV4Contracts() private {
        if (!config.readBool('.protocols.v4.deploy')) return;

        bool deployPoolManager = config.readBool('.protocols.v4.contracts.PoolManager.deploy');
        bool deployPositionDescriptor = config.readBool('.protocols.v4.contracts.PositionDescriptor.deploy');
        bool deployPositionManager = config.readBool('.protocols.v4.contracts.PositionManager.deploy');
        bool deployV4Quoter = config.readBool('.protocols.v4.contracts.V4Quoter.deploy');
        bool deployStateView = config.readBool('.protocols.v4.contracts.StateView.deploy');

        address positionDescriptor;

        if (deployPoolManager) {
            address initialOwner = config.readAddress('.protocols.v4.contracts.PoolManager.params.initialOwner.value');
            console.log('deploying Pool Manager');
            poolManager = address(PoolManagerDeployer.deploy(initialOwner));
        }

        if (deployPositionDescriptor) {
            string memory nativeCurrencyLabel =
                config.readString('.protocols.v4.contracts.PositionDescriptor.params.nativeCurrencyLabel.value');
            bytes32 nativeCurrencyLabelBytes;
            assembly {
                nativeCurrencyLabelBytes := mload(add(nativeCurrencyLabel, 32))
            }
            address proxyAdminOwner =
                config.readAddress('.protocols.v4.contracts.PositionDescriptor.params.proxyAdminOwner.value');
            if (!deployPoolManager) {
                poolManager = config.readAddress('.protocols.v4.contracts.PoolManager.address');
            }
            address positionDescriptorImplementation =
                address(PositionDescriptorDeployer.deploy(poolManager, weth(), nativeCurrencyLabelBytes));
            positionDescriptor =
                address(new TransparentUpgradeableProxy(positionDescriptorImplementation, proxyAdminOwner, ''));
        }

        if (deployPositionManager) {
            if (!deployPoolManager) {
                poolManager = config.readAddress('.protocols.v4.contracts.PoolManager.address');
            }
            if (permit2 == address(0)) {
                permit2 = config.readAddress('.protocols.permit2.contracts.Permit2.address');
            }
            uint256 unsubscribeGasLimit =
                config.readUint('.protocols.v4.contracts.PositionManager.params.unsubscribeGasLimit.value');
            if (!deployPositionDescriptor) {
                positionDescriptor = config.readAddress('.protocols.v4.contracts.PositionDescriptor.address');
            }
            console.log('deploying Position Manager');
            positionManager = address(
                PositionManagerDeployer.deploy(poolManager, permit2, unsubscribeGasLimit, positionDescriptor, weth())
            );
        }

        if (deployV4Quoter) {
            if (!deployPoolManager) {
                poolManager = config.readAddress('.protocols.v4.contracts.PoolManager.address');
            }
            console.log('deploying V4 Quoter');
            V4QuoterDeployer.deploy(poolManager);
        }

        if (deployStateView) {
            if (!deployPoolManager) {
                poolManager = config.readAddress('.protocols.v4.contracts.PoolManager.address');
            }
            console.log('deploying State View');
            StateViewDeployer.deploy(poolManager);
        }
    }

    function deployPermit2() private {
        // TODO: handle permit2 more like WETH, get code at default address and check whether it's already deployed, if not, deploy it
        if (!config.readBool('.protocols.permit2.deploy')) return;

        address deterministicProxy = 0x4e59b44847b379578588920cA78FbF26c0B4956C;
        if (deterministicProxy.code.length == 0) {
            console.log('Deterministic deployment proxy not deployed, deploying');
            address deployerSigner = 0x3fAB184622Dc19b6109349B94811493BF2a45362;
            if (deployerSigner.balance < 0.01 ether) {
                console.log('Deployer signer balance is less than 0.01 ether, funding...');
                // fund the deployer signer to deploy the deterministic proxy
                (bool success,) = deployerSigner.call{value: 0.01 ether - deployerSigner.balance}('');
                require(success, 'Failed to fund deployer signer');
            }
            // send the deployment transaction from the deployer signer:
            vm.broadcastRawTransaction(
                hex'f8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222'
            );
        }

        bytes32 salt = config.readBytes32('.protocols.permit2.contracts.Permit2.params.salt.value');
        console.log('deploying Permit2');
        (bool result,) = deterministicProxy.call(abi.encodePacked(salt, Permit2Deployer.initcode()));
        require(result, 'Failed to deploy permit2');
        address computedAddress =
            computeAddress(deterministicProxy, salt, keccak256(abi.encodePacked(Permit2Deployer.initcode())));
        console.log('Computed permit2 address:', computedAddress);
        permit2 = computedAddress;
    }

    function deployViewQuoterV3() private {
        if (!config.readBool('.protocols.view-quoter-v3.deploy')) return;

        if (v3Factory == address(0)) {
            v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
        }
        console.log('deploying View Quoter v3');
        QuoterDeployer.deploy(v3Factory);
    }

    function deploySwapRouters() private {
        if (!config.readBool('.protocols.swap-router-contracts.deploy')) return;

        if (v2Factory == address(0)) {
            v2Factory = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.address');
        }
        if (v3Factory == address(0)) {
            v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
        }
        if (nonfungiblePositionManager == address(0)) {
            nonfungiblePositionManager =
                config.readAddress('.protocols.v3.contracts.NonfungiblePositionManager.address');
        }
        console.log('deploying Swap Router 02');
        SwapRouter02Deployer.deploy(v2Factory, v3Factory, nonfungiblePositionManager, weth());
    }

    function deployUtilsContracts() private {
        if (!config.readBool('.protocols.util-contracts.deploy')) return;

        if (v2Factory == address(0)) {
            v2Factory = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.address');
        }
        console.log('deploying Fee On Transfer Detector');
        FeeOnTransferDetectorDeployer.deploy(v2Factory);
    }

    function deployUniversalRouter() private {
        if (!config.readBool('.protocols.universal-router.deploy')) return;

        if (permit2 == address(0)) {
            permit2 = config.readAddress('.protocols.permit2.contracts.Permit2.address');
        }
        if (v2Factory == address(0)) {
            v2Factory = config.readAddress('.protocols.v2.contracts.UniswapV2Factory.address');
        }
        if (v3Factory == address(0)) {
            v3Factory = config.readAddress('.protocols.v3.contracts.UniswapV3Factory.address');
        }
        bytes32 v2PairInitCodeHash =
            config.readBytes32('.protocols.universal-router.contracts.UniversalRouter.params.v2PairInitCodeHash.value');
        bytes32 v3PoolInitCodeHash =
            config.readBytes32('.protocols.universal-router.contracts.UniversalRouter.params.v3PoolInitCodeHash.value');
        if (poolManager == address(0)) {
            poolManager = config.readAddress('.protocols.v4.contracts.PoolManager.address');
        }
        if (nonfungiblePositionManager == address(0)) {
            nonfungiblePositionManager =
                config.readAddress('.protocols.v3.contracts.NonfungiblePositionManager.address');
        }
        if (positionManager == address(0)) {
            positionManager = config.readAddress('.protocols.v4.contracts.PositionManager.address');
        }
        console.log('deploying Universal Router');
        UniversalRouterDeployer.deploy(
            permit2,
            weth(),
            v2Factory,
            v3Factory,
            v2PairInitCodeHash,
            v3PoolInitCodeHash,
            poolManager,
            nonfungiblePositionManager,
            positionManager
        );
    }

    function weth() internal returns (address) {
        if (_weth == address(0)) {
            _weth = config.readAddress('.dependencies.weth.value');
        }
        return _weth;
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
