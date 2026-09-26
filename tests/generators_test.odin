package hegel_tests

import "core:encoding/uuid"
import "core:math"
import "core:mem/virtual"
import "core:net"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:text/regex"
import "core:time/datetime"
import "core:unicode/utf8"

import hegel "../hegel"

// Runs `property`, which should fail, and returns the output of its minimal
// example.
minimal :: proc(t: ^testing.T, property: hegel.Property, test_cases := 1000, loc := #caller_location) -> string {
	result := hegel.run(property, quiet(test_cases), loc = loc)
	defer hegel.destroy_run_result(&result)
	failure, ok := single_failure(t, result, loc)
	if !ok {
		return ""
	}
	return strings.clone(failure.output, context.temp_allocator)
}

@(test)
test_integers_respect_bounds :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		a := hegel.draw(tc, hegel.integers(i8))
		hegel.expect(tc, a >= min(i8) && a <= max(i8))
		b := hegel.draw(tc, hegel.integers(int, -5, 5))
		hegel.expect(tc, b >= -5 && b <= 5)
		c := hegel.draw(tc, hegel.integers(u16, min_value = 100))
		hegel.expect(tc, c >= 100)
		d := hegel.draw(tc, hegel.integers(i64, max_value = -1))
		hegel.expect(tc, d <= -1)
		e := hegel.draw(tc, hegel.integers(int, 7, 7))
		hegel.expect_value(tc, e, 7)
	}, quiet())
}

@(test)
test_wide_integers_respect_bounds :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		a := hegel.draw(tc, hegel.integers(u64, min_value = 1 << 63))
		hegel.expect(tc, a >= 1 << 63)
		b := hegel.draw(tc, hegel.integers(u128, min_value = 1 << 100))
		hegel.expect(tc, b >= 1 << 100)
		c := hegel.draw(tc, hegel.integers(i128, min_value = -(1 << 120), max_value = -(1 << 119)))
		hegel.expect(tc, c >= -(1 << 120) && c <= -(1 << 119))
		d := hegel.draw(tc, hegel.integers(uint, 10, 20))
		hegel.expect(tc, d >= 10 && d <= 20)
	}, quiet())
}

@(test)
test_wide_integers_reach_extremes :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(u128, min_value = max(u128) - 10), "n")
		hegel.expect(tc, n < max(u128) - 3)
	})
	testing.expect_value(t, out, "n: u128 = 340282366920938463463374607431768211452")
	out = minimal(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(i128, max_value = min(i128) + 10), "n")
		hegel.expect(tc, n > min(i128) + 3)
	})
	testing.expect_value(t, out, "n: i128 = -170141183460469231731687303715884105725")
	out = minimal(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(u64), "n")
		hegel.expect(tc, n < 1 << 63)
	})
	testing.expect_value(t, out, "n: u64 = 9223372036854775808")
}

@(test)
test_integers_shrink_towards_zero :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(int), "n")
		hegel.expect(tc, n > -1000)
	})
	testing.expect_value(t, out, "n: int = -1000")
}

@(test)
test_floats_respect_bounds :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		a := hegel.draw(tc, hegel.floats(f64, 0, 1))
		hegel.expect(tc, a >= 0 && a <= 1)
		b := hegel.draw(tc, hegel.floats(f64, 0, 1, exclude_min = true, exclude_max = true))
		hegel.expect(tc, b > 0 && b < 1)
		c := hegel.draw(tc, hegel.floats(f32, min_value = -2.5))
		hegel.expect(tc, c >= -2.5 && !math.is_nan(c))
		d := hegel.draw(tc, hegel.floats(f64, allow_nan = false, allow_infinity = false))
		hegel.expect(tc, !math.is_nan(d) && !math.is_inf(d))
	}, quiet())
}

@(test)
test_floats_can_be_nan :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		x := hegel.draw(tc, hegel.floats(f64), "x")
		hegel.expect(tc, !math.is_nan(x))
	})
	testing.expect_value(t, out, "x: f64 = NaN")
}

@(test)
test_floats_shrink_to_simple_values :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		x := hegel.draw(tc, hegel.floats(f64, allow_nan = false), "x")
		hegel.expect(tc, x < 1.5)
	})
	testing.expect_value(t, out, "x: f64 = 2")
}

@(test)
test_float_misconfiguration_is_an_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.floats(f64, 0, 1, allow_nan = true))
	}, quiet())
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Error)
	expect_contains(t, result.error, "allow_nan")
}

@(test)
test_booleans :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		hegel.expect(tc, hegel.draw(tc, hegel.booleans(1)))
		hegel.expect(tc, !hegel.draw(tc, hegel.booleans(0)))
	}, quiet())
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		hegel.expect(tc, !hegel.draw(tc, hegel.booleans()))
	})
	testing.expect_value(t, out, "draw_1: bool = true")
}

@(test)
test_text_respects_size_and_alphabet :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		s := hegel.draw(tc, hegel.text(min_size = 2, max_size = 5, alphabet = hegel.chars_of("xyz")))
		n := utf8.rune_count_in_string(s)
		hegel.expect(tc, n >= 2 && n <= 5)
		for r in s {
			hegel.expect(tc, strings.contains_rune("xyz", r))
		}
		ascii := hegel.draw(tc, hegel.text(alphabet = {codec = "ascii"}))
		for r in ascii {
			hegel.expect(tc, r < 128)
		}
		digits := hegel.draw(tc, hegel.text(alphabet = {categories = []string{"Nd"}, max_codepoint = 127}))
		for r in digits {
			hegel.expect(tc, r >= '0' && r <= '9')
		}
		no_vowels := hegel.draw(tc, hegel.text(alphabet = {min_codepoint = 'a', max_codepoint = 'z', exclude_characters = "aeiou"}))
		for r in no_vowels {
			hegel.expect(tc, r >= 'a' && r <= 'z' && !strings.contains_rune("aeiou", r))
		}
		any := hegel.draw(tc, hegel.text())
		hegel.expect(tc, utf8.valid_string(any))
	}, quiet())
}

@(test)
test_text_finds_non_ascii :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		s := hegel.draw(tc, hegel.text(), "s")
		for r in s {
			hegel.expect(tc, r < 128)
		}
	})
	testing.expect_value(t, out, `s: string = "\u0080"`)
}

@(test)
test_characters :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		r := hegel.draw(tc, hegel.characters({categories = []string{"Lu"}, max_codepoint = 127}))
		hegel.expect(tc, r >= 'A' && r <= 'Z')
	}, quiet())
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		r := hegel.draw(tc, hegel.characters(), "r")
		hegel.expect(tc, r < 'a')
	})
	testing.expect_value(t, out, "r: rune = 'a'")
}

@(test)
test_empty_alphabet_is_an_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.text(min_size = 1, alphabet = hegel.chars_of("")))
	}, quiet())
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Error)
}

@(test)
test_byte_slices :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		b := hegel.draw(tc, hegel.byte_slices(3, 8))
		hegel.expect(tc, len(b) >= 3 && len(b) <= 8)
	}, quiet())
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		b := hegel.draw(tc, hegel.byte_slices(), "b")
		hegel.expect(tc, len(b) < 3)
	})
	testing.expect_value(t, out, "b: []u8 = {0, 0, 0}")
}

@(test)
test_from_regex :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		s := hegel.draw(tc, hegel.from_regex(`[a-c]{2,4}[0-9]`, fullmatch = true))
		pattern, err := regex.create(`^[a-c]{2,4}[0-9]$`)
		hegel.expect(tc, err == nil)
		defer regex.destroy(pattern)
		_, matched := regex.match(pattern, s)
		hegel.expectf(tc, matched, "%q does not match", s)

		padded := hegel.draw(tc, hegel.from_regex(`ab`, alphabet = hegel.chars_of("abxy")))
		hegel.expect(tc, strings.contains(padded, "ab"))
		for r in padded {
			hegel.expect(tc, strings.contains_rune("abxy", r))
		}
	}, quiet())
}

@(test)
test_emails_urls_domains :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		email := hegel.draw(tc, hegel.emails())
		hegel.expect(tc, strings.count(email, "@") == 1)
		url := hegel.draw(tc, hegel.urls())
		hegel.expect(tc, strings.has_prefix(url, "http://") || strings.has_prefix(url, "https://"))
		domain := hegel.draw(tc, hegel.domains(max_length = 20))
		hegel.expect(tc, len(domain) > 0 && len(domain) <= 20)
	}, quiet())
}

@(test)
test_lists_respect_size_bounds :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		xs := hegel.draw(tc, hegel.lists(hegel.booleans(), min_size = 2, max_size = 6))
		hegel.expect(tc, len(xs) >= 2 && len(xs) <= 6)
		exact := hegel.draw(tc, hegel.lists(hegel.integers(u8), min_size = 3, max_size = 3))
		hegel.expect_value(tc, len(exact), 3)
		nested := hegel.draw(tc, hegel.lists(hegel.lists(hegel.integers(int, 0, 3), max_size = 2), max_size = 3))
		hegel.expect(tc, len(nested) <= 3)
		for inner in nested {
			hegel.expect(tc, len(inner) <= 2)
		}
	}, quiet())
}

@(test)
test_lists_shrink_by_deleting_and_shrinking :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		xs := hegel.draw(tc, hegel.lists(hegel.integers(int)), "xs")
		sorted := slice.clone(xs)
		slice.sort(sorted)
		hegel.expect(tc, len(slice.unique(sorted)) == len(xs))
	})
	testing.expect_value(t, out, "xs: []int = {0, 0}")
}

@(test)
test_unique_lists_sets_and_maps :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		xs := hegel.draw(tc, hegel.unique_lists(hegel.integers(int, 0, 20), min_size = 5, max_size = 10))
		hegel.expect(tc, len(xs) >= 5 && len(xs) <= 10)
		sorted := slice.clone(xs)
		slice.sort(sorted)
		hegel.expect(tc, len(slice.unique(sorted)) == len(xs))

		set := hegel.draw(tc, hegel.sets(hegel.integers(u8, 0, 9), min_size = 3))
		hegel.expect(tc, len(set) >= 3)
		for k in set {
			hegel.expect(tc, k <= 9)
		}

		m := hegel.draw(tc, hegel.maps(hegel.text(max_size = 3), hegel.booleans(), min_size = 1, max_size = 4))
		hegel.expect(tc, len(m) >= 1 && len(m) <= 4)
	}, quiet())
}

@(test)
test_arrays :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		a := hegel.draw(tc, hegel.arrays(hegel.integers(int, 0, 10), 3), "a")
		hegel.expect(tc, a[0] + a[1] + a[2] < 5)
	})
	testing.expect_value(t, out, "a: [3]int = {0, 0, 5}")
}

@(test)
test_dates_and_times :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		lo := datetime.Date{2020, 2, 1}
		hi := datetime.Date{2020, 3, 31}
		d := hegel.draw(tc, hegel.dates(lo, hi))
		hegel.expect(tc, datetime.validate(d) == nil)
		ordinal, _ := datetime.date_to_ordinal(d)
		lo_ordinal, _ := datetime.date_to_ordinal(lo)
		hi_ordinal, _ := datetime.date_to_ordinal(hi)
		hegel.expect(tc, ordinal >= lo_ordinal && ordinal <= hi_ordinal)

		any_date := hegel.draw(tc, hegel.dates())
		hegel.expect(tc, datetime.validate(any_date) == nil)

		tm := hegel.draw(tc, hegel.times(max_value = datetime.Time{12, 0, 0, 0}))
		hegel.expect(tc, datetime.validate(tm) == nil)
		hegel.expect(tc, tm.hour < 12 || (tm.hour == 12 && tm.minute == 0 && tm.second == 0 && tm.nano == 0))

		dt := hegel.draw(tc, hegel.date_times())
		hegel.expect(tc, datetime.validate(dt.date) == nil && datetime.validate(dt.time) == nil)
	}, quiet())
}

@(test)
test_dates_shrink_towards_2000 :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		d := hegel.draw(tc, hegel.dates(), "d")
		hegel.expect(tc, d.year < 2000)
	})
	testing.expect_value(t, out, "d: Date = Date{year = 2000, month = 1, day = 1}")
}

@(test)
test_uuids :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		id := hegel.draw(tc, hegel.uuids(4))
		hegel.expect_value(tc, uuid.version(id), 4)
		hegel.expect(tc, uuid.variant(id) == .RFC_4122)
		any_id := hegel.draw(tc, hegel.uuids())
		hegel.expect(tc, any_id != uuid.Identifier{})
	}, quiet())
}

@(test)
test_ip_addresses :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		addr := hegel.draw(tc, hegel.ip_addresses(), "addr")
		_, is_v4 := addr.(net.IP4_Address)
		hegel.expect(tc, is_v4)
	})
	testing.expect_value(t, out, "addr: Address = IP6_Address{0, 0, 0, 0, 0, 0, 0, 0}")
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		v4 := hegel.draw(tc, hegel.ipv4_addresses())
		v6 := hegel.draw(tc, hegel.ipv6_addresses())
		_ = v4
		_ = v6
	}, quiet())
}

@(test)
test_just_and_sampled_from :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		hegel.expect_value(tc, hegel.draw(tc, hegel.just("hello")), "hello")
		word := hegel.draw(tc, hegel.sampled_from([]string{"red", "green", "blue"}))
		hegel.expect(tc, slice.contains([]string{"red", "green", "blue"}, word))
	}, quiet())
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.sampled_from([]int{10, 20, 30, 40}), "n")
		hegel.expect(tc, n < 30)
	})
	testing.expect_value(t, out, "n: int = 30")
}

@(test)
test_sampled_from_empty_is_an_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.sampled_from([]int{}))
	}, quiet())
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Error)
	expect_contains(t, result.error, "sampled_from")
}

Direction :: enum {
	North,
	East,
	South,
	West,
}

@(test)
test_enum_values :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		d := hegel.draw(tc, hegel.enum_values(Direction), "d")
		hegel.expect(tc, d != .South)
	})
	testing.expect_value(t, out, "d: Direction = Direction.South")
}

@(test)
test_one_of_and_optional :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.one_of(hegel.integers(int, 0, 9), hegel.integers(int, 100, 109)))
		hegel.expect(tc, (n >= 0 && n <= 9) || (n >= 100 && n <= 109))
	}, quiet())
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.one_of(hegel.integers(int, 0, 9), hegel.integers(int, 100, 109)), "n")
		hegel.expect(tc, n < 50)
	})
	testing.expect_value(t, out, "n: int = 100")
	out = minimal(t, proc(tc: ^hegel.Test_Case) {
		m := hegel.draw(tc, hegel.optional(hegel.integers(int, 5, 10)), "m")
		_, present := m.?
		hegel.expect(tc, !present)
	})
	testing.expect_value(t, out, "m: Maybe(int) = 5")
}

@(test)
test_mapped_filtered_flat_mapped :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		even := hegel.draw(tc, hegel.mapped(hegel.integers(int, 0, 100), proc(n: int) -> int { return n * 2 }))
		hegel.expect(tc, even % 2 == 0)

		odd := hegel.draw(tc, hegel.filtered(hegel.integers(int, 0, 100), proc(n: int) -> bool { return n % 2 == 1 }))
		hegel.expect(tc, odd % 2 == 1)

		sized := hegel.draw(tc, hegel.flat_mapped(hegel.integers(int, 1, 5), proc(n: int) -> hegel.Generator([]bool) {
			return hegel.lists(hegel.booleans(), min_size = n, max_size = n)
		}))
		hegel.expect(tc, len(sized) >= 1 && len(sized) <= 5)
	}, quiet())
}

@(test)
test_impossible_filter_is_a_health_check_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.filtered(hegel.integers(int), proc(n: int) -> bool { return false }))
	}, quiet())
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Error)
}

Person :: struct {
	name: string,
	age:  int,
}

people :: proc() -> hegel.Generator(Person) {
	return hegel.composite(proc(tc: ^hegel.Test_Case) -> Person {
		return {name = hegel.draw(tc, hegel.text(min_size = 1, max_size = 10)), age = hegel.draw(tc, hegel.integers(int, 0, 120))}
	})
}

@(test)
test_composite :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hegel.Test_Case) {
		p := hegel.draw(tc, people(), "p")
		hegel.expect(tc, p.age < 18)
	})
	testing.expect_value(t, out, `p: Person = Person{name = "0", age = 18}`)
}

@(test)
test_composite_with_data :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		bound := 3
		gen := hegel.composite_with_data(&bound, proc(tc: ^hegel.Test_Case, bound: ^int) -> []int {
			return hegel.draw(tc, hegel.lists(hegel.integers(int, 0, bound^), max_size = bound^))
		})
		xs := hegel.draw(tc, gen)
		hegel.expect(tc, len(xs) <= 3)
		for x in xs {
			hegel.expect(tc, x <= 3)
		}
	}, quiet())
}

@(test)
test_generators_built_outside_properties :: proc(t: ^testing.T) {
	Gens :: struct {
		pairs: hegel.Generator([2]int),
	}
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	gens: Gens
	{
		context.allocator = virtual.arena_allocator(&arena)
		gens.pairs = hegel.arrays(hegel.integers(int, 0, 9), 2)
	}
	hegel.test_with_data(t, &gens, proc(tc: ^hegel.Test_Case, gens: ^Gens) {
		p := hegel.draw(tc, gens.pairs)
		hegel.expect(tc, p[0] <= 9 && p[1] <= 9)
	}, quiet())
}
