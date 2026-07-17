# Changelog

## [1.2.1](https://github.com/nicolasgarcia214/Ephemera/compare/v1.2.0...v1.2.1) (2026-07-17)


### Bug Fixes

* 🐛 harden runtime lifecycles and release contracts ([0f5826e](https://github.com/nicolasgarcia214/Ephemera/commit/0f5826e09e6b3ce10bfa1d1897f374727b8950fc))

## [1.2.0](https://github.com/nicolasgarcia214/Ephemera/compare/v1.1.0...v1.2.0) (2026-07-15)


### Features

* ✨ disclose saved-chat trimming and harden Ollama probes ([cf21f64](https://github.com/nicolasgarcia214/Ephemera/commit/cf21f64b9e45ca00971e3a2598464b0e67d4870a))


### Bug Fixes

* **anthropic:** request visible thinking summaries ([50c4ba8](https://github.com/nicolasgarcia214/Ephemera/commit/50c4ba8264268f1024ac8a221f2f429e5d058a3e))
* **anthropic:** request visible thinking summaries ([2ea3cad](https://github.com/nicolasgarcia214/Ephemera/commit/2ea3cad73c52b49a249c6f5558c26abf33af1a45))
* bound panel width to active screen ([#9017](https://github.com/nicolasgarcia214/Ephemera/issues/9017)) ([6e1c12d](https://github.com/nicolasgarcia214/Ephemera/commit/6e1c12d5733fce5ab1173cb74414a5f5dcbbb584))
* capture trailing OpenAI stream usage ([3d1b982](https://github.com/nicolasgarcia214/Ephemera/commit/3d1b982dd38f86e2e621c7c4152859e533a05ef6))
* **chat:** unify submission safety gates ([de68168](https://github.com/nicolasgarcia214/Ephemera/commit/de68168e0dcd78daeabc3b5382133e68d1aaa915))
* confirm conversation export completion ([e4d78b1](https://github.com/nicolasgarcia214/Ephemera/commit/e4d78b1b25230e400c638be4f2b3c3c2babd291b))
* handle in-stream provider failures ([13cd9bc](https://github.com/nicolasgarcia214/Ephemera/commit/13cd9bcd7b96d890639eb0603e6fe021025c181a))
* honor DMS injected property contract ([#9019](https://github.com/nicolasgarcia214/Ephemera/issues/9019)) ([e6a9a6a](https://github.com/nicolasgarcia214/Ephemera/commit/e6a9a6a9ca49abc856750a77760d78228ccbe0f4))
* keep keyring cache synchronized ([62b458a](https://github.com/nicolasgarcia214/Ephemera/commit/62b458a99ab70812874357fed20aab6a49869c28))
* **markdown:** invalidate cache on theme changes ([52ad56e](https://github.com/nicolasgarcia214/Ephemera/commit/52ad56e8e1fd2a0c475901059343f07d5657dbc3))
* **ollama:** bound probe response collectors ([21c79a6](https://github.com/nicolasgarcia214/Ephemera/commit/21c79a634672d808138f4548090736cf8d6b534b))
* **ollama:** preserve lifecycle ownership ([94b1391](https://github.com/nicolasgarcia214/Ephemera/commit/94b139167e3226ef8329cd3eed2cd2cce54701da))
* **ollama:** synchronize endpoint URL updates ([aed56ed](https://github.com/nicolasgarcia214/Ephemera/commit/aed56ed2654a405f96ac230a587dacf4b0d51686))
* **persistence:** bound saved chat state ([10d1d42](https://github.com/nicolasgarcia214/Ephemera/commit/10d1d422d15480c1b6242b54ad67bdb6e451616c))
* **persistence:** make chat state atomic ([4c52136](https://github.com/nicolasgarcia214/Ephemera/commit/4c521364b615f9dabf65b0a1001bd76f45148d2a))
* **providers:** align advertised API contracts ([80e773e](https://github.com/nicolasgarcia214/Ephemera/commit/80e773eb1c23b1b1dfb360921594c2e8567b553c))
* **providers:** align advertised API contracts ([10d5f1a](https://github.com/nicolasgarcia214/Ephemera/commit/10d5f1adc9c354b940ef28a0313334fe9bae668b))
* **providers:** block remote plaintext custom URLs ([f34f236](https://github.com/nicolasgarcia214/Ephemera/commit/f34f2360d90c63e8fc2df2f2c31e4a87662f13f9))
* **providers:** block remote plaintext custom URLs ([92b6731](https://github.com/nicolasgarcia214/Ephemera/commit/92b6731ca397e97963de3ea5b7f20d9f42aa4c90))
* secure clipboard and curl process inputs ([#9007](https://github.com/nicolasgarcia214/Ephemera/issues/9007)) ([529e563](https://github.com/nicolasgarcia214/Ephemera/commit/529e5631efc923ad526fedaa2a3808a8dcf5be83))
* **services:** 🐛 recover from failed process starts and tighten probe accuracy ([b0ddae4](https://github.com/nicolasgarcia214/Ephemera/commit/b0ddae4b41708d4bfcfe2eed4b02048206b80956))
* **streaming:** snapshot request settings per stream ([5af8f09](https://github.com/nicolasgarcia214/Ephemera/commit/5af8f090663c161dc11b502a032690bb6a426cef))

## [1.1.0](https://github.com/nicolasgarcia214/Ephemera/compare/v1.0.1...v1.1.0) (2026-05-01)


### Features

* **ollama:** ✨ add configurable thinking mode for Ollama provider ([17c1661](https://github.com/nicolasgarcia214/Ephemera/commit/17c166148bae165ea941a40e26ae4d31b2ddcdd3))

## [1.0.1](https://github.com/nicolasgarcia214/Ephemera/compare/v1.0.0...v1.0.1) (2026-03-16)


### Bug Fixes

* **keyring:** 🐛 use onStreamFinished for keyring lookup output ([f998731](https://github.com/nicolasgarcia214/Ephemera/commit/f998731e8387716494d1fd3d2e154bab5f9bd3bd))

## [1.0.0](https://github.com/nicolasgarcia214/Ephemera/compare/v0.1.5...v1.0.0) (2026-03-10)


### ⚠ BREAKING CHANGES

* **core:** Backoff.isInCooldown() signature changed from (lastErrorTime, consecutiveErrors, baseDelayMs, maxDelayMs) to a single cooldownUntil timestamp. Use computeCooldownUntil() at error time.

### Features

* **core:** ✨ add unlimited tokens mode and improve chat UX ([e14112a](https://github.com/nicolasgarcia214/Ephemera/commit/e14112af63d8ac4123ac7d4094b524a9bd13bb46))
* **core:** ✨ resolve 18 audit findings and stabilize for v1.0 ([dde2869](https://github.com/nicolasgarcia214/Ephemera/commit/dde2869f00bd0814888d5d175996464446da3582))
* **security:** 🔒 add system keyring integration and harden curl requests ([85fd6a5](https://github.com/nicolasgarcia214/Ephemera/commit/85fd6a553d784ef0bc4760a3864035880a07c592))
* **streaming:** ✨ add API-reported token counts for accurate tok/s stats ([3880c59](https://github.com/nicolasgarcia214/Ephemera/commit/3880c59980826139bc21b5233839bc72608bc9f5))
* **ui:** ✨ add hardcoded model lists for provider dropdowns ([024e2e6](https://github.com/nicolasgarcia214/Ephemera/commit/024e2e6ac82e72ae097bec368e7c8ee2e17511cb))
* **ui:** ✨ add streaming stats, model selector polish, and ollama boot banner ([e5f75af](https://github.com/nicolasgarcia214/Ephemera/commit/e5f75af0f2e06a6cd836942ed415ae37aa8a8040))


### Bug Fixes

* **core:** 🐛 resolve critical bugs and expand test coverage ([670b81a](https://github.com/nicolasgarcia214/Ephemera/commit/670b81a1d6d36a16d1f30c8226ffec4b83060220))
* **core:** 🐛🔒✨ resolve critical bugs, harden security, and add temperature clamping ([bc3e82c](https://github.com/nicolasgarcia214/Ephemera/commit/bc3e82cd180207edbe793a441641f9139cf97002))
* **markdown:** 🐛 restore inline code after protected blocks ([d726cc8](https://github.com/nicolasgarcia214/Ephemera/commit/d726cc80a8cb73ced8ab367d3f6ccba433635c0b))
* **readme:** 🐛 use query param badge URL to prevent 404 after version bump ([05718bf](https://github.com/nicolasgarcia214/Ephemera/commit/05718bfe7c4ebfe4398fd222815202272dbbef7c))
* **settings:** 🐛 fix custom system prompt not syncing to service ([bafe2b0](https://github.com/nicolasgarcia214/Ephemera/commit/bafe2b0b35d91222f3a3ed15c5cda6c45fa76675))


### Refactoring

* ♻️ restructure project into src/ directory hierarchy ([9fd5436](https://github.com/nicolasgarcia214/Ephemera/commit/9fd54365b7fb5175e52631d5208a407fe78d33c7))
* **core:** ♻️ decompose monoliths into coordinator pattern with child services ([bc3122d](https://github.com/nicolasgarcia214/Ephemera/commit/bc3122dd8ea93055be96f4ecb13d9e3219a0346c))
* **core:** ♻️ decompose settings, extract JS modules, fix bugs, add chat features ([bad75c0](https://github.com/nicolasgarcia214/Ephemera/commit/bad75c0216fae41717e3374ef39d03a35ef2359b))


### Documentation

* 📝 condense AGENTS.md and trim README ([169092c](https://github.com/nicolasgarcia214/Ephemera/commit/169092c05c4ffeb119591bcbdef6a21c67ce13c9))
* add badges to README and create .gitignore ([987d8d7](https://github.com/nicolasgarcia214/Ephemera/commit/987d8d761bd3a687803f256fb6d0870c11e03203))

## [0.1.5](https://github.com/nicolasgarcia214/Ephemera/compare/v0.1.4...v0.1.5) (2026-03-09)


### Features

* **security:** 🔒 add system keyring integration and harden curl requests ([85fd6a5](https://github.com/nicolasgarcia214/Ephemera/commit/85fd6a553d784ef0bc4760a3864035880a07c592))
* **streaming:** ✨ add API-reported token counts for accurate tok/s stats ([3880c59](https://github.com/nicolasgarcia214/Ephemera/commit/3880c59980826139bc21b5233839bc72608bc9f5))
* **ui:** ✨ add hardcoded model lists for provider dropdowns ([024e2e6](https://github.com/nicolasgarcia214/Ephemera/commit/024e2e6ac82e72ae097bec368e7c8ee2e17511cb))


### Refactoring

* **core:** ♻️ decompose monoliths into coordinator pattern with child services ([bc3122d](https://github.com/nicolasgarcia214/Ephemera/commit/bc3122dd8ea93055be96f4ecb13d9e3219a0346c))

## [0.1.4](https://github.com/nicolasgarcia214/Ephemera/compare/v0.1.3...v0.1.4) (2026-03-07)


### Features

* **ui:** ✨ add streaming stats, model selector polish, and ollama boot banner ([e5f75af](https://github.com/nicolasgarcia214/Ephemera/commit/e5f75af0f2e06a6cd836942ed415ae37aa8a8040))


### Bug Fixes

* **core:** 🐛 resolve critical bugs and expand test coverage ([670b81a](https://github.com/nicolasgarcia214/Ephemera/commit/670b81a1d6d36a16d1f30c8226ffec4b83060220))
* **settings:** 🐛 fix custom system prompt not syncing to service ([bafe2b0](https://github.com/nicolasgarcia214/Ephemera/commit/bafe2b0b35d91222f3a3ed15c5cda6c45fa76675))


### Refactoring

* **core:** ♻️ decompose settings, extract JS modules, fix bugs, add chat features ([bad75c0](https://github.com/nicolasgarcia214/Ephemera/commit/bad75c0216fae41717e3374ef39d03a35ef2359b))

## [0.1.3](https://github.com/nicolasgarcia214/Ephemera/compare/v0.1.2...v0.1.3) (2026-03-02)


### Features

* **core:** ✨ add unlimited tokens mode and improve chat UX ([e14112a](https://github.com/nicolasgarcia214/Ephemera/commit/e14112af63d8ac4123ac7d4094b524a9bd13bb46))

## [0.1.2](https://github.com/nicolasgarcia214/Ephemera/compare/v0.1.1...v0.1.2) (2026-02-28)


### Bug Fixes

* **markdown:** 🐛 restore inline code after protected blocks ([d726cc8](https://github.com/nicolasgarcia214/Ephemera/commit/d726cc80a8cb73ced8ab367d3f6ccba433635c0b))
* **readme:** 🐛 use query param badge URL to prevent 404 after version bump ([05718bf](https://github.com/nicolasgarcia214/Ephemera/commit/05718bfe7c4ebfe4398fd222815202272dbbef7c))

## [0.1.1](https://github.com/nicolasgarcia214/Ephemera/compare/v0.1.0...v0.1.1) (2026-02-27)


### Bug Fixes

* **core:** 🐛🔒✨ resolve critical bugs, harden security, and add temperature clamping ([bc3e82c](https://github.com/nicolasgarcia214/Ephemera/commit/bc3e82cd180207edbe793a441641f9139cf97002))


### Refactoring

* ♻️ restructure project into src/ directory hierarchy ([9fd5436](https://github.com/nicolasgarcia214/Ephemera/commit/9fd54365b7fb5175e52631d5208a407fe78d33c7))


### Documentation

* 📝 condense AGENTS.md and trim README ([169092c](https://github.com/nicolasgarcia214/Ephemera/commit/169092c05c4ffeb119591bcbdef6a21c67ce13c9))
