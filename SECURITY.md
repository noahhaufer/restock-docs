# Security

## Reporting a vulnerability

Email **security@restock.fun**. Please include the affected component (program, web app, indexer or keeper), steps
to reproduce, and the impact you believe it has. Do not open a public issue for a vulnerability.

## Scope

- The ReStock program `EyQygGKAxe9Py1MWfGM2KLPQ7FCQZ3RwncxSDiTL412v` on Solana mainnet
- restock.fun and its API routes
- The indexer's public read API

Out of scope: Raydium, Jupiter, Squads, Privy, the stock token issuers, and third-party wallets.

## Authorities

The upgrade authority, protocol admin and treasury are a Squads multisig vault. The keys the off-chain services hold,
and what each one can and cannot do, are listed in [Architecture → Keys and trust](docs/architecture.md#keys-and-trust).

## Known risks

- **Stock token issuers** can freeze or claw back tokens in any account, including ReStock's vaults and Raydium's pools.
- **Unlocked positions** can be withdrawn by their creator. The pool page labels every pool's lock mode.
- **Payout lists are computed off-chain.** The program bounds what a bad list can reserve and gives the multisig a
  one-hour window to cancel it; [Verify it yourself](docs/verify.md#a-payout-list-is-fair) shows how to recompute one.
- **The program is upgradeable** by the multisig.
