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

import hg "../hegel"

// Runs `property`, which should fail, and returns the output of its minimal
// example.
minimal :: proc(t: ^testing.T, property: hg.Property, test_cases := 1000, loc := #caller_location) -> string {
	result := hg.run(property, quiet(test_cases), loc = loc)
	defer hg.destroy_run_result(&result)
	failure, ok := single_failure(t, result, loc)
	if !ok {
		return ""
	}
	return strings.clone(failure.output, context.temp_allocator)
}

@(test) test_integers_respect_bounds :: proc(t: ^testing.T) { hg.test(t, integers_respect_bounds, quiet()) }

integers_respect_bounds :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, hg.integers(i8))
	hg.expect(tc, a >= min(i8) && a <= max(i8))
	b := hg.draw(tc, hg.integers(int, -5, 5))
	hg.expect(tc, b >= -5 && b <= 5)
	c := hg.draw(tc, hg.integers(u16, min_value = 100))
	hg.expect(tc, c >= 100)
	d := hg.draw(tc, hg.integers(i64, max_value = -1))
	hg.expect(tc, d <= -1)
	e := hg.draw(tc, hg.integers(int, 7, 7))
	hg.expect_value(tc, e, 7)
}

@(test) test_wide_integers_respect_bounds :: proc(t: ^testing.T) { hg.test(t, wide_integers_respect_bounds, quiet()) }

wide_integers_respect_bounds :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, hg.integers(u64, min_value = 1 << 63))
	hg.expect(tc, a >= 1 << 63)
	b := hg.draw(tc, hg.integers(u128, min_value = 1 << 100))
	hg.expect(tc, b >= 1 << 100)
	c := hg.draw(tc, hg.integers(i128, min_value = -(1 << 120), max_value = -(1 << 119)))
	hg.expect(tc, c >= -(1 << 120) && c <= -(1 << 119))
	d := hg.draw(tc, hg.integers(uint, 10, 20))
	hg.expect(tc, d >= 10 && d <= 20)
}

@(test)
test_wide_integers_reach_extremes :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(u128, min_value = max(u128) - 10), "n")
		hg.expect(tc, n < max(u128) - 3)
	})
	testing.expect_value(t, out, "n: u128 = 340282366920938463463374607431768211452")
	out = minimal(t, proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(i128, max_value = min(i128) + 10), "n")
		hg.expect(tc, n > min(i128) + 3)
	})
	testing.expect_value(t, out, "n: i128 = -170141183460469231731687303715884105725")
	out = minimal(t, proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(u64), "n")
		hg.expect(tc, n < 1 << 63)
	})
	testing.expect_value(t, out, "n: u64 = 9223372036854775808")
}

@(test)
test_integers_shrink_towards_zero :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(int), "n")
		hg.expect(tc, n > -1000)
	})
	testing.expect_value(t, out, "n: int = -1000")
}

@(test) test_floats_respect_bounds :: proc(t: ^testing.T) { hg.test(t, floats_respect_bounds, quiet()) }

floats_respect_bounds :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, hg.floats(f64, 0, 1))
	hg.expect(tc, a >= 0 && a <= 1)
	b := hg.draw(tc, hg.floats(f64, 0, 1, exclude_min = true, exclude_max = true))
	hg.expect(tc, b > 0 && b < 1)
	c := hg.draw(tc, hg.floats(f32, min_value = -2.5))
	hg.expect(tc, c >= -2.5 && !math.is_nan(c))
	d := hg.draw(tc, hg.floats(f64, allow_nan = false, allow_infinity = false))
	hg.expect(tc, !math.is_nan(d) && !math.is_inf(d))
}

@(test)
test_floats_can_be_nan :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		x := hg.draw(tc, hg.floats(f64), "x")
		hg.expect(tc, !math.is_nan(x))
	})
	testing.expect_value(t, out, "x: f64 = NaN")
}

@(test)
test_floats_shrink_to_simple_values :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		x := hg.draw(tc, hg.floats(f64, allow_nan = false), "x")
		hg.expect(tc, x < 1.5)
	})
	testing.expect_value(t, out, "x: f64 = 2")
}

@(test)
test_float_misconfiguration_is_an_error :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.floats(f64, 0, 1, allow_nan = true))
	}, quiet())
	defer hg.destroy_run_result(&result)
	testing.expect_value(t, result.status, hg.Run_Status.Error)
	expect_contains(t, result.error, "allow_nan")
}

@(test) test_booleans_respect_extreme_probabilities :: proc(t: ^testing.T) { hg.test(t, booleans_respect_extreme_probabilities, quiet()) }

booleans_respect_extreme_probabilities :: proc(tc: ^hg.Test_Case) {
	hg.expect(tc, hg.draw(tc, hg.booleans(1)))
	hg.expect(tc, !hg.draw(tc, hg.booleans(0)))
}

@(test)
test_booleans_find_true :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		hg.expect(tc, !hg.draw(tc, hg.booleans()))
	})
	testing.expect_value(t, out, "draw_1: bool = true")
}

@(test) test_text_respects_size_and_alphabet :: proc(t: ^testing.T) { hg.test(t, text_respects_size_and_alphabet, quiet()) }

text_respects_size_and_alphabet :: proc(tc: ^hg.Test_Case) {
	s := hg.draw(tc, hg.text(min_size = 2, max_size = 5, alphabet = hg.chars_of("xyz")))
	n := utf8.rune_count_in_string(s)
	hg.expect(tc, n >= 2 && n <= 5)
	for r in s {
		hg.expect(tc, strings.contains_rune("xyz", r))
	}
	ascii := hg.draw(tc, hg.text(alphabet = {codec = "ascii"}))
	for r in ascii {
		hg.expect(tc, r < 128)
	}
	digits := hg.draw(tc, hg.text(alphabet = {categories = []string{"Nd"}, max_codepoint = 127}))
	for r in digits {
		hg.expect(tc, r >= '0' && r <= '9')
	}
	no_vowels := hg.draw(tc, hg.text(alphabet = {min_codepoint = 'a', max_codepoint = 'z', exclude_characters = "aeiou"}))
	for r in no_vowels {
		hg.expect(tc, r >= 'a' && r <= 'z' && !strings.contains_rune("aeiou", r))
	}
	any := hg.draw(tc, hg.text())
	hg.expect(tc, utf8.valid_string(any))
}

@(test)
test_text_finds_non_ascii :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		s := hg.draw(tc, hg.text(), "s")
		for r in s {
			hg.expect(tc, r < 128)
		}
	})
	testing.expect_value(t, out, `s: string = "\u0080"`)
}

@(test) test_characters_respect_categories :: proc(t: ^testing.T) { hg.test(t, characters_respect_categories, quiet()) }

characters_respect_categories :: proc(tc: ^hg.Test_Case) {
	r := hg.draw(tc, hg.characters({categories = []string{"Lu"}, max_codepoint = 127}))
	hg.expect(tc, r >= 'A' && r <= 'Z')
}

@(test)
test_characters_find_lowercase :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		r := hg.draw(tc, hg.characters(), "r")
		hg.expect(tc, r < 'a')
	})
	testing.expect_value(t, out, "r: rune = 'a'")
}

@(test)
test_empty_alphabet_is_an_error :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.text(min_size = 1, alphabet = hg.chars_of("")))
	}, quiet())
	defer hg.destroy_run_result(&result)
	testing.expect_value(t, result.status, hg.Run_Status.Error)
}

@(test) test_byte_slices_respect_size_bounds :: proc(t: ^testing.T) { hg.test(t, byte_slices_respect_size_bounds, quiet()) }

byte_slices_respect_size_bounds :: proc(tc: ^hg.Test_Case) {
	b := hg.draw(tc, hg.byte_slices(3, 8))
	hg.expect(tc, len(b) >= 3 && len(b) <= 8)
}

@(test)
test_byte_slices_find_long_slices :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		b := hg.draw(tc, hg.byte_slices(), "b")
		hg.expect(tc, len(b) < 3)
	})
	testing.expect_value(t, out, "b: []u8 = {0, 0, 0}")
}

@(test) test_from_regex :: proc(t: ^testing.T) { hg.test(t, from_regex, quiet()) }

from_regex :: proc(tc: ^hg.Test_Case) {
	s := hg.draw(tc, hg.from_regex(`[a-c]{2,4}[0-9]`, fullmatch = true))
	pattern, err := regex.create(`^[a-c]{2,4}[0-9]$`)
	hg.expect(tc, err == nil)
	defer regex.destroy(pattern)
	_, matched := regex.match(pattern, s)
	hg.expectf(tc, matched, "%q does not match", s)

	padded := hg.draw(tc, hg.from_regex(`ab`, alphabet = hg.chars_of("abxy")))
	hg.expect(tc, strings.contains(padded, "ab"))
	for r in padded {
		hg.expect(tc, strings.contains_rune("abxy", r))
	}
}

@(test) test_emails_urls_domains :: proc(t: ^testing.T) { hg.test(t, emails_urls_domains, quiet()) }

emails_urls_domains :: proc(tc: ^hg.Test_Case) {
	email := hg.draw(tc, hg.emails())
	hg.expect(tc, strings.count(email, "@") == 1)
	url := hg.draw(tc, hg.urls())
	hg.expect(tc, strings.has_prefix(url, "http://") || strings.has_prefix(url, "https://"))
	domain := hg.draw(tc, hg.domains(max_length = 20))
	hg.expect(tc, len(domain) > 0 && len(domain) <= 20)
}

@(test) test_lists_respect_size_bounds :: proc(t: ^testing.T) { hg.test(t, lists_respect_size_bounds, quiet()) }

lists_respect_size_bounds :: proc(tc: ^hg.Test_Case) {
	xs := hg.draw(tc, hg.lists(hg.booleans(), min_size = 2, max_size = 6))
	hg.expect(tc, len(xs) >= 2 && len(xs) <= 6)
	exact := hg.draw(tc, hg.lists(hg.integers(u8), min_size = 3, max_size = 3))
	hg.expect_value(tc, len(exact), 3)
	nested := hg.draw(tc, hg.lists(hg.lists(hg.integers(int, 0, 3), max_size = 2), max_size = 3))
	hg.expect(tc, len(nested) <= 3)
	for inner in nested {
		hg.expect(tc, len(inner) <= 2)
	}
}

@(test)
test_lists_shrink_by_deleting_and_shrinking :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		xs := hg.draw(tc, hg.lists(hg.integers(int)), "xs")
		sorted := slice.clone(xs)
		slice.sort(sorted)
		hg.expect(tc, len(slice.unique(sorted)) == len(xs))
	})
	testing.expect_value(t, out, "xs: []int = {0, 0}")
}

@(test) test_unique_lists_sets_and_maps :: proc(t: ^testing.T) { hg.test(t, unique_lists_sets_and_maps, quiet()) }

unique_lists_sets_and_maps :: proc(tc: ^hg.Test_Case) {
	xs := hg.draw(tc, hg.unique_lists(hg.integers(int, 0, 20), min_size = 5, max_size = 10))
	hg.expect(tc, len(xs) >= 5 && len(xs) <= 10)
	sorted := slice.clone(xs)
	slice.sort(sorted)
	hg.expect(tc, len(slice.unique(sorted)) == len(xs))

	set := hg.draw(tc, hg.sets(hg.integers(u8, 0, 9), min_size = 3))
	hg.expect(tc, len(set) >= 3)
	for k in set {
		hg.expect(tc, k <= 9)
	}

	m := hg.draw(tc, hg.maps(hg.text(max_size = 3), hg.booleans(), min_size = 1, max_size = 4))
	hg.expect(tc, len(m) >= 1 && len(m) <= 4)
}

@(test)
test_arrays :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		a := hg.draw(tc, hg.arrays(hg.integers(int, 0, 10), 3), "a")
		hg.expect(tc, a[0] + a[1] + a[2] < 5)
	})
	testing.expect_value(t, out, "a: [3]int = {0, 0, 5}")
}

@(test) test_dates_and_times :: proc(t: ^testing.T) { hg.test(t, dates_and_times, quiet()) }

dates_and_times :: proc(tc: ^hg.Test_Case) {
	lo := datetime.Date{2020, 2, 1}
	hi := datetime.Date{2020, 3, 31}
	d := hg.draw(tc, hg.dates(lo, hi))
	hg.expect(tc, datetime.validate(d) == nil)
	ordinal, _ := datetime.date_to_ordinal(d)
	lo_ordinal, _ := datetime.date_to_ordinal(lo)
	hi_ordinal, _ := datetime.date_to_ordinal(hi)
	hg.expect(tc, ordinal >= lo_ordinal && ordinal <= hi_ordinal)

	any_date := hg.draw(tc, hg.dates())
	hg.expect(tc, datetime.validate(any_date) == nil)

	tm := hg.draw(tc, hg.times(max_value = datetime.Time{12, 0, 0, 0}))
	hg.expect(tc, datetime.validate(tm) == nil)
	hg.expect(tc, tm.hour < 12 || (tm.hour == 12 && tm.minute == 0 && tm.second == 0 && tm.nano == 0))

	dt := hg.draw(tc, hg.date_times())
	hg.expect(tc, datetime.validate(dt.date) == nil && datetime.validate(dt.time) == nil)
}

@(test)
test_dates_shrink_towards_2000 :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		d := hg.draw(tc, hg.dates(), "d")
		hg.expect(tc, d.year < 2000)
	})
	testing.expect_value(t, out, "d: Date = Date{year = 2000, month = 1, day = 1}")
}

@(test) test_uuids :: proc(t: ^testing.T) { hg.test(t, uuids, quiet()) }

uuids :: proc(tc: ^hg.Test_Case) {
	id := hg.draw(tc, hg.uuids(4))
	hg.expect_value(tc, uuid.version(id), 4)
	hg.expect(tc, uuid.variant(id) == .RFC_4122)
	any_id := hg.draw(tc, hg.uuids())
	hg.expect(tc, any_id != uuid.Identifier{})
}

@(test)
test_ip_addresses_find_ipv6 :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		addr := hg.draw(tc, hg.ip_addresses(), "addr")
		_, is_v4 := addr.(net.IP4_Address)
		hg.expect(tc, is_v4)
	})
	testing.expect_value(t, out, "addr: Address = IP6_Address{0, 0, 0, 0, 0, 0, 0, 0}")
}

@(test) test_ipv4_and_ipv6_addresses :: proc(t: ^testing.T) { hg.test(t, ipv4_and_ipv6_addresses, quiet()) }

ipv4_and_ipv6_addresses :: proc(tc: ^hg.Test_Case) {
	v4 := hg.draw(tc, hg.ipv4_addresses())
	v6 := hg.draw(tc, hg.ipv6_addresses())
	_ = v4
	_ = v6
}

@(test) test_just_and_sampled_from :: proc(t: ^testing.T) { hg.test(t, just_and_sampled_from, quiet()) }

just_and_sampled_from :: proc(tc: ^hg.Test_Case) {
	hg.expect_value(tc, hg.draw(tc, hg.just("hello")), "hello")
	word := hg.draw(tc, hg.sampled_from([]string{"red", "green", "blue"}))
	hg.expect(tc, slice.contains([]string{"red", "green", "blue"}, word))
}

@(test)
test_sampled_from_shrinks_towards_first :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.sampled_from([]int{10, 20, 30, 40}), "n")
		hg.expect(tc, n < 30)
	})
	testing.expect_value(t, out, "n: int = 30")
}

@(test)
test_sampled_from_empty_is_an_error :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.sampled_from([]int{}))
	}, quiet())
	defer hg.destroy_run_result(&result)
	testing.expect_value(t, result.status, hg.Run_Status.Error)
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
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		d := hg.draw(tc, hg.enum_values(Direction), "d")
		hg.expect(tc, d != .South)
	})
	testing.expect_value(t, out, "d: Direction = Direction.South")
}

@(test) test_one_of_stays_in_its_branches :: proc(t: ^testing.T) { hg.test(t, one_of_stays_in_its_branches, quiet()) }

one_of_stays_in_its_branches :: proc(tc: ^hg.Test_Case) {
	n := hg.draw(tc, hg.one_of(hg.integers(int, 0, 9), hg.integers(int, 100, 109)))
	hg.expect(tc, (n >= 0 && n <= 9) || (n >= 100 && n <= 109))
}

@(test)
test_one_of_and_optional_shrink :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.one_of(hg.integers(int, 0, 9), hg.integers(int, 100, 109)), "n")
		hg.expect(tc, n < 50)
	})
	testing.expect_value(t, out, "n: int = 100")
	out = minimal(t, proc(tc: ^hg.Test_Case) {
		m := hg.draw(tc, hg.optional(hg.integers(int, 5, 10)), "m")
		_, present := m.?
		hg.expect(tc, !present)
	})
	testing.expect_value(t, out, "m: Maybe(int) = 5")
}

@(test) test_mapped_filtered_flat_mapped :: proc(t: ^testing.T) { hg.test(t, mapped_filtered_flat_mapped, quiet()) }

mapped_filtered_flat_mapped :: proc(tc: ^hg.Test_Case) {
	even := hg.draw(tc, hg.mapped(hg.integers(int, 0, 100), proc(n: int) -> int { return n * 2 }))
	hg.expect(tc, even % 2 == 0)

	odd := hg.draw(tc, hg.filtered(hg.integers(int, 0, 100), proc(n: int) -> bool { return n % 2 == 1 }))
	hg.expect(tc, odd % 2 == 1)

	sized := hg.draw(tc, hg.flat_mapped(hg.integers(int, 1, 5), proc(n: int) -> hg.Generator([]bool) {
		return hg.lists(hg.booleans(), min_size = n, max_size = n)
	}))
	hg.expect(tc, len(sized) >= 1 && len(sized) <= 5)
}

@(test)
test_impossible_filter_is_a_health_check_error :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.filtered(hg.integers(int), proc(n: int) -> bool { return false }))
	}, quiet())
	defer hg.destroy_run_result(&result)
	testing.expect_value(t, result.status, hg.Run_Status.Error)
}

Person :: struct {
	name: string,
	age:  int,
}

people :: proc() -> hg.Generator(Person) {
	return hg.composite(proc(tc: ^hg.Test_Case) -> Person {
		return {name = hg.draw(tc, hg.text(min_size = 1, max_size = 10)), age = hg.draw(tc, hg.integers(int, 0, 120))}
	})
}

@(test)
test_composite :: proc(t: ^testing.T) {
	out := minimal(t, proc(tc: ^hg.Test_Case) {
		p := hg.draw(tc, people(), "p")
		hg.expect(tc, p.age < 18)
	})
	testing.expect_value(t, out, `p: Person = Person{name = "0", age = 18}`)
}

@(test) test_composite_with_data :: proc(t: ^testing.T) { hg.test(t, composite_with_data, quiet()) }

composite_with_data :: proc(tc: ^hg.Test_Case) {
	bound := 3
	gen := hg.composite_with_data(&bound, proc(tc: ^hg.Test_Case, bound: ^int) -> []int {
		return hg.draw(tc, hg.lists(hg.integers(int, 0, bound^), max_size = bound^))
	})
	xs := hg.draw(tc, gen)
	hg.expect(tc, len(xs) <= 3)
	for x in xs {
		hg.expect(tc, x <= 3)
	}
}

@(test)
test_generators_built_outside_properties :: proc(t: ^testing.T) {
	Gens :: struct {
		pairs: hg.Generator([2]int),
	}
	arena: virtual.Arena
	testing.expect(t, virtual.arena_init_growing(&arena) == nil)
	defer virtual.arena_destroy(&arena)
	gens: Gens
	{
		context.allocator = virtual.arena_allocator(&arena)
		gens.pairs = hg.arrays(hg.integers(int, 0, 9), 2)
	}
	hg.test_with_data(t, &gens, proc(tc: ^hg.Test_Case, gens: ^Gens) {
		p := hg.draw(tc, gens.pairs)
		hg.expect(tc, p[0] <= 9 && p[1] <= 9)
	}, quiet())
}
