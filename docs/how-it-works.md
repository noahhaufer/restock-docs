# How it works

[← Back](../README.md)

## The pair

A ReStock pool is a Raydium CLMM pool with a project token on one side and a tokenized stock on the other
(xStocks such as NVDAx, or Ondo tokens such as TSLAon). Only stock mints on the protocol's allowlist can be the
quote side. The project token must already exist; you do not need to be its creator to open a pool.

## Opening a pool

Pool creation is invite-only: apply on [restock.fun/create](https://restock.fun/create) with the wallet you will
use. Once approved, one transaction:

1. pays the 0.05 SOL creation fee,
2. creates the Raydium pool if the pair does not have one yet, or checks the supplied price against it if it does,
3. opens the liquidity position, with its position NFT owned by a ReStock vault,
4. creates the pool's accounts and its holder vault.

The creator chooses the stock, the amounts, the price range (full range by default), the fee tier (1% or 2%),
the lock mode, and optionally a minimum holder balance and a cap on how many of the largest holders qualify.
The creator chooses nothing about where fees go.

Treasuries held in a Squads multisig use a two-step flow: the operator wallet prepares the pool and pays the fee,
then the multisig funds the position in a vault transaction. The multisig becomes the position's owner.

### Starting price

The price comes from Jupiter's quote for one unit of each token, cross-checked against the deepest on-chain
pool read directly over RPC. If the two disagree by more than 3%, creation is refused until they agree. When the
Raydium pool already exists, the program itself rejects a supplied price more than ~3% from the pool's.

## Lock modes

| Mode | Where the position NFT sits | Can the liquidity leave? |
|---|---|---|
| **Locked** | Program vault `["lock", pool]` | No. The program has no instruction that transfers or closes this vault, and the only Raydium call it signs for it collects fees with liquidity hardcoded to zero. |
| **Unlocked** | Creator vault `["cvault", pool]` | Only by the creator, through `withdraw_position`. The pool is then marked withdrawn and stops harvesting. |

Both are labelled on the pool page.

## Where the fees go

A CLMM position earns fees in both tokens of the pair. Holders receive all of them in the stock.

```mermaid
flowchart LR
  T[Swaps in the Raydium pool] -->|1% or 2% trade fee| H[harvest]
  H -->|protocol share, 5% default| P[Protocol treasury]
  P -.->|20% of the protocol share, if referred| R[Referrer]
  H -->|stock side| V[Holder vault]
  H -->|project-token side| C[Conversion key]
  C -->|sold for the stock via Jupiter| V
  V -->|hourly epoch| E[Token holders' wallets]
```

Each harvest splits both sides of the collected fees identically:

| Share | Amount |
|---|---|
| Protocol | `protocol_fee_bps` of the gross, 500 bps by default, at most 1,000 bps (enforced in the program) |
| Referrer | 20% of the protocol share, only for pools created through a referral link |
| Holders | Everything else |

The stock side of the holders' share stays in the pool's holder vault. The project-token side goes to the
protocol's conversion key, which sells it for the stock through Jupiter and deposits the stock into the same vault.
Nothing a holder receives needs to be sold on the project's own chart, and the pool creator keeps no share.

Anything sent directly to a pool's holder vault is paid out to holders in full at the next epoch, with no
protocol share: the program measures harvested fees as the vault's balance change across the Raydium call, so
deposits are never counted as fees.

## Hourly payouts

Every hour, for every pool:

1. **Harvest.** Any key may call `harvest`; the protocol's keeper does it for every pool that has accrued fees.
2. **Convert.** The project-token side is sold for the stock and added to the holder vault. Amounts worth less
   than about $1 wait for the next round.
3. **Snapshot and publish.** The indexer snapshots every holder of the project token, excluding the pool's own
   Raydium vault. It keeps holders at or above the pool's minimum balance, keeps only the largest N if the
   creator set a cap, and splits the vault's unreserved stock pro-rata by balance. The list is committed as a
   Merkle root in a new on-chain epoch, which reserves that amount in the vault. Epochs are skipped while the pot
   is under about $5, and are at least one hour apart (enforced in the program).
4. **Challenge window.** Claims open one hour after publication. Inside that hour the protocol admin (the
   multisig) can cancel a bad root, which releases its reservation.
5. **Pay.** Once the window passes, the keeper executes every leaf. The stock lands in each holder's own
   associated token account with nothing to sign. Holders can also claim themselves on the site. When a holder
   has no token account for the stock yet, the keeper waits until what they are owed across open epochs is worth
   more than the account rent (~$1).
6. **Close.** A week after claims open, or once an epoch is fully claimed or cancelled, anyone may close it.
   Unclaimed stock returns to the vault and rolls into the next epoch.

## Protocol economics

| | |
|---|---|
| Pool creation | 0.05 SOL (capped at 1 SOL in the program) |
| Protocol share of pool fees | 5% default, adjustable per pool by the admin up to 10% |
| Referrals | 20% of the protocol share from pools created through the referrer's link |
| Swaps through the site's Jupiter dialog | 0.5% site fee on top of Jupiter's |
| Trades through the site's pool trade dialog | No site fee; the pool's trade fee applies as normal |

## Copilot

[restock.fun/copilot](https://restock.fun/copilot) walks through the same settings as the create wizard, with preset
questions and answers, and accepts plain English ("half my WIF against Tesla, locked").

- Simple phrases are parsed on your device.
- Anything else is encrypted on our server to the public key of [SolRouter](https://solrouter.com)'s Intel TDX
  enclave, relayed blind, and answered inside the enclave by an open-weight model running on Nosana. The reply
  comes back encrypted.
- The model only chooses among the preset answers. It never picks a mint address and never writes the text you read.
- The result is handed to the wizard's review step, where you see the exact numbers before signing. Nothing is
  signed outside the wizard.

## Regions

Tokenized stocks are not available in some regions, including the United States. restock.fun gates access by the
visitor's country.
