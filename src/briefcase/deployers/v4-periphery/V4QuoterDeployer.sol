// SPDX-License-Identifier: MIT
pragma solidity >= 0.8.0;

import {IV4Quoter} from '../../protocols/v4-periphery/interfaces/IV4Quoter.sol';

library V4QuoterDeployer {
    function deploy(address poolManager) internal returns (IV4Quoter v4quoter) {
        bytes memory args = abi.encode(poolManager);
        bytes memory initcode_ = abi.encodePacked(initcode(), args);

        assembly {
            v4quoter := create(0, add(initcode_, 32), mload(initcode_))
        }
    }

    /// @dev autogenerated - run `./script/util/create_briefcase.sh` to generate current initcode
    function initcode() internal pure returns (bytes memory) {
        return
        hex'60a034607b57601f61175038819003918201601f19168301916001600160401b03831184841017607f57808492602094604052833981010312607b57516001600160a01b0381168103607b576080526040516116bc908161009482396080518181816101b5015281816102ab015281816105b001526114910152f35b5f80fd5b634e487b7160e01b5f52604160045260245ffdfe60806040526004361015610011575f80fd5b5f3560e01c8063147d2af91461087f578063587330731461082d578063595323f5146107815780636a36a38c1461065657806391dd73461461052c578063aa2f15011461037f578063aa9d21cb1461032d578063ca253dc9146101d9578063dc4c90d31461016b5763eebe0c6a14610087575f80fd5b346101675761009536610d77565b30330361013f57806101016100fb6100f660a06fffffffffffffffffffffffffffffffff9501936100c5856110fd565b6100de876100d560c0850161110a565b16600f0b611289565b906100ec60e0840184611127565b9490933690610c2a565b61134b565b916110fd565b156101355781165b7fecbd9804000000000000000000000000000000000000000000000000000000005f521660045260245ffd5b60801d8116610109565b7f29c3b7ee000000000000000000000000000000000000000000000000000000005f5260045ffd5b5f80fd5b34610167575f7ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc36011261016757602060405173ffffffffffffffffffffffffffffffffffffffff7f0000000000000000000000000000000000000000000000000000000000000000168152f35b346101675760406101e936610a53565b5f806102915f61022b6102575a9688519283917f6a36a38c00000000000000000000000000000000000000000000000000000000602084015260248301610e99565b037fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe08101835282610936565b8651809381927f48c89491000000000000000000000000000000000000000000000000000000008352602060048401526024830190610de7565b03818373ffffffffffffffffffffffffffffffffffffffff7f0000000000000000000000000000000000000000000000000000000000000000165af1908161030d575b506103055750506102f76102f16102e9611020565b925a9061104f565b916112b5565b905b82519182526020820152f35b9091506102f9565b610328903d805f833e6103208183610936565b810190610fbd565b6102d4565b3461016757604061033d36610c93565b5f806102915f61022b6102575a9688519283917feebe0c6a0000000000000000000000000000000000000000000000000000000060208401526024830161105c565b346101675761038d36610e2a565b30330361013f57602081016103a281836111a7565b90506103b06040840161110a565b916103ba846111fb565b9190815b610400576fffffffffffffffffffffffffffffffff847fecbd9804000000000000000000000000000000000000000000000000000000005f521660045260245ffd5b90919261040d82866111a7565b91907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff85018581116104dc5761046561045e6fffffffffffffffffffffffffffffffff926104ac966104819561121c565b9788611588565b939061047460808a018a611127565b939092169085159061134b565b90156105095761049390600f0b611178565b6fffffffffffffffffffffffffffffffff165b936111fb565b9180156104dc577fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff0190816103be565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52601160045260245ffd5b6105159060801d611178565b6fffffffffffffffffffffffffffffffff166104a6565b346101675760207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc3601126101675760043567ffffffffffffffff811161016757366023820112156101675780600401359067ffffffffffffffff82116101675736602483830101116101675773ffffffffffffffffffffffffffffffffffffffff7f000000000000000000000000000000000000000000000000000000000000000016330361062e575f6024819284806040519384930183378101838152039082305af16105f9611020565b9061060657602081519101fd5b7fe0752a5a000000000000000000000000000000000000000000000000000000005f5260045ffd5b7fae18210a000000000000000000000000000000000000000000000000000000005f5260045ffd5b346101675761066436610e2a565b30330361013f57602081019061067a82826111a7565b90506106886040830161110a565b91610692816111fb565b935f915b8383106106db576fffffffffffffffffffffffffffffffff857fecbd9804000000000000000000000000000000000000000000000000000000005f521660045260245ffd5b9091929361075c6fffffffffffffffffffffffffffffffff61073d61072860019461071a6107138a61070d8b8b6111a7565b9061121c565b9b8c611588565b948593919216600f0b611289565b61073560808d018d611127565b93909261134b565b9015610767576fffffffffffffffffffffffffffffffff165b966111fb565b959493019190610696565b60801d6fffffffffffffffffffffffffffffffff16610756565b346101675761078f36610d77565b30330361013f57806107db6100fb6100f660a06fffffffffffffffffffffffffffffffff9501936107bf856110fd565b866107cc60c0840161110a565b16906100ec60e0840184611127565b1561081a576107ec9060801d611178565b81167fecbd9804000000000000000000000000000000000000000000000000000000005f521660045260245ffd5b61082690600f0b611178565b8116610109565b3461016757604061083d36610c93565b5f806102915f61022b6102575a9688519283917f595323f50000000000000000000000000000000000000000000000000000000060208401526024830161105c565b3461016757604061088f36610a53565b5f806102915f61022b6102575a9688519283917faa2f150100000000000000000000000000000000000000000000000000000000602084015260248301610e99565b6060810190811067ffffffffffffffff8211176108ed57604052565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52604160045260245ffd5b60a0810190811067ffffffffffffffff8211176108ed57604052565b90601f7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0910116810190811067ffffffffffffffff8211176108ed57604052565b359073ffffffffffffffffffffffffffffffffffffffff8216820361016757565b359062ffffff8216820361016757565b35908160020b820361016757565b67ffffffffffffffff81116108ed57601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe01660200190565b81601f8201121561016757803590610a07826109b6565b92610a156040519485610936565b8284526020838301011161016757815f926020809301838601378301015290565b35906fffffffffffffffffffffffffffffffff8216820361016757565b60207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc8201126101675760043567ffffffffffffffff81116101675760607ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc82840301126101675760405191610ac8836108d1565b610ad482600401610977565b8352602482013567ffffffffffffffff811161016757820190806023830112156101675760048201359167ffffffffffffffff83116108ed578260051b60405193610b226020830186610936565b845281016024019060208401908383116101675760248101915b838310610b615750505050506020830152610b5990604401610a36565b604082015290565b823567ffffffffffffffff8111610167576004908301019060a07fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe083880301126101675760405190610bb28261091a565b610bbe60208401610977565b8252610bcc60408401610998565b6020830152610bdd606084016109a8565b6040830152610bee60808401610977565b606083015260a08301359167ffffffffffffffff831161016757610c1a886020809695819601016109f0565b6080820152815201920191610b3c565b91908260a091031261016757604051610c428161091a565b6080610c8e818395610c5381610977565b8552610c6160208201610977565b6020860152610c7260408201610998565b6040860152610c83606082016109a8565b606086015201610977565b910152565b60207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc8201126101675760043567ffffffffffffffff8111610167576101007ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc828403011261016757604051916080830183811067ffffffffffffffff8211176108ed57604052610d278183600401610c2a565b835260a48201358015158103610167576020840152610d4860c48301610a36565b604084015260e48201359167ffffffffffffffff831161016757610d6f92016004016109f0565b606082015290565b60207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc820112610167576004359067ffffffffffffffff8211610167577ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc82610100920301126101675760040190565b907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0601f602080948051918291828752018686015e5f8582860101520116010190565b60207ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc820112610167576004359067ffffffffffffffff8211610167577ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffc826060920301126101675760040190565b60208152608081019173ffffffffffffffffffffffffffffffffffffffff815116602083015260208101519260606040840152835180915260a0830190602060a08260051b8601019501915f905b828210610f1157505050506fffffffffffffffffffffffffffffffff604060609201511691015290565b90919295602080610faf837fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff608a6001960301865260a060808c5173ffffffffffffffffffffffffffffffffffffffff815116845262ffffff868201511686850152604081015160020b604085015273ffffffffffffffffffffffffffffffffffffffff60608201511660608501520151918160808201520190610de7565b980192019201909291610ee7565b6020818303126101675780519067ffffffffffffffff8211610167570181601f8201121561016757805190610ff1826109b6565b92610fff6040519485610936565b8284526020838301011161016757815f9260208093018386015e8301015290565b3d1561104a573d90611031826109b6565b9161103f6040519384610936565b82523d5f602084013e565b606090565b919082039182116104dc57565b61012060606110fa93602084526110c160208501825173ffffffffffffffffffffffffffffffffffffffff6080809282815116855282602082015116602086015262ffffff6040820151166040860152606081015160020b6060860152015116910152565b6020810151151560c08501526fffffffffffffffffffffffffffffffff60408201511660e0850152015191610100808201520190610de7565b90565b3580151581036101675790565b356fffffffffffffffffffffffffffffffff811681036101675790565b9035907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe181360301821215610167570180359067ffffffffffffffff82116101675760200191813603831361016757565b600f0b7fffffffffffffffffffffffffffffffff8000000000000000000000000000000081146104dc575f0390565b9035907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe181360301821215610167570180359067ffffffffffffffff821161016757602001918160051b3603831361016757565b3573ffffffffffffffffffffffffffffffffffffffff811681036101675790565b919081101561125c5760051b810135907fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff6181360301821215610167570190565b7f4e487b71000000000000000000000000000000000000000000000000000000005f52603260045260245ffd5b7f800000000000000000000000000000000000000000000000000000000000000081146104dc575f0390565b7fecbd9804000000000000000000000000000000000000000000000000000000007fffffffff0000000000000000000000000000000000000000000000000000000060208301511603611309576024015190565b611347906040519182917f6190b2b0000000000000000000000000000000000000000000000000000000008352602060048401526024830190610de7565b0390fd5b92949390801561156d576401000276a4915b806040519261136b846108d1565b1515978884526020840194868652604085019073ffffffffffffffffffffffffffffffffffffffff1681526040519586957ff3cd914c00000000000000000000000000000000000000000000000000000000875260048701611417908b73ffffffffffffffffffffffffffffffffffffffff6080809282815116855282602082015116602086015262ffffff6040820151166040860152606081015160020b6060860152015116910152565b51151560a48701525160c48601525173ffffffffffffffffffffffffffffffffffffffff1660e48501526101048401610120905281610124850152610144840137808201610144015f9052601f017fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe01681010361014401817f000000000000000000000000000000000000000000000000000000000000000073ffffffffffffffffffffffffffffffffffffffff1691815a6020945f91f1908115611562575f91611530575b5080945f8312145f146115285760801d5b600f0b036114f95750565b60a090207f7a5ed734000000000000000000000000000000000000000000000000000000005f5260045260245ffd5b600f0b6114ee565b90506020813d60201161155a575b8161154b60209383610936565b8101031261016757515f6114dd565b3d915061153e565b6040513d5f823e3d90fd5b73fffd8963efd1fc6a506488495d951d5263988d259161135d565b905f60806040516115988161091a565b82815282602082015282604082015282606082015201526115b8826111fb565b73ffffffffffffffffffffffffffffffffffffffff82169173ffffffffffffffffffffffffffffffffffffffff82168084105f14611690575073ffffffffffffffffffffffffffffffffffffffff905b1680921492602081013562ffffff8116809103610167576040820135918260020b80930361016757606001359273ffffffffffffffffffffffffffffffffffffffff84168094036101675773ffffffffffffffffffffffffffffffffffffffff90604051956116768761091a565b865216602085015260408401526060830152608082015291565b91505073ffffffffffffffffffffffffffffffffffffffff829161160856fea164736f6c634300081a000a';
    }
}
