/*
Hegel is a property-based testing library for Odin, built on libhegel — the
native engine behind Hegel's frontends for Rust, Go, C++, and others, itself a
port of Hypothesis.

A property is a procedure that draws inputs and checks that the code under
test behaves. Hegel runs it against many generated inputs and, when one
fails, shrinks it to a minimal example:

	import "core:slice"
	import "core:testing"
	import hegel "hegel-odin/hegel"

	@(test) test_sort_keeps_length :: proc(t: ^testing.T) { hegel.test(t, sort_keeps_length) }

	sort_keeps_length :: proc(tc: ^hegel.Test_Case) {
		xs := hegel.draw(tc, hegel.lists(hegel.integers(int)), "xs")
		ys := slice.clone(xs)
		slice.sort(ys)
		hegel.expect(tc, len(xs) == len(ys))
	}

A failing property is reported through `core:testing` with the values that
produced the failure:

	Property failed with minimal example:
	    xs: []int = {0, 0}
	expected len(xs) == len(ys) to be true

Checking properties: inside a property, `assert`, `panic`, `hegel.expect`,
`hegel.fail`, and error-level `log` messages (including a failed
`testing.expect`) each fail the test case at their location. Failures at
different locations are treated as different bugs. `hegel.assume` discards
test cases that do not meet a precondition.

Memory: inside a property, `context.allocator` and `context.temp_allocator`
are an arena reset after every test case. Drawn values and generators built in
the property are freed automatically; nothing needs a `defer delete`.

Control flow: a failed check stops the test case with a non-local jump, so
`defer` statements between it and the property's entry do not run. Hardware
faults (out-of-bounds indexing, nil dereferences) are not caught and still
abort the test.

Generators: numbers (`integers`, `floats`, `booleans`), text (`text`,
`characters`, `byte_slices`, `from_regex`, `emails`, `urls`, `domains`),
collections (`lists`, `unique_lists`, `sets`, `maps`, `arrays`), formats
(`dates`, `times`, `date_times`, `uuids`, `ip_addresses`), and combinators
(`just`, `sampled_from`, `enum_values`, `one_of`, `optional`, `mapped`,
`filtered`, `flat_mapped`, `composite`, `recursive`). Stateful systems can be
tested as state machines with `run_state_machine` and `Pool`.

Engine: link the static libhegel built by `scripts/build_libhegel.sh`.
*/
package hegel
