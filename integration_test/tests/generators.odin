package geom_tests

import "core:slice"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

/*
Coordinates in `[-limit, limit]`. Half the time they come from a tiny range
instead, so points collide and line up often: the degenerate cases geometry
code gets wrong.
*/
coords :: proc(limit: i64 = geom.MAX_COORD) -> hg.Generator(i64) {
	return hg.one_of(hg.integers(i64, -min(limit, 8), min(limit, 8)), hg.integers(i64, -limit, limit))
}

points :: proc(limit: i64 = geom.MAX_COORD) -> hg.Generator(geom.Point) {
	return hg.arrays(coords(limit), 2)
}

point_lists :: proc(limit: i64 = geom.MAX_COORD, min_size := 0, max_size := 40) -> hg.Generator([]geom.Point) {
	return hg.lists(points(limit), min_size, max_size)
}

segments :: proc(limit: i64 = geom.MAX_COORD) -> hg.Generator(geom.Segment) {
	return hg.mapped(hg.arrays(points(limit), 2), proc(ends: [2]geom.Point) -> geom.Segment {
		return {ends[0], ends[1]}
	})
}

boxes :: proc(limit: i64 = geom.MAX_COORD) -> hg.Generator(geom.AABB) {
	return hg.mapped(hg.arrays(points(limit), 2), proc(corners: [2]geom.Point) -> geom.AABB {
		a, b := corners[0], corners[1]
		return {{min(a.x, b.x), min(a.y, b.y)}, {max(a.x, b.x), max(a.y, b.y)}}
	})
}

// Point sets whose convex hull is a proper polygon.
hull_polygons :: proc(limit: i64 = geom.MAX_COORD) -> hg.Generator([]geom.Point) {
	return hg.composite_with_data(new_clone(limit), proc(tc: ^hg.Test_Case, limit: ^i64) -> []geom.Point {
		hull := geom.convex_hull(hg.draw(tc, point_lists(limit^, min_size = 3)))
		hg.assume(tc, len(hull) >= 3)
		return hull
	})
}

/*
Simple, usually non-convex, counter-clockwise polygons that are star-shaped
around a centre, with vertex offsets from it in `[-radius, radius]`.

Every open quadrant around the centre gets at least one vertex, so the angular
gap between consecutive vertices stays below a half turn. Sorting by angle then
gives a simple polygon with the centre strictly inside.
*/
star_polygons :: proc(radius: i64 = geom.MAX_COORD / 2) -> hg.Generator(Star) {
	return hg.composite_with_data(new_clone(radius), proc(tc: ^hg.Test_Case, radius: ^i64) -> Star {
		r := radius^
		centre := hg.draw(tc, points(geom.MAX_COORD - r), "centre")
		magnitudes := hg.arrays(hg.integers(i64, 1, r), 2)
		offsets := make([dynamic]geom.Point)
		for quadrant in ([4]geom.Point{{1, 1}, {-1, 1}, {-1, -1}, {1, -1}}) {
			for m in hg.draw(tc, hg.lists(magnitudes, min_size = 1, max_size = 6)) {
				append(&offsets, m * quadrant)
			}
		}
		slice.sort_by(offsets[:], by_angle)
		poly := make([dynamic]geom.Point)
		for d, i in offsets {
			// Keep one vertex per ray from the centre.
			if i > 0 && same_ray(d, offsets[i - 1]) {
				continue
			}
			append(&poly, centre + d)
		}
		return {poly[:], centre}
	})
}

Star :: struct {
	vertices: []geom.Point,
	centre:   geom.Point,
}

@(private = "file")
by_angle :: proc(a, b: geom.Point) -> bool {
	ha, hb := half(a), half(b)
	return ha < hb || (ha == hb && geom.cross(a, b) > 0)
}

@(private = "file")
same_ray :: proc(a, b: geom.Point) -> bool {
	return half(a) == half(b) && geom.cross(a, b) == 0
}

@(private = "file")
half :: proc(d: geom.Point) -> int {
	return 0 if d.y > 0 || (d.y == 0 && d.x > 0) else 1
}

// A permutation of `0 ..< n`, shrinking towards the identity.
permutations :: proc(tc: ^hg.Test_Case, n: int) -> []int {
	perm := make([]int, n)
	for &x, i in perm {
		x = i
	}
	// Fisher-Yates, each swap drawn from the engine.
	for i := n - 1; i > 0; i -= 1 {
		j := hg.draw(tc, hg.integers(int, 0, i))
		perm[i], perm[j] = perm[j], perm[i]
	}
	return perm
}

// `poly` rotated so that it starts at its lexicographically smallest vertex,
// making cyclically equal polygons compare equal.
canonical :: proc(poly: []geom.Point) -> []geom.Point {
	if len(poly) == 0 {
		return poly
	}
	start := 0
	for p, i in poly {
		if geom.less_xy(p, poly[start]) {
			start = i
		}
	}
	out := make([]geom.Point, len(poly))
	for i in 0 ..< len(poly) {
		out[i] = poly[(start + i) % len(poly)]
	}
	return out
}

translated :: proc(poly: []geom.Point, by: geom.Point) -> []geom.Point {
	out := make([]geom.Point, len(poly))
	for p, i in poly {
		out[i] = p + by
	}
	return out
}

rotated90 :: proc(poly: []geom.Point) -> []geom.Point {
	out := make([]geom.Point, len(poly))
	for p, i in poly {
		out[i] = geom.rot90(p)
	}
	return out
}

reversed :: proc(poly: []geom.Point) -> []geom.Point {
	out := slice.clone(poly)
	slice.reverse(out)
	return out
}
