package geom_tests

import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

@(test) test_intersection_is_symmetric :: proc(t: ^testing.T) { hg.test(t, intersection_is_symmetric) }

intersection_is_symmetric :: proc(tc: ^hg.Test_Case) {
	s := hg.draw(tc, segments(), "s")
	u := hg.draw(tc, segments(), "u")
	expected := geom.segments_intersect(s, u)
	hg.expect_value(tc, geom.segments_intersect(u, s), expected)
	hg.expect_value(tc, geom.segments_intersect({s.b, s.a}, u), expected)
	hg.expect_value(tc, geom.segments_intersect(s, {u.b, u.a}), expected)
	hg.expect(tc, geom.segments_intersect(s, s))
}

@(test) test_intersection_is_invariant_under_rigid_motions :: proc(t: ^testing.T) { hg.test(t, intersection_is_invariant_under_rigid_motions) }

intersection_is_invariant_under_rigid_motions :: proc(tc: ^hg.Test_Case) {
	limit :: geom.MAX_COORD / 2
	s := hg.draw(tc, segments(limit), "s")
	u := hg.draw(tc, segments(limit), "u")
	shift := hg.draw(tc, points(limit), "shift")
	expected := geom.segments_intersect(s, u)
	hg.expect_value(tc, geom.segments_intersect({s.a + shift, s.b + shift}, {u.a + shift, u.b + shift}), expected)
	hg.expect_value(tc, geom.segments_intersect({geom.rot90(s.a), geom.rot90(s.b)}, {geom.rot90(u.a), geom.rot90(u.b)}), expected)
}

@(test) test_segments_sharing_an_endpoint_intersect :: proc(t: ^testing.T) { hg.test(t, segments_sharing_an_endpoint_intersect) }

segments_sharing_an_endpoint_intersect :: proc(tc: ^hg.Test_Case) {
	p := hg.draw(tc, points(), "p")
	q := hg.draw(tc, points(), "q")
	r := hg.draw(tc, points(), "r")
	hg.expect(tc, geom.segments_intersect({p, q}, {r, p}))
	hg.expect(tc, geom.segments_intersect({q, p}, {p, r}))
}

@(test) test_segments_through_a_common_point_intersect :: proc(t: ^testing.T) { hg.test(t, segments_through_a_common_point_intersect) }

// p - d .. p + d and p - e .. p + e both pass through p.
segments_through_a_common_point_intersect :: proc(tc: ^hg.Test_Case) {
	limit :: geom.MAX_COORD / 2
	p := hg.draw(tc, points(limit), "p")
	d := hg.draw(tc, points(limit), "d")
	e := hg.draw(tc, points(limit), "e")
	hg.expect(tc, geom.segments_intersect({p - d, p + d}, {p - e, p + e}))
	hg.expect(tc, geom.on_segment(p, {p - d, p + d}))
}

@(test) test_parallel_translates_do_not_intersect :: proc(t: ^testing.T) { hg.test(t, parallel_translates_do_not_intersect) }

// Shifting a segment sideways (off its own line) moves it clear of itself.
parallel_translates_do_not_intersect :: proc(tc: ^hg.Test_Case) {
	limit :: geom.MAX_COORD / 2
	s := hg.draw(tc, segments(limit), "s")
	shift := hg.draw(tc, points(limit), "shift")
	hg.assume(tc, geom.cross(s.b - s.a, shift) != 0)
	hg.expect(tc, !geom.segments_intersect(s, {s.a + shift, s.b + shift}))
}

@(test) test_intersecting_segments_have_overlapping_boxes :: proc(t: ^testing.T) { hg.test(t, intersecting_segments_have_overlapping_boxes) }

intersecting_segments_have_overlapping_boxes :: proc(tc: ^hg.Test_Case) {
	s := hg.draw(tc, segments(), "s")
	u := hg.draw(tc, segments(), "u")
	if geom.segments_intersect(s, u) {
		sb, _ := geom.bounding_box({s.a, s.b})
		ub, _ := geom.bounding_box({u.a, u.b})
		hg.expect(tc, geom.aabb_intersects(sb, ub))
	}
}

@(test) test_on_segment_along_its_line :: proc(t: ^testing.T) { hg.test(t, on_segment_along_its_line) }

// For s = a .. a + n*d, the point a + k*d is on s exactly when 0 <= k <= n.
on_segment_along_its_line :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, points(1000), "a")
	d := hg.draw(tc, points(1000), "d")
	hg.assume(tc, d != {})
	n := hg.draw(tc, hg.integers(i64, 0, 100), "n")
	k := hg.draw(tc, hg.integers(i64, -100, 200), "k")
	hg.expect_value(tc, geom.on_segment(a + k * d, {a, a + n * d}), 0 <= k && k <= n)
}

@(test) test_points_off_the_line_are_not_on_the_segment :: proc(t: ^testing.T) { hg.test(t, points_off_the_line_are_not_on_the_segment) }

points_off_the_line_are_not_on_the_segment :: proc(tc: ^hg.Test_Case) {
	s := hg.draw(tc, segments(), "s")
	p := hg.draw(tc, points(), "p")
	if geom.orient(s.a, s.b, p) != .Collinear {
		hg.expect(tc, !geom.on_segment(p, s))
	}
}
