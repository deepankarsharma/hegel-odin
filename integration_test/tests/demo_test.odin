package geom_tests

import "core:log"
import "core:slice"
import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

/*
What a failure looks like. This closest-pair "optimisation" sorts by x and
only compares neighbours, which looks plausible and passes simple hand-written
tests. Hegel finds a counterexample and shrinks it to a minimal one.
*/
@(test)
test_demo_hegel_catches_a_plausible_bug :: proc(t: ^testing.T) {
	result := hg.run(proc(tc: ^hg.Test_Case) {
		pts := hg.draw(tc, point_lists(min_size = 2), "pts")
		hg.expect_value(tc, sorted_neighbours_closest(pts), brute_force_closest(pts))
	}, {database = "", derandomize = true})
	defer hg.destroy_run_result(&result)

	if !testing.expect_value(t, result.status, hg.Run_Status.Failed) {
		return
	}
	// Logs the shrunk example, e.g. pts = {{0, 0}, {0, 2}, {1, 0}}: sorted by
	// x, the closest pair {0, 0} and {1, 0} are not neighbours.
	log.infof("Hegel found the bug in sorted_neighbours_closest:\n%s", hg.format_failure(result.failures[0], allocator = context.temp_allocator))
}

sorted_neighbours_closest :: proc(pts: []geom.Point) -> i64 {
	sorted := slice.clone(pts)
	slice.sort_by(sorted, geom.less_xy)
	best := max(i64)
	for i in 1 ..< len(sorted) {
		best = min(best, geom.dist2(sorted[i - 1], sorted[i]))
	}
	return best
}
