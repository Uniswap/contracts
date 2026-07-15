// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import {ISwapProxy} from '../../protocols/universal-router/interfaces/ISwapProxy.sol';
import {DeployerHelper} from '../DeployerHelper.sol';

library SwapProxyDeployer {
    function deploy() internal returns (ISwapProxy swapProxy) {
        bytes memory initcode_ = abi.encodePacked(initcode());
        swapProxy = ISwapProxy(DeployerHelper.create(initcode_));
    }

    /**
     * @dev FROZEN canonical initcode. Do NOT run `./script/util/create_briefcase.sh` to regenerate it.
     *
     * @notice This is the one deployer whose initcode is not regenerated from source. The canonical
     * SwapProxy address 0x0000000085E102724e78eCd2F45DC9cA239Affad is locked to the mainnet-verified
     * build from the standalone universal-router repo, which embeds an IPFS metadata hash
     * (bytecode_hash = ipfs). This monorepo builds universal-router with bytecode_hash = none, so a
     * recompile produces identical runtime but a different metadata hash, and therefore a different
     * initcode and a different address (verified: a local recompile yields initcode hash 0x5927...
     * instead of 0x342d...). Unlike Permit2 (whose canonical build used bytecode_hash = none, which is
     * reproducible), SwapProxy cannot be regenerated here, so the bytes are frozen and deployed
     * verbatim via CREATE2 through the canonical factory in Deploy-all.s.sol::deploySwapProxy.
     *
     * Reference build: src/pkgs/universal-router/contracts/SwapProxy.sol, solc 0.8.26,
     * optimizer_runs 4444, via_ir true, evm_version cancun, bytecode_hash ipfs; initcode hash
     * 0x342d83f4d7400dd603e2a6829db9cb032e7f62a2dda94746f2acd4e7e881bb2f. Legacy pre-CREATE2 instances
     * live at 0x02E5be68d46DAc0b524905BfF209cf47EE6dB2A9.
     */
    function initcode() internal pure returns (bytes memory) {
        return hex'608080604052346015576103ed908161001a8239f35b5f80fdfe6080806040526004361015610012575f80fd5b5f905f3560e01c632894adf914610027575f80fd5b346103175760c07ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126103175760043573ffffffffffffffffffffffffffffffffffffffff81168091036103175760243573ffffffffffffffffffffffffffffffffffffffff8116809103610317576064359067ffffffffffffffff821161031757366023830112156103175781600401359367ffffffffffffffff8511610317573660248685010111610317576084359267ffffffffffffffff841161031757366023850112156103175783600401359267ffffffffffffffff8411610317578360051b923660248588010111610317576064815f6020947f23b872dd000000000000000000000000000000000000000000000000000000008295523360048401528a602484015260443560448401525af13d15601f3d1160015f51141617161561031b57843b15610317579492906101b96040519687957f3593564c000000000000000000000000000000000000000000000000000000008752606060048801526024606488019201610379565b927ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc8585030160248601528084526020808501928501019360248401935f917fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffbd82360301905b848410610297578b895f818d8183818f60a435604483015203925af1801561028c57610249575080f35b905067ffffffffffffffff811161025f57604052005b7f4e487b71000000000000000000000000000000000000000000000000000000005f52604160045260245ffd5b6040513d5f823e3d90fd5b91939597509193957fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0828203018752873583811215610317578401906044602483013592019167ffffffffffffffff8111610317578036038313610317576103056020928392600195610379565b9901970194019189979695939161021f565b5f80fd5b60646040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601460248201527f5452414e534645525f46524f4d5f4641494c45440000000000000000000000006044820152fd5b601f82602094937fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe093818652868601375f858286010152011601019056fea26469706673582212208ac0c35628927f6bcae2e9d562e95e23928185675564d5ae5f0d72393ee3c27e64736f6c634300081a0033';
    }
}
