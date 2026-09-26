package hegel

import "base:intrinsics"
import "base:runtime"
import "core:c/libc"
import "core:fmt"
import "core:log"
import "core:strings"

import lh "libhegel"

// A span label: an opaque identity the shrinker uses to recognise draws made
// by the same generator. See `label_of` and `combine_labels`.
Label :: u64

/*
The handle a property draws from.

A `^Test_Case` is only valid inside the property (or generator) it was passed
to. `user_data` carries the pointer given to `run_with_data` / `test_with_data`.
*/
Test_Case :: struct {
	user_data: rawptr,

	_ctx:      ^lh.Context,
	_handle:   ^lh.Test_Case,
	_case:     ^Case_State,
	_boundary: ^Boundary,
	_depth:    int,
}

// How one execution of a property ended.
Outcome_Kind :: enum u8 {
	Passed,   // The property returned normally.
	Rejected, // An assumption failed; the test case is discarded.
	Overrun,  // The engine ran out of choices for this test case.
	Failed,   // The property failed: this test case is a counterexample.
	Error,    // The API was misused, or the engine reported an error.
	Retry,    // Internal: a recursive draw must restart from its root.
}

Outcome :: struct {
	kind:     Outcome_Kind,
	message:  string,
	location: runtime.Source_Code_Location,
	// For `.Retry`: the recursion scope that must restart.
	_scope:   rawptr,
}

@(private)
Boundary :: struct {
	buf:     libc.jmp_buf,
	outcome: Outcome,
}

// State shared by every handle onto one test case.
@(private)
Case_State :: struct {
	run:        ^Run_State,
	capturing:  bool,
	draw_count: int,
	owned:      [dynamic]Owned_Handle,
}

// Engine handles created during a test case, released when it completes so
// that an aborted draw cannot leak them.
@(private)
Owned_Handle :: union {
	^lh.Collection,
	^lh.Recursion,
	^lh.Pool,
	^lh.State_Machine,
	^lh.Test_Case,
}

@(private, thread_local)
tls_current: ^Test_Case

/*
Abandons the current test case if `condition` is false.

Rejected test cases do not count as failures; the engine simply generates
another one. Prefer constraining generators over heavy use of `assume`, since
too many rejections fail the `Filter_Too_Much` health check.
*/
assume :: proc(tc: ^Test_Case, condition: bool) {
	if !condition {
		abort(tc, .Rejected)
	}
}

// Unconditionally abandons the current test case, as `assume(tc, false)`.
reject :: proc(tc: ^Test_Case) -> ! {
	abort(tc, .Rejected)
}

// Fails the property at the caller's location and stops the test case.
fail :: proc(tc: ^Test_Case, message := "", loc := #caller_location) -> ! {
	abort(tc, .Failed, message if message != "" else "property failed", loc)
}

// Fails the property with a formatted message and stops the test case.
failf :: proc(tc: ^Test_Case, format: string, args: ..any, loc := #caller_location) -> ! {
	abort(tc, .Failed, fmt.tprintf(format, ..args), loc)
}

/*
Fails the property if `ok` is false. Unlike `testing.expect`, a failed
expectation stops the test case immediately, so later code may rely on it.
*/
expect :: proc(tc: ^Test_Case, ok: bool, message := "", expr := #caller_expression(ok), loc := #caller_location) {
	if !ok {
		fail(tc, message if message != "" else fmt.tprintf("expected %v to be true", expr), loc)
	}
}

expectf :: proc(tc: ^Test_Case, ok: bool, format: string, args: ..any, loc := #caller_location) {
	if !ok {
		abort(tc, .Failed, fmt.tprintf(format, ..args), loc)
	}
}

expect_value :: proc(tc: ^Test_Case, value, expected: $T, value_expr := #caller_expression(value), loc := #caller_location) where intrinsics.type_is_comparable(T) {
	if value != expected {
		abort(tc, .Failed, fmt.tprintf("expected %v to be %v, got %v", value_expr, expected, value), loc)
	}
}

/*
Records a message that is shown with the minimal failing example.

Notes are only kept while replaying a failure, so they cost nothing during
generation and shrinking. `log.info` and friends behave the same way inside a
property.
*/
note :: proc(tc: ^Test_Case, message: string) {
	if !tc._case.capturing {
		return
	}
	check(tc, lh.note(tc._ctx, tc._handle, raw_data(message), len(message)))
}

notef :: proc(tc: ^Test_Case, format: string, args: ..any) {
	if tc._case.capturing {
		note(tc, fmt.tprintf(format, ..args))
	}
}

/*
Guides generation towards test cases that maximise `value`, which must be
finite. Each label may be targeted at most once per test case.
*/
target :: proc(tc: ^Test_Case, value: f64, label := "") {
	check(tc, lh.target(tc._ctx, tc._handle, value, cstr(label)))
}

// Records `label` for the end-of-run statistics (see `Settings.show_statistics`).
event :: proc(tc: ^Test_Case, label: string) {
	check(tc, lh.event(tc._ctx, tc._handle, cstr(label)))
}

// Records a finite numeric observation for the end-of-run statistics.
event_value :: proc(tc: ^Test_Case, label: string, value: f64) {
	check(tc, lh.event_value(tc._ctx, tc._handle, value, cstr(label)))
}

/*
Draws a value from `gen`.

When the property fails, every top-level draw of the minimal example is shown
as an Odin declaration. `name` labels it there; unnamed draws are shown as
`draw_1`, `draw_2`, ... in draw order.
*/
draw :: proc(tc: ^Test_Case, gen: Generator($T), name := "") -> T {
	start_span(tc, gen.label)
	value := gen.draw_proc(tc, gen.data)
	stop_span(tc)
	if tc._depth == 0 && tc._case.capturing {
		report_draw(tc, value, name)
	}
	return value
}

@(private)
report_draw :: proc(tc: ^Test_Case, value: $T, name: string) {
	tc._case.draw_count += 1
	label := name if name != "" else fmt.tprintf("draw_%d", tc._case.draw_count)
	note(tc, fmt.tprintf("%s: %s = %w", label, type_name(T), value))
}

// The name of `T` as written in source: `Maybe(int)` rather than the
// `Maybe($T=int)` that formatting a parapoly typeid produces.
@(private)
type_name :: proc($T: typeid) -> string {
	raw := fmt.tprintf("%v", typeid_of(T))
	b := strings.builder_make()
	for i := 0; i < len(raw); i += 1 {
		if raw[i] == '$' {
			j := i + 1
			for j < len(raw) && raw[j] != '=' && raw[j] != ',' && raw[j] != ')' {
				j += 1
			}
			if j < len(raw) && raw[j] == '=' {
				i = j
				continue
			}
		}
		strings.write_byte(&b, raw[i])
	}
	return strings.to_string(b)
}

/*
Opens a span labelled `label`. Spans group the draws that make up one value so
the shrinker can move, duplicate, and delete them as a unit. `draw` opens one
around every generator, so custom generators rarely need this directly.
*/
start_span :: proc(tc: ^Test_Case, label: Label) {
	check(tc, lh.start_span(tc._ctx, tc._handle, label))
	tc._depth += 1
}

// Closes the innermost span. `discard` marks its draws as rejected.
stop_span :: proc(tc: ^Test_Case, discard := false) {
	check(tc, lh.stop_span(tc._ctx, tc._handle, discard))
	tc._depth -= 1
}

@(private)
abort :: proc(tc: ^Test_Case, kind: Outcome_Kind, message := "", loc := #caller_location) -> ! {
	abort_with(tc, {kind = kind, message = message, location = loc})
}

// Re-raises an outcome caught by a nested boundary.
@(private)
abort_with :: proc(tc: ^Test_Case, outcome: Outcome) -> ! {
	b := tc._boundary
	if b == nil {
		runtime.default_assertion_failure_proc("hegel", "a Test_Case was used outside of its property", outcome.location)
	}
	b.outcome = outcome
	longjmp_boundary(b)
}

@(private)
longjmp_boundary :: proc(b: ^Boundary) -> ! {
	libc.longjmp(&b.buf, 1)
}

@(private)
usage_error :: proc(tc: ^Test_Case, format: string, args: ..any, loc := #caller_location) -> ! {
	abort(tc, .Error, fmt.tprintf(format, ..args), loc)
}

// Converts a draw's result code into control flow: stop, reject, or error.
@(private)
check :: proc(tc: ^Test_Case, rc: lh.Result, loc := #caller_location) {
	#partial switch rc {
	case .Ok:
		return
	case .Stop_Test:
		abort(tc, .Overrun, "", loc)
	case .Assume:
		abort(tc, .Rejected, "", loc)
	}
	abort(tc, .Error, engine_error(tc._ctx, rc), loc)
}

@(private)
engine_error :: proc(ctx: ^lh.Context, rc: lh.Result, allocator := context.temp_allocator) -> string {
	message := string(lh.context_last_error(ctx))
	if message == "" {
		return fmt.aprintf("libhegel returned %v", rc, allocator = allocator)
	}
	return fmt.aprintf("libhegel returned %v: %s", rc, message, allocator = allocator)
}

/*
Runs `body` behind a fresh abort boundary and reports how it ended. Every
abort — failed assertions, rejected assumptions, exhausted choice budgets —
longjmps back here, so `defer` statements between the abort and this boundary
do not run. The per-test-case arena reclaims their memory instead.

Kept out of line and unoptimised because the compiler does not know `setjmp`
returns twice.
*/
@(private, optimization_mode = "none")
invoke :: proc(tc: ^Test_Case, body: proc(tc: ^Test_Case, data: rawptr), data: rawptr) -> Outcome {
	boundary: Boundary
	saved_boundary := tc._boundary
	saved_depth := tc._depth
	saved_current := tls_current

	tc._boundary = &boundary
	tls_current = tc
	if libc.setjmp(&boundary.buf) != 0 {
		tc._boundary = saved_boundary
		tc._depth = saved_depth
		tls_current = saved_current
		return boundary.outcome
	}
	body(tc, data)
	tc._boundary = saved_boundary
	tls_current = saved_current
	return {kind = .Passed}
}

// Keeps an engine handle alive until the test case completes.
@(private)
own :: proc(tc: ^Test_Case, handle: Owned_Handle) {
	append(&tc._case.owned, handle)
}

@(private)
release_owned :: proc(ctx: ^lh.Context, cs: ^Case_State) {
	#reverse for handle in cs.owned {
		switch h in handle {
		case ^lh.Collection:    lh.collection_free(ctx, h)
		case ^lh.Recursion:     lh.recursion_free(ctx, h)
		case ^lh.Pool:          lh.pool_free(ctx, h)
		case ^lh.State_Machine: lh.state_machine_free(ctx, h)
		case ^lh.Test_Case:     lh.test_case_free(ctx, h)
		}
	}
	clear(&cs.owned)
}

// Inside a property, `assert` and `panic` fail the test case instead of
// crashing the test.
@(private)
property_assertion_failure :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	tc := tls_current
	if tc == nil || tc._boundary == nil {
		runtime.default_assertion_failure_proc(prefix, message, loc)
	}
	text := prefix if message == "" else fmt.tprintf("%s: %s", prefix, message)
	abort(tc, .Failed, text, loc)
}

// Inside a property, error-level log messages (including `testing.expect`
// failures) fail the test case; lower levels become notes.
@(private)
property_logger_proc :: proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
	tc := tls_current
	if tc == nil || tc._boundary == nil {
		return
	}
	if level >= .Error {
		abort(tc, .Failed, text, location)
	}
	if tc._case.capturing {
		note(tc, fmt.tprintf("[%v] %s", level, text))
	}
}

// NUL-terminates a string in the temporary allocator.
@(private)
cstr :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}
