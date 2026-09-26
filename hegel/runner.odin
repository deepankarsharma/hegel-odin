package hegel

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:log"
import "core:mem/virtual"
import "core:path/filepath"
import "core:strings"
import "core:testing"

import lh "libhegel"

Verbosity     :: lh.Verbosity
Backend       :: lh.Backend
Phase         :: lh.Phase
Phases        :: lh.Phases
Health_Check  :: lh.Health_Check
Health_Checks :: lh.Health_Checks

ALL_PHASES        :: lh.ALL_PHASES
ALL_HEALTH_CHECKS :: lh.ALL_HEALTH_CHECKS

/*
Configures a run. Every field left at its zero value (`nil` for the `Maybe`
fields) keeps the value from the active settings profile, which defaults to
100 test cases, all phases, and an example database under `.hegel/`.

	hegel.test(t, my_property, {test_cases = 1000, seed = 42})
*/
Settings :: struct {
	// Number of valid test cases to try before declaring the property held.
	test_cases:               Maybe(int),
	// Fixes the random seed, making the run reproducible.
	seed:                     Maybe(u64),
	// Derives the seed from the database key instead of fresh randomness.
	derandomize:              Maybe(bool),
	// Directory of the example database; `""` disables it.
	database:                 Maybe(string),
	// Scopes the database. Defaults to the calling file and procedure.
	database_key:             string,
	verbosity:                Maybe(Verbosity),
	phases:                   Maybe(Phases),
	suppress_health_checks:   Maybe(Health_Checks),
	// Keep searching after the first failure to report every distinct bug.
	report_multiple_failures: Maybe(bool),
	// Print a statistics block for `event` / `event_value` at the end.
	show_statistics:          Maybe(bool),
	// Include the reproduction blob in failure reports.
	print_blob:               Maybe(bool),
	// Lift the per-test-case limit of 2^20 choices.
	unbounded_choices:        Maybe(bool),
	backend:                  Maybe(Backend),
	// Settings profile to start from: "development", "ci", "workload", or one
	// registered with `register_profile` or defined in `hegel.toml`.
	profile:                  string,
	// Replay exactly this reproduction blob instead of generating test cases.
	reproduce:                string,
}

Run_Status :: enum u8 {
	Passed, // Every test case satisfied the property.
	Failed, // The property failed; see `Run_Result.failures`.
	Error,  // The run itself failed (health check, misuse); see `Run_Result.error`.
}

// One distinct counterexample, as observed when replaying its minimal example.
Failure :: struct {
	message:  string,
	location: runtime.Source_Code_Location,
	// The draws and notes printed while replaying the minimal example.
	output:   string,
	// The key the engine grouped this failure under.
	origin:   string,
	// Replays this failure via `Settings.reproduce`. Empty when unavailable.
	blob:     string,
	// The failure did not reproduce on replay.
	flaky:    bool,
}

Run_Result :: struct {
	status:     Run_Status,
	error:      string,
	failures:   []Failure,
	print_blob: bool,
	allocator:  runtime.Allocator,
}

// A property: a procedure that draws values and checks they behave.
Property :: #type proc(tc: ^Test_Case)

@(private)
Run_State :: struct {
	ctx:            ^lh.Context,
	settings:       ^lh.Settings,
	property:       Property,
	data_property:  proc(tc: ^Test_Case, data: rawptr),
	user_data:      rawptr,
	logger:         log.Logger,
	arena:          virtual.Arena,
	allocator:      runtime.Allocator,
}

/*
Runs `property` against many generated test cases, shrinking any failure to a
minimal example, and returns the outcome. Release the result with
`destroy_run_result`.

Inside the property:

- `context.allocator` and `context.temp_allocator` point at an arena that is
  reset after every test case, so drawn values never need freeing (and must
  not be kept past the test case).
- `assert`, `panic`, `hegel.expect`, and error-level `log` calls fail the test
  case at their location and stop it; `defer`s between that point and the
  property's entry are skipped.
- Hardware faults such as out-of-bounds indexing still crash the process.
*/
run :: proc(property: Property, settings := Settings{}, allocator := context.allocator, loc := #caller_location) -> Run_Result {
	rs := Run_State{property = property}
	return run_state(&rs, settings, allocator, loc)
}

// Like `run`, but passes `data` to the property.
run_with_data :: proc(data: ^$D, property: proc(tc: ^Test_Case, data: ^D), settings := Settings{}, allocator := context.allocator, loc := #caller_location) -> Run_Result {
	rs := Run_State{data_property = transmute(proc(tc: ^Test_Case, data: rawptr))property, user_data = data}
	return run_state(&rs, settings, allocator, loc)
}

/*
Runs `property` as part of a `core:testing` test, failing `t` with a report of
each minimal failing example.

	@(test)
	test_reverse_twice :: proc(t: ^testing.T) {
		hegel.test(t, proc(tc: ^hegel.Test_Case) {
			xs := hegel.draw(tc, hegel.lists(hegel.integers(int)))
			ys := slice.clone(xs)
			slice.reverse(ys)
			slice.reverse(ys)
			hegel.expect(tc, slice.equal(xs, ys))
		})
	}
*/
test :: proc(t: ^testing.T, property: Property, settings := Settings{}, loc := #caller_location) {
	result := run(property, settings, context.allocator, loc)
	defer destroy_run_result(&result)
	report(t, result, loc)
}

// Like `test`, but passes `data` to the property.
test_with_data :: proc(t: ^testing.T, data: ^$D, property: proc(tc: ^Test_Case, data: ^D), settings := Settings{}, loc := #caller_location) {
	result := run_with_data(data, property, settings, context.allocator, loc)
	defer destroy_run_result(&result)
	report(t, result, loc)
}

// Fails `t` once per failure in `result`, or once for a run error.
report :: proc(t: ^testing.T, result: Run_Result, loc := #caller_location) {
	switch result.status {
	case .Passed:
	case .Error:
		testing.expectf(t, false, "hegel: %s", result.error, loc = loc)
	case .Failed:
		for failure in result.failures {
			message := format_failure(failure, result.print_blob, context.temp_allocator)
			failure_loc := failure.location if failure.location.file_path != "" else loc
			testing.expect(t, false, message, loc = failure_loc)
		}
	}
}

/*
Renders a failure the way `test` reports it:

	Property failed with minimal example:
	    xs: []int = {0, 0}
	expected slice.equal(xs, ys) to be true
	Reproduce with: hegel.Settings{reproduce = "AXicY2BgYGA..."}
*/
format_failure :: proc(failure: Failure, print_blob := true, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	if failure.flaky {
		strings.write_string(&b, "Flaky failure: the minimal example passed when replayed.\n")
	}
	if failure.output != "" {
		strings.write_string(&b, "Property failed with minimal example:\n")
		output := failure.output
		for line in strings.split_lines_iterator(&output) {
			if line != "" {
				fmt.sbprintf(&b, "    %s\n", line)
			}
		}
	} else {
		strings.write_string(&b, "Property failed.\n")
	}
	strings.write_string(&b, failure.message)
	if print_blob && failure.blob != "" {
		fmt.sbprintf(&b, "\nReproduce with: hegel.Settings{{reproduce = %q}}", failure.blob)
	}
	return strings.to_string(b)
}

destroy_run_result :: proc(result: ^Run_Result) {
	context.allocator = result.allocator
	delete(result.error)
	for f in result.failures {
		delete(f.message)
		delete(f.output)
		delete(f.origin)
		delete(f.blob)
	}
	delete(result.failures)
	result^ = {}
}

// The version of the linked libhegel engine.
engine_version :: proc() -> string {
	v: cstring
	lh.version(nil, &v)
	return string(v)
}

/*
Registers `settings` as the named profile for the whole process. Only the
fields that are set are recorded, over the `base` profile.
*/
register_profile :: proc(name: string, settings: Settings) -> (ok: bool) {
	ctx := lh.context_new()
	defer lh.context_free(ctx)
	s, err := build_settings(ctx, settings, context.temp_allocator)
	if err != "" {
		return false
	}
	defer lh.settings_free(ctx, s)
	return lh.settings_register_profile(ctx, cstr(name), s) == .Ok
}

@(private)
run_state :: proc(rs: ^Run_State, settings: Settings, allocator: runtime.Allocator, loc: runtime.Source_Code_Location) -> (result: Run_Result) {
	result.allocator = allocator
	rs.allocator = allocator
	rs.logger = context.logger

	rs.ctx = lh.context_new()
	defer lh.context_free(rs.ctx)

	resolved := settings
	if resolved.database_key == "" {
		resolved.database_key = fmt.tprintf("%s::%s", filepath.base(loc.file_path), loc.procedure)
	}
	s, err := build_settings(rs.ctx, resolved, context.temp_allocator)
	if err != "" {
		result.status = .Error
		result.error = strings.clone(err, allocator)
		return
	}
	rs.settings = s
	defer lh.settings_free(rs.ctx, s)
	lh.settings_set_test_location(rs.ctx, s, cstr(loc.file_path), u32(loc.line), cstr(filepath.base(filepath.dir(loc.file_path))), cstr(loc.procedure))
	lh.settings_get_print_blob(rs.ctx, s, &result.print_blob)

	if arena_err := virtual.arena_init_growing(&rs.arena); arena_err != nil {
		result.status = .Error
		result.error = fmt.aprintf("hegel: could not create the test-case arena: %v", arena_err, allocator = allocator)
		return
	}
	defer virtual.arena_destroy(&rs.arena)

	if settings.reproduce != "" {
		reproduce(rs, &result, settings.reproduce)
		return
	}
	run_generation(rs, &result)
	return
}

// The main loop: pull test cases until the engine is done, then replay each
// distinct failure to observe it.
@(private)
run_generation :: proc(rs: ^Run_State, result: ^Run_Result) {
	run: ^lh.Run
	if rc := lh.run_start(rs.ctx, rs.settings, engine_output, rs, &run); rc != .Ok {
		fail_run(rs, result, rc)
		return
	}
	defer lh.run_free(rs.ctx, run)

	for {
		handle: ^lh.Test_Case
		if rc := lh.next_test_case(rs.ctx, run, &handle); rc != .Ok {
			fail_run(rs, result, rc)
			return
		}
		if handle == nil {
			break
		}
		outcome, _ := execute(rs, handle, false)
		lh.test_case_free(rs.ctx, handle)
		if outcome.kind == .Error || outcome.kind == .Retry {
			result.status = .Error
			result.error = describe_error(outcome, rs.allocator)
			delete(outcome.message, rs.allocator)
			return
		}
	}

	engine_result: ^lh.Run_Result
	if rc := lh.run_result(rs.ctx, run, &engine_result); rc != .Ok {
		fail_run(rs, result, rc)
		return
	}
	defer lh.run_result_free(rs.ctx, engine_result)

	status: lh.Run_Status
	lh.run_result_status(rs.ctx, engine_result, &status)
	switch status {
	case .Passed:
		result.status = .Passed
	case .Error:
		message: cstring
		lh.run_result_error(rs.ctx, engine_result, &message)
		result.status = .Error
		result.error = strings.clone(string(message), rs.allocator)
	case .Failed, .Failed_Nondeterministic:
		result.status = .Failed
		count: c.size_t
		lh.run_result_failure_count(rs.ctx, engine_result, &count)
		failures := make([dynamic]Failure, 0, int(count), rs.allocator)
		for i in 0 ..< count {
			engine_failure: ^lh.Failure
			lh.run_result_failure(rs.ctx, engine_result, i, &engine_failure)
			origin, blob: cstring
			lh.failure_origin(rs.ctx, engine_failure, &origin)
			lh.failure_reproduction_blob(rs.ctx, engine_failure, &blob)
			failure, _ := replay(rs, string(blob), string(origin))
			append(&failures, failure)
			lh.failure_free(rs.ctx, engine_failure)
		}
		result.failures = failures[:]
	}
}

@(private)
reproduce :: proc(rs: ^Run_State, result: ^Run_Result, blob: string) {
	failure, ok := replay(rs, blob, "")
	if !ok {
		result.status = .Error
		result.error = failure.message
		failure.message = ""
		destroy_failure(failure, rs.allocator)
		return
	}
	if failure.flaky {
		destroy_failure(failure, rs.allocator)
		result.status = .Passed
		return
	}
	result.status = .Failed
	result.failures = make([]Failure, 1, rs.allocator)
	result.failures[0] = failure
}

// Replays a reproduction blob, recording the output of the minimal example.
@(private)
replay :: proc(rs: ^Run_State, blob, origin: string) -> (failure: Failure, ok: bool) {
	failure.origin = strings.clone(origin, rs.allocator)
	failure.blob = strings.clone(blob, rs.allocator)
	if blob == "" {
		failure.message = strings.clone("The failure could not be replayed: the engine produced no reproduction blob.", rs.allocator)
		return failure, true
	}
	handle: ^lh.Test_Case
	if rc := lh.test_case_from_blob(rs.ctx, rs.settings, cstr(blob), engine_output, rs, &handle); rc != .Ok {
		failure.message = engine_error(rs.ctx, rc, rs.allocator)
		return failure, false
	}
	outcome, output := execute(rs, handle, true)
	lh.test_case_free(rs.ctx, handle)

	failure.output = output
	failure.location = outcome.location
	switch outcome.kind {
	case .Failed:
		failure.message = outcome.message
	case .Error, .Retry:
		failure.message = describe_error(outcome, rs.allocator)
		delete(outcome.message, rs.allocator)
	case .Passed, .Rejected, .Overrun:
		failure.flaky = true
		failure.message = fmt.aprintf("The minimal example ended as %v when replayed.", outcome.kind, allocator = rs.allocator)
		failure.location = {}
		delete(outcome.message, rs.allocator)
	}
	return failure, true
}

/*
Runs the property once against `handle` and completes the test case. When
`capture` is set the property's draws and notes are recorded and returned,
and the outcome's message is copied into the run allocator.
*/
@(private)
execute :: proc(rs: ^Run_State, handle: ^lh.Test_Case, capture: bool) -> (outcome: Outcome, output: string) {
	cs := Case_State{run = rs, capturing = capture}
	tc := Test_Case{user_data = rs.user_data, _ctx = rs.ctx, _handle = handle, _case = &cs}

	printer: ^lh.Printer
	if capture {
		lh.test_case_printer(rs.ctx, handle, nil, &printer)
	}

	{
		arena := virtual.arena_allocator(&rs.arena)
		context.allocator = arena
		context.temp_allocator = arena
		context.logger = {property_logger_proc, nil, .Debug, nil}
		context.assertion_failure_proc = property_assertion_failure

		cs.owned = make([dynamic]Owned_Handle)
		outcome = invoke(&tc, run_property, rs)
		release_owned(rs.ctx, &cs)
	}

	status: lh.Status
	origin: cstring
	origin_buf: [1024]u8
	switch outcome.kind {
	case .Passed:           status = .Valid
	case .Rejected:         status = .Invalid
	case .Overrun:          status = .Overrun
	case .Error, .Retry:    status = .Invalid
	case .Failed:
		status = .Interesting
		origin = origin_of(outcome.location, origin_buf[:])
	}
	lh.mark_complete(rs.ctx, handle, status, origin)

	if capture {
		lh.printer_resolve(rs.ctx, printer)
		value: lh.Printer_Value_Result
		if lh.printer_value(rs.ctx, printer, &value) == .Ok {
			output = strings.clone(strings.trim_right(string(value.data[:value.len]), "\n"), rs.allocator)
			lh.printer_value_result_free(rs.ctx, &value)
		}
		lh.printer_free(rs.ctx, printer)
	}
	if capture || outcome.kind == .Error || outcome.kind == .Retry {
		outcome.message = strings.clone(outcome.message, rs.allocator)
	} else {
		outcome.message = ""
	}
	virtual.arena_free_all(&rs.arena)
	return
}

@(private)
run_property :: proc(tc: ^Test_Case, data: rawptr) {
	rs := (^Run_State)(data)
	if rs.property != nil {
		rs.property(tc)
	} else {
		rs.data_property(tc, tc.user_data)
	}
}

// Failures are grouped by where they happened: one location, one bug.
@(private)
origin_of :: proc(loc: runtime.Source_Code_Location, buf: []u8) -> cstring {
	s := fmt.bprintf(buf[:len(buf) - 1], "%s:%d:%d", loc.file_path, loc.line, loc.column)
	buf[len(s)] = 0
	return cstring(raw_data(buf))
}

@(private)
describe_error :: proc(outcome: Outcome, allocator: runtime.Allocator) -> string {
	if outcome.kind == .Retry {
		return fmt.aprintf("internal error: a recursive draw escaped its generator at %v", outcome.location, allocator = allocator)
	}
	return fmt.aprintf("%s (at %v)", outcome.message, outcome.location, allocator = allocator)
}

@(private)
fail_run :: proc(rs: ^Run_State, result: ^Run_Result, rc: lh.Result) {
	result.status = .Error
	result.error = engine_error(rs.ctx, rc, rs.allocator)
}

@(private)
destroy_failure :: proc(f: Failure, allocator: runtime.Allocator) {
	delete(f.message, allocator)
	delete(f.output, allocator)
	delete(f.origin, allocator)
	delete(f.blob, allocator)
}

// Engine output (statistics, notices) goes to the caller's logger.
@(private)
engine_output :: proc "c" (user_data: rawptr, line: cstring, len: c.size_t) {
	rs := (^Run_State)(user_data)
	context = runtime.default_context()
	context.logger = rs.logger
	log.info(string(line))
}

@(private)
build_settings :: proc(ctx: ^lh.Context, settings: Settings, allocator: runtime.Allocator) -> (s: ^lh.Settings, err: string) {
	rc: lh.Result
	if settings.profile == "" {
		rc = lh.settings_new(ctx, &s)
	} else {
		rc = lh.settings_new_for_profile(ctx, cstr(settings.profile), &s)
	}
	if rc != .Ok {
		return nil, engine_error(ctx, rc, allocator)
	}

	if n, ok := settings.test_cases.?; ok {
		if n < 1 {
			lh.settings_free(ctx, s)
			return nil, fmt.aprintf("test_cases must be positive, got %d", n, allocator = allocator)
		}
		lh.settings_set_test_cases(ctx, s, u64(n))
	}
	if seed, ok := settings.seed.?; ok {
		lh.settings_set_seed(ctx, s, seed, true)
	}
	if v, ok := settings.derandomize.?; ok {
		lh.settings_set_derandomize(ctx, s, v)
	}
	if db, ok := settings.database.?; ok {
		lh.settings_set_database(ctx, s, cstr(db))
	}
	if settings.database_key != "" {
		lh.settings_set_database_key(ctx, s, cstr(settings.database_key))
	}
	if v, ok := settings.verbosity.?; ok {
		lh.settings_set_verbosity(ctx, s, u32(v))
	}
	if v, ok := settings.phases.?; ok {
		lh.settings_set_phases(ctx, s, v)
	}
	if v, ok := settings.suppress_health_checks.?; ok {
		lh.settings_set_suppress_health_check(ctx, s, v)
	}
	if v, ok := settings.report_multiple_failures.?; ok {
		lh.settings_set_report_multiple_failures(ctx, s, v)
	}
	if v, ok := settings.show_statistics.?; ok {
		lh.settings_set_show_statistics(ctx, s, v)
	}
	if v, ok := settings.print_blob.?; ok {
		lh.settings_set_print_blob(ctx, s, v)
	}
	if v, ok := settings.unbounded_choices.?; ok {
		lh.settings_set_unbounded_choices(ctx, s, v)
	}
	if v, ok := settings.backend.?; ok {
		lh.settings_set_backend(ctx, s, u32(v))
	}
	return s, ""
}
