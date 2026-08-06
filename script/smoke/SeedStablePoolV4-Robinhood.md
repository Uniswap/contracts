# Seeding a Uniswap v4 pool on Robinhood (chain 4663)

Guide for creating and funding a single Uniswap v4 pool on Robinhood without a UI, using Foundry.
You only ever supply USD prices and a USD budget; the script (`script/smoke/SeedStablePoolV4.s.sol`)
derives the v4 price, tick range, and liquidity for you. No ticks, no sqrt prices, no hand-encoding.

The script is chain-agnostic: it resolves all infra addresses from `deployments/json/4663.json` by
chain id, so nothing is hardcoded.

---

## Do you need to run a node?

Robinhood is an Arbitrum Orbit chain with split endpoints: the public Blockscout RPC is **read-only**,
and writes go to the sequencer. `forge script --broadcast` needs one RPC that does **both** reads and
writes, which on Robinhood means a Nitro follower node.

- **Read-only steps work on the public Blockscout RPC, no node needed:** the dry-run (no `--broadcast`)
  and the V4Quoter quote-test.
- **The `--broadcast` steps need a read+write RPC.** Ask Robinhood for a node endpoint that accepts
  transactions, or run your own follower node. Set that as `RH_RPC` below.

## Gas

Robinhood uses **ETH** as the gas token (confirmed onchain: the L1 bridge has no custom native token).
Your deploy EOA just needs a little ETH for gas. There is no separate gas-token ERC-20 to source.

---

## Why seed small first (read this before Run 1)

A v4 pool's price is **not** fixed: it floats with every swap, like any AMM. The only thing that
happens once is **initialization**: `initializePool` sets the starting price and can only be called
once per pool. You cannot re-initialize to reset a bad starting price.

If you initialize at the wrong starting price, the pool is mispriced versus the market. An arbitrageur
trades against it to pull it to the true price and keeps the difference, and that loss scales with how
much liquidity you posted. So:

1. **Initialize + seed a tiny amount first** (a few dollars), using a live price quote. If the starting
   price is off, only a few dollars are exposed.
2. **Test** with the read-only quote (and/or let the integrator route against it) to confirm it works.
3. **Top up to full size** once confirmed. The pool is already initialized, so the top-up adds liquidity
   at the pool's current live price (wherever swaps have left it); it does **not** re-initialize.

The script is built to be run exactly this way: run it once with a small budget, then again with the
full budget.

---

## Deployed Uniswap v4 addresses on Robinhood (chain 4663)

Resolved automatically by the script from `deployments/json/4663.json`; listed here for reference.

| Contract        | Address                                      |
|-----------------|----------------------------------------------|
| PoolManager     | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` |
| StateView       | `0xF3334192D15450CdD385c8B70e03f9A6bD9E673b` |
| V4Quoter        | `0x8dc178efb8111bb0973dd9d722ebeff267c98f94` |
| UniversalRouter | `0x8876789976decBfcbBBe364623c63652Db8C0904` |
| Permit2         | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |
| WETH9           | `0x0Bd7D308f8E1639FAb988df18A8011f41EAcAD73` |

---

## This pair: syrupUSDG / USDG

Both tokens are verified onchain on Robinhood (4663) and are **6 decimals**, so the equal-decimals
path applies and the script runs unchanged.

| Token     | Address                                      | Decimals | Notes                          |
|-----------|----------------------------------------------|----------|--------------------------------|
| USDG      | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | 6        | Global Dollar (Paxos), ~ $1.00 |
| syrupUSDG | `0x40858070814a57FdF33a613ae84fE0a8b4a874f7` | 6        | Maple yield-bearing, **> $1**  |

### The starting price is the one thing you must get right

syrupUSDG is **yield-bearing**, so 1 syrupUSDG is worth **more** than 1 USDG, and that ratio drifts
upward over time as yield accrues. The pool's starting price must match the current redemption ratio,
or the pool gets arbitraged the moment it is live.

The syrupUSDG deployed on Robinhood is a **bridged ERC-20**: it has no onchain exchange-rate function
(`convertToAssets`, `previewRedeem`, etc. all revert), so the ratio cannot be read from the RH contract.
**Get the current syrupUSDG → USDG rate from Maple** (or from the canonical syrupUSDG vault on its home
chain) at run time. Then:

- `PRICE_A_USD_8DP` for USDG = `100000000` ($1.00)
- `PRICE_B_USD_8DP` for syrupUSDG = `rate × 1e8`. Example: if 1 syrupUSDG = 1.05 USDG, use `105000000`.

Only the **ratio** between the two prices matters, so you can also express it relative to $1: USDG at
`100000000` and syrupUSDG at the rate × 1e8.

### Yield drift caveat (worth telling Maple)

Because the pool price is set once and only moves via swaps, a full-range syrupUSDG/USDG pool slowly
becomes underpriced as syrupUSDG accrues yield: the real NAV rises but the pool price does not, so
arbitrageurs buy syrupUSDG cheap from the pool and LPs bleed the yield over time. For a modest test/
bootstrap pool this is small in absolute terms, but it is inherent to LPing a yield-bearing token
against its underlying in a constant-product AMM. Keep the size modest, monitor it, and re-seed or
re-price if it drifts materially.

---

## You never touch ticks or sqrt prices

You only ever provide USD prices and a USD budget. The script converts those into the v4
`sqrtPriceX96`, the tick range, and the liquidity. Use a live quote for the prices on the first run,
since that run sets the pool's starting price.

This script supports **equal-decimal** pairs only (e.g. two 6-decimal stables, or two 18-decimal
tokens). The USD→amount math assumes both tokens share decimals.

---

## Step 0: confirm tokens and gas (do this first)

Never hardcode token addresses. Confirm the canonical addresses from the issuer's docs, then verify
onchain:

```bash
export RH_RPC=<your-robinhood-rpc>          # read+write endpoint for broadcast; Blockscout RPC ok for reads
export USDG=0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168
export SYRUP_USDG=0x40858070814a57FdF33a613ae84fE0a8b4a874f7
cast call $USDG       "symbol()(string)"  --rpc-url $RH_RPC   # USDG
cast call $USDG       "decimals()(uint8)" --rpc-url $RH_RPC   # 6
cast call $SYRUP_USDG "symbol()(string)"  --rpc-url $RH_RPC   # syrupUSDG
cast call $SYRUP_USDG "decimals()(uint8)" --rpc-url $RH_RPC   # 6 (matches USDG)
```

Make sure your deploy EOA holds:
- a little **ETH** for gas, and
- enough of **each token** to cover the per-side budget you choose.

Prefer a dedicated seeding EOA over a treasury wallet: the script grants standing Permit2 allowances
from whichever account runs it.

---

## Inputs (all USD figures scaled by 1e8, "Chainlink style")

| Env var            | Meaning                                  | Example                              |
|--------------------|------------------------------------------|--------------------------------------|
| `TOKEN_A`          | one token address (order doesn't matter) | `0x...`                              |
| `TOKEN_B`          | the other token address                  | `0x...`                              |
| `PRICE_A_USD_8DP`  | USD price of 1 whole TOKEN_A × 1e8       | $1.00 → `100000000`                  |
| `PRICE_B_USD_8DP`  | USD price of 1 whole TOKEN_B × 1e8       | $1.08 → `108000000`                  |
| `USD_PER_SIDE_8DP` | USD value to deposit per side × 1e8      | $2 test → `200000000`; $1000 → `100000000000` |

Rule for the 1e8 scale: multiply the dollar figure by `100000000`. Use a live quote for any non-$1
price at run time.

The script also needs two env vars so `foundry.toml` parses (they are never used here):

```bash
export TENDERLY_PUBLIC_RPC_URL=http://x
export TENDERLY_ACCESS_KEY=dummy
```

---

## Run 1: tiny test seed (this sets the starting price)

```bash
export TOKEN_A=$USDG                   # 0x5fc5...d168
export TOKEN_B=$SYRUP_USDG             # 0x4085...74f7
export PRICE_A_USD_8DP=100000000      # USDG $1.00
export PRICE_B_USD_8DP=105000000      # syrupUSDG: rate x 1e8  <-- replace 1.05 with the live Maple rate
export USD_PER_SIDE_8DP=200000000     # $2 per side for the test

# Dry run first (no broadcast). Read the logged amounts/price and confirm they look right.
# Works against the read-only Blockscout RPC.
forge script script/smoke/SeedStablePoolV4.s.sol \
  --rpc-url $RH_RPC --sender <YOUR_EOA> --skip '*/node_modules/*'

# Broadcast (needs the read+write RPC):
forge script script/smoke/SeedStablePoolV4.s.sol \
  --rpc-url $RH_RPC --account <keystore-name> --sender <YOUR_EOA> \
  --broadcast --slow --legacy --with-gas-price 200000000 --gas-estimate-multiplier 400 \
  --skip '*/node_modules/*'
```

Why these flags on Robinhood (an Orbit chain):
- `--slow`: submit nonces sequentially; avoids reordering on sequencer-driven chains.
- `--legacy`: Robinhood's RPC path is happiest with legacy gas pricing.
- `--with-gas-price 200000000`: 0.2 gwei; this is the **actual broadcast price** (not `--gas-price`,
  which only affects simulation).
- `--gas-estimate-multiplier 400`: the small approval txs otherwise get rejected as
  `intrinsic gas too low` because forge's local sizing doesn't model Orbit's L1-data gas. Excess gas is
  rebated, so over-budgeting is free.

---

## Test it (read-only quote, does not move the price)

For this pair, sorted by address: `c0 = syrupUSDG` (`0x4085...74f7`), `c1 = USDG` (`0x5fc5...d168`).
`zeroForOne=true` sells `c0` (syrupUSDG). The amount `1000000` is 1 token (6 decimals).

```bash
cast call 0x8dc178efb8111bb0973dd9d722ebeff267c98f94 \
  "quoteExactInputSingle(((address,address,uint24,int24,address),bool,uint128,bytes))(uint256,uint256)" \
  "(($SYRUP_USDG,$USDG,500,10,0x0000000000000000000000000000000000000000),true,1000000,0x)" \
  --rpc-url $RH_RPC
```

It returns `(amountOut, gasEstimate)` and simulates the swap without changing the pool price. That
matters because when you top up, the new liquidity is added at the pool's current price, so you want
the price still sitting where you created it. A real swap would shift it; the quote does not.

**Expect the quoted rate to look bad at this stage.** Quoting 1 whole token against only a few dollars
of seeded depth has heavy price impact, so `amountOut` will come back noticeably below the FX rate.
That is depth, not mispricing. Check that the direction and rough ratio make sense (or quote a much
smaller amount); the rate tightens up once the full liquidity is in.

---

## Run 2: top up to full size (price unchanged)

Re-run the exact same command with the real budget. The script detects the pool is already initialized,
reads the live price from StateView, and adds liquidity there without re-pricing.

Two things about this run:

- **Re-export every env var, not just the budget** (fresh shells lose them, and the script needs the
  prices to size the amounts). Refresh `PRICE_B_USD_8DP` from a live FX quote at the same time.
- **A leftover on one side is normal.** The prices size the two amounts, but the pool's live price
  decides the exact ratio it accepts; the script deposits the binding side in full and up to the
  requested amount of the other. Whatever isn't consumed stays in your wallet, nothing is lost.

```bash
export TOKEN_A=$USDG
export TOKEN_B=$SYRUP_USDG
export PRICE_A_USD_8DP=100000000       # USDG $1.00
export PRICE_B_USD_8DP=105000000       # refresh with the live Maple rate
export USD_PER_SIDE_8DP=100000000000   # $1000 per side
forge script script/smoke/SeedStablePoolV4.s.sol \
  --rpc-url $RH_RPC --account <keystore-name> --sender <YOUR_EOA> \
  --broadcast --slow --legacy --with-gas-price 200000000 --gas-estimate-multiplier 400 \
  --skip '*/node_modules/*'
```

---

## What the script does (and its safety checks)

- Resolves all infra addresses from `deployments/json/4663.json` (nothing hardcoded).
- Sorts the tokens (`currency0 < currency1`) and keeps prices/amounts aligned.
- Requires equal decimals (the USD→price math assumes it).
- First run: computes `sqrtPriceX96` from the USD prices and initializes. Later runs: funds at the live
  price read from StateView.
- Derives token amounts from `USD_PER_SIDE_8DP` and the prices, and the liquidity from those amounts.
- Uses the 0.05% fee tier and a full-range position.
- Permit2 dual-approval, then `modifyLiquidities` (`MINT_POSITION` + `SETTLE_PAIR`).
- Checks your token balances before minting, and asserts pool liquidity increased afterward.

## Fee tier

This script uses the v4 0.05% fee tier with tick spacing 10 (`FEE = 500`, `TICK_SPACING = 10`). In v4 any
fee/tickSpacing combo is allowed; edit the constants at the top of the script if you want a different
tier.

---

## Validation status

This script + flow was run end-to-end against a fork of a live Robinhood (4663) node, exercising the
real PoolManager / PositionManager / StateView at the addresses above:

- Run 1 (init + seed): pool initialized at the USD-derived price, position minted, liquidity 0 → nonzero.
- Run 2 (top-up): detected already-initialized, added liquidity at the live price with the price
  unchanged.
- V4Quoter read-only quote: routed and returned an amount-out + gas estimate.

Specifically for **syrupUSDG / USDG**, a fork test using the **real token contracts** confirmed:

- both tokens are freely transferable into the PositionManager (no whitelist / transfer restriction),
- the 6-decimal equal-decimals path works,
- a 1.05 syrupUSDG/USDG rate initialized at the correct tick (≈ `1.0001^487 = 1.05`) and minted
  liquidity successfully.

The mint encoding matches the v4 smoke test that already passes on chain 4663.

## References

- Script: `script/smoke/SeedStablePoolV4.s.sol`
- Proven-on-4663 v4 flow: `script/smoke/V4SmokeTest.s.sol`
- Uniswap v4 docs: https://docs.uniswap.org/contracts/v4/overview
