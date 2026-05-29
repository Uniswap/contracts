# Seeding a USDC/EURC pool on Arc (Uniswap v4, chain 5042)

Guide for creating and funding a single test pool without a UI, using Foundry. Written for the
Arc / LI.FI same-chain swap testing requirement. Uses **Uniswap v4**.

## Why seed small first

The pool price is NOT fixed: it floats with every swap, like any AMM. The only thing that happens once
is **initialization** — `initializePool` sets the *starting* price and can only be called once per pool,
so you can't re-initialize to reset a bad starting price.

If you initialize at the wrong starting price, the pool is mispriced versus the market. An arbitrageur
trades against it to pull it to the true price and keeps the difference, and **that loss scales with how
much liquidity you posted**. Correcting a bad starting price yourself means swapping the pool back, which
costs fees/spread. With a tiny position that's cheap; with a big one it's a real loss.

So the safe sequence is:

1. **Initialize + seed a tiny amount first** (a few dollars), using a live FX quote for the price. If the
   starting price is off, only a few dollars are exposed and it's cheap to nudge back.
2. **Run a test swap / let LI.FI route against it** to confirm everything works.
3. **Top up to the full ~$1k/$1k** once confirmed. The pool is already initialized, so the top-up adds
   liquidity at the pool's current live price (wherever swaps have left it); it does not re-initialize.

The script below is built to be run exactly this way: run it once with a small budget, then run it
again with the full budget.

## You never touch ticks or sqrt prices

You only ever provide **USD prices** (and a USD budget). The script converts those into the v4
sqrtPriceX96, the tick range, and the liquidity for you. Use a live FX quote for the prices on the first
run, since that run sets the pool's starting price (see above).

## Deployed Uniswap v4 addresses on Arc (chain 5042)

Explorer: https://explorer.arc.io · resolved automatically by the script from `deployments/json/5042.json`.

| Contract | Address |
|---|---|
| PoolManager | `0x8366a39cc670b4001a1121b8f6a443a643e40951` |
| PositionManager | `0x6049c9a0e26405c0985f9e3685c87d0ae917f82b` |
| StateView | `0xf3334192d15450cdd385c8b70e03f9a6bd9e673b` |
| V4Quoter | `0x8dc178efb8111bb0973dd9d722ebeff267c98f94` |
| UniversalRouter | `0x4fca4a51ab4f23a7447b3284fbd7d73289a89fb1` |
| Permit2 | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |

## Step 0 — confirm tokens and gas (do this first)

We never hardcode token addresses. Confirm the canonical USDC and EURC addresses on Arc from Circle's
docs, then verify onchain:

```bash
export ARC_RPC=<arc-rpc-url>
cast call <USDC> "symbol()(string)"   --rpc-url $ARC_RPC   # expect USDC
cast call <USDC> "decimals()(uint8)"  --rpc-url $ARC_RPC   # expect 6
cast call <EURC> "symbol()(string)"   --rpc-url $ARC_RPC   # expect EURC
cast call <EURC> "decimals()(uint8)"  --rpc-url $ARC_RPC   # expect 6
```

Both are 6 decimals, so the script's equal-decimals path applies.

**Gas note:** Arc's native gas token is an ERC-20 (not ETH). Your funding EOA must hold some of Arc's
native token to pay for transactions. The USDC/EURC pool itself never touches the native token.

## The script

`script/smoke/SeedStablePoolV4.s.sol` — creates the pool (first run) and funds it, in one transaction.
It mirrors the v4 encoding from the smoke test that is already proven to work on Arc
(`script/smoke/native-is-erc20/V4SmokeNativeIsERC20.s.sol`): same action codes, same
`modifyLiquidities` encoding, same Permit2 dual-approval. It uses the 0.05% fee tier and a full-range
position.

### Inputs (all USD figures scaled by 1e8, "Chainlink style")

| Env var | Meaning | Example |
|---|---|---|
| `TOKEN_A` | one token address (e.g. USDC) | `0x...` |
| `TOKEN_B` | the other token address (e.g. EURC) | `0x...` |
| `PRICE_A_USD_8DP` | USD price of 1 TOKEN_A × 1e8 | `$1.00` → `100000000` |
| `PRICE_B_USD_8DP` | USD price of 1 TOKEN_B × 1e8 | `$1.08` → `108000000` |
| `USD_PER_SIDE_8DP` | USD value to deposit per side × 1e8 | `$2` test → `200000000`; `$1000` → `100000000000` |

The rule for the 1e8 scale: **multiply the dollar figure by 100000000**. Use a real EUR/USD quote for
`PRICE_B_USD_8DP` at run time.

### Run 1 — tiny test seed (this locks the price)

```bash
export ARC_RPC=<arc-rpc-url>
export TOKEN_A=<USDC>
export TOKEN_B=<EURC>
export PRICE_A_USD_8DP=100000000     # USDC $1.00
export PRICE_B_USD_8DP=108000000     # EURC $1.08  <-- use the live rate
export USD_PER_SIDE_8DP=200000000    # $2 per side for the test

# Dry run first (no broadcast) — read the logged amounts/price, confirm they look right:
forge script script/smoke/SeedStablePoolV4.s.sol --rpc-url $ARC_RPC --sender <YOUR_EOA>

# Broadcast:
forge script script/smoke/SeedStablePoolV4.s.sol \
  --rpc-url $ARC_RPC --account <keystore-name> --sender <YOUR_EOA> --broadcast
```

> Arc gas: if a tx gets stuck, prior Arc deploys have used `--legacy --gas-price 200000000`. Add those
> flags if you hit replacement/underpriced errors.

### Test it

Quote a small swap to prove the pool is routable (V4Quoter):

```bash
cast call 0x8dc178efb8111bb0973dd9d722ebeff267c98f94 \
  "quoteExactInputSingle(((address,address,uint24,int24,address),bool,uint128,bytes))(uint256,uint256)" \
  "((<c0>,<c1>,500,10,0x0000000000000000000000000000000000000000),<zeroForOne>,1000000,0x)" \
  --rpc-url $ARC_RPC
```

`<c0>`/`<c1>` are USDC/EURC sorted by address (lower address is c0). `zeroForOne=true` means selling c0.
Then point LI.FI at the pool for their same-chain swap test.

### Run 2 — top up to full size (price unchanged)

Re-run the exact same command with the real budget. The script detects the pool is already initialized,
reads the live price from StateView, and adds liquidity there without re-pricing:

```bash
export USD_PER_SIDE_8DP=100000000000   # $1000 per side
forge script script/smoke/SeedStablePoolV4.s.sol \
  --rpc-url $ARC_RPC --account <keystore-name> --sender <YOUR_EOA> --broadcast
```

## What the script does (and safety checks)

- Resolves all infra addresses from `deployments/json/5042.json` (nothing hardcoded).
- Sorts the tokens (currency0 < currency1) and keeps prices/amounts aligned.
- Requires equal decimals (the USD→price math assumes it).
- First run: computes sqrtPriceX96 from the USD prices and initializes. Later runs: funds at the live price.
- Derives token amounts from `USD_PER_SIDE_8DP` and the prices, and the liquidity from those amounts.
- Permit2 dual-approval, then `modifyLiquidities` (MINT_POSITION + SETTLE_PAIR), full range.
- Checks your balances before minting and asserts pool liquidity increased after.

## References

- Uniswap v4 docs: https://docs.uniswap.org/contracts/v4/overview
- Proven-on-Arc v4 flow: `script/smoke/native-is-erc20/V4SmokeNativeIsERC20.s.sol`
- All Arc deployments: `deployments/5042.md`
