package hegel

import "base:intrinsics"

import lh "libhegel"

/*
Slices of `min_size` to `max_size` elements drawn from `elements`. The engine
chooses the length, so lists shrink by deleting elements as well as by
shrinking them.

	hegel.lists(hegel.integers(int))
	hegel.lists(hegel.text(), min_size = 1, max_size = 5)
*/
lists :: proc(elements: Generator($T), min_size := 0, max_size: Maybe(int) = nil) -> Generator([]T) {
	State :: struct {
		elements: Generator(T),
		min_size: int,
		max_size: Maybe(int),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> []T {
		s := (^State)(data)
		coll := new_collection(tc, "lists", s.min_size, s.max_size)
		out := make([dynamic]T, 0, s.min_size)
		for collection_more(tc, coll) {
			append(&out, draw(tc, s.elements))
		}
		return out[:]
	}
	state := State{elements, min_size, max_size}
	return {generate, new_clone(state), combine_labels(label_of("hegel_odin.lists"), elements.label)}
}

/*
Slices of distinct elements. Duplicates drawn along the way are rejected and
replaced, so the size bounds still hold.
*/
unique_lists :: proc(elements: Generator($T), min_size := 0, max_size: Maybe(int) = nil) -> Generator([]T) where intrinsics.type_is_comparable(T) {
	State :: struct {
		elements: Generator(T),
		min_size: int,
		max_size: Maybe(int),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> []T {
		s := (^State)(data)
		coll := new_collection(tc, "unique_lists", s.min_size, s.max_size)
		seen := make(map[T]struct{})
		out := make([dynamic]T, 0, s.min_size)
		for collection_more(tc, coll) {
			value := draw(tc, s.elements)
			if value in seen {
				collection_reject(tc, coll, "duplicate element")
				continue
			}
			seen[value] = {}
			append(&out, value)
		}
		return out[:]
	}
	state := State{elements, min_size, max_size}
	return {generate, new_clone(state), combine_labels(label_of("hegel_odin.unique_lists"), elements.label)}
}

// Sets, represented as `map[T]struct{}`, of `min_size` to `max_size` elements.
sets :: proc(elements: Generator($T), min_size := 0, max_size: Maybe(int) = nil) -> Generator(map[T]struct{}) {
	State :: struct {
		elements: Generator(T),
		min_size: int,
		max_size: Maybe(int),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> map[T]struct{} {
		s := (^State)(data)
		coll := new_collection(tc, "sets", s.min_size, s.max_size)
		out := make(map[T]struct{})
		for collection_more(tc, coll) {
			value := draw(tc, s.elements)
			if value in out {
				collection_reject(tc, coll, "duplicate element")
				continue
			}
			out[value] = {}
		}
		return out
	}
	state := State{elements, min_size, max_size}
	return {generate, new_clone(state), combine_labels(label_of("hegel_odin.sets"), elements.label)}
}

// Maps with `min_size` to `max_size` entries, keys drawn from `keys` and
// values from `values`.
maps :: proc(keys: Generator($K), values: Generator($V), min_size := 0, max_size: Maybe(int) = nil) -> Generator(map[K]V) {
	State :: struct {
		keys:     Generator(K),
		values:   Generator(V),
		min_size: int,
		max_size: Maybe(int),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> map[K]V {
		s := (^State)(data)
		coll := new_collection(tc, "maps", s.min_size, s.max_size)
		out := make(map[K]V)
		for collection_more(tc, coll) {
			key := draw(tc, s.keys)
			if key in out {
				collection_reject(tc, coll, "duplicate key")
				continue
			}
			out[key] = draw(tc, s.values)
		}
		return out
	}
	state := State{keys, values, min_size, max_size}
	return {generate, new_clone(state), combine_labels(label_of("hegel_odin.maps"), keys.label, values.label)}
}

// Fixed-size arrays of `N` elements.
arrays :: proc(elements: Generator($T), $N: int) -> Generator([N]T) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> (out: [N]T) {
		elements := (^Generator(T))(data)
		for &x in out {
			x = draw(tc, elements^)
		}
		return
	}
	return {generate, new_clone(elements), combine_labels(label_of("hegel_odin.arrays"), elements.label)}
}

/*
The engine side of a variable-length draw: call `collection_more` before each
element and stop when it returns false. Use it to write generators for your
own container types.
*/
Collection :: struct {
	handle: ^lh.Collection,
}

new_collection :: proc(tc: ^Test_Case, name: string, min_size: int, max_size: Maybe(int)) -> Collection {
	lo, hi := size_bounds(tc, name, min_size, max_size)
	handle: ^lh.Collection
	check(tc, lh.new_collection(tc._ctx, tc._handle, lo, hi, &handle))
	own(tc, handle)
	return {handle}
}

// Whether the engine wants another element.
collection_more :: proc(tc: ^Test_Case, coll: Collection) -> bool {
	more: bool
	check(tc, lh.collection_more(tc._ctx, tc._handle, coll.handle, &more))
	return more
}

// Discards the element just drawn; it does not count towards the size.
collection_reject :: proc(tc: ^Test_Case, coll: Collection, why := "") {
	check(tc, lh.collection_reject(tc._ctx, tc._handle, coll.handle, cstr(why)))
}
