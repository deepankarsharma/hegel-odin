# AGENTS.md

Guidance for coding agents working in this repository.

## Commits and pull requests

- Do not add any Claude, Anthropic, or AI-assistant attribution to commit
  messages, pull request descriptions, code comments, or any other files.
- Do not add a `Co-Authored-By` trailer (or any similar trailer) naming an AI
  assistant or yourself.

## Layout

- `hegel/` — the `hegel` package: the public property-testing API.
- `hegel/libhegel/` — raw bindings to libhegel's C ABI (`hegel.h` in
  hegel-rust's `hegel-c` crate). `lib/` holds the built static library and is
  not committed.
- `tests/` — the test suite (`odin test tests`).
- `scripts/build_libhegel.sh` — builds libhegel from `ref/hegel-rust` (or
  clones the pinned tag) and installs it into `hegel/libhegel/lib/`.
- `integration_test/` — a small geometry library property-tested against
  hegel-odin fetched from GitHub (`integration_test/setup.sh`, then
  `odin test tests -vet -strict-style` from that directory).
- `ref/` — reference Hegel frontends for other languages; git-ignored.

## Build and test

```
./scripts/build_libhegel.sh
odin test tests -vet -strict-style
```

## Test conventions

- Tests import the package as `hg` (`import hg "../hegel"`) and call
  `hg.draw`, `hg.expect`, and so on. String literals that quote library output
  (e.g. `hegel.Settings{...}`) keep the real name.
- Write each property as a named `proc(tc: ^hg.Test_Case)` registered with a
  one-line test: `@(test) test_x :: proc(t: ^testing.T) { hg.test(t, x) }`.
  Keep one property per test; put checks of a failing run (`hg.run`,
  `minimal`) in their own test, where an inline `proc` literal is fine.
