package geom

import "core:slice"

/*
The convex hull of `points` by Andrew's monotone chain, in O(n log n).

The hull is counter-clockwise, starts at the lexicographically smallest point,
and has no collinear vertices. Degenerate inputs give degenerate hulls: no
points give an empty hull, coincident points a single vertex, and collinear
points the two extreme ones.
*/
convex_hull :: proc(points: []Point, allocator := context.allocator) -> []Point {
	sorted := slice.clone(points, context.temp_allocator)
	slice.sort_by(sorted, less_xy)
	sorted = unique(sorted)
	n := len(sorted)
	if n <= 2 {
		return slice.clone(sorted, allocator)
	}

	hull := make([dynamic]Point, 0, 2 * n, allocator)
	// Lower chain left to right, then upper chain right to left. Popping on
	// `<= 0` drops collinear points.
	for p in sorted {
		for len(hull) >= 2 && cross(hull[len(hull) - 1] - hull[len(hull) - 2], p - hull[len(hull) - 1]) <= 0 {
			pop(&hull)
		}
		append(&hull, p)
	}
	lower_len := len(hull)
	#reverse for p in sorted[:n - 1] {
		for len(hull) > lower_len && cross(hull[len(hull) - 1] - hull[len(hull) - 2], p - hull[len(hull) - 1]) <= 0 {
			pop(&hull)
		}
		append(&hull, p)
	}
	// The last point appended is the first point again.
	pop(&hull)
	return hull[:]
}

// Removes adjacent duplicates in place.
@(private)
unique :: proc(sorted: []Point) -> []Point {
	if len(sorted) == 0 {
		return sorted
	}
	n := 1
	for p in sorted[1:] {
		if p != sorted[n - 1] {
			sorted[n] = p
			n += 1
		}
	}
	return sorted[:n]
}
