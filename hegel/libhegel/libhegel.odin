/*
Raw bindings to libhegel, the native Hegel engine (hegel-rust's `hegel-c`
crate), mirroring `hegel.h` one-to-one.

Most users want the `hegel` package one directory up, which wraps these
bindings in a safe, idiomatic API. Use this package directly only to build
another frontend or to reach an engine feature the wrapper does not expose.

Every procedure takes a `^Context` as its first argument (nil opts out of
error messages) and returns a `Result`. `.Ok` is zero and every error is
negative. Values are written through trailing `out_*` pointer parameters.
See `hegel.h` in hegel-rust for the full contract of each call.

Linking: by default the static library `lib/libhegel_c.a` (built by
`scripts/build_libhegel.sh`) is linked into the binary. Build with
`-define:HEGEL_SYSTEM_LIBRARY=true` to link a system-installed `hegel_c`
shared library instead.
*/
package libhegel

import "core:c"

HEGEL_SYSTEM_LIBRARY :: #config(HEGEL_SYSTEM_LIBRARY, false)

when HEGEL_SYSTEM_LIBRARY {
	foreign import lib "system:hegel_c"
} else when ODIN_OS == .Darwin {
	foreign import lib {"lib/libhegel_c.a", "system:iconv"}
} else when ODIN_OS == .Windows {
	foreign import lib {
		"lib/hegel_c.lib",
		"system:kernel32.lib",
		"system:advapi32.lib",
		"system:bcrypt.lib",
		"system:ntdll.lib",
		"system:userenv.lib",
		"system:ws2_32.lib",
	}
} else {
	foreign import lib {"lib/libhegel_c.a", "system:pthread", "system:dl", "system:m"}
}

// Written by `state_machine_next_rule` when the worker's round is over, and
// by `state_machine_next_group` when the whole machine is done.
STATE_MACHINE_DONE :: min(i64)

Result :: enum c.int {
	Ok               = 0,
	Stop_Test        = -1,
	Assume           = -2,
	Backend          = -3,
	Invalid_Handle   = -4,
	Invalid_Arg      = -5,
	Already_Complete = -6,
	Not_Complete     = -7,
	Internal         = -8,
	Concurrent_Use   = -9,
	Retry            = -10,
}

Verbosity :: enum c.int {
	Normal  = 0,
	Quiet   = 1,
	Verbose = 2,
	Debug   = 3,
}

Backend :: enum c.int {
	Default  = 1,
	URandom  = 2,
}

Run_Status :: enum c.int {
	Passed                  = 0,
	Failed                  = 1,
	Error                   = 2,
	Failed_Nondeterministic = 3,
}

// Bit positions of `hegel_phase_t`; a `Phases` set has the C flag layout.
Phase :: enum u32 {
	Explicit = 0,
	Reuse    = 1,
	Generate = 2,
	Target   = 3,
	Shrink   = 4,
}
Phases :: bit_set[Phase; u32]
ALL_PHASES :: Phases{.Explicit, .Reuse, .Generate, .Target, .Shrink}

// Bit positions of `hegel_health_check_t`; a `Health_Checks` set has the C
// flag layout.
Health_Check :: enum u32 {
	Filter_Too_Much         = 0,
	Too_Slow                = 1,
	Test_Cases_Too_Large    = 2,
	Large_Initial_Test_Case = 3,
}
Health_Checks :: bit_set[Health_Check; u32]
ALL_HEALTH_CHECKS :: Health_Checks{.Filter_Too_Much, .Too_Slow, .Test_Cases_Too_Large, .Large_Initial_Test_Case}

// Outcome of a single test case, passed to `mark_complete`.
Status :: enum u32 {
	Valid       = 0,
	Invalid     = 1,
	Overrun     = 2,
	Interesting = 3,
}

Context          :: struct {}
Settings         :: struct {}
Run              :: struct {}
Run_Result       :: struct {}
Failure          :: struct {}
Test_Case        :: struct {}
Collection       :: struct {}
Recursion        :: struct {}
Pool             :: struct {}
State_Machine    :: struct {}
String_Generator :: struct {}
Printer          :: struct {}
Printer_Options  :: struct {}

Output_Callback :: #type proc "c" (user_data: rawptr, line: cstring, len: c.size_t)

// Engine-allocated buffers. Release with the matching `*_result_free`.
Bytes_Result :: struct {
	data: [^]u8,
	len:  c.size_t,
}
String_Result :: struct {
	data: [^]u8,
	len:  c.size_t,
}
Printer_Value_Result :: struct {
	data: [^]u8,
	len:  c.size_t,
}

Date :: struct {
	year:  i32,
	month: u8,
	day:   u8,
}
Time :: struct {
	hour:       u8,
	minute:     u8,
	second:     u8,
	nanosecond: u32,
}
Datetime :: struct {
	date: Date,
	time: Time,
}

@(default_calling_convention = "c", link_prefix = "hegel_")
foreign lib {
	// Contexts
	context_new        :: proc() -> ^Context ---
	context_free       :: proc(ctx: ^Context) -> Result ---
	context_last_error :: proc(ctx: ^Context) -> cstring ---

	// Settings
	settings_new                   :: proc(ctx: ^Context, out_settings: ^^Settings) -> Result ---
	settings_new_for_profile       :: proc(ctx: ^Context, name: cstring, out_settings: ^^Settings) -> Result ---
	settings_free                  :: proc(ctx: ^Context, s: ^Settings) -> Result ---
	settings_set_backend           :: proc(ctx: ^Context, s: ^Settings, backend: u32) -> Result ---
	settings_set_test_cases        :: proc(ctx: ^Context, s: ^Settings, n: u64) -> Result ---
	settings_set_verbosity         :: proc(ctx: ^Context, s: ^Settings, v: u32) -> Result ---
	settings_set_seed              :: proc(ctx: ^Context, s: ^Settings, seed: u64, has_seed: bool) -> Result ---
	settings_set_derandomize       :: proc(ctx: ^Context, s: ^Settings, derandomize: bool) -> Result ---
	settings_set_report_multiple_failures :: proc(ctx: ^Context, s: ^Settings, yes: bool) -> Result ---
	settings_set_show_statistics   :: proc(ctx: ^Context, s: ^Settings, yes: bool) -> Result ---
	settings_set_unbounded_choices :: proc(ctx: ^Context, s: ^Settings, yes: bool) -> Result ---
	settings_set_database          :: proc(ctx: ^Context, s: ^Settings, database: cstring) -> Result ---
	settings_set_database_key      :: proc(ctx: ^Context, s: ^Settings, key: cstring) -> Result ---
	settings_set_test_location     :: proc(ctx: ^Context, s: ^Settings, file: cstring, begin_line: u32, class_name: cstring, function: cstring) -> Result ---
	settings_set_phases            :: proc(ctx: ^Context, s: ^Settings, phases: Phases) -> Result ---
	settings_set_suppress_health_check :: proc(ctx: ^Context, s: ^Settings, checks: Health_Checks) -> Result ---
	settings_set_print_blob        :: proc(ctx: ^Context, s: ^Settings, yes: bool) -> Result ---
	settings_register_profile      :: proc(ctx: ^Context, name: cstring, settings: ^Settings) -> Result ---
	set_default_profile            :: proc(ctx: ^Context, name: cstring) -> Result ---
	settings_get_test_cases        :: proc(ctx: ^Context, s: ^Settings, out: ^u64) -> Result ---
	settings_get_verbosity         :: proc(ctx: ^Context, s: ^Settings, out: ^Verbosity) -> Result ---
	settings_get_seed              :: proc(ctx: ^Context, s: ^Settings, out_seed: ^u64, out_has_seed: ^bool) -> Result ---
	settings_get_derandomize       :: proc(ctx: ^Context, s: ^Settings, out: ^bool) -> Result ---
	settings_get_database          :: proc(ctx: ^Context, s: ^Settings, out_database: ^cstring) -> Result ---
	settings_get_phases            :: proc(ctx: ^Context, s: ^Settings, out: ^Phases) -> Result ---
	settings_get_suppress_health_check :: proc(ctx: ^Context, s: ^Settings, out: ^Health_Checks) -> Result ---
	settings_get_report_multiple_failures :: proc(ctx: ^Context, s: ^Settings, out: ^bool) -> Result ---
	settings_get_show_statistics   :: proc(ctx: ^Context, s: ^Settings, out: ^bool) -> Result ---
	settings_get_unbounded_choices :: proc(ctx: ^Context, s: ^Settings, out: ^bool) -> Result ---
	settings_get_print_blob        :: proc(ctx: ^Context, s: ^Settings, out: ^bool) -> Result ---
	settings_get_backend           :: proc(ctx: ^Context, s: ^Settings, out: ^Backend) -> Result ---

	// Runs
	run_start       :: proc(ctx: ^Context, settings: ^Settings, callback: Output_Callback, user_data: rawptr, out_run: ^^Run) -> Result ---
	next_test_case  :: proc(ctx: ^Context, run: ^Run, out_test_case: ^^Test_Case) -> Result ---
	run_result      :: proc(ctx: ^Context, run: ^Run, out_result: ^^Run_Result) -> Result ---
	run_result_free :: proc(ctx: ^Context, r: ^Run_Result) -> Result ---
	run_free        :: proc(ctx: ^Context, run: ^Run) -> Result ---

	// Test cases
	test_case_from_blob          :: proc(ctx: ^Context, s: ^Settings, blob: cstring, callback: Output_Callback, user_data: rawptr, out_test_case: ^^Test_Case) -> Result ---
	test_case_free               :: proc(ctx: ^Context, tc: ^Test_Case) -> Result ---
	test_case_is_nondeterministic :: proc(ctx: ^Context, tc: ^Test_Case, out_is_nondeterministic: ^bool) -> Result ---
	test_case_clone              :: proc(ctx: ^Context, tc: ^Test_Case, out_test_case: ^^Test_Case) -> Result ---
	test_case_block              :: proc(ctx: ^Context, tc: ^Test_Case, indent: u64, out_test_case: ^^Test_Case) -> Result ---
	test_case_set_worker         :: proc(ctx: ^Context, tc: ^Test_Case, worker_index: i64) -> Result ---
	mark_complete                :: proc(ctx: ^Context, tc: ^Test_Case, status: Status, origin: cstring) -> Result ---

	// Spans and labels
	start_span       :: proc(ctx: ^Context, tc: ^Test_Case, label: u64) -> Result ---
	stop_span        :: proc(ctx: ^Context, tc: ^Test_Case, discard: bool) -> Result ---
	label_from_name  :: proc(ctx: ^Context, name: cstring, out_label: ^u64) -> Result ---
	label_combine    :: proc(ctx: ^Context, labels: [^]u64, len: c.size_t, out_label: ^u64) -> Result ---

	// Collections
	new_collection    :: proc(ctx: ^Context, tc: ^Test_Case, min_size: u64, max_size: u64, out_collection: ^^Collection) -> Result ---
	collection_more   :: proc(ctx: ^Context, tc: ^Test_Case, collection: ^Collection, out_more: ^bool) -> Result ---
	collection_reject :: proc(ctx: ^Context, tc: ^Test_Case, collection: ^Collection, why: cstring) -> Result ---
	collection_free   :: proc(ctx: ^Context, collection: ^Collection) -> Result ---

	// Recursion
	new_recursion     :: proc(ctx: ^Context, tc: ^Test_Case, max_depth: u64, max_leaves: u64, out_recursion: ^^Recursion) -> Result ---
	recursion_branch  :: proc(ctx: ^Context, tc: ^Test_Case, recursion: ^Recursion, depth: u64, out_branch: ^bool) -> Result ---
	recursion_leaf    :: proc(ctx: ^Context, tc: ^Test_Case, recursion: ^Recursion) -> Result ---
	recursion_retry   :: proc(ctx: ^Context, tc: ^Test_Case, recursion: ^Recursion) -> Result ---
	recursion_finish  :: proc(ctx: ^Context, tc: ^Test_Case, recursion: ^Recursion) -> Result ---
	recursion_free    :: proc(ctx: ^Context, recursion: ^Recursion) -> Result ---

	// Pools
	new_pool      :: proc(ctx: ^Context, tc: ^Test_Case, out_pool: ^^Pool) -> Result ---
	pool_add      :: proc(ctx: ^Context, tc: ^Test_Case, pool: ^Pool, out_variable_id: ^i64) -> Result ---
	pool_generate :: proc(ctx: ^Context, tc: ^Test_Case, pool: ^Pool, consume: bool, out_variable_id: ^i64) -> Result ---
	pool_free     :: proc(ctx: ^Context, pool: ^Pool) -> Result ---

	// State machines
	new_state_machine :: proc(
		ctx: ^Context,
		tc: ^Test_Case,
		rule_names: [^]cstring,
		rule_groups: [^]i64,
		rule_weights: [^]f64,
		num_rules: c.size_t,
		invariant_names: [^]cstring,
		invariant_always_check: [^]bool,
		num_invariants: c.size_t,
		min_concurrency: i64,
		max_concurrency: i64,
		step_count: i64,
		out_state_machine: ^^State_Machine,
		out_concurrency: ^i64,
	) -> Result ---
	state_machine_next_group            :: proc(ctx: ^Context, tc: ^Test_Case, state_machine: ^State_Machine, out_group_id: ^i64) -> Result ---
	state_machine_next_rule             :: proc(ctx: ^Context, tc: ^Test_Case, state_machine: ^State_Machine, worker_index: i64, out_rule_index: ^i64) -> Result ---
	state_machine_rule_rejected         :: proc(ctx: ^Context, tc: ^Test_Case, state_machine: ^State_Machine, worker_index: i64) -> Result ---
	state_machine_should_check_invariant :: proc(ctx: ^Context, tc: ^Test_Case, state_machine: ^State_Machine, invariant_index: i64, out_should_check: ^bool) -> Result ---
	state_machine_free                  :: proc(ctx: ^Context, state_machine: ^State_Machine) -> Result ---

	// Draws
	generate_boolean     :: proc(ctx: ^Context, tc: ^Test_Case, p: f64, forced: bool, has_forced: bool, out_value: ^bool) -> Result ---
	generate_integer     :: proc(ctx: ^Context, tc: ^Test_Case, min_value: i64, max_value: i64, out_value: ^i64) -> Result ---
	generate_integer_big :: proc(ctx: ^Context, tc: ^Test_Case, min_value: [^]u8, min_value_len: c.size_t, max_value: [^]u8, max_value_len: c.size_t, out_value: [^]u8, out_value_cap: c.size_t, out_value_len: ^c.size_t) -> Result ---
	generate_float       :: proc(ctx: ^Context, tc: ^Test_Case, width: u32, min_value: f64, max_value: f64, allow_nan: bool, allow_infinity: bool, exclude_min: bool, exclude_max: bool, smallest_nonzero_magnitude: f64, out_value: ^f64) -> Result ---
	generate_bytes       :: proc(ctx: ^Context, tc: ^Test_Case, min_size: u64, max_size: u64, out_result: ^Bytes_Result) -> Result ---
	generate_bytes_result_free :: proc(ctx: ^Context, result: ^Bytes_Result) -> Result ---

	string_generator_text :: proc(
		ctx: ^Context,
		min_size: u64,
		max_size: u64,
		codec: cstring,
		min_codepoint: u32,
		max_codepoint: u32,
		categories: [^]cstring,
		categories_len: c.size_t,
		exclude_categories: [^]cstring,
		exclude_categories_len: c.size_t,
		include_characters: [^]u8,
		include_characters_len: c.size_t,
		exclude_characters: [^]u8,
		exclude_characters_len: c.size_t,
		out_generator: ^^String_Generator,
	) -> Result ---
	string_generator_regex  :: proc(ctx: ^Context, pattern: cstring, fullmatch: bool, alphabet: ^String_Generator, out_generator: ^^String_Generator) -> Result ---
	string_generator_email  :: proc(ctx: ^Context, out_generator: ^^String_Generator) -> Result ---
	string_generator_url    :: proc(ctx: ^Context, out_generator: ^^String_Generator) -> Result ---
	string_generator_domain :: proc(ctx: ^Context, max_length: u64, out_generator: ^^String_Generator) -> Result ---
	string_generator_free   :: proc(ctx: ^Context, generator: ^String_Generator) -> Result ---
	generate_string         :: proc(ctx: ^Context, tc: ^Test_Case, generator: ^String_Generator, out_result: ^String_Result) -> Result ---
	generate_string_result_free :: proc(ctx: ^Context, result: ^String_Result) -> Result ---

	generate_date     :: proc(ctx: ^Context, tc: ^Test_Case, min_value: Date, max_value: Date, out_value: ^Date) -> Result ---
	generate_time     :: proc(ctx: ^Context, tc: ^Test_Case, min_value: Time, max_value: Time, out_value: ^Time) -> Result ---
	generate_datetime :: proc(ctx: ^Context, tc: ^Test_Case, min_value: Datetime, max_value: Datetime, out_value: ^Datetime) -> Result ---
	generate_uuid     :: proc(ctx: ^Context, tc: ^Test_Case, version: u8, has_version: bool, out_bytes: ^[16]u8) -> Result ---
	generate_ipv4     :: proc(ctx: ^Context, tc: ^Test_Case, out_bytes: ^[4]u8) -> Result ---
	generate_ipv6     :: proc(ctx: ^Context, tc: ^Test_Case, out_bytes: ^[16]u8) -> Result ---

	// Targeting and statistics
	target      :: proc(ctx: ^Context, tc: ^Test_Case, value: f64, label: cstring) -> Result ---
	event       :: proc(ctx: ^Context, tc: ^Test_Case, label: cstring) -> Result ---
	event_value :: proc(ctx: ^Context, tc: ^Test_Case, value: f64, label: cstring) -> Result ---

	// Pretty printer
	printer_options_new           :: proc(ctx: ^Context, out_options: ^^Printer_Options) -> Result ---
	printer_options_free          :: proc(ctx: ^Context, options: ^Printer_Options) -> Result ---
	printer_options_set_max_width :: proc(ctx: ^Context, options: ^Printer_Options, max_width: u64) -> Result ---
	printer_new                   :: proc(ctx: ^Context, options: ^Printer_Options, out_printer: ^^Printer) -> Result ---
	printer_free                  :: proc(ctx: ^Context, printer: ^Printer) -> Result ---
	printer_if_break              :: proc(ctx: ^Context, printer: ^Printer, text: [^]u8, len: c.size_t) -> Result ---
	printer_text                  :: proc(ctx: ^Context, printer: ^Printer, text: [^]u8, len: c.size_t) -> Result ---
	printer_breakable             :: proc(ctx: ^Context, printer: ^Printer, sep: [^]u8, len: c.size_t) -> Result ---
	printer_comment               :: proc(ctx: ^Context, printer: ^Printer, text: [^]u8, len: c.size_t) -> Result ---
	printer_hard_break            :: proc(ctx: ^Context, printer: ^Printer) -> Result ---
	printer_begin_group           :: proc(ctx: ^Context, printer: ^Printer, indent: u64, open: [^]u8, open_len: c.size_t) -> Result ---
	printer_end_group             :: proc(ctx: ^Context, printer: ^Printer, close: [^]u8, close_len: c.size_t) -> Result ---
	printer_shift_indent          :: proc(ctx: ^Context, printer: ^Printer, delta: i64) -> Result ---
	printer_deferred              :: proc(ctx: ^Context, printer: ^Printer, out_printer: ^^Printer) -> Result ---
	printer_begin_speculative     :: proc(ctx: ^Context, printer: ^Printer) -> Result ---
	printer_commit_speculative    :: proc(ctx: ^Context, printer: ^Printer) -> Result ---
	printer_abort_speculative     :: proc(ctx: ^Context, printer: ^Printer) -> Result ---
	printer_resolve               :: proc(ctx: ^Context, printer: ^Printer) -> Result ---
	printer_is_live               :: proc(ctx: ^Context, printer: ^Printer, out_live: ^bool) -> Result ---
	printer_value                 :: proc(ctx: ^Context, printer: ^Printer, out_result: ^Printer_Value_Result) -> Result ---
	printer_value_result_free     :: proc(ctx: ^Context, result: ^Printer_Value_Result) -> Result ---
	test_case_printer             :: proc(ctx: ^Context, tc: ^Test_Case, options: ^Printer_Options, out_printer: ^^Printer) -> Result ---
	note                          :: proc(ctx: ^Context, tc: ^Test_Case, text: [^]u8, len: c.size_t) -> Result ---

	// Results and failures
	run_result_status        :: proc(ctx: ^Context, r: ^Run_Result, out_status: ^Run_Status) -> Result ---
	run_result_error         :: proc(ctx: ^Context, r: ^Run_Result, out_error: ^cstring) -> Result ---
	run_result_failure_count :: proc(ctx: ^Context, r: ^Run_Result, out_count: ^c.size_t) -> Result ---
	run_result_failure       :: proc(ctx: ^Context, r: ^Run_Result, index: c.size_t, out_failure: ^^Failure) -> Result ---
	failure_free             :: proc(ctx: ^Context, f: ^Failure) -> Result ---
	failure_origin           :: proc(ctx: ^Context, f: ^Failure, out_origin: ^cstring) -> Result ---
	failure_reproduction_blob :: proc(ctx: ^Context, f: ^Failure, out_blob: ^cstring) -> Result ---

	version :: proc(ctx: ^Context, out_version: ^cstring) -> Result ---
}
