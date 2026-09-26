package hegel

import "base:intrinsics"

import lh "libhegel"

/*
A recipe for producing values of type `T`; pass it to `draw`.

Generators are immutable once built and may be drawn from any number of
times. Constructors allocate their state from `context.allocator`, which is
the per-test-case arena inside a property — so building generators inline in
the property, the common case, needs no cleanup. A generator built outside a
property lives in whatever allocator was current; use an arena if you build
many.

To write a generator of your own, prefer `composite`. For full control, fill
in the fields: `draw_proc` receives the test case and `data`, and `label`
identifies the generator to the shrinker (see `label_of`).
*/
Generator :: struct($T: typeid) {
	draw_proc: proc(tc: ^Test_Case, data: rawptr) -> T,
	data:      rawptr,
	label:     Label,
}

// The label for a generator named `name`: the FNV-1a hash of its bytes.
label_of :: #force_inline proc "contextless" ($name: string) -> Label {
	return Label(#hash(name, "fnv64a"))
}

// The label of a generator built from others: a hash of the labels in order.
combine_labels :: proc "contextless" (labels: ..Label) -> Label {
	out: u64
	lh.label_combine(nil, raw_data(labels), len(labels), &out)
	return out
}

// Always produces `value`.
just :: proc(value: $T) -> Generator(T) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		return (^T)(data)^
	}
	return {generate, new_clone(value), label_of("hegel_odin.just")}
}

/*
Picks one of `values`, shrinking towards the first. The slice is copied.
Drawing from an empty slice is an error.
*/
sampled_from :: proc(values: []$T) -> Generator(T) {
	State :: struct {
		values: []T,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		s := (^State)(data)
		if len(s.values) == 0 {
			usage_error(tc, "sampled_from requires at least one value")
		}
		return s.values[draw_index(tc, len(s.values))]
	}
	cloned := make([]T, len(values))
	copy(cloned, values)
	return {generate, new_clone(State{cloned}), label_of("hegel_odin.sampled_from")}
}

// Picks any value of the enum `E`, shrinking towards its first value.
enum_values :: proc($E: typeid) -> Generator(E) where intrinsics.type_is_enum(E) {
	values := make([dynamic]E)
	for v in E {
		append(&values, v)
	}
	return sampled_from(values[:])
}

// Draws from one of the given generators, shrinking towards the first.
one_of :: proc(first: Generator($T), rest: ..Generator(T)) -> Generator(T) {
	State :: struct {
		generators: []Generator(T),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		s := (^State)(data)
		return draw(tc, s.generators[draw_index(tc, len(s.generators))])
	}
	generators := make([]Generator(T), len(rest) + 1)
	generators[0] = first
	copy(generators[1:], rest)
	labels := make([]Label, len(generators) + 1)
	labels[0] = label_of("hegel_odin.one_of")
	for g, i in generators {
		labels[i + 1] = g.label
	}
	label := combine_labels(..labels)
	delete(labels)
	return {generate, new_clone(State{generators}), label}
}

// Produces `nil` or a value from `gen`, shrinking towards `nil`.
optional :: proc(gen: Generator($T)) -> Generator(Maybe(T)) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> Maybe(T) {
		inner := (^Generator(T))(data)
		if draw_index(tc, 2) == 0 {
			return nil
		}
		return draw(tc, inner^)
	}
	return {generate, new_clone(gen), combine_labels(label_of("hegel_odin.optional"), gen.label)}
}

// Transforms every value drawn from `gen` with `f`.
mapped :: proc(gen: Generator($T), f: proc(value: T) -> $U) -> Generator(U) {
	State :: struct {
		gen: Generator(T),
		f:   proc(value: T) -> U,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> U {
		s := (^State)(data)
		return s.f(draw(tc, s.gen))
	}
	return {generate, new_clone(State{gen, f}), combine_labels(label_of("hegel_odin.mapped"), gen.label)}
}

/*
Keeps only the values of `gen` that satisfy `predicate`. A few attempts are
made per draw; when all fail the test case is rejected, so a predicate that
rarely holds trips the `Filter_Too_Much` health check. Prefer constraining the
underlying generator.
*/
filtered :: proc(gen: Generator($T), predicate: proc(value: T) -> bool) -> Generator(T) {
	State :: struct {
		gen:       Generator(T),
		predicate: proc(value: T) -> bool,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		s := (^State)(data)
		for _ in 0 ..< MAX_FILTER_ATTEMPTS {
			start_span(tc, label_of("hegel_odin.filter_attempt"))
			value := draw(tc, s.gen)
			if s.predicate(value) {
				stop_span(tc)
				return value
			}
			stop_span(tc, discard = true)
		}
		reject(tc)
	}
	return {generate, new_clone(State{gen, predicate}), combine_labels(label_of("hegel_odin.filtered"), gen.label)}
}

@(private)
MAX_FILTER_ATTEMPTS :: 3

// Draws a value from `gen`, then draws from the generator `f` builds from it.
flat_mapped :: proc(gen: Generator($T), f: proc(value: T) -> Generator($U)) -> Generator(U) {
	State :: struct {
		gen: Generator(T),
		f:   proc(value: T) -> Generator(U),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> U {
		s := (^State)(data)
		return draw(tc, s.f(draw(tc, s.gen)))
	}
	return {generate, new_clone(State{gen, f}), combine_labels(label_of("hegel_odin.flat_mapped"), gen.label)}
}

/*
A generator defined by a procedure that draws from other generators.

	Person :: struct { name: string, age: int }

	people :: proc() -> hegel.Generator(Person) {
		return hegel.composite(proc(tc: ^hegel.Test_Case) -> Person {
			return {
				name = hegel.draw(tc, hegel.text(max_size = 20)),
				age  = hegel.draw(tc, hegel.integers(int, 0, 120)),
			}
		})
	}
*/
composite :: proc(f: proc(tc: ^Test_Case) -> $T) -> Generator(T) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		f := (proc(tc: ^Test_Case) -> T)(data)
		return f(tc)
	}
	return {generate, rawptr(f), label_of("hegel_odin.composite")}
}

// Like `composite`, but passes `data` along to `f`. `data` must outlive the
// generator.
composite_with_data :: proc(data: ^$D, f: proc(tc: ^Test_Case, data: ^D) -> $T) -> Generator(T) {
	State :: struct {
		data: ^D,
		f:    proc(tc: ^Test_Case, data: ^D) -> T,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		s := (^State)(data)
		return s.f(tc, s.data)
	}
	return {generate, new_clone(State{data, f}), label_of("hegel_odin.composite")}
}

// An integer in `[0, n)`, shrinking towards 0.
@(private)
draw_index :: proc(tc: ^Test_Case, n: int) -> int {
	out: i64
	check(tc, lh.generate_integer(tc._ctx, tc._handle, 0, i64(n - 1), &out))
	return int(out)
}
