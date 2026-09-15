// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2 as console} from 'forge-std/Script.sol';
import {UniswapV2FactoryDeployer} from '../../src/briefcase/deployers/v2-core/UniswapV2FactoryDeployer.sol';
import {UniswapV2Router02Deployer} from '../../src/briefcase/deployers/v2-periphery/UniswapV2Router02Deployer.sol';
import {UniswapV3FactoryDeployer} from '../../src/briefcase/deployers/v3-core/UniswapV3FactoryDeployer.sol';
import {UniswapInterfaceMulticallDeployer} from '../../src/briefcase/deployers/v3-periphery/UniswapInterfaceMulticallDeployer.sol';
import {QuoterV2Deployer} from '../../src/briefcase/deployers/v3-periphery/QuoterV2Deployer.sol';
import {TickLensDeployer} from '../../src/briefcase/deployers/v3-periphery/TickLensDeployer.sol';
import {NFTDescriptorDeployer} from '../../src/briefcase/deployers/v3-periphery/NFTDescriptorDeployer.sol';
import {NonfungiblePositionManagerDeployer} from '../../src/briefcase/deployers/v3-periphery/NonfungiblePositionManagerDeployer.sol';
import {V3MigratorDeployer} from '../../src/briefcase/deployers/v3-periphery/V3MigratorDeployer.sol';
import {SwapRouterDeployer} from '../../src/briefcase/deployers/v3-periphery/SwapRouterDeployer.sol';
import {PoolManagerDeployer} from '../../src/briefcase/deployers/v4-core/PoolManagerDeployer.sol';
import {PositionDescriptorDeployer} from '../../src/briefcase/deployers/v4-periphery/PositionDescriptorDeployer.sol';
import {PositionManagerDeployer} from '../../src/briefcase/deployers/v4-periphery/PositionManagerDeployer.sol';
import {V4QuoterDeployer} from '../../src/briefcase/deployers/v4-periphery/V4QuoterDeployer.sol';
import {StateViewDeployer} from '../../src/briefcase/deployers/v4-periphery/StateViewDeployer.sol';
import {ReservesLensDeployer} from '../../src/briefcase/deployers/v4-periphery/ReservesLensDeployer.sol';
import {PermissionsAdapterFactoryDeployer} from '../../src/briefcase/deployers/v4-periphery/PermissionsAdapterFactoryDeployer.sol';
import {QuoterDeployer} from '../../src/briefcase/deployers/view-quoter-v3/QuoterDeployer.sol';
import {MixedRouteQuoterV2Deployer} from '../../src/briefcase/deployers/mixed-quoter/MixedRouteQuoterV2Deployer.sol';
import {SwapRouter02Deployer} from '../../src/briefcase/deployers/swap-router-contracts/SwapRouter02Deployer.sol';
import {UniversalRouterDeployer} from '../../src/briefcase/deployers/universal-router/UniversalRouterDeployer.sol';
import {SwapProxyDeployer} from '../../src/briefcase/deployers/universal-router/SwapProxyDeployer.sol';
import {FeeOnTransferDetectorDeployer} from '../../src/briefcase/deployers/util-contracts/FeeOnTransferDetectorDeployer.sol';
import {FeeCollectorDeployer} from '../../src/briefcase/deployers/util-contracts/FeeCollectorDeployer.sol';

/// @notice Prints keccak256 of every briefcase initcode we deploy on HyperEVM, so it can be diffed against a
///         fresh `forge inspect <fqn> bytecode` compile (script/hyperevm/check_reproducibility.sh). Equal hashes
///         mean explorer verification with the recorded compile settings will match exactly.
contract BriefcaseHashes is Script {
    function run() public pure {
        _p('UniswapV2Factory', UniswapV2FactoryDeployer.initcode());
        _p('UniswapV2Router02', UniswapV2Router02Deployer.initcode());
        _p('UniswapV3Factory', UniswapV3FactoryDeployer.initcode());
        _p('UniswapInterfaceMulticall', UniswapInterfaceMulticallDeployer.initcode());
        _p('QuoterV2', QuoterV2Deployer.initcode());
        _p('TickLens', TickLensDeployer.initcode());
        _p('NFTDescriptor', NFTDescriptorDeployer.initcode());
        _p('NonfungiblePositionManager', NonfungiblePositionManagerDeployer.initcode());
        _p('V3Migrator', V3MigratorDeployer.initcode());
        _p('SwapRouter', SwapRouterDeployer.initcode());
        _p('PoolManager', PoolManagerDeployer.initcode());
        _p('PositionDescriptor', PositionDescriptorDeployer.initcode());
        _p('PositionManager', PositionManagerDeployer.initcode());
        _p('V4Quoter', V4QuoterDeployer.initcode());
        _p('StateView', StateViewDeployer.initcode());
        _p('ReservesLens', ReservesLensDeployer.initcode());
        _p('PermissionsAdapterFactory', PermissionsAdapterFactoryDeployer.initcode());
        _p('Quoter', QuoterDeployer.initcode());
        _p('MixedRouteQuoterV2', MixedRouteQuoterV2Deployer.initcode());
        _p('SwapRouter02', SwapRouter02Deployer.initcode());
        _p('UniversalRouter', UniversalRouterDeployer.initcode());
        _p('SwapProxy', SwapProxyDeployer.initcode());
        _p('FeeOnTransferDetector', FeeOnTransferDetectorDeployer.initcode());
        _p('FeeCollector', FeeCollectorDeployer.initcode());
    }

    function _p(string memory name, bytes memory code) private pure {
        console.log(string.concat(name, ' ', vm.toString(keccak256(code)), ' ', vm.toString(code.length)));
    }
}
