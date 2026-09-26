package hegel_tests

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "core:testing"

import hg "../hegel"

@(test) test_passing_property :: proc(t: ^testing.T) { hg.test(t, passing_property, quiet()) }

passing_property :: proc(tc: ^hg.Test_Case) {
	xs := hg.draw(tc, hg.lists(hg.integers(int)))
	ys := slice.clone(xs)
	slice.reverse(ys)
	slice.reverse(ys)
	hg.expect(tc, slice.equal(xs, ys))
}

@(test)
test_engine_version :: proc(t: ^testing.T) {
	testing.expect(t, hg.engine_version() != "")
}

@(test)
test_failure_is_shrunk_to_minimal_integer :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(int), "n")
		hg.expect(tc, n < 50)
	}, quiet())
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.output, "n: int = 50")
	testing.expect_value(t, failure.message, "expected n < 50 to be true")
	testing.expect(t, failure.blob != "")
	testing.expect(t, !failure.flaky)
	testing.expect(t, strings.has_suffix(failure.location.file_path, "runner_test.odin"))
}

@(test)
test_assert_fails_the_property :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		x := hg.draw(tc, hg.integers(i32, 0, 1000))
		assert(x < 10, "x is too big")
	}, quiet())
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.output, "draw_1: i32 = 10")
	expect_contains(t, failure.message, "x is too big")
}

@(test)
test_panic_fails_the_property :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		if hg.draw(tc, hg.booleans()) {
			panic("boom")
		}
	}, quiet())
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	expect_contains(t, failure.message, "boom")
	testing.expect_value(t, failure.output, "draw_1: bool = true")
}

@(test)
test_log_error_fails_the_property :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(u8))
		if n > 3 {
			log.errorf("n = %d", n)
		}
	}, quiet())
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "n = 4")
}

@(test)
test_testing_expect_inside_property :: proc(t: ^testing.T) {
	result := hg.run_with_data(t, proc(tc: ^hg.Test_Case, t: ^testing.T) {
		s := hg.draw(tc, hg.text(alphabet = hg.chars_of("ab")), "s")
		testing.expect(t, !strings.contains(s, "b"))
	}, quiet())
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.output, `s: string = "b"`)
}

@(test)
test_fail_and_failf :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(int, 0, 100))
		if n == 100 {
			hg.fail(tc, "hit the top")
		}
		if n > 20 {
			hg.failf(tc, "%d is more than 20", n)
		}
	}, quiet(500))
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "21 is more than 20")
}

@(test)
test_expect_value_message :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(int, 0, 10))
		hg.expect_value(tc, n * 2, 0)
	}, quiet())
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "expected n * 2 to be 0, got 2")
}

@(test) test_assume_filters_test_cases :: proc(t: ^testing.T) { hg.test(t, assume_filters_test_cases, quiet()) }

assume_filters_test_cases :: proc(tc: ^hg.Test_Case) {
	n := hg.draw(tc, hg.integers(int, 0, 100))
	hg.assume(tc, n % 2 == 0)
	hg.expect(tc, n % 2 == 0)
}

@(test)
test_rejecting_everything_is_a_health_check_error :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.integers(int))
		hg.reject(tc)
	}, quiet())
	defer hg.destroy_run_result(&result)

	testing.expect_value(t, result.status, hg.Run_Status.Error)
	testing.expect(t, result.error != "")
}

@(test)
test_suppressed_health_check_passes :: proc(t: ^testing.T) {
	s := quiet()
	s.suppress_health_checks = hg.Health_Checks{.Filter_Too_Much}
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.integers(int))
		hg.reject(tc)
	}, s)
	defer hg.destroy_run_result(&result)

	testing.expect_value(t, result.status, hg.Run_Status.Passed)
}

@(test)
test_generator_misuse_is_an_error :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.integers(int, 10, 0))
	}, quiet())
	defer hg.destroy_run_result(&result)

	testing.expect_value(t, result.status, hg.Run_Status.Error)
	expect_contains(t, result.error, "min_value 10 is greater than max_value 0")
}

@(test)
test_engine_rejects_bad_arguments :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.floats(f64, 1, 0))
	}, quiet())
	defer hg.destroy_run_result(&result)

	testing.expect_value(t, result.status, hg.Run_Status.Error)
	expect_contains(t, result.error, "Invalid_Arg")
}

@(test)
test_invalid_settings_are_an_error :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {}, {test_cases = 0})
	defer hg.destroy_run_result(&result)

	testing.expect_value(t, result.status, hg.Run_Status.Error)
}

@(test)
test_notes_and_named_draws_appear_in_output :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		a := hg.draw(tc, hg.integers(int, 0, 10), "a")
		b := hg.draw(tc, hg.integers(int, 0, 10))
		hg.notef(tc, "sum = %d", a + b)
		log.info("an info line")
		hg.expect(tc, a + b < 5)
	}, quiet())
	defer hg.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	lines := strings.split_lines(failure.output, context.temp_allocator)
	testing.expect_value(t, len(lines), 4)
	testing.expect_value(t, lines[0], "a: int = 0")
	testing.expect_value(t, lines[1], "draw_2: int = 5")
	testing.expect_value(t, lines[2], "sum = 5")
	testing.expect_value(t, lines[3], "[Info] an info line")
}

@(test)
test_reproduce_replays_a_failure :: proc(t: ^testing.T) {
	property :: proc(tc: ^hg.Test_Case) {
		xs := hg.draw(tc, hg.lists(hg.integers(int, 0, 100)), "xs")
		sum := 0
		for x in xs {
			sum += x
		}
		hg.expect(tc, sum < 150)
	}
	result := hg.run(property, quiet())
	defer hg.destroy_run_result(&result)
	failure, ok := single_failure(t, result)
	if !ok {
		return
	}

	s := quiet()
	s.reproduce = failure.blob
	replayed := hg.run(property, s)
	defer hg.destroy_run_result(&replayed)
	again, again_ok := single_failure(t, replayed)
	if !again_ok {
		return
	}
	testing.expect_value(t, again.output, failure.output)
	testing.expect_value(t, again.message, failure.message)
}

@(test)
test_reproduce_rejects_a_bad_blob :: proc(t: ^testing.T) {
	s := quiet()
	s.reproduce = "not a blob"
	result := hg.run(proc(tc: ^hg.Test_Case) {}, s)
	defer hg.destroy_run_result(&result)
	testing.expect_value(t, result.status, hg.Run_Status.Error)
}

@(test)
test_reproducing_a_fixed_bug_passes :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		hg.expect(tc, !hg.draw(tc, hg.booleans()))
	}, quiet())
	defer hg.destroy_run_result(&result)
	failure, ok := single_failure(t, result)
	if !ok {
		return
	}

	s := quiet()
	s.reproduce = failure.blob
	fixed := hg.run(proc(tc: ^hg.Test_Case) {
		hg.draw(tc, hg.booleans())
	}, s)
	defer hg.destroy_run_result(&fixed)
	testing.expect_value(t, fixed.status, hg.Run_Status.Passed)
}

@(test)
test_report_multiple_failures :: proc(t: ^testing.T) {
	s := quiet(1000)
	s.report_multiple_failures = true
	result := hg.run(proc(tc: ^hg.Test_Case) {
		n := hg.draw(tc, hg.integers(int, -1000, 1000))
		hg.expect(tc, n < 100)
		hg.expect(tc, n > -100)
	}, s)
	defer hg.destroy_run_result(&result)

	testing.expect_value(t, result.status, hg.Run_Status.Failed)
	testing.expect_value(t, len(result.failures), 2)
	outputs: [2]string
	for f, i in result.failures[:min(2, len(result.failures))] {
		outputs[i] = f.output
	}
	slice.sort(outputs[:])
	testing.expect_value(t, outputs[0], "draw_1: int = -100")
	testing.expect_value(t, outputs[1], "draw_1: int = 100")
}

@(test)
test_run_with_data_passes_data :: proc(t: ^testing.T) {
	Counter :: struct {
		calls: int,
	}
	counter: Counter
	result := hg.run_with_data(&counter, proc(tc: ^hg.Test_Case, c: ^Counter) {
		hg.draw(tc, hg.integers(int))
		c.calls += 1
	}, quiet(25))
	defer hg.destroy_run_result(&result)

	testing.expect_value(t, result.status, hg.Run_Status.Passed)
	testing.expect(t, counter.calls >= 25)
}

@(test)
test_fixed_seed_is_reproducible :: proc(t: ^testing.T) {
	Seen :: struct {
		values: [dynamic]i64,
	}
	collect :: proc(seed: u64) -> [dynamic]i64 {
		seen: Seen
		seen.values.allocator = context.allocator
		result := hg.run_with_data(&seen, proc(tc: ^hg.Test_Case, seen: ^Seen) {
			append(&seen.values, hg.draw(tc, hg.integers(i64)))
		}, {test_cases = 20, seed = seed, database = ""})
		hg.destroy_run_result(&result)
		return seen.values
	}
	a := collect(1234)
	defer delete(a)
	b := collect(1234)
	defer delete(b)
	testing.expect(t, slice.equal(a[:], b[:]))
}

@(test)
test_format_failure :: proc(t: ^testing.T) {
	failure := hg.Failure {
		message = "boom",
		output  = "x: int = 1\ny: int = 2",
		blob    = "AXic",
	}
	text := hg.format_failure(failure, true, context.temp_allocator)
	testing.expect_value(t, text, "Property failed with minimal example:\n    x: int = 1\n    y: int = 2\nboom\nReproduce with: hegel.Settings{reproduce = \"AXic\"}")
	without_blob := hg.format_failure(failure, false, context.temp_allocator)
	testing.expect(t, !strings.contains(without_blob, "Reproduce"))
}

@(test)
test_targeting_and_events :: proc(t: ^testing.T) {
	s := quiet()
	s.show_statistics = true
	hg.test(t, targeting_and_events, s)
}

targeting_and_events :: proc(tc: ^hg.Test_Case) {
	n := hg.draw(tc, hg.integers(int, 0, 1000))
	hg.target(tc, f64(n), "n")
	hg.event(tc, "even" if n % 2 == 0 else "odd")
	hg.event_value(tc, "n", f64(n))
}

@(test)
test_register_profile :: proc(t: ^testing.T) {
	testing.expect(t, hg.register_profile("hegel_odin_tests_small", {test_cases = 7}))
	Count :: struct {
		n: int,
	}
	count: Count
	s := quiet()
	s.test_cases = nil
	s.profile = "hegel_odin_tests_small"
	result := hg.run_with_data(&count, proc(tc: ^hg.Test_Case, c: ^Count) {
		hg.draw(tc, hg.booleans())
		c.n += 1
	}, s)
	defer hg.destroy_run_result(&result)
	testing.expect_value(t, result.status, hg.Run_Status.Passed)
	testing.expectf(t, count.n <= 7, "ran %d test cases", count.n)

	unknown := hg.run(proc(tc: ^hg.Test_Case) {}, {profile = "no_such_profile"})
	defer hg.destroy_run_result(&unknown)
	testing.expect_value(t, unknown.status, hg.Run_Status.Error)
}

@(test) test_allocations_are_reclaimed_between_test_cases :: proc(t: ^testing.T) { hg.test(t, allocations_are_reclaimed_between_test_cases, quiet(200)) }

allocations_are_reclaimed_between_test_cases :: proc(tc: ^hg.Test_Case) {
	big := make([]u8, 1 << 20)
	big[len(big) - 1] = 1
	_ = fmt.tprintf("%v", hg.draw(tc, hg.lists(hg.text())))
}
