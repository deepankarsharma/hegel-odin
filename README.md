# Hegel for Odin

Property-based testing for [Odin](https://odin-lang.org), built on
[libhegel](https://github.com/hegeldev/hegel-rust) — the native engine behind
the other [Hegel](https://hegel.dev) frontends, itself a port of Hypothesis.

```odin
import "core:slice"
import "core:testing"
import hegel "hegel-odin/hegel"

@(test)
test_sort_matches_builtin :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		xs := hegel.draw(tc, hegel.lists(hegel.integers(int)), "xs")
		expected := slice.clone(xs)
		slice.sort(expected)
		hegel.expect(tc, slice.equal(my_sort(xs), expected))
	})
}
```

When the property fails, Hegel shrinks the input and reports a minimal example:

```
Property failed with minimal example:
    xs: []int = {0, 0}
expected slice.equal(my_sort(xs), expected) to be true
Reproduce with: hegel.Settings{reproduce = "AXicY2VgYGBkZOBiZEBhMAAAAd8AIQ=="}
```

## Setup

Hegel links libhegel statically. Build it once (requires `cargo`):

```
./scripts/build_libhegel.sh
```

This uses `ref/hegel-rust` if present (or `$HEGEL_RUST_DIR`), otherwise it
clones the pinned `libhegel-v0.43.7` tag, then installs the library into
`hegel/libhegel/lib/`. To link a system-installed `libhegel_c` instead, build
with `-define:HEGEL_SYSTEM_LIBRARY=true`.

Run the tests:

```
odin test tests -vet -strict-style
```

## Writing properties

- Draw values with `hegel.draw(tc, generator, "name")`.
- Check with `hegel.expect`, `hegel.expect_value`, `hegel.fail`, `assert`,
  `panic`, or error-level `log` calls — each fails the test case at its
  location. Use `hegel.assume` to discard inputs.
- Inside a property, `context.allocator` and `context.temp_allocator` are an
  arena reset after each test case, so nothing needs freeing.
- A failed check stops the test case with `longjmp`: `defer`s between it and
  the property entry are skipped. Hardware faults (bounds errors, nil
  dereferences) are not caught.
- Configure runs with `hegel.Settings`, e.g.
  `hegel.test(t, prop, {test_cases = 1000, seed = 42})`.
- Use `hegel.run` to get a `Run_Result` instead of failing a `testing.T`.

Generators include `integers`, `floats`, `booleans`, `text`, `characters`,
`byte_slices`, `from_regex`, `emails`, `urls`, `domains`, `lists`,
`unique_lists`, `sets`, `maps`, `arrays`, `dates`, `times`, `date_times`,
`uuids`, `ip_addresses`, `just`, `sampled_from`, `enum_values`, `one_of`,
`optional`, `mapped`, `filtered`, `flat_mapped`, `composite`, and
`recursive`. Stateful systems can be tested with `run_state_machine` and
`Pool`.

## Platform status

Developed and tested on macOS (arm64). The Linux and Windows link lines in
`hegel/libhegel/libhegel.odin` are untested.
