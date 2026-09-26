package geom_tests

import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

@(test) test_bounding_box_is_tight :: proc(t: ^testing.T) { hg.test(t, bounding_box_is_tight) }

bounding_box_is_tight :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(), "pts")
	box, ok := geom.bounding_box(pts)
	hg.expect_value(tc, ok, len(pts) > 0)
	if !ok {
		return
	}
	touches: [4]bool
	for p in pts {
		hg.expect(tc, geom.aabb_contains(box, p))
		touches[0] ||= p.x == box.min.x
		touches[1] ||= p.y == box.min.y
		touches[2] ||= p.x == box.max.x
		touches[3] ||= p.y == box.max.y
	}
	// Every side of the box has a point on it.
	hg.expect_value(tc, touches, [4]bool{true, true, true, true})
}

@(test) test_union_contains_both :: proc(t: ^testing.T) { hg.test(t, union_contains_both) }

union_contains_both :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, boxes(), "a")
	b := hg.draw(tc, boxes(), "b")
	u := geom.aabb_union(a, b)
	hg.expect_value(tc, geom.aabb_union(b, a), u)
	for box in ([2]geom.AABB{a, b}) {
		hg.expect(tc, geom.aabb_contains(u, box.min) && geom.aabb_contains(u, box.max))
	}
	hg.expect_value(tc, geom.aabb_union(a, a), a)
	// It is the bounding box of all four corners.
	expected, _ := geom.bounding_box({a.min, a.max, b.min, b.max})
	hg.expect_value(tc, u, expected)
}

@(test) test_intersection_matches_membership :: proc(t: ^testing.T) { hg.test(t, intersection_matches_membership) }

// Small boxes and points so overlaps and hits are common.
intersection_matches_membership :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, boxes(20), "a")
	b := hg.draw(tc, boxes(20), "b")
	p := hg.draw(tc, points(20), "p")
	i, ok := geom.aabb_intersection(a, b)
	hg.expect_value(tc, ok, geom.aabb_intersects(a, b))
	hg.expect_value(tc, geom.aabb_intersects(b, a), ok)
	in_both := geom.aabb_contains(a, p) && geom.aabb_contains(b, p)
	hg.expect_value(tc, ok && geom.aabb_contains(i, p), in_both)
}

@(test) test_lattice_count_matches_enumeration :: proc(t: ^testing.T) { hg.test(t, lattice_count_matches_enumeration) }

lattice_count_matches_enumeration :: proc(tc: ^hg.Test_Case) {
	box := hg.draw(tc, boxes(10), "box")
	count: i64
	for y in i64(-12) ..= 12 {
		for x in i64(-12) ..= 12 {
			if geom.aabb_contains(box, {x, y}) {
				count += 1
			}
		}
	}
	hg.expect_value(tc, geom.aabb_lattice_count(box), count)
}
