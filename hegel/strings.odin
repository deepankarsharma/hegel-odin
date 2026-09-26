package hegel

import "core:strings"
import "core:unicode/utf8"

import lh "libhegel"

/*
The characters a `text` or `characters` generator may use. The zero value
allows every Unicode scalar value.

- `codec`: `"ascii"`, `"latin-1"`, or `"utf-8"` (the default).
- `min_codepoint` / `max_codepoint`: intersected with the codec's range.
- `categories`: restrict to these Unicode general categories (`"Lu"`, `"N"`,
  ...). A non-nil empty slice allows nothing, which is useful together with
  `include_characters`.
- `exclude_categories`: remove these categories.
- `include_characters` / `exclude_characters`: added, then removed, last.
*/
Alphabet :: struct {
	codec:              string,
	min_codepoint:      rune,
	max_codepoint:      Maybe(rune),
	categories:         Maybe([]string),
	exclude_categories: []string,
	include_characters: string,
	exclude_characters: string,
}

// An alphabet of exactly the characters in `chars`.
chars_of :: proc(chars: string) -> Alphabet {
	return {categories = []string{}, include_characters = chars}
}

/*
Strings of `min_size` to `max_size` Unicode characters drawn from `alphabet`.
Shrinks towards shorter strings of lower code points.

	hegel.text()
	hegel.text(max_size = 10, alphabet = {codec = "ascii"})
	hegel.text(min_size = 1, alphabet = hegel.chars_of("abc"))
*/
text :: proc(min_size := 0, max_size: Maybe(int) = nil, alphabet := Alphabet{}) -> Generator(string) {
	State :: struct {
		min_size: int,
		max_size: Maybe(int),
		alphabet: Alphabet,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> string {
		s := (^State)(data)
		sg := text_generator(tc, s.min_size, s.max_size, s.alphabet)
		return draw_string(tc, sg)
	}
	state := State{min_size, max_size, clone_alphabet(alphabet)}
	return {generate, new_clone(state), label_of("hegel_odin.text")}
}

// Single characters drawn from `alphabet`.
characters :: proc(alphabet := Alphabet{}) -> Generator(rune) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> rune {
		sg := text_generator(tc, 1, 1, (^Alphabet)(data)^)
		r, _ := utf8.decode_rune_in_string(draw_string(tc, sg))
		return r
	}
	return {generate, new_clone(clone_alphabet(alphabet)), label_of("hegel_odin.characters")}
}

// Byte slices with a length in `[min_size, max_size]`.
byte_slices :: proc(min_size := 0, max_size: Maybe(int) = nil) -> Generator([]u8) {
	State :: struct {
		min_size: int,
		max_size: Maybe(int),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> []u8 {
		s := (^State)(data)
		lo, hi := size_bounds(tc, "byte_slices", s.min_size, s.max_size)
		result: lh.Bytes_Result
		rc := lh.generate_bytes(tc._ctx, tc._handle, lo, hi, &result)
		out: []u8
		if rc == .Ok {
			out = make([]u8, result.len)
			copy(out, result.data[:result.len])
			lh.generate_bytes_result_free(tc._ctx, &result)
		}
		check(tc, rc)
		return out
	}
	return {generate, new_clone(State{min_size, max_size}), label_of("hegel_odin.byte_slices")}
}

/*
Strings matching the regular expression `pattern` (Python `re` syntax).
Without `fullmatch`, the match may be surrounded by arbitrary text drawn from
`alphabet`.
*/
from_regex :: proc(pattern: string, fullmatch := false, alphabet: Maybe(Alphabet) = nil) -> Generator(string) {
	State :: struct {
		pattern:   string,
		fullmatch: bool,
		alphabet:  Maybe(Alphabet),
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> string {
		s := (^State)(data)
		alphabet_gen: ^lh.String_Generator
		if a, ok := s.alphabet.?; ok {
			alphabet_gen = text_generator(tc, 0, nil, a)
		}
		sg: ^lh.String_Generator
		rc := lh.string_generator_regex(tc._ctx, cstr(s.pattern), s.fullmatch, alphabet_gen, &sg)
		lh.string_generator_free(tc._ctx, alphabet_gen)
		check(tc, rc)
		return draw_string(tc, sg)
	}
	state := State{strings.clone(pattern), fullmatch, nil}
	if a, ok := alphabet.?; ok {
		state.alphabet = clone_alphabet(a)
	}
	return {generate, new_clone(state), label_of("hegel_odin.from_regex")}
}

// RFC 5322 email addresses such as `alice@example.com`.
emails :: proc() -> Generator(string) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> string {
		sg: ^lh.String_Generator
		check(tc, lh.string_generator_email(tc._ctx, &sg))
		return draw_string(tc, sg)
	}
	return {generate, nil, label_of("hegel_odin.emails")}
}

// RFC 3986 `http` and `https` URLs.
urls :: proc() -> Generator(string) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> string {
		sg: ^lh.String_Generator
		check(tc, lh.string_generator_url(tc._ctx, &sg))
		return draw_string(tc, sg)
	}
	return {generate, nil, label_of("hegel_odin.urls")}
}

// Fully qualified domain names of at most `max_length` characters (4..=255).
domains :: proc(max_length := 255) -> Generator(string) {
	generate :: proc(tc: ^Test_Case, data: rawptr) -> string {
		max_length := (^int)(data)^
		if max_length < 4 || max_length > 255 {
			usage_error(tc, "domains: max_length must be in [4, 255], got %d", max_length)
		}
		sg: ^lh.String_Generator
		check(tc, lh.string_generator_domain(tc._ctx, u64(max_length), &sg))
		return draw_string(tc, sg)
	}
	return {generate, new_clone(max_length), label_of("hegel_odin.domains")}
}

// Builds an engine text generator; the caller must free it.
@(private)
text_generator :: proc(tc: ^Test_Case, min_size: int, max_size: Maybe(int), a: Alphabet) -> ^lh.String_Generator {
	lo, hi := size_bounds(tc, "text", min_size, max_size)
	categories: []cstring
	has_categories := false
	if cats, ok := a.categories.?; ok {
		has_categories = true
		categories = make([]cstring, len(cats))
		for c, i in cats {
			categories[i] = cstr(c)
		}
	}
	exclude := make([]cstring, len(a.exclude_categories))
	for c, i in a.exclude_categories {
		exclude[i] = cstr(c)
	}
	codec: cstring = cstr(a.codec) if a.codec != "" else nil
	max_cp := u32(a.max_codepoint.? or_else max(rune))

	// A non-nil pointer distinguishes "no categories" from "no restriction".
	empty: cstring
	categories_ptr: [^]cstring = raw_data(categories) if len(categories) > 0 else (&empty if has_categories else nil)

	sg: ^lh.String_Generator
	check(tc, lh.string_generator_text(
		tc._ctx,
		lo,
		hi,
		codec,
		u32(a.min_codepoint),
		max_cp,
		categories_ptr,
		len(categories),
		raw_data(exclude),
		len(exclude),
		raw_data(a.include_characters),
		len(a.include_characters),
		raw_data(a.exclude_characters),
		len(a.exclude_characters),
		&sg,
	))
	return sg
}

// Draws from `sg`, then frees it.
@(private)
draw_string :: proc(tc: ^Test_Case, sg: ^lh.String_Generator) -> string {
	result: lh.String_Result
	rc := lh.generate_string(tc._ctx, tc._handle, sg, &result)
	lh.string_generator_free(tc._ctx, sg)
	out: string
	if rc == .Ok {
		out = strings.clone(string(result.data[:result.len]))
		lh.generate_string_result_free(tc._ctx, &result)
	}
	check(tc, rc)
	return out
}

@(private)
size_bounds :: proc(tc: ^Test_Case, name: string, min_size: int, max_size: Maybe(int)) -> (lo, hi: u64) {
	if min_size < 0 {
		usage_error(tc, "%s: min_size must be non-negative, got %d", name, min_size)
	}
	hi = max(u64)
	if m, ok := max_size.?; ok {
		if m < min_size {
			usage_error(tc, "%s: max_size %d is less than min_size %d", name, m, min_size)
		}
		hi = u64(m)
	}
	return u64(min_size), hi
}

@(private)
clone_alphabet :: proc(a: Alphabet) -> Alphabet {
	out := a
	out.codec = strings.clone(a.codec)
	out.include_characters = strings.clone(a.include_characters)
	out.exclude_characters = strings.clone(a.exclude_characters)
	if cats, ok := a.categories.?; ok {
		out.categories = clone_strings(cats)
	}
	out.exclude_categories = clone_strings(a.exclude_categories)
	return out
}

@(private)
clone_strings :: proc(ss: []string) -> []string {
	out := make([]string, len(ss))
	for s, i in ss {
		out[i] = strings.clone(s)
	}
	return out
}
