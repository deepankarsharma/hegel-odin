package hegel_tests

import "core:fmt"
import "core:log"
import "core:slice"
import "core:strings"
import "core:testing"

import hegel "../hegel"

@(test)
test_passing_property :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		xs := hegel.draw(tc, hegel.lists(hegel.integers(int)))
		ys := slice.clone(xs)
		slice.reverse(ys)
		slice.reverse(ys)
		hegel.expect(tc, slice.equal(xs, ys))
	}, quiet())
}

@(test)
test_engine_version :: proc(t: ^testing.T) {
	testing.expect(t, hegel.engine_version() != "")
}

@(test)
test_failure_is_shrunk_to_minimal_integer :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(int), "n")
		hegel.expect(tc, n < 50)
	}, quiet())
	defer hegel.destroy_run_result(&result)

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
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		x := hegel.draw(tc, hegel.integers(i32, 0, 1000))
		assert(x < 10, "x is too big")
	}, quiet())
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.output, "draw_1: i32 = 10")
	expect_contains(t, failure.message, "x is too big")
}

@(test)
test_panic_fails_the_property :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		if hegel.draw(tc, hegel.booleans()) {
			panic("boom")
		}
	}, quiet())
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	expect_contains(t, failure.message, "boom")
	testing.expect_value(t, failure.output, "draw_1: bool = true")
}

@(test)
test_log_error_fails_the_property :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(u8))
		if n > 3 {
			log.errorf("n = %d", n)
		}
	}, quiet())
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "n = 4")
}

@(test)
test_testing_expect_inside_property :: proc(t: ^testing.T) {
	result := hegel.run_with_data(t, proc(tc: ^hegel.Test_Case, t: ^testing.T) {
		s := hegel.draw(tc, hegel.text(alphabet = hegel.chars_of("ab")), "s")
		testing.expect(t, !strings.contains(s, "b"))
	}, quiet())
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.output, `s: string = "b"`)
}

@(test)
test_fail_and_failf :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(int, 0, 100))
		if n == 100 {
			hegel.fail(tc, "hit the top")
		}
		if n > 20 {
			hegel.failf(tc, "%d is more than 20", n)
		}
	}, quiet(500))
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "21 is more than 20")
}

@(test)
test_expect_value_message :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(int, 0, 10))
		hegel.expect_value(tc, n * 2, 0)
	}, quiet())
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "expected n * 2 to be 0, got 2")
}

@(test)
test_assume_filters_test_cases :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(int, 0, 100))
		hegel.assume(tc, n % 2 == 0)
		hegel.expect(tc, n % 2 == 0)
	}, quiet())
}

@(test)
test_rejecting_everything_is_a_health_check_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.integers(int))
		hegel.reject(tc)
	}, quiet())
	defer hegel.destroy_run_result(&result)

	testing.expect_value(t, result.status, hegel.Run_Status.Error)
	testing.expect(t, result.error != "")
}

@(test)
test_suppressed_health_check_passes :: proc(t: ^testing.T) {
	s := quiet()
	s.suppress_health_checks = hegel.Health_Checks{.Filter_Too_Much}
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.integers(int))
		hegel.reject(tc)
	}, s)
	defer hegel.destroy_run_result(&result)

	testing.expect_value(t, result.status, hegel.Run_Status.Passed)
}

@(test)
test_generator_misuse_is_an_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.integers(int, 10, 0))
	}, quiet())
	defer hegel.destroy_run_result(&result)

	testing.expect_value(t, result.status, hegel.Run_Status.Error)
	expect_contains(t, result.error, "min_value 10 is greater than max_value 0")
}

@(test)
test_engine_rejects_bad_arguments :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.floats(f64, 1, 0))
	}, quiet())
	defer hegel.destroy_run_result(&result)

	testing.expect_value(t, result.status, hegel.Run_Status.Error)
	expect_contains(t, result.error, "Invalid_Arg")
}

@(test)
test_invalid_settings_are_an_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {}, {test_cases = 0})
	defer hegel.destroy_run_result(&result)

	testing.expect_value(t, result.status, hegel.Run_Status.Error)
}

@(test)
test_notes_and_named_draws_appear_in_output :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		a := hegel.draw(tc, hegel.integers(int, 0, 10), "a")
		b := hegel.draw(tc, hegel.integers(int, 0, 10))
		hegel.notef(tc, "sum = %d", a + b)
		log.info("an info line")
		hegel.expect(tc, a + b < 5)
	}, quiet())
	defer hegel.destroy_run_result(&result)

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
	property :: proc(tc: ^hegel.Test_Case) {
		xs := hegel.draw(tc, hegel.lists(hegel.integers(int, 0, 100)), "xs")
		sum := 0
		for x in xs {
			sum += x
		}
		hegel.expect(tc, sum < 150)
	}
	result := hegel.run(property, quiet())
	defer hegel.destroy_run_result(&result)
	failure, ok := single_failure(t, result)
	if !ok {
		return
	}

	s := quiet()
	s.reproduce = failure.blob
	replayed := hegel.run(property, s)
	defer hegel.destroy_run_result(&replayed)
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
	result := hegel.run(proc(tc: ^hegel.Test_Case) {}, s)
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Error)
}

@(test)
test_reproducing_a_fixed_bug_passes :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.expect(tc, !hegel.draw(tc, hegel.booleans()))
	}, quiet())
	defer hegel.destroy_run_result(&result)
	failure, ok := single_failure(t, result)
	if !ok {
		return
	}

	s := quiet()
	s.reproduce = failure.blob
	fixed := hegel.run(proc(tc: ^hegel.Test_Case) {
		hegel.draw(tc, hegel.booleans())
	}, s)
	defer hegel.destroy_run_result(&fixed)
	testing.expect_value(t, fixed.status, hegel.Run_Status.Passed)
}

@(test)
test_report_multiple_failures :: proc(t: ^testing.T) {
	s := quiet(1000)
	s.report_multiple_failures = true
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(int, -1000, 1000))
		hegel.expect(tc, n < 100)
		hegel.expect(tc, n > -100)
	}, s)
	defer hegel.destroy_run_result(&result)

	testing.expect_value(t, result.status, hegel.Run_Status.Failed)
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
	result := hegel.run_with_data(&counter, proc(tc: ^hegel.Test_Case, c: ^Counter) {
		hegel.draw(tc, hegel.integers(int))
		c.calls += 1
	}, quiet(25))
	defer hegel.destroy_run_result(&result)

	testing.expect_value(t, result.status, hegel.Run_Status.Passed)
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
		result := hegel.run_with_data(&seen, proc(tc: ^hegel.Test_Case, seen: ^Seen) {
			append(&seen.values, hegel.draw(tc, hegel.integers(i64)))
		}, {test_cases = 20, seed = seed, database = ""})
		hegel.destroy_run_result(&result)
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
	failure := hegel.Failure {
		message = "boom",
		output  = "x: int = 1\ny: int = 2",
		blob    = "AXic",
	}
	text := hegel.format_failure(failure, true, context.temp_allocator)
	testing.expect_value(t, text, "Property failed with minimal example:\n    x: int = 1\n    y: int = 2\nboom\nReproduce with: hegel.Settings{reproduce = \"AXic\"}")
	without_blob := hegel.format_failure(failure, false, context.temp_allocator)
	testing.expect(t, !strings.contains(without_blob, "Reproduce"))
}

@(test)
test_targeting_and_events :: proc(t: ^testing.T) {
	s := quiet()
	s.show_statistics = true
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		n := hegel.draw(tc, hegel.integers(int, 0, 1000))
		hegel.target(tc, f64(n), "n")
		hegel.event(tc, "even" if n % 2 == 0 else "odd")
		hegel.event_value(tc, "n", f64(n))
	}, s)
}

@(test)
test_register_profile :: proc(t: ^testing.T) {
	testing.expect(t, hegel.register_profile("hegel_odin_tests_small", {test_cases = 7}))
	Count :: struct {
		n: int,
	}
	count: Count
	s := quiet()
	s.test_cases = nil
	s.profile = "hegel_odin_tests_small"
	result := hegel.run_with_data(&count, proc(tc: ^hegel.Test_Case, c: ^Count) {
		hegel.draw(tc, hegel.booleans())
		c.n += 1
	}, s)
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Passed)
	testing.expectf(t, count.n <= 7, "ran %d test cases", count.n)

	unknown := hegel.run(proc(tc: ^hegel.Test_Case) {}, {profile = "no_such_profile"})
	defer hegel.destroy_run_result(&unknown)
	testing.expect_value(t, unknown.status, hegel.Run_Status.Error)
}

@(test)
test_allocations_are_reclaimed_between_test_cases :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		big := make([]u8, 1 << 20)
		big[len(big) - 1] = 1
		_ = fmt.tprintf("%v", hegel.draw(tc, hegel.lists(hegel.text())))
	}, quiet(200))
}
