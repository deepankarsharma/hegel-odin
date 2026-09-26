package geom_tests

import "core:slice"
import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

@(test) test_area_under_reordering_and_motion :: proc(t: ^testing.T) { hg.test(t, area_under_reordering_and_motion) }

area_under_reordering_and_motion :: proc(tc: ^hg.Test_Case) {
	limit :: geom.MAX_COORD / 2
	poly := hg.draw(tc, point_lists(limit, min_size = 3), "poly")
	shift := hg.draw(tc, points(limit), "shift")
	k := hg.draw(tc, hg.integers(int, 0, len(poly) - 1), "k")
	area := geom.signed_area2(poly)
	// The shoelace formula holds for any vertex list, simple or not.
	cycled := slice.concatenate([][]geom.Point{poly[k:], poly[:k]})
	hg.expect_value(tc, geom.signed_area2(cycled), area)
	hg.expect_value(tc, geom.signed_area2(reversed(poly)), -area)
	hg.expect_value(tc, geom.signed_area2(translated(poly, shift)), area)
	hg.expect_value(tc, geom.signed_area2(rotated90(poly)), area)
}

@(test) test_area_of_rectangles_and_triangles :: proc(t: ^testing.T) { hg.test(t, area_of_rectangles_and_triangles) }

area_of_rectangles_and_triangles :: proc(tc: ^hg.Test_Case) {
	box := hg.draw(tc, boxes(), "box")
	w, h := box.max.x - box.min.x, box.max.y - box.min.y
	rect := []geom.Point{box.min, {box.max.x, box.min.y}, box.max, {box.min.x, box.max.y}}
	hg.expect_value(tc, geom.signed_area2(rect), 2 * w * h)
	hg.expect_value(tc, geom.boundary_lattice_count(rect), 2 * (w + h))
	hg.expect(tc, abs(geom.perimeter(rect) - f64(2 * (w + h))) < 1e-6)

	a := hg.draw(tc, points(), "a")
	b := hg.draw(tc, points(), "b")
	c := hg.draw(tc, points(), "c")
	hg.expect_value(tc, geom.signed_area2({a, b, c}), geom.cross(b - a, c - a))
}

@(test) test_star_polygons_are_ccw_and_contain_their_centre :: proc(t: ^testing.T) { hg.test(t, star_polygons_are_ccw_and_contain_their_centre) }

star_polygons_are_ccw_and_contain_their_centre :: proc(tc: ^hg.Test_Case) {
	star := hg.draw(tc, star_polygons(), "star")
	hg.expect(tc, geom.signed_area2(star.vertices) > 0)
	hg.expect_value(tc, geom.locate_point(star.vertices, star.centre), geom.Location.Inside)
	hg.expect_value(tc, geom.locate_point(reversed(star.vertices), star.centre), geom.Location.Inside)
	for v in star.vertices {
		hg.expect_value(tc, geom.locate_point(star.vertices, v), geom.Location.Boundary)
	}
}

@(test) test_locate_is_invariant_under_relabelling_and_motion :: proc(t: ^testing.T) { hg.test(t, locate_is_invariant_under_relabelling_and_motion) }

locate_is_invariant_under_relabelling_and_motion :: proc(tc: ^hg.Test_Case) {
	star := hg.draw(tc, star_polygons(geom.MAX_COORD / 4), "star")
	poly := star.vertices
	p := hg.draw(tc, points(geom.MAX_COORD / 2), "p")
	shift := hg.draw(tc, points(geom.MAX_COORD / 4), "shift")
	k := hg.draw(tc, hg.integers(int, 0, len(poly) - 1), "k")
	location := geom.locate_point(poly, p)
	hg.expect_value(tc, geom.locate_point(slice.concatenate([][]geom.Point{poly[k:], poly[:k]}), p), location)
	hg.expect_value(tc, geom.locate_point(reversed(poly), p), location)
	hg.expect_value(tc, geom.locate_point(translated(poly, shift), p + shift), location)
	hg.expect_value(tc, geom.locate_point(rotated90(poly), geom.rot90(p)), location)
}

@(test) test_picks_theorem_for_star_polygons :: proc(t: ^testing.T) { hg.test(t, picks_theorem_for_star_polygons) }

// For a lattice polygon, 2A = 2I + B - 2 where I and B count the lattice
// points inside and on the boundary. Counting I by brute force checks
// `locate_point`, `signed_area2` and `boundary_lattice_count` together.
picks_theorem_for_star_polygons :: proc(tc: ^hg.Test_Case) {
	star := hg.draw(tc, star_polygons(8), "star")
	check_picks_theorem(tc, star.vertices, geom.locate_point)
}

@(test) test_picks_theorem_for_convex_hulls :: proc(t: ^testing.T) { hg.test(t, picks_theorem_for_convex_hulls) }

picks_theorem_for_convex_hulls :: proc(tc: ^hg.Test_Case) {
	hull := hg.draw(tc, hull_polygons(12), "hull")
	check_picks_theorem(tc, hull, geom.locate_point_convex)
}

check_picks_theorem :: proc(tc: ^hg.Test_Case, poly: []geom.Point, locate: proc "contextless" (poly: []geom.Point, p: geom.Point) -> geom.Location) {
	box, _ := geom.bounding_box(poly)
	inside, boundary: i64
	for y in box.min.y ..= box.max.y {
		for x in box.min.x ..= box.max.x {
			switch locate(poly, {x, y}) {
			case .Inside:
				inside += 1
			case .Boundary:
				boundary += 1
			case .Outside:
			}
		}
	}
	hg.expect_value(tc, boundary, geom.boundary_lattice_count(poly))
	hg.expect_value(tc, geom.signed_area2(poly), 2 * inside + boundary - 2)
}

@(test) test_convexity :: proc(t: ^testing.T) { hg.test(t, convexity) }

convexity :: proc(tc: ^hg.Test_Case) {
	hull := hg.draw(tc, hull_polygons(), "hull")
	hg.expect(tc, geom.is_strictly_convex_ccw(hull))
	hg.expect(tc, !geom.is_strictly_convex_ccw(reversed(hull)))
	// Walking a convex polygon twice turns twice: not simple, not convex.
	hg.expect(tc, !geom.is_strictly_convex_ccw(slice.concatenate([][]geom.Point{hull, hull})))
}

@(test) test_non_convex_stars_are_not_convex :: proc(t: ^testing.T) { hg.test(t, non_convex_stars_are_not_convex) }

non_convex_stars_are_not_convex :: proc(tc: ^hg.Test_Case) {
	star := hg.draw(tc, star_polygons(), "star")
	hull := geom.convex_hull(star.vertices)
	convex := len(hull) == len(star.vertices)
	hg.expect_value(tc, geom.is_strictly_convex_ccw(star.vertices), convex)
	// The hull encloses the polygon, so has at least its area and at most
	// its perimeter.
	hg.expect(tc, geom.signed_area2(hull) >= geom.signed_area2(star.vertices))
	hg.expect(tc, geom.perimeter(hull) <= geom.perimeter(star.vertices) * (1 + 1e-12))
}

@(test) test_convex_locate_agrees_with_general_locate :: proc(t: ^testing.T) { hg.test(t, convex_locate_agrees_with_general_locate) }

// Two independent algorithms: O(log n) fan search and O(n) ray casting.
convex_locate_agrees_with_general_locate :: proc(tc: ^hg.Test_Case) {
	hull := hg.draw(tc, hull_polygons(30), "hull")
	for _ in 0 ..< 20 {
		p := hg.draw(tc, points(32), "p")
		hg.expect_value(tc, geom.locate_point_convex(hull, p), geom.locate_point(hull, p))
	}
}
