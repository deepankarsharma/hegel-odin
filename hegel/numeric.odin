package hegel

import "base:intrinsics"

import lh "libhegel"

/*
Integers of type `T` in `[min_value, max_value]`, defaulting to the whole
range of `T`. Shrinks towards zero (or the bound nearest it).

	hegel.integers(int)
	hegel.integers(u8, max_value = 9)
	hegel.integers(i128, -1 << 100, 1 << 100)
*/
integers :: proc($T: typeid, min_value: Maybe(T) = nil, max_value: Maybe(T) = nil) -> Generator(T) where intrinsics.type_is_integer(T) {
	State :: struct {
		lo, hi: T,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		s := (^State)(data)
		if s.lo > s.hi {
			usage_error(tc, "integers: min_value %v is greater than max_value %v", s.lo, s.hi)
		}
		when size_of(T) < 8 || (size_of(T) == 8 && !intrinsics.type_is_unsigned(T)) {
			out: i64
			check(tc, lh.generate_integer(tc._ctx, tc._handle, i64(s.lo), i64(s.hi), &out))
			return T(out)
		} else {
			return draw_big_integer(tc, s.lo, s.hi)
		}
	}
	state := State{min_value.? or_else min(T), max_value.? or_else max(T)}
	return {generate, new_clone(state), label_of("hegel_odin.integers")}
}

// Bounds outside `i64` go through the engine's arbitrary-precision draw, as
// two's-complement little-endian bytes with a spare sign byte.
@(private)
draw_big_integer :: proc(tc: ^Test_Case, lo, hi: $T) -> T {
	Wide :: u128 when intrinsics.type_is_unsigned(T) else i128
	encode :: proc(v: Wide) -> (bytes: [17]u8) {
		le := transmute([16]u8)(Wide(v))
		copy(bytes[:16], le[:])
		bytes[16] = 0xff if v < 0 else 0
		return
	}
	lo_bytes, hi_bytes := encode(Wide(lo)), encode(Wide(hi))
	out: [17]u8
	out_len: uint
	check(tc, lh.generate_integer_big(tc._ctx, tc._handle, raw_data(lo_bytes[:]), len(lo_bytes), raw_data(hi_bytes[:]), len(hi_bytes), raw_data(out[:]), len(out), &out_len))
	le: [16]u8
	copy(le[:], out[:16])
	return T(transmute(Wide)le)
}

/*
Floats of type `f32` or `f64`.

Without bounds, NaN and infinities are included unless disabled. With a bound,
NaN defaults to excluded, and infinity is only possible towards an unbounded
side. `exclude_min` / `exclude_max` make the bounds exclusive.

	hegel.floats(f64)
	hegel.floats(f64, 0, 1, exclude_max = true)
	hegel.floats(f32, allow_nan = false, allow_infinity = false)
*/
floats :: proc(
	$T: typeid,
	min_value: Maybe(T) = nil,
	max_value: Maybe(T) = nil,
	allow_nan: Maybe(bool) = nil,
	allow_infinity: Maybe(bool) = nil,
	exclude_min := false,
	exclude_max := false,
) -> Generator(T) where T == f32 || T == f64 {
	State :: struct {
		lo, hi:                   f64,
		has_lo, has_hi:           bool,
		allow_nan, allow_inf:     bool,
		exclude_min, exclude_max: bool,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		s := (^State)(data)
		if s.allow_nan && (s.has_lo || s.has_hi) {
			usage_error(tc, "floats: allow_nan cannot be combined with min_value or max_value")
		}
		if s.allow_inf && s.has_lo && s.has_hi {
			usage_error(tc, "floats: allow_infinity cannot be combined with both min_value and max_value")
		}
		smallest_nonzero := f64(transmute(f32)u32(1)) when T == f32 else transmute(f64)u64(1)
		out: f64
		check(tc, lh.generate_float(tc._ctx, tc._handle, 8 * size_of(T), s.lo, s.hi, s.allow_nan, s.allow_inf, s.exclude_min, s.exclude_max, smallest_nonzero, &out))
		return T(out)
	}
	lo, has_lo := min_value.?
	hi, has_hi := max_value.?
	state := State {
		lo          = f64(lo) if has_lo else -INF,
		hi          = f64(hi) if has_hi else INF,
		has_lo      = has_lo,
		has_hi      = has_hi,
		allow_nan   = allow_nan.? or_else (!has_lo && !has_hi),
		allow_inf   = allow_infinity.? or_else (!has_lo || !has_hi),
		exclude_min = exclude_min,
		exclude_max = exclude_max,
	}
	return {generate, new_clone(state), label_of("hegel_odin.floats")}
}

@(private)
INF :: 0h7ff00000_00000000

// `true` with probability `p`, shrinking towards `false`.
booleans :: proc(p := 0.5) -> Generator(bool) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> bool {
		p := (^f64)(data)^
		if !(p >= 0 && p <= 1) {
			usage_error(tc, "booleans: p must be in [0, 1], got %v", p)
		}
		out: bool
		check(tc, lh.generate_boolean(tc._ctx, tc._handle, p, false, false, &out))
		return out
	}
	return {generate, new_clone(p), label_of("hegel_odin.booleans")}
}
