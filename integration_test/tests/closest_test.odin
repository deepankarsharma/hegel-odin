package geom_tests

import "core:slice"
import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

brute_force_closest :: proc(pts: []geom.Point) -> i64 {
	best := max(i64)
	for a, i in pts {
		for b in pts[i + 1:] {
			best = min(best, geom.dist2(a, b))
		}
	}
	return best
}

@(test) test_closest_pair_matches_brute_force :: proc(t: ^testing.T) { hg.test(t, closest_pair_matches_brute_force) }

closest_pair_matches_brute_force :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(max_size = 60), "pts")
	i, j, d2, ok := geom.closest_pair(pts)
	hg.expect_value(tc, ok, len(pts) >= 2)
	if !ok {
		return
	}
	hg.expect(tc, 0 <= i && i < j && j < len(pts))
	hg.expect_value(tc, geom.dist2(pts[i], pts[j]), d2)
	hg.expect_value(tc, d2, brute_force_closest(pts))
}

@(test) test_closest_pair_on_crowded_columns :: proc(t: ^testing.T) { hg.test(t, closest_pair_on_crowded_columns) }

// Few distinct x values stress the strip step of the divide and conquer.
closest_pair_on_crowded_columns :: proc(tc: ^hg.Test_Case) {
	column_points := hg.composite(proc(tc: ^hg.Test_Case) -> geom.Point {
		return {hg.draw(tc, hg.integers(i64, -3, 3)), hg.draw(tc, hg.integers(i64, -1000, 1000))}
	})
	pts := hg.draw(tc, hg.lists(column_points, min_size = 2, max_size = 80), "pts")
	_, _, d2, _ := geom.closest_pair(pts)
	hg.expect_value(tc, d2, brute_force_closest(pts))
}

@(test) test_closest_pair_does_not_modify_input :: proc(t: ^testing.T) { hg.test(t, closest_pair_does_not_modify_input) }

closest_pair_does_not_modify_input :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(), "pts")
	before := slice.clone(pts)
	geom.closest_pair(pts)
	hg.expect(tc, slice.equal(pts, before))
}
