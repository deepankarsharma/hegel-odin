package hegel_tests

import "core:strings"
import "core:testing"

import hegel "../hegel"

// Deterministic settings with the example database disabled, so tests
// neither depend on nor pollute state from earlier runs.
quiet :: proc(test_cases := 100) -> hegel.Settings {
	return {test_cases = test_cases, database = "", derandomize = true}
}

// Checks that `result` failed exactly once and returns that failure.
single_failure :: proc(t: ^testing.T, result: hegel.Run_Result, loc := #caller_location) -> (failure: hegel.Failure, ok: bool) {
	testing.expect_value(t, result.status, hegel.Run_Status.Failed, loc = loc) or_return
	testing.expect_value(t, len(result.failures), 1, loc = loc) or_return
	return result.failures[0], true
}

expect_contains :: proc(t: ^testing.T, haystack, needle: string, loc := #caller_location) -> bool {
	return testing.expectf(t, strings.contains(haystack, needle), "expected %q to contain %q", haystack, needle, loc = loc)
}
