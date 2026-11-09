# Elysium (99901) deployment records

Deploy-all ran from `ac1f0be` (`script/deploy/tasks/99901/task-1793678944.json`, broadcast
`broadcast/Deploy-all.s.sol/99901/run-1793678997020.json`). Three contracts were deployed afterwards from their own
repositories and are merged in from `extra-deploys.json`:

- `PermissionsAdapterFactory` from Uniswap/v4-periphery `9969eec`. Deploy-all's factory
  (`0x3feDaD0Abb1EE1066672e93999b672036FD98A10`) was built from stale briefcase initcode and is superseded.
- `UniversalRouter#v2.1.2` from Uniswap/universal-router `802fe4c` (tag 2.1.2), also the unversioned `UniversalRouter`.
- `UniversalRouter#v2.2` from Uniswap/universal-router `64027f3` (tag 2.2.0), pointing at the new factory. Deploy-all's
  router (`0x1bd4d69BfB8927a045F20518a08390ceE3913B0D`) points at the superseded factory and is superseded.

The superseded contracts stay in `history`; `latest` points at their replacements. Never allowlist either of them in a
permissioned hook. Each replacement's creation code is byte-identical to the HyperEVM deployment built from the same
commit.

## Rebuilding the registry

Needs every `src/pkgs` submodule checked out and built (`git submodule update --init --recursive && forge build`), and
`origin/main` fetched. Start from an empty file so the run is reproducible:

```bash
RPC=<elysium rpc>
EXPLORER=https://elysium.kinetiq.xyz/explorer
rm -f deployments/json/99901.json
node lib/forge-chronicles Deploy-all.s.sol -c 99901 -e $EXPLORER -r $RPC --force
python3 script/util/merge_extra_deploys.py $RPC 99901 script/elysium/extra-deploys.json
node lib/forge-chronicles -c 99901 --skip-json -e $EXPLORER
python3 script/util/merge_extra_deploys.py --relink-md 99901 script/elysium/extra-deploys.json
```

Chronicles also rewrites other rows of `deployments/index.md` and appends the 99901 row on every run; keep exactly one 99901 row
(`grep -c "^| 99901 |" deployments/index.md` prints 1).
