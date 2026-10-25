# Conditionals (COND)

A fixed-supply ERC-20 for the Conditionals custom-token launch. The production
contract is [`src/ConditionalsToken.sol`](src/ConditionalsToken.sol).

## Token behavior

| Parameter | Value |
| --- | --- |
| Solidity contract identifier | `ConditionalsToken` |
| Name | `Conditionals` |
| Symbol | `COND` |
| Decimals | `18` |
| Supply in whole tokens | `1,000,000,000` |
| Supply in base units | `1000000000000000000000000000` (`10^27`) |
| Named supply constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None (`[]`) |
| Constructor payment | None; nonpayable |
| Initial recipient | Immediate deployer, `msg.sender` |
| Administrative authority | None |

The constructor mints the entire supply once and emits the standard mint
`Transfer` event. There is no callable mint, burn, owner, initializer, proxy,
upgrade, pause, blacklist, seizure, transfer fee, rebasing, or external dependency.
Supply remains constant. The deployer has ordinary holder rights only.

Transfers deliver the exact requested amount and return `true`; invalid transfers
revert with OpenZeppelin ERC-20 custom errors. Zero-value and self-transfers are
supported; transfers to the zero address are rejected. Contracts can receive
tokens without implementing a callback. Standard `approve`, `allowance`, and
`transferFrom` are supported. Finite allowances decrease when spent;
`type(uint256).max` is treated as unlimited. A failed transfer rolls back any
allowance update. Explicit approval emits `Approval`; spending an allowance does
not emit an additional `Approval` event in the vendored implementation.

## Scope and assumptions

The supplied [Conditionals site](https://conditionals-bay.vercel.app) and
[whitepaper](https://conditionals-bay.vercel.app/docs), read for this assignment,
describe an existing prediction-market application using IMD on Robinhood Chain.
Neither specifies extra COND transfer rules. The URL is therefore treated as
project context for the requested custom token. This deliverable creates COND on
the assignment's Ethereum launch chain; it does not redeploy those markets or
connect to their oracle. The site's settlement fees and IMD burns are not COND
transfer fees. COND grants no programmatic governance, revenue, redemption, or
reward rights in this implementation. No application contracts are needed.

## Reproducible build and tests

Run from the repository root with Foundry and Solidity 0.8.26 installed:

```sh
forge build
FOUNDRY_FUZZ_SEED=0x3848e3ab5842fad44835f6272bcfcc9e2572ae2ee2e83ad174804896e8eadff8 forge test
forge fmt --check
```

`foundry.toml` pins Solidity **0.8.26**, Cancun EVM, optimization with 200 runs,
and `bytecode_hash = "none"`. It does not enable FFI or filesystem permissions.
All Solidity dependencies are vendored as ordinary files in `lib/`; no package
installation, submodule, RPC, fork, or network access is needed to build or test.
See [`DEPENDENCIES.md`](DEPENDENCIES.md) for exact revisions and licenses.

The tests use isolated deployments and synthetic test participants, with no
environment reads or writes. Coverage includes constructor metadata and mint
events, EOA and CREATE2 factory deployment, exact transfers, contract recipients,
zero and self-transfers, approval replacement/revocation, infinite approvals,
allowance isolation, failure atomicity, unauthorized movement, unavailable admin
selectors, and rejection of ordinary ETH payments.

Four fuzz tests run 1,024 cases each. Two stateful invariants run 128 sequences of
64 operations each, checking total supply and conservation plus balances and
allowances against an independent ledger, including failed calls. The launch
test exercises factory distribution, distributor claims, and transfers into and
out of a pool address. It tests token movement, not Uniswap pricing, liquidity
math, or the full production factory. The supplied protected tests require the
separate network launch harness and are left for the independent verifier.

## Deployment parameters and handoff

Deploy `ConditionalsToken` from the compiled artifact
`out/ConditionalsToken.sol/ConditionalsToken.json`, with **no constructor
arguments** and **zero native value**. Its Solidity name is short enough for the
launch's contract registry. There are no linked libraries, initialization calls,
constructor external calls, or chain-specific addresses in the bytecode.

For the authorized launch, the immediate deployer is the IMD factory on Ethereum
(chain ID **1**). All `10^27` base units initially belong to that factory, which
handles distribution. An EOA deploying independently would instead receive the
entire supply itself. `tx.origin` is never used. The constructor performs no
allocation to the requester, distributor, pool, or any application contract.

The assignment supplies these launch settings for the separate manifest step:

| Setting | Supplied launch value |
| --- | --- |
| Pair | IMD, `0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, 18 decimals |
| Pool fee | `12500` (1.25%; a pool fee, not a token tax) |
| Tick spacing | `60` |
| Manifest initial-price field | `79228162514264337593543950336` |
| Initial market cap | `2500000000000000000000` IMD base units (2,500 IMD) |
| Pool share | `poolBps = 5000`: 500,000,000 COND |
| Swarm share handled by factory | 100,000,000 COND |
| Remainder | 400,000,000 COND to `0xee2aaa315cf7ed169f93148d30d24af9318dbb66` |

The launch system derives the actual pool opening price from the supplied market
cap, supply, and deployed token address. These settings are not enforced or
configured by the token. The launch operator owns manifest creation, CREATE2
deployment, allocation, liquidity seeding, source verification, and independent
acceptance checks. No `launch.json`, transaction broadcast, or signing material
is included here.

## After launch

No token setters or configuration steps exist. The launch operator should confirm
the deployed metadata, `10^27` base-unit supply, constructor mint, and exact
distribution against the accepted manifest. Frontend operators must use the
actual deployed Ethereum token address and 18 decimals; this repository contains
no guessed deployment address and makes no change to the existing website.

Holders control transfers and approvals. Integrations should request only the
allowance needed; unlimited allowances expose the holder's current and future
balance to that spender. To replace an existing nonzero allowance safely, users
should first revoke it and wait for confirmation before setting a new value,
while recognizing that an already-authorized spend can precede revocation.

Tokens sent to an inaccessible account, including the token contract itself,
cannot be recovered by an administrator. Ordinary ETH transfers revert, and
there is no ETH or token recovery function. Forced ETH does not affect token
accounting. Neither the token deployer nor an IMD operator can freeze a holder or
repair the token through an upgrade.

## Security review

The implementation adds only a fixed constructor mint to the vendored
OpenZeppelin ERC-20. Review checked the reachable supply-changing paths,
allowance authorization, atomic reverts, absence of external calls and admin
controls, and exact transfer behavior against the supplied security reference.
There are no oracles, signatures, payable operations, callbacks, or AMM logic in
the token. Inherited internal mint/burn helpers are not externally reachable
after construction.

Local validation consists of Foundry build, unit/fuzz/invariant tests, and format
checks. All passed with Solidity 0.8.26 and the specified fuzz seed: 32 unit/fuzz
tests and both invariants (8,192 handler calls; Foundry groups the invariants as
one test suite entry and reports 33 passed tests overall). The compiled runtime
is 1,752 bytes, contains no linked libraries, and passes the protected test's
reachable-opcode scan for DELEGATECALL, CALLCODE, and SELFDESTRUCT.

Slither and Mythril were not run. This is not an independent security audit; the
network's independent review and protected launch checks remain the release gate.
