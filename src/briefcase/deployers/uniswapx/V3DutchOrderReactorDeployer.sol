// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import {IReactor} from '../../protocols/uniswapx/interfaces/IReactor.sol';

library V3DutchOrderReactorDeployer {
    function deploy(address permit2, address owner) internal returns (IReactor reactor) {
        bytes memory initcode_ = abi.encodePacked(initcode(), abi.encode(permit2, owner));
        assembly {
            reactor := create2(0, add(initcode_, 32), mload(initcode_), hex'00')
        }
    }

    /**
     * @dev autogenerated - run `./script/util/create_briefcase.sh` to generate current initcode
     *
     * @notice This initcode is generated from the following contract:
     * - Source Contract: src/pkgs/uniswapx/src/reactors/V3DutchOrderReactor.sol
     */
    function initcode() internal pure returns (bytes memory) {
        return
        hex'60c0346100e457601f613aa338819003918201601f19168301916001600160401b038311848410176100e85780849260409485528339810103126100e4578051906001600160a01b03821682036100e457602001516001600160a01b038116908190036100e4575f80546001600160a01b031916821781557f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e08180a360016002556080524661a4b1036100da57600160a0525b6040516139a690816100fd823960805181818161034f0152612927015260a0518161136a0152f35b600260a0526100b2565b5f80fd5b634e487b7160e01b5f52604160045260245ffdfe6080604052600436101561001a575b3615610018575f80fd5b005b5f3560e01c80630d335884146100a95780630d7a16c3146100a457806312261ee71461009f57806313fb72c71461009a5780632d771389146100955780633f62192e146100905780636999b3771461008b5780638da5cb5b146100865763f2fde38b0361000e576106d7565b610687565b610636565b6105b3565b6104ce565b610373565b610305565b61024a565b60407ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d45760043567ffffffffffffffff81116101d4576100f39036906004016101dd565b60243567ffffffffffffffff81116101d4576101139036906004016101eb565b919061011d610d7e565b61012e610128610952565b9261131d565b8251156101d857602083015261014382610a49565b5061014d82611427565b333b156101d45761018f925f9160405194859283927f585da6280000000000000000000000000000000000000000000000000000000084528660048501610c16565b038183335af19182156101cf576101ab926101b5575b50611583565b6100186001600255565b806101c35f6101c993610845565b806102fb565b826101a5565b610886565b5f80fd5b610a1c565b908160409103126101d45790565b9181601f840112156101d45782359167ffffffffffffffff83116101d457602083818601950101116101d457565b9181601f840112156101d45782359167ffffffffffffffff83116101d4576020808501948460051b0101116101d457565b60207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d45760043567ffffffffffffffff81116101d457610294903690600401610219565b9061029d610d7e565b6102a6826109b0565b915f5b8181106102c9576102c2846102bd81611427565b611583565b6001600255005b806102df6102da6001938587610cd9565b61131d565b6102e98287610a56565b526102f48186610a56565b50016102a9565b5f9103126101d457565b346101d4575f7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d457602060405173ffffffffffffffffffffffffffffffffffffffff7f0000000000000000000000000000000000000000000000000000000000000000168152f35b60407ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d45760043567ffffffffffffffff81116101d4576103bd903690600401610219565b60243567ffffffffffffffff81116101d4576103dd9036906004016101eb565b926103e6610d7e565b6103ef836109b0565b925f5b8181106104765750505061040582611427565b333b156101d457610447925f9160405194859283927f585da6280000000000000000000000000000000000000000000000000000000084528660048501610c16565b038183335af19182156101cf576101ab926104625750611583565b806101c35f61047093610845565b5f6101a5565b806104876102da6001938587610cd9565b6104918288610a56565b5261049c8187610a56565b50016103f2565b73ffffffffffffffffffffffffffffffffffffffff8116036101d457565b35906104cc826104a3565b565b346101d45760207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d4577fb904ae9529e373e48bc82df4326cceaf1b4c472babf37f5b7dec46fecc6b53e0604060043561052c816104a3565b61054e73ffffffffffffffffffffffffffffffffffffffff5f54163314610d19565b73ffffffffffffffffffffffffffffffffffffffff6001549116807fffffffffffffffffffffffff000000000000000000000000000000000000000083161760015573ffffffffffffffffffffffffffffffffffffffff8351921682526020820152a1005b60207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d45760043567ffffffffffffffff81116101d4576105fd9036906004016101dd565b610605610d7e565b610616610610610952565b9161131d565b8151156101d85760208201528051156101d857806102bd6102c292611427565b346101d4575f7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d457602073ffffffffffffffffffffffffffffffffffffffff60015416604051908152f35b346101d4575f7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d457602073ffffffffffffffffffffffffffffffffffffffff5f5416604051908152f35b346101d45760207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101d4577fffffffffffffffffffffffff0000000000000000000000000000000000000000600435610733816104a3565b73ffffffffffffffffffffffffffffffffffffffff5f54916107588284163314610d19565b1691829116175f55337f8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e05f80a3005b7f4e487b71000000000000000000000000000000000000000000000000000000005f52604160045260245ffd5b6060810190811067ffffffffffffffff8211176107d057604052565b610787565b60a0810190811067ffffffffffffffff8211176107d057604052565b60c0810190811067ffffffffffffffff8211176107d057604052565b6040810190811067ffffffffffffffff8211176107d057604052565b60e0810190811067ffffffffffffffff8211176107d057604052565b90601f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0910116810190811067ffffffffffffffff8211176107d057604052565b6040513d5f823e3d90fd5b604051906104cc60e083610845565b604051906104cc60a083610845565b604051906104cc606083610845565b67ffffffffffffffff81116107d05760051b60200190565b604051906108e3826107b4565b5f6040838281528260208201520152565b60405190610901826107d5565b5f608083604051610911816107f1565b8381528360208201528360408201528360608201528383820152606060a0820152815261093c6108d6565b6020820152606060408201526060808201520152565b604080519091906109638382610845565b60018152917fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe001825f5b82811061099957505050565b6020906109a46108f4565b8282850101520161098d565b906109ba826108be565b6109c76040519182610845565b8281527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe06109f582946108be565b01905f5b828110610a0557505050565b602090610a106108f4565b828285010152016109f9565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52603260045260245ffd5b8051156101d85760200190565b80518210156101d85760209160051b010190565b907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0601f602080948051918291828752018686015e5f8582860101520116010190565b90602080835192838152019201905f5b818110610aca5750505090565b9091926020606060019273ffffffffffffffffffffffffffffffffffffffff60408851828151168452858101518685015201511660408201520194019101919091610abd565b9060c06080610c0d610bfb610bae60a0875160e0885273ffffffffffffffffffffffffffffffffffffffff81511660e089015273ffffffffffffffffffffffffffffffffffffffff6020820151166101008901526040810151610120890152606081015161014089015273ffffffffffffffffffffffffffffffffffffffff86820151166101608901520151856101808801526101a0870190610a6a565b610bea602088015160208801906040809173ffffffffffffffffffffffffffffffffffffffff8151168452602081015160208501520151910152565b604087015186820385880152610aad565b606086015185820360a0870152610a6a565b93015191015290565b939293919091604081016040825283518091526060820190602060608260051b8501019501915f905b828210610c90575050505084602094957fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0938387601f958803910152818652868601375f8582860101520116010190565b90919295602080610ccb837fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffa089600196030186528a51610b10565b980192019201909291610c3f565b91908110156101d85760051b810135907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc1813603018212156101d4570190565b15610d2057565b60646040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152600c60248201527f554e415554484f52495a454400000000000000000000000000000000000000006044820152fd5b6002805414610d8d5760028055565b60646040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601f60248201527f5265656e7472616e637947756172643a207265656e7472616e742063616c6c006044820152fd5b9035907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe1813603018212156101d4570180359067ffffffffffffffff82116101d4576020019181360383136101d457565b67ffffffffffffffff81116107d057601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe01660200190565b929192610e8282610e3c565b91610e906040519384610845565b8294818452818301116101d4578281602093845f960137010152565b9080601f830112156101d457816020610ec793359101610e76565b90565b919060c0838203126101d45760405190610ee3826107f1565b81938035610ef0816104a3565b8352610efe602082016104c1565b60208401526040810135604084015260608101356060840152610f23608082016104c1565b608084015260a08101359167ffffffffffffffff83116101d45760a092610f4a9201610eac565b910152565b91906040838203126101d457604051610f678161080d565b80938035825260208101359067ffffffffffffffff82116101d457019180601f840112156101d4578235610f9a816108be565b93610fa86040519586610845565b81855260208086019260051b8201019283116101d457602001905b828210610fd35750505060200152565b8135815260209182019101610fc3565b91909160a0818403126101d45760405190610ffd826107d5565b8193813561100a816104a3565b83526020820135602084015260408201359167ffffffffffffffff83116101d45761103b6080939284938301610f4f565b6040850152606081013560608501520135910152565b81601f820112156101d457803590611068826108be565b926110766040519485610845565b82845260208085019360051b830101918183116101d45760208101935b8385106110a257505050505090565b843567ffffffffffffffff81116101d457820160c07fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe082860301126101d457604051916110ee836107f1565b60208201356110fc816104a3565b83526040820135602084015260608201359267ffffffffffffffff84116101d45760c083611131886020809881980101610f4f565b6040840152611142608082016104c1565b606084015260a08101356080840152013560a0820152815201940193611093565b919060a0838203126101d45760405161117b816107d5565b809380358252602081013561118f816104a3565b6020830152604081013560408301526060810135606083015260808101359067ffffffffffffffff82116101d457019180601f840112156101d45782356111d5816108be565b936111e36040519586610845565b81855260208086019260051b8201019283116101d457602001905b82821061120e5750505060800152565b81358152602091820191016111fe565b6020818303126101d45780359067ffffffffffffffff82116101d4570160e0818303126101d45761124d610891565b91813567ffffffffffffffff81116101d4578161126b918401610eca565b8352611279602083016104c1565b602084015260408201356040840152606082013567ffffffffffffffff81116101d457816112a8918401610fe3565b6060840152608082013567ffffffffffffffff81116101d457816112cd918401611051565b608084015260a082013567ffffffffffffffff81116101d457816112f2918401611163565b60a084015260c082013567ffffffffffffffff81116101d4576113159201610eac565b60c082015290565b906113266108f4565b506104cc61133f6113378480610deb565b81019061121e565b61134881611b93565b906113538183611c8d565b61135c81611dc8565b61136581611eb7565b61138e7f00000000000000000000000000000000000000000000000000000000000000006138ed565b916113ec8251926060810151976113cd6113c28760806113b68260a088019e8f515190611f6b565b9501518c515190612081565b916020810190610deb565b9190926113d86108a0565b968752602087015260408601523691610e76565b6060830152608082015280945161141a602082015173ffffffffffffffffffffffffffffffffffffffff1690565b604082519201519261336b565b8051905f5b82811061143857505050565b6114428183610a56565b519061144d826122e4565b61148c611473611473845173ffffffffffffffffffffffffffffffffffffffff90511690565b73ffffffffffffffffffffffffffffffffffffffff1690565b300361155b576114b761147360808451015173ffffffffffffffffffffffffffffffffffffffff1690565b73ffffffffffffffffffffffffffffffffffffffff81166114e7575b506114e16001923390612910565b0161142c565b91823b156101d4575f60405180947f6e84ba2b0000000000000000000000000000000000000000000000000000000082528180611528863360048401612758565b03915afa9081156101cf576001936114e192611547575b5092506114d3565b806101c35f61155593610845565b5f61153f565b7f4ddf4a64000000000000000000000000000000000000000000000000000000005f5260045ffd5b8051905f5b8281106115a3575050504761159957565b6104cc4733612b74565b6115ad8183610a56565b5160408101805151905f5b828110611655575050509060019160806115d28386610a56565b51015190519060406115fb602084015173ffffffffffffffffffffffffffffffffffffffff1690565b920151907f78ad7ec0e9f89e74012afa58738b6b661c024cb0fd185ee2f616c0a28924bd6673ffffffffffffffffffffffffffffffffffffffff6040519416938061164c3395829190602083019252565b0390a401611588565b806116ac6116666001938551610a56565b51805173ffffffffffffffffffffffffffffffffffffffff169060206116a3604083015173ffffffffffffffffffffffffffffffffffffffff1690565b91015191612a81565b016115b8565b6040517f563344757463684f72646572280000000000000000000000000000000000000060208201527f4f72646572496e666f20696e666f2c0000000000000000000000000000000000602d8201527f6164647265737320636f7369676e65722c000000000000000000000000000000603c8201527f75696e74323536207374617274696e67426173654665652c0000000000000000604d8201527f56334475746368496e7075742062617365496e7075742c00000000000000000060658201527f563344757463684f75747075745b5d20626173654f7574707574732900000000607c82015260788152610ec7609882610845565b6040517f4e6f6e6c696e656172447574636844656361792800000000000000000000000060208201527f75696e743235362072656c6174697665426c6f636b732c00000000000000000060348201527f696e743235365b5d2072656c6174697665416d6f756e74732900000000000000604b82015260448152610ec7606482610845565b6040519061183b60c083610845565b608d82527f6c69646174696f6e44617461290000000000000000000000000000000000000060a0837f4f72646572496e666f28616464726573732072656163746f722c61646472657360208201527f7320737761707065722c75696e74323536206e6f6e63652c75696e743235362060408201527f646561646c696e652c61646472657373206164646974696f6e616c56616c696460608201527f6174696f6e436f6e74726163742c6279746573206164646974696f6e616c566160808201520152565b6040517f56334475746368496e707574280000000000000000000000000000000000000060208201527f6164647265737320746f6b656e2c000000000000000000000000000000000000602d8201527f75696e74323536207374617274416d6f756e742c000000000000000000000000603b8201527f4e6f6e6c696e656172447574636844656361792063757276652c000000000000604f8201527f75696e74323536206d6178416d6f756e742c000000000000000000000000000060698201527f75696e743235362061646a7573746d656e745065724777656942617365466565607b8201527f2900000000000000000000000000000000000000000000000000000000000000609b820152610ec781609c81015b037fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe08101835282610845565b6040517f563344757463684f75747075742800000000000000000000000000000000000060208201527f6164647265737320746f6b656e2c000000000000000000000000000000000000602e8201527f75696e74323536207374617274416d6f756e742c000000000000000000000000603c8201527f4e6f6e6c696e656172447574636844656361792063757276652c00000000000060508201527f6164647265737320726563697069656e742c0000000000000000000000000000606a8201527f75696e74323536206d696e416d6f756e742c0000000000000000000000000000607c8201527f75696e743235362061646a7573746d656e745065724777656942617365466565608e8201527f290000000000000000000000000000000000000000000000000000000000000060ae820152610ec78160af8101611a15565b805191908290602001825e015f815290565b611b9b6116b2565b611bdf611be5611ba96117a8565b611a15611bb461182c565b611bdf611bbf6118ff565b611bdf611bca611a41565b93604051988997611bdf60208a01809d611b81565b90611b81565b51902090611c87611bf68251612bd8565b611a15611c1a602085015173ffffffffffffffffffffffffffffffffffffffff1690565b93604081015190611c3b6080611c336060840151612c89565b920151612d21565b9160405196879560208701998a9273ffffffffffffffffffffffffffffffffffffffff9060a095929897969360c086019986526020860152166040840152606083015260808201520152565b51902090565b91906060815101514211611da05773ffffffffffffffffffffffffffffffffffffffff6020820151169060a081015193604051602080820152608060e08201968051604084015273ffffffffffffffffffffffffffffffffffffffff6020820151166060840152604081015182840152606081015160a084015201519560a060c08301528651809152602061010083019701905f5b818110611d8a5750505090611a15611d7e83611d6b60c0956104cc999a037fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe08101835282610845565b6040519283916020830195469087612e73565b51902091015191612e89565b8251895260209889019890920191600101611d22565b7fb08ce5b3000000000000000000000000000000000000000000000000000000005f5260045ffd5b60a081019060608251015180611e6d575b50608080835101515191019081515103611e4557805151905f5b828110611e005750505050565b611e0b818351610a56565b5190611e1c81608087510151610a56565b519182611e2f575b506001915001611df3565b6020019182518110611e4557600192525f611e24565b7fa305df82000000000000000000000000000000000000000000000000000000005f5260045ffd5b606082019060208251015110611e8f576020606084510151915101525f611dd9565b7fac9143e7000000000000000000000000000000000000000000000000000000005f5260045ffd5b6080611ec7604083015148612fbe565b916060810182815101518481611f3e575b5050500190815151915f5b838110611ef05750505050565b80611efe6001928451610a56565b518460a082015180611f14575b50505001611ee3565b611f3491611f2191613031565b91602081019260808451920151916130ec565b90525f8481611f0b565b611f4d611f5f91602093613031565b835190606084830151920151916130ca565b915101525f8084611ed8565b9091611fd873ffffffffffffffffffffffffffffffffffffffff91611f8e6108d6565b50604084015190602085015190606086019687519260405194611fb086610829565b85526020850152604084015260608301525f608083015260a0820152600360c0820152613293565b91511691519061200860405193611fee856107b4565b73ffffffffffffffffffffffffffffffffffffffff168452565b6020830152604082015290565b9061201f826108be565b61202c6040519182610845565b8281527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe061205a82946108be565b01905f5b82811061206a57505050565b6020906120756108d6565b8282850101520161205e565b92919083519161209083612015565b945f5b8481106120a1575050505050565b806120ae60019284610a56565b516120b76108d6565b506121ae61212560408301516020840151608085015190604051926120db84610829565b8352602083015289604083015288606083015260808201527fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff60a0820152600460c0820152613293565b6121646060612148855173ffffffffffffffffffffffffffffffffffffffff1690565b94015173ffffffffffffffffffffffffffffffffffffffff1690565b9061218c6121706108af565b73ffffffffffffffffffffffffffffffffffffffff9095168552565b602084015273ffffffffffffffffffffffffffffffffffffffff166040830152565b6121b8828a610a56565b526121c38189610a56565b5001612093565b6020818303126101d45780519067ffffffffffffffff82116101d4570181601f820112156101d4578051906121fe826108be565b9261220c6040519485610845565b828452602060608186019402830101918183116101d457602001925b828410612236575050505090565b6060848303126101d4576020606091604051612251816107b4565b865161225c816104a3565b815282870151838201526040870151612274816104a3565b6040820152815201930192612228565b906020610ec7928181520190610b10565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52601160045260245ffd5b612710019081612710116122d257565b612295565b919082018092116122d257565b61230661147360015473ffffffffffffffffffffffffffffffffffffffff1690565b73ffffffffffffffffffffffffffffffffffffffff811615612754575f60405180927f8aa6cf03000000000000000000000000000000000000000000000000000000008252818061235a8760048301612284565b03915afa9081156101cf575f91612732575b5060408201908151519080519161238b61238684836122d7565b612015565b945f5b82811061270757505f905f905f5b8681106123ad575050505050505052565b6123b78187610a56565b515f5b82811061263e57505f805b8781106125b3575060208401866123f5611473835173ffffffffffffffffffffffffffffffffffffffff90511690565b73ffffffffffffffffffffffffffffffffffffffff61242b611473875173ffffffffffffffffffffffffffffffffffffffff1690565b911614612569575b5050801561250757612449602083015191613429565b811161247357509061246c8a600193612465848a018093610a56565b528b610a56565b500161239c565b61250492506124b7604061249b845173ffffffffffffffffffffffffffffffffffffffff1690565b93015173ffffffffffffffffffffffffffffffffffffffff1690565b917f82e75656000000000000000000000000000000000000000000000000000000005f52929173ffffffffffffffffffffffffffffffffffffffff91826064951660045260245216604452565b5ffd5b612504612528835173ffffffffffffffffffffffffffffffffffffffff1690565b7feddf07f5000000000000000000000000000000000000000000000000000000005f5273ffffffffffffffffffffffffffffffffffffffff16600452602490565b9092955061258b57602061258092510151906122d7565b926001935f86612433565b7fedc7e2e4000000000000000000000000000000000000000000000000000000005f5260045ffd5b6125be818c51610a56565b51805173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff61260d611473875173ffffffffffffffffffffffffffffffffffffffff1690565b91161461261e575b506001016123c5565b919096508561258b576020612635920151906122d7565b60019586612615565b815173ffffffffffffffffffffffffffffffffffffffff1673ffffffffffffffffffffffffffffffffffffffff61269661147361267b858d610a56565b515173ffffffffffffffffffffffffffffffffffffffff1690565b9116146126a5576001016123ba565b6125046126c6835173ffffffffffffffffffffffffffffffffffffffff1690565b7ffff08303000000000000000000000000000000000000000000000000000000005f5273ffffffffffffffffffffffffffffffffffffffff16600452602490565b806127156001928851610a56565b51612720828a610a56565b5261272b8189610a56565b500161238e565b61274e91503d805f833e6127468183610845565b8101906121ca565b5f61236c565b5050565b60409073ffffffffffffffffffffffffffffffffffffffff610ec794931681528160208201520190610b10565b7f563344757463684f72646572207769746e657373290000000000000000000000610ec76020611a156127b66117a8565b611bdf6127c161182c565b611bdf6040516127d2606082610845565b602e81527f546f6b656e5065726d697373696f6e73286164647265737320746f6b656e2c75878201527f696e7432353620616d6f756e74290000000000000000000000000000000000006040820152611bdf61282c6118ff565b91611bdf6128386116b2565b95611bdf612844611a41565b996040519e8f9d8e015260358d0190611b81565b9491612901936128e273ffffffffffffffffffffffffffffffffffffffff926040610ec79a98956128aa8b82516020809173ffffffffffffffffffffffffffffffffffffffff81511684520151910152565b6020818101518c84015291015160608b0152815173ffffffffffffffffffffffffffffffffffffffff1660808b0152015160a0890152565b1660c086015260e0850152610140610100850152610140840190610a6a565b91610120818403910152610a6a565b73ffffffffffffffffffffffffffffffffffffffff7f0000000000000000000000000000000000000000000000000000000000000000165f60408051612955816107b4565b61295d613498565b815282602082015201526129e5602083015193604073ffffffffffffffffffffffffffffffffffffffff86511695015173ffffffffffffffffffffffffffffffffffffffff604051966129af8861080d565b168652602086015283516060604082015191015190604051966129d3606089610845565b875260208701526040860152836134b0565b90612a0860208451015173ffffffffffffffffffffffffffffffffffffffff1690565b916080840151946060612a19612785565b95015190833b156101d457612a625f96928793604051998a98899788967f137c29fe00000000000000000000000000000000000000000000000000000000885260048801612858565b03925af180156101cf57612a735750565b806101c35f6104cc93610845565b90919073ffffffffffffffffffffffffffffffffffffffff1680612aa957506104cc91612b74565b6020925f606492819473ffffffffffffffffffffffffffffffffffffffff604051947f23b872dd00000000000000000000000000000000000000000000000000000000865233600487015216602485015260448401525af13d15601f3d1160015f511416171615612b1657565b60646040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152601460248201527f5452414e534645525f46524f4d5f4641494c45440000000000000000000000006044820152fd5b5f80809381935af13d15612bd3573d612b8c81610e3c565b90612b9a6040519283610845565b81525f60203d92013e5b15612bab57565b7ff4b3b1bc000000000000000000000000000000000000000000000000000000005f5260045ffd5b612ba4565b612be061182c565b602081519101209073ffffffffffffffffffffffffffffffffffffffff8151169073ffffffffffffffffffffffffffffffffffffffff60208201511690604081015160608201519060a073ffffffffffffffffffffffffffffffffffffffff6080850151169301516020815191012093604051956020870197885260408701526060860152608085015260a084015260c083015260e082015260e08152611c8761010082610845565b612c916118ff565b611a15612cb3612c9f6117a8565b604051928391611bdf602084018097611b81565b5190209073ffffffffffffffffffffffffffffffffffffffff81511690602081015190612ce360408201516134ee565b6080606083015192015192604051946020860196875260408601526060850152608084015260a083015260c082015260c08152611c8760e082610845565b805160051b612d48612d3282610e3c565b91612d406040519384610845565b808352610e3c565b917fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe06020830193013684378051905f5b828110612d885750505051902090565b80612d9560019284610a56565b51612d9e611a41565b611a15612dac612c9f6117a8565b51902090612e6073ffffffffffffffffffffffffffffffffffffffff825116611a15602084015193612de160408201516134ee565b90612e03606082015173ffffffffffffffffffffffffffffffffffffffff1690565b60a0608083015192015192604051978896602088019a8b9360c095919897969373ffffffffffffffffffffffffffffffffffffffff809460e088019b88521660208701526040860152606085015216608083015260a08201520152565b51902060208260051b8701015201612d78565b610ec79392604092825260208201520190611b81565b91906040828051810103126101d45760208201516040830151918351604010156101d857612f125f93612eeb612ee56060602098017fff0000000000000000000000000000000000000000000000000000000000000090511690565b60f81c90565b93604051948594859094939260ff6060936080840197845216602083015260408201520152565b838052039060015afa156101cf5773ffffffffffffffffffffffffffffffffffffffff90612f545f5173ffffffffffffffffffffffffffffffffffffffff1690565b9116811480159190612f90575b50612f6857565b7fd7815be1000000000000000000000000000000000000000000000000000000005f5260045ffd5b9050155f612f61565b919082039182116122d257565b81810392915f1380158285131691841216176122d257565b81811015612ff25781039081116122d257612fd890613592565b5f81810391125f82128116905f8313901516176122d25790565b9081039081116122d257610ec790613592565b7f800000000000000000000000000000000000000000000000000000000000000081146122d2575f0390565b905f811261307757807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff048211810215633b9aca0002156101d457633b9aca0091020490565b61308090613005565b807fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff048211810215633b9aca0002156101d457610ec79102633b9aca008082049106151501613005565b5f8281039392811380158286131691851216176122d257610ec7925f916131af565b91905f811215613190576130ff90613005565b828119106131695782018092116122d25761311991613876565b7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff8110156131445790565b507fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff90565b5050507fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff90565b8083106131a95782039182116122d25761311991613876565b50905090565b919291905f8112156131ee576131c490613005565b818119106131e75781018091116122d257610ec7926131e291613876565b6136de565b5050905090565b80821061320b5781039081116122d257610ec7926131e291613876565b50505090565b9190915f83820193841291129080158216911516176122d257565b9391938185101561328b578085039485116122d25781039081116122d257610ec793838084121561327957906132696132739461326e9493612fa6565b613464565b613005565b90613211565b6132869061327394612fa6565b613680565b505091505090565b60106020825101515111613343576040810151906060810151808310801590613335575b613319576132dd6132d66132d1610ec79561330294612f99565b6136ca565b61ffff1690565b6132e8818451613736565b9361ffff808060c08a979597015193169416921690613971565b9060208101519160a06080830151920151926131af565b50610ec7915060208101519060a06080820151910151916136bc565b5060208251015151156132b7565b7f0e996766000000000000000000000000000000000000000000000000000000005f5260045ffd5b929493919073ffffffffffffffffffffffffffffffffffffffff1690811592831561341f575b50508115613415575b506134105782156133e85760400151915f5b83518110156133e2578060206133c460019387610a56565b51016133da81516133d4866122c2565b90613640565b9052016133ac565b50509050565b7fb9ec1e96000000000000000000000000000000000000000000000000000000005f5260045ffd5b509050565b905033145f61339a565b1191505f80613391565b7f333333333333333333333333333333333333333333333333333333333333333381116005021561271002156101d457600561271091020490565b817fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0481118202158302156101d457020490565b604051906134a58261080d565b5f6020838281520152565b602080916134bc613498565b500151015173ffffffffffffffffffffffffffffffffffffffff604051926134e38461080d565b168252602082015290565b6134f66117a8565b60208151910120906020815191015160405160208101918260208251919201905f5b81811061357c575050509061355881611c879493037fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe08101835282610845565b51902060408051602081019586529081019390935260608301528160808101611a15565b8251845260209384019390920191600101613518565b7f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff81116135bc5790565b60846040517f08c379a000000000000000000000000000000000000000000000000000000000815260206004820152602860248201527f53616665436173743a2076616c756520646f65736e27742066697420696e206160448201527f6e20696e743235360000000000000000000000000000000000000000000000006064820152fd5b817fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff04811182021561271002156101d45702612710808204910615150190565b817fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0481118202158302156101d4570290808204910615150190565b610ec792916131e291613876565b61ffff8110156136d75790565b5061ffff90565b90808210156136eb575090565b905090565b61ffff7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff9116019061ffff82116122d257565b61ffff1661ffff81146122d25760010190565b805161ffff928316939290919082168481101561381357506020019161376761376284515161ffff1690565b6136f0565b61ffff1660015b61ffff81168281116137ec57866137886132d68388613883565b101561379d575061379890613723565b61376e565b9095506137e491506137dc6137c7826137c16137bb6132d68b6136f0565b88613883565b96613883565b966137d66132d68851926136f0565b90610a56565b519451610a56565b519193929190565b505093506137e4613807856138018186613883565b94613883565b946137dc818651610a56565b9350613823915060200151610a49565b515f92915f9190565b9391938185101561328b578085039485116122d25781039081116122d257610ec793838084121561386957906132866132739461326e9493612fa6565b6132699061327394612fa6565b90808211156136eb575090565b60108210156138985761ffff9160041b1c1690565b7f4e23d035000000000000000000000000000000000000000000000000000000005f5260045ffd5b7f4e487b71000000000000000000000000000000000000000000000000000000005f52605160045260245ffd5b8060021461396c576001036138c0576040517fa3b1b31d00000000000000000000000000000000000000000000000000000000815260208160048160645afa9081156101cf575f9161393d575090565b90506020813d602011613964575b8161395860209383610845565b810103126101d4575190565b3d915061394b565b504390565b9493929190948060031461398f576004036138c057610ec79461382c565b50610ec79461322c56fea164736f6c634300081a000a';
    }
}
