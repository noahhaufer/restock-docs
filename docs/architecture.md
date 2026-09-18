# Architecture

[← Back](../README.md)

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../assets/architecture-dark.png">
  <img src="../assets/architecture-light.png" alt="ReStock system architecture">
</picture>

ReStock has one on-chain program and three off-chain pieces. Funds only ever move through the program; the
off-chain pieces build transactions, index the chain, and run the hourly schedule.

## On-chain: Solana mainnet

### ReStock program

An Anchor program that owns every ReStock position and its fee accounting. It calls Raydium's CLMM program or
Meteora's DAMM v2 (cp-amm) program to create pools, open positions and collect fees. Full reference:
[Program reference](program.md).

### Raydium CLMM and Meteora DAMM v2

The pools are ordinary Raydium CLMM or Meteora DAMM v2 pools, so they trade on those venues and through any
aggregator that routes to them. ReStock only restricts the trade fee a ReStock pool may use: 1% or 2%.

Stock tokens are Token-2022 mints with issuer-controlled extensions. Each venue supports them through its own
per-mint whitelist (Raydium's `SupportMintAssociated`, Meteora's `TokenBadge`), which the program passes through on
pool creation. The whitelists barely overlap, so the stock decides the venue: see
[How it works](how-it-works.md#raydium-or-meteora).

### Squads multisig

The protocol's upgrade authority, admin and treasury are one Squads multisig vault. Every admin action is a
multisig proposal: program upgrades, protocol parameters, per-pool protocol fees, pausing, and cancelling an epoch
inside its challenge window.

## Off-chain

### restock.fun (Vercel)

A Next.js app. It builds transactions; the user's wallet signs them. It never holds user keys.

- **Wallets** connect through Privy.
- **Pool creation** runs a wizard that prices the pair (Jupiter cross-checked against on-chain pools), compiles the
  transaction against the protocol's address lookup table, and hands it to the wallet.
- **Trading** on a Raydium pool goes straight through its CLMM pool, using Raydium's SDK server-side to quote and build
  the swap. Aggregators often do not route to young pools yet, and a swap routed through other pools pays nothing to
  this pool's holders.
- **Getting the stock** uses a Jupiter swap dialog.
- **Claims** read a holder's proofs from the indexer and submit `claim`.
- **Charts** use Birdeye, with GeckoTerminal as the fallback.
- **Copilot** relays encrypted prompts to SolRouter's TEE. See [How it works](how-it-works.md#copilot).

Data comes from the indexer's read API.

### Indexer (Render web service)

Turns chain activity into the data the site reads, stored in Postgres.

- Receives Helius webhooks for the program and for every ReStock pool's venue account, decodes program events
  and swaps, and reconciles against the chain every hour.
- Refreshes pool stats, prices and fee revenue every minute.
- Snapshots token holders (Helius DAS) and builds each epoch's Merkle tree, storing every leaf and proof so the
  site and the keeper can submit claims.
- Serves the read API: pools, positions, epochs, claims, trades and the competition leaderboard.

### Keeper (Render worker)

Runs the hourly cycle over every pool: harvest, convert, publish the epoch, execute due claims, close finished
epochs. Details: [Hourly payouts](how-it-works.md#hourly-payouts).

## Keys and trust

| Key | Held by | Can do | Cannot do |
|---|---|---|---|
| Squads vault (multisig) | The team, 2 signatures required | Upgrade the program; set protocol fee (max 10%), creation fee (max 1 SOL), treasury, indexer authority; pause; cancel an epoch in its window | Move liquidity out of a locked position (no such instruction exists) |
| Indexer authority | Keeper service | Publish epochs; receive the project-token side of fees and convert it to the stock | Touch any position; publish more than a pool's unreserved vault balance; publish a pool twice within an hour |
| Keeper fee payer | Keeper service | Pay for `harvest`, `claim` and `close_epoch`, all callable by any signer | Redirect funds: claims go to the holder's own token account, harvest splits are fixed in the program |
| Pool creator | The creator's wallet or multisig | Withdraw an **unlocked** position | Withdraw a locked position; change where fees go |

**Worst case for a compromised indexer authority:** it could publish a wrong payout list for pools' unreserved
fees, which is at most about one hour of fees per pool, and the multisig can cancel that list during the one-hour
challenge window before any claim opens. It could also keep the project-token side it receives for conversion,
which is visible on-chain as conversions that never reach the holder vault.

**If the off-chain services stop,** no funds move and none are lost: fees keep accruing in the positions and
vaults, and published epochs stay on-chain. `harvest`, `claim` and `close_epoch` can be called by any signer, but a
claim needs its Merkle proof, which the indexer serves, so payouts and new epochs resume when the services do.

## Inherent asset risk

Stock tokens carry issuer-controlled extensions (permanent delegate, pausable, transfer hook). The issuer can freeze
or claw back tokens in any account, including ReStock's vaults and the venues'. This is a property of the stock
tokens, not something ReStock can change, and is disclosed in the [Terms](https://restock.fun/terms).
