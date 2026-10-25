# Vendored dependencies

All required Solidity sources are included as ordinary files. No submodules,
package manager, or downloads are needed during verification. Upstream source
files and license text are unmodified.

| Library | Version | Exact upstream commit | Included files |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3) | v5.0.2 | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | Five Solidity files comprising ERC20 and its dependencies; MIT license |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | `src/` and MIT/Apache-2.0 licenses; tests only |

OpenZeppelin's included Solidity files are `ERC20.sol`, `IERC20.sol`,
`IERC20Metadata.sol`, `Context.sol`, and `draft-IERC6093.sol`.
Only their ERC-20 functionality is used. The full library's additional token
extensions, access control, and upgrade modules are not included.

Sources were extracted from GitHub's codeload archives for the exact commits
above. Archive SHA-256 values at retrieval:

```text
OpenZeppelin: 4a9c091852052f4319173629e0bf0b5cdf7a39d70e5e2298a7a6a149eff9f385
forge-std:    a387f7c2a10387f889b0d18b999cfa667a5273ac11cc11e18923022eb8b24bc3
```

License copies: [`lib/openzeppelin-contracts/LICENSE`](lib/openzeppelin-contracts/LICENSE),
[`lib/forge-std/LICENSE-MIT`](lib/forge-std/LICENSE-MIT), and
[`lib/forge-std/LICENSE-APACHE`](lib/forge-std/LICENSE-APACHE).
