# Program reference

[← Back](../README.md)

Program ID: `EyQygGKAxe9Py1MWfGM2KLPQ7FCQZ3RwncxSDiTL412v` (Solana mainnet). Built with Anchor.

## Accounts

| Account | PDA seeds | Holds |
|---|---|---|
| `ProtocolConfig` | `["config"]` | Admin, treasury, indexer authority, default protocol fee, creation fee, pause flag, pool count, protocol lookup table |
| `QuoteMint` | `["quote", mint]` | Allowlist entry for one stock mint |
| `Pool` | `["pool", project_mint, quote_mint, creator]` (Raydium) or `["pool", project_mint, quote_mint, creator, "meteora"]` (Meteora) | One position on one venue pool, plus all its fee accounting. A wallet has at most one position per pair on each venue. |
| Lock vault | `["lock", pool]` | Owner of a **locked** position's NFT |
| Creator vault | `["cvault", pool]` | Owner of an **unlocked** position's NFT |
| Fee authority | `["fees", pool]` | Signs payouts. Its associated token account for the stock is the pool's **holder vault**. |
| `Epoch` | `["epoch", pool, index]` | One hourly payout: Merkle root, total, claimed amount, claim times, cancelled flag, claimed bitmap |

`Pool` records, among others: the venue pool (a Raydium `pool_state` or a Meteora cp-amm pool; the venue is read
from that account's owner), the position NFT mint, lock mode, state (`Prepared`, `Active`,
`Withdrawn`), minimum holder balance, holder cap, protocol fee, creator, operator, referrer, lifetime harvested,
protocol, distributed and reserved amounts, the epoch count and the last epoch time.

## Instructions

### Admin (the Squads multisig)

| Instruction | Does |
|---|---|
| `initialize_protocol` | Creates the config once |
| `set_quote_mint` | Adds or removes a stock mint from the allowlist |
| `set_pool_fee_bps` | Sets one pool's protocol fee, at most 1,000 bps |
| `set_protocol_params` | Default fee, creation fee (max 1 SOL), treasury, indexer authority, lookup table, admin |
| `pause` / `unpause` | Stops or resumes pool creation |
| `cancel_epoch` | Voids an epoch's root inside its challenge window and releases its reservation |

### Pools

| Instruction | Caller | Does |
|---|---|---|
| `create_pool` | Creator | Creation fee, Raydium pool if new (else price check), position owned by the vault, pool accounts. Rejects fee tiers below 1%. |
| `create_pool_prepare` | Operator wallet | Multisig flow, step 1: pays the fee, binds the multisig, creates the `Pool` in `Prepared` state |
| `create_pool_execute` | Multisig | Multisig flow, step 2: creates the Raydium pool and position funded from the multisig |
| `harvest` | Any signer | Collects the position's fees and splits them (see below) |
| `withdraw_position` | Creator, unlocked pools only | Moves the position NFT out of the creator vault; fails with `PositionLocked` otherwise |
| `create_pool_meteora` | Creator | The Meteora DAMM v2 twin of `create_pool`: creation fee, cp-amm pool if new (fees collected in the stock only, flat 1% or 2% base fee), position owned by the vault, pool accounts. Refuses an existing cp-amm pool whose fee collection mode or fee schedule would stop holders being paid in the stock. |
| `harvest_meteora` | Any signer | Claims the position's fees through cp-amm's `claim_position_fee`; the split is identical to `harvest` |
| `withdraw_position_meteora` | Creator, unlocked pools only | Harvests, then moves the position NFT out of the creator vault |

### Payouts

| Instruction | Caller | Does |
|---|---|---|
| `publish_epoch` | Indexer authority | Reserves `total` of the vault's unreserved stock behind a Merkle root. Claims open 1 hour later; epochs of one pool are at least 1 hour apart. |
| `claim` | Any signer | Verifies a proof and pays the leaf into the holder's own associated token account. Each leaf pays once. |
| `close_epoch` | Any signer | Closes a fully claimed, cancelled, or week-old epoch. Unclaimed stock returns to the vault; rent returns to the indexer authority. |

## Harvest

On Raydium, fees are collected with `decrease_liquidity_v2` at liquidity 0, the only way Raydium CLMM exposes fee
collection. On Meteora, they are collected with cp-amm's `claim_position_fee`. Either way the program measures what
arrived as the balance change across that call, so tokens sent to the vault beforehand are never counted as fees.

For each side of the pair, with `gross` the collected amount:

```
protocol  = gross × protocol_fee_bps / 10,000
referrer  = protocol × 20%        (only if the pool has a referrer)
treasury  = protocol − referrer
holders   = gross − protocol
```

The stock side of `holders` stays in the holder vault. The project-token side goes to the indexer authority's
token account, to be converted into the stock off-chain and deposited back into the holder vault. On a Meteora pool
that collects fees in the stock only, the project-token side is always zero. All fee math is
128-bit and checked.

## Payout Merkle tree

Leaves and nodes are SHA-256:

```
leaf = sha256(0x00 || claim_index as u32 LE || holder pubkey (32 bytes) || amount as u64 LE)
node = sha256(0x01 || min(a, b) || max(a, b))
```

Children are sorted before hashing, and an odd node is promoted to the next layer unchanged. The domain-separation
prefixes stop a node from being passed off as a leaf.

Off-chain, holders are sorted by address before indexes are assigned. Each holder's amount is
`vault_unreserved × balance / eligible_total`, rounded down; zero amounts are dropped.

## Events

Emitted through Anchor's `emit_cpi!` (a self-CPI), so they are recorded as inner instructions rather than program logs
and are not lost to log truncation.

`PoolCreated` · `Harvested` · `EpochPublished` · `EpochCancelled` · `EpochClosed` · `Claimed` · `PositionWithdrawn` · `PoolFeeUpdated`

## Invariants

- The only venue calls a vault PDA ever signs are fee collects: Raydium's with liquidity hardcoded to 0, and
  cp-amm's `claim_position_fee`. Liquidity cannot leave a locked position through this program, and no
  instruction transfers or closes the lock vault.
- The fee authority only ever transfers to the treasury, the referrer, the indexer authority (project-token side)
  and holders' associated token accounts.
- An epoch can reserve no more than the vault's unreserved balance, and epochs are at least an hour apart, so a
  compromised indexer key can target at most about one hour of one pool's fees per epoch, and the admin can cancel
  it before claims open.
- The protocol fee cannot exceed 10% and the creation fee cannot exceed 1 SOL, whoever holds the admin key.

## Build profiles

Test and devnet builds compile in shorter epoch timings and devnet's Raydium program. Every build embeds a marker
string (`RESTOCK_BUILD:raydium=mainnet`, `RESTOCK_BUILD:epochs=slow` on mainnet), and the deploy tooling refuses
to ship a binary with the wrong markers. You can check the markers in the deployed binary yourself:
see [Verify it yourself](verify.md#the-deployed-binary).
