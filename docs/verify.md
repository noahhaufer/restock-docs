# Verify it yourself

[← Back](../README.md)

The source is closed, but everything that moves funds happens on-chain. This page lists the addresses and the
checks anyone can run.

## Mainnet addresses

| What | Address |
|---|---|
| ReStock program | [`EyQygGKAxe9Py1MWfGM2KLPQ7FCQZ3RwncxSDiTL412v`](https://solscan.io/account/EyQygGKAxe9Py1MWfGM2KLPQ7FCQZ3RwncxSDiTL412v) |
| Upgrade authority, admin, treasury (Squads vault) | [`7upasAXvUZHyCkXQC4CQoPZGVidbGCdGp9zX8svyoATq`](https://solscan.io/account/7upasAXvUZHyCkXQC4CQoPZGVidbGCdGp9zX8svyoATq) |
| Indexer authority (publishes epochs, converts fees) | [`7sndakbyRLvBezANREAJTS7jGC1pmTkMa8Go8tFLFXxa`](https://solscan.io/account/7sndakbyRLvBezANREAJTS7jGC1pmTkMa8Go8tFLFXxa) |
| Keeper (pays for harvests, claims, closes) | [`FFv5vRrNtVZzRHJsjsXR72C2pNW2wRx4XZdHsUwgENVJ`](https://solscan.io/account/FFv5vRrNtVZzRHJsjsXR72C2pNW2wRx4XZdHsUwgENVJ) |
| Protocol address lookup table | [`AcT5A23P1hhTqyEGZaCAxCZ1bja5drGiV9rLdBCA9v3D`](https://solscan.io/account/AcT5A23P1hhTqyEGZaCAxCZ1bja5drGiV9rLdBCA9v3D) |
| Raydium CLMM program | [`CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK`](https://solscan.io/account/CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK) |
| Raydium 1% fee tier (AmmConfig) | [`A1BBtTYJd4i3xU8D6Tc2FzU6ZN4oXZWXKZnCxwbHXr8x`](https://solscan.io/account/A1BBtTYJd4i3xU8D6Tc2FzU6ZN4oXZWXKZnCxwbHXr8x) |
| Raydium 2% fee tier (AmmConfig) | [`Gex2NJRS3jVLPfbzSFM5d5DRsNoL5ynnwT1TXoDEhanz`](https://solscan.io/account/Gex2NJRS3jVLPfbzSFM5d5DRsNoL5ynnwT1TXoDEhanz) |
| Meteora DAMM v2 (cp-amm) program | [`cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG`](https://solscan.io/account/cpamdpZCGKUy5JxQXB4dcpGPiikHawvSWAd6mEn1sGG) |

## Who controls the program

```bash
solana program show EyQygGKAxe9Py1MWfGM2KLPQ7FCQZ3RwncxSDiTL412v -um
```

`Authority` should be the Squads vault above. Open it in [Squads](https://app.squads.so) to see the members, the
threshold and every past proposal.

## The deployed binary

```bash
solana program dump EyQygGKAxe9Py1MWfGM2KLPQ7FCQZ3RwncxSDiTL412v restock.so -um
strings restock.so | grep RESTOCK_BUILD
```

A mainnet build prints `RESTOCK_BUILD:raydium=mainnet` and `RESTOCK_BUILD:epochs=slow`. Anything else would mean a
test build with shortened challenge windows. The binary also embeds a `security.txt`
(`strings restock.so | grep -A12 '=======BEGIN SECURITY.TXT'`) with contact details.

## A pool's position is locked

For a locked pool:

1. Find the pool's position NFT mint (shown on the pool page, and in the `PoolCreated` event).
2. Look up who holds that NFT. It should be the PDA `["lock", pool]` of the ReStock program.
3. The program has no instruction that moves an NFT out of that PDA, and its only venue call for the position
   collects fees (Raydium: liquidity 0; Meteora: `claim_position_fee`). Every transaction touching the position is
   on the explorer.

You can derive the vault address with `@solana/web3.js`:

```ts
import { PublicKey } from "@solana/web3.js";
const PROGRAM = new PublicKey("EyQygGKAxe9Py1MWfGM2KLPQ7FCQZ3RwncxSDiTL412v");
const [lockVault] = PublicKey.findProgramAddressSync([Buffer.from("lock"), pool.toBuffer()], PROGRAM);
const [feeAuthority] = PublicKey.findProgramAddressSync([Buffer.from("fees"), pool.toBuffer()], PROGRAM);
// The holder vault is feeAuthority's associated token account for the pool's stock mint.
```

## Harvests pay what they should

Every `harvest` transaction emits a `Harvested` event with the collected amounts and each share: protocol,
referrer, holders (stock) and the project-token side sent for conversion. Check that:

- the protocol share is the pool's `protocol_fee_bps` of the gross (500 by default),
- the stock holders' share arrived in the pool's holder vault,
- the project-token side went to the indexer authority, and a later Jupiter swap by that key deposits the
  proceeds, in the stock, into the same holder vault (Raydium pools; a Meteora pool opened by ReStock has no
  project-token side).

## A payout list is fair

Each `EpochPublished` event carries the Merkle root, the total and the number of claimants. To check a list:

1. Take a snapshot of the project token's holders at the publish slot. Exclude the pool's venue vaults, apply the
   pool's minimum balance and holder cap.
2. Split the total pro-rata by balance, rounding down, sorting holders by address to assign claim indexes.
3. Build the tree with the leaf format in [Program reference](program.md#payout-merkle-tree) and compare the root.

Your own entry and proof are served by the site: `restock.fun` shows each epoch you are part of on the pool page.
Every paid leaf emits a `Claimed` event naming the holder, the amount and the epoch.

## Nothing is left behind

`close_epoch` emits `EpochClosed` with the unclaimed amount, which returns to the holder vault and is included in
the next epoch's total.
