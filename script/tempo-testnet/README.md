# Tempo testnet Moderato (42431) deployment records

The dev wallet `0x2179a60856E37dfeAacA0ab043B931fE224b27B6` ran Deploy-all on Tempo testnet on 2026-01-13 (blocks
848755 to 850185, nonces 0 to 28), but the broadcast never made it into this repo. So every contract here is recorded
from its onchain creation tx through `extra-deploys.json`, and the constructor inputs are decoded from those txs.
The commit that run was built from isn't known, so the entries carry no `commitHash`.

The code is still the reviewed build, though: the inputs of the transactions at nonces 1 to 28 (26 deploys plus the v3
factory's `enableFeeAmount` and `setOwner` calls) are byte-identical to the matching transactions in the Tempo mainnet
Deploy-all broadcast (`broadcast/Deploy-all.s.sol/4217/`, built from `db65edc`) except for the constructor and call
argument words, and the CREATE2 salts match too. `src/briefcase` didn't change between `1868754` (main when this run
happened) and `db65edc`. Nonce 0 is `UnsupportedProtocol`, which mainnet deployed separately.

Tempo has no native token, so the wrapped-native and spokePool params point at `UnsupportedProtocol`
(`0x8702463e73f74d0b6765aBceb314Ef07aCb92650`). Every admin role (v2 feeToSetter, v3 factory owner, PoolManager
owner and both descriptor ProxyAdmins) is still held by the dev wallet.

## Not recorded: the v4 copy at the Tempo mainnet addresses

On 2026-09-28 a third party (`0x900a0F5260b91Fd65D0C2b03D92Cf8013a1F073e`) replayed the Tempo mainnet v4 deploy
through the deterministic CREATE2 factory, so these mainnet addresses also have code on testnet: PoolManager
`0x33620f62C5b9B2086dD6b62F4A297A9f30347029`, PositionDescriptor `0xc73ED2cBa8C347593d1d9120AA0bE8fF88C6FF77`,
PositionManager `0x3Fc79444F8EACc1894775493Ff3Fa41f1e35Ce11`, V4Quoter `0x20E6487C371a2086F841eF453F85378223DF4f4E`,
StateView `0x21B954fBa3F5ddEbe77Ef2D47A3100c066908B2A` and UniversalRouter 2.1
`0xA2Dc7d0266f0CC50b3eEaF36c9BFCeCFF1BEea91`. They aren't ours and they're mis-wired for this chain: since they reuse
mainnet's constructor args, that router points at v2/v3 factory addresses with no code here, and its wrapped-native
(`0xBbBcC62853a5fA27b93d6Bab3E6F7ce841E25Df2`) is this chain's V2Factory. Don't integrate them.

## Rebuilding the registry

Needs `origin/main` fetched. Start from an empty file so the run is reproducible:

```bash
RPC=https://rpc.moderato.tempo.xyz
printf '{\n  "chainId": "42431",\n  "latest": {},\n  "history": []\n}\n' > deployments/json/42431.json
python3 script/util/merge_extra_deploys.py $RPC 42431 script/tempo-testnet/extra-deploys.json
node lib/forge-chronicles -c 42431 --skip-json -e https://explore.testnet.tempo.xyz
```

Chronicles also rewrites other rows of `deployments/index.md`; keep only the 42431 row it adds
(`grep -c "^| 42431 |" deployments/index.md` prints 1).
