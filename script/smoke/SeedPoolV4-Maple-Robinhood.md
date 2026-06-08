# Adding liquidity to a syrupUSDG / USDG pool on Robinhood (Uniswap v4, chain 4663)

Instructions for Maple to create and fund a Uniswap v4 pool on Robinhood using Foundry, while the UI
is not yet available. You provide two token addresses and two token amounts; the script
(`script/smoke/SeedPoolV4.s.sol`) builds the pool at the ratio your amounts imply and mints a
concentrated position around the current price (default +/- 1%). No sqrt prices, no encoding.

The script is chain-agnostic: it resolves all Uniswap infra addresses from `deployments/json/4663.json`
by chain id, so nothing is hardcoded.

---

## What you need

**An RPC that accepts transactions.** Robinhood is an Arbitrum Orbit chain with split endpoints: the
public Blockscout RPC is read-only, and writes go to the sequencer. `forge script --broadcast` needs one
RPC that does both reads and writes, which means a Nitro follower node. Ask Robinhood for a node endpoint
that accepts transactions, or run your own follower. Set it as `RH_RPC` below.

- Read-only steps (the dry run, the quote test) work against the public Blockscout RPC, no node needed.
- The `--broadcast` steps need the read+write RPC.

**ETH for gas.** Robinhood uses ETH as its gas token (confirmed onchain). Your funding EOA needs a little
ETH for gas. There is no separate gas-token ERC-20.

**The two tokens.** Your EOA must hold enough syrupUSDG and USDG to cover the amounts you choose.

---

## Tokens (verified onchain on Robinhood 4663)

| Token     | Address                                      | Decimals | Notes                          |
|-----------|----------------------------------------------|----------|--------------------------------|
| USDG      | `0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168` | 6        | Global Dollar (Paxos), ~ $1.00 |
| syrupUSDG | `0x40858070814a57FdF33a613ae84fE0a8b4a874f7` | 6        | Maple yield-bearing (starts at par, accrues over time) |

## Uniswap v4 addresses (chain 4663)

Resolved automatically by the script; listed for reference.

| Contract        | Address                                      |
|-----------------|----------------------------------------------|
| PoolManager     | `0x8366a39CC670B4001A1121B8F6A443A643e40951` |
| PositionManager | `0x58daec3116aae6D93017bAAea7749052E8a04fA7` |
| StateView       | `0xF3334192D15450CdD385c8B70e03f9A6bD9E673b` |
| V4Quoter        | `0x8dc178efb8111bb0973dd9d722ebeff267c98f94` |
| Permit2         | `0x000000000022D473030F116dDEE9F6B43aC78BA3` |

---

## How pricing works (read this first)

You do not enter a price. **The starting price is the ratio of the two amounts you deposit.** The script
sets `price(USDG per syrupUSDG) = AMOUNT_USDG / AMOUNT_syrupUSDG` and mints there.

**Start the pool at 1:1: deposit equal amounts of syrupUSDG and USDG.** syrupUSDG launches at par with
USDG and accrues yield over time, so 1:1 is the right starting price at launch.

- Deposit equal raw amounts: `AMOUNT_syrupUSDG == AMOUNT_USDG`.
- Example: 1000 syrupUSDG with 1000 USDG.

Amounts are in each token's **raw smallest units**. Both tokens have 6 decimals, so multiply whole
tokens by 1,000,000:

- 1000 syrupUSDG = `1000000000`
- 1000 USDG = `1000000000`

(If syrupUSDG has already accrued above par by the time you seed, a 1:1 start will be slightly low and a
small arbitrage will nudge the price up; keeping Run 1 tiny limits that.)

### Seed small first

The price is set once, at initialization, and cannot be reset. So:

1. Initialize and seed a **tiny** amount first (a few tokens), at 1:1.
2. Confirm it works with the read-only quote below.
3. Re-run with the full size. The pool is already initialized, so the second run adds liquidity at the
   pool's current live price without re-pricing.

### Yield drift (worth knowing)

A pool of a yield-bearing token against its underlying slowly becomes underpriced as syrupUSDG accrues
yield: the real value rises but the pool price only moves when someone swaps, so arbitrageurs buy
syrupUSDG cheap from the pool and LPs give up the yield over time. The 0.05% fee buffers this (drift
below the fee is not profitably arbitraged), so for a modest pool it is small. With a concentrated range
there is a second effect: as the price drifts up it walks toward the upper bound, and once it exits the
range the position sits entirely in syrupUSDG and stops earning fees. At ~5% APY a +/- 1% band has
roughly two months of runway before the upper edge. Keep the size modest, monitor it, and re-seed or
widen the range if it drifts materially. A wider `RANGE_TICKS` buys more runway at the cost of fee
density.

---

## Step 0: confirm tokens and gas

```bash
export RH_RPC=<your-robinhood-rpc>     # read+write endpoint for broadcast; Blockscout RPC ok for reads
export USDG=0x5fc5360D0400a0Fd4f2af552ADD042D716F1d168
export SYRUP_USDG=0x40858070814a57FdF33a613ae84fE0a8b4a874f7

cast call $USDG       "symbol()(string)"  --rpc-url $RH_RPC   # USDG
cast call $USDG       "decimals()(uint8)" --rpc-url $RH_RPC   # 6
cast call $SYRUP_USDG "symbol()(string)"  --rpc-url $RH_RPC   # syrupUSDG
cast call $SYRUP_USDG "decimals()(uint8)" --rpc-url $RH_RPC   # 6

cast balance <YOUR_EOA> --rpc-url $RH_RPC                                  # ETH for gas
cast call $USDG       "balanceOf(address)(uint256)" <YOUR_EOA> --rpc-url $RH_RPC
cast call $SYRUP_USDG "balanceOf(address)(uint256)" <YOUR_EOA> --rpc-url $RH_RPC
```

---

## Inputs

| Env var    | Meaning                                               | Example       |
|------------|-------------------------------------------------------|---------------|
| `TOKEN_A`  | one token address (order does not matter)             | syrupUSDG     |
| `TOKEN_B`  | the other token address                               | USDG          |
| `AMOUNT_A` | raw amount of TOKEN_A to deposit (smallest units)     | `1000000000`  |
| `AMOUNT_B` | raw amount of TOKEN_B to deposit (smallest units)     | `1000000000`  |
| `RANGE_TICKS` | (optional) ticks on each side of the current price | `100` (default)|

The ratio `AMOUNT_B / AMOUNT_A` (after the script sorts the tokens) is the pool price.

### Range (concentrated, not full range)

The position is concentrated: it spans `RANGE_TICKS` ticks on each side of the current price, not the
whole curve. With this pool's tick spacing (10), 1 tick is about 0.01%, so `RANGE_TICKS` of 100 is about
+/- 1%. If you do not set it, it defaults to 100. The bounds are aligned to the tick spacing and clamped
to the usable range.

Why concentrate: for a stablecoin / correlated pair, putting the liquidity in a tight band around the
price is far more capital-efficient than full range (more fee revenue per dollar deposited), because the
price rarely leaves the band. `100` (+/- 1%) is the recommended default: tight enough to be efficient,
wide enough to cover normal stablecoin movement, and it gives syrupUSDG's upward yield drift roughly two
months of runway at ~5% APY before the price walks out the top.

Tradeoffs, with the actual bounds and liquidity for this pair (starting price 1:1 = tick 0, depositing
2 syrupUSDG / 2 USDG, from a live dry run):

| `RANGE_TICKS` | approx band | tickLower / tickUpper | liquidity (denser = more fees) |
|---------------|-------------|-----------------------|--------------------------------|
| `10`          | +/- 0.1%    | -10 / 10              | 4,001,200,079                  |
| `50`          | +/- 0.5%    | -50 / 50              | 801,040,415                    |
| `100` (default) | +/- 1%    | -100 / 100           | 401,020,832                    |
| `200`         | +/- 2%      | -200 / 200           | 201,011,666                    |

Tighter earns more fees but exits the range sooner (during any depeg, or as syrupUSDG yield pushes the
price up); wider is safer but less dense. If the price leaves the range, the position sits entirely in
one token and stops earning until you re-seed or widen it, so monitor it.

Set it like any other input, for example a tighter half-percent band:

```bash
export RANGE_TICKS=50
```

The script also needs two unused env vars so `foundry.toml` parses:

```bash
export TENDERLY_PUBLIC_RPC_URL=http://x
export TENDERLY_ACCESS_KEY=dummy
```

---

## Run 1: tiny test seed (this sets the starting price)

Seed a tiny 2 syrupUSDG / 2 USDG (1:1) to start.

```bash
export TOKEN_A=$SYRUP_USDG
export TOKEN_B=$USDG
export AMOUNT_A=2000000     # 2 syrupUSDG
export AMOUNT_B=2000000     # 2 USDG  -> 1:1 starting price

# Dry run first (no broadcast). Read the logged amounts/price and confirm they look right.
forge script script/smoke/SeedPoolV4.s.sol \
  --rpc-url $RH_RPC --sender <YOUR_EOA> --skip '*/node_modules/*'

# Broadcast (needs the read+write RPC):
forge script script/smoke/SeedPoolV4.s.sol \
  --rpc-url $RH_RPC --account <keystore-name> --sender <YOUR_EOA> \
  --broadcast --slow --legacy --with-gas-price 200000000 --gas-estimate-multiplier 400 \
  --skip '*/node_modules/*'
```

Why these flags on Robinhood (an Orbit chain):
- `--slow`: submit nonces sequentially; avoids reordering on sequencer-driven chains.
- `--legacy`: Robinhood's RPC path is happiest with legacy gas pricing.
- `--with-gas-price 200000000`: 0.2 gwei; this is the actual broadcast price (not `--gas-price`, which
  only affects simulation).
- `--gas-estimate-multiplier 400`: the small approval txs otherwise get rejected as
  `intrinsic gas too low` because forge's local sizing does not model Orbit's L1-data gas. Excess gas is
  rebated, so over-budgeting is free.

---

## Test it (read-only quote, does not move the price)

Sorted by address, `c0 = syrupUSDG`, `c1 = USDG`. `zeroForOne=true` sells syrupUSDG. `1000000` is 1 token
(6 decimals).

```bash
cast call 0x8dc178efb8111bb0973dd9d722ebeff267c98f94 \
  "quoteExactInputSingle(((address,address,uint24,int24,address),bool,uint128,bytes))(uint256,uint256)" \
  "(($SYRUP_USDG,$USDG,500,10,0x0000000000000000000000000000000000000000),true,1000000,0x)" \
  --rpc-url $RH_RPC
```

Returns `(amountOut, gasEstimate)` and simulates the swap without changing the pool price.

---

## Run 2: top up to full size (price unchanged)

Re-run with the full amounts. The script detects the pool is already initialized, reads the live price
from StateView, and adds liquidity there without re-pricing. At the live price the deposit consumes the
full amount of the binding side and up to the requested amount of the other side.

```bash
export AMOUNT_A=1000000000     # 1000 syrupUSDG
export AMOUNT_B=1000000000     # 1000 USDG  (1:1)
forge script script/smoke/SeedPoolV4.s.sol \
  --rpc-url $RH_RPC --account <keystore-name> --sender <YOUR_EOA> \
  --broadcast --slow --legacy --with-gas-price 200000000 --gas-estimate-multiplier 400 \
  --skip '*/node_modules/*'
```

---

## What the script does (and its safety checks)

- Resolves all infra addresses from `deployments/json/4663.json` (nothing hardcoded).
- Sorts the tokens (`currency0 < currency1`) and keeps amounts aligned. You can pass them in any order.
- First run: sets the starting price to `AMOUNT_B / AMOUNT_A` (after sorting) and initializes. Later runs:
  funds at the live price read from StateView.
- Uses the 0.05% fee tier and a concentrated position spanning `RANGE_TICKS` (default 100, ~ +/- 1%)
  ticks on each side of the current price, aligned to the tick spacing.
- Permit2 dual-approval, then `modifyLiquidities` (mint + settle).
- Checks your token balances before minting, and asserts pool liquidity increased afterward.

Note: because you give amounts directly, the script does not sanity-check the price for you. If you enter
the wrong ratio it will initialize there. This is why Run 1 should be tiny.

## Validation status

The script was run end-to-end against a fork of a live Robinhood (4663) node using the real syrupUSDG and
USDG contracts:

- Both tokens are freely transferable into the PositionManager (no whitelist or transfer restriction).
- Depositing syrupUSDG and USDG 1:1 initialized the pool at par (tick 0).
- Dry runs of the final script against live Robinhood state created the concentrated position at
  `RANGE_TICKS` of 10, 50, 100 (default) and 200, with correctly aligned symmetric bounds (e.g. -100 / 100
  for the default +/- 1%) and liquidity scaling as expected (tighter range = denser liquidity). All succeeded.
- The pool does not exist yet on Robinhood, so the first broadcast will create it; this is why the
  starting ratio on Run 1 matters and why Run 1 should be tiny.

## References

- Script: `script/smoke/SeedPoolV4.s.sol`
- Uniswap v4 docs: https://docs.uniswap.org/contracts/v4/overview
