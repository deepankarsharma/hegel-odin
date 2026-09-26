package geom_tests

import "core:slice"
import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

@(test) test_hull_contains_every_point :: proc(t: ^testing.T) { hg.test(t, hull_contains_every_point) }

hull_contains_every_point :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(), "pts")
	hull := geom.convex_hull(pts)
	for p in pts {
		hg.expect(tc, geom.locate_point_convex(hull, p) != .Outside)
	}
}

@(test) test_hull_vertices_are_extreme_input_points :: proc(t: ^testing.T) { hg.test(t, hull_vertices_are_extreme_input_points) }

// Each hull vertex is an input point, and removing it shrinks the hull:
// the hull has no vertex it does not need.
hull_vertices_are_extreme_input_points :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(max_size = 25), "pts")
	hull := geom.convex_hull(pts)
	for v in hull {
		hg.expect(tc, slice.contains(pts, v))
		others := make([dynamic]geom.Point)
		for p in pts {
			if p != v {
				append(&others, p)
			}
		}
		hg.expect_value(tc, geom.locate_point_convex(geom.convex_hull(others[:]), v), geom.Location.Outside)
	}
}

@(test) test_hull_shape :: proc(t: ^testing.T) { hg.test(t, hull_shape) }

hull_shape :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(), "pts")
	hull := geom.convex_hull(pts)
	switch len(hull) {
	case 0:
		hg.expect_value(tc, len(pts), 0)
	case 1:
		for p in pts {
			hg.expect_value(tc, p, hull[0])
		}
	case 2:
		hg.expect(tc, hull[0] != hull[1])
		for p in pts {
			hg.expect(tc, geom.on_segment(p, {hull[0], hull[1]}))
		}
	case:
		hg.expect(tc, geom.is_strictly_convex_ccw(hull))
	}
	if len(hull) > 0 {
		// It starts at the lexicographically smallest point.
		for p in pts {
			hg.expect(tc, !geom.less_xy(p, hull[0]))
		}
	}
}

@(test) test_hull_ignores_order_and_duplicates :: proc(t: ^testing.T) { hg.test(t, hull_ignores_order_and_duplicates) }

hull_ignores_order_and_duplicates :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(), "pts")
	perm := permutations(tc, len(pts))
	shuffled := make([dynamic]geom.Point)
	for i in perm {
		append(&shuffled, pts[i])
	}
	append(&shuffled, ..pts)
	hg.expect(tc, slice.equal(geom.convex_hull(shuffled[:]), geom.convex_hull(pts)))
}

@(test) test_hull_is_idempotent :: proc(t: ^testing.T) { hg.test(t, hull_is_idempotent) }

hull_is_idempotent :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(), "pts")
	hull := geom.convex_hull(pts)
	hg.expect(tc, slice.equal(geom.convex_hull(hull), hull))
	// Adding points already inside the hull changes nothing.
	inside := hg.draw(tc, point_lists(), "inside")
	more := slice.clone_to_dynamic(pts)
	for p in inside {
		if geom.locate_point_convex(hull, p) != .Outside {
			append(&more, p)
		}
	}
	hg.expect(tc, slice.equal(geom.convex_hull(more[:]), hull))
}

@(test) test_hull_commutes_with_rigid_motions :: proc(t: ^testing.T) { hg.test(t, hull_commutes_with_rigid_motions) }

hull_commutes_with_rigid_motions :: proc(tc: ^hg.Test_Case) {
	limit :: geom.MAX_COORD / 2
	pts := hg.draw(tc, point_lists(limit), "pts")
	shift := hg.draw(tc, points(limit), "shift")
	hull := geom.convex_hull(pts)
	hg.expect(tc, slice.equal(geom.convex_hull(translated(pts, shift)), translated(hull, shift)))
	hg.expect(tc, slice.equal(geom.convex_hull(rotated90(pts)), canonical(rotated90(hull))))
}
