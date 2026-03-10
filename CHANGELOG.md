# Changelog

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
