package geom

/*
Polygons are vertex slices in order, with an implicit closing edge from the
last vertex back to the first. Unless stated otherwise a polygon must be
simple (its edges meet only at shared vertices) with at least three vertices.
*/

// Where a point lies relative to a polygon.
Location :: enum u8 {
	Outside,
	Boundary,
	Inside,
}

// Twice the signed area: positive for counter-clockwise vertex order.
signed_area2 :: proc "contextless" (poly: []Point) -> i64 {
	sum: i64
	for p, i in poly {
		sum += cross(p, poly[(i + 1) % len(poly)])
	}
	return sum
}

perimeter :: proc "contextless" (poly: []Point) -> f64 {
	sum: f64
	for p, i in poly {
		sum += distance(p, poly[(i + 1) % len(poly)])
	}
	return sum
}

// The number of lattice points on the polygon's boundary.
boundary_lattice_count :: proc "contextless" (poly: []Point) -> i64 {
	sum: i64
	for p, i in poly {
		d := poly[(i + 1) % len(poly)] - p
		sum += gcd(abs(d.x), abs(d.y))
	}
	return sum
}

// Whether `poly` is strictly convex (no three consecutive vertices collinear)
// and counter-clockwise.
is_strictly_convex_ccw :: proc "contextless" (poly: []Point) -> bool {
	n := len(poly)
	if n < 3 {
		return false
	}
	for i in 0 ..< n {
		if orient(poly[i], poly[(i + 1) % n], poly[(i + 2) % n]) != .Counter_Clockwise {
			return false
		}
	}
	// Positive turns everywhere still allow a star that winds twice.
	return signed_area2(poly) > 0 && winding_turns(poly) == 1
}

// Locates `p` relative to any simple polygon, in either orientation, by
// counting boundary crossings of a ray towards +x.
locate_point :: proc "contextless" (poly: []Point, p: Point) -> Location {
	inside := false
	for a, i in poly {
		b := poly[(i + 1) % len(poly)]
		if on_segment(p, {a, b}) {
			return .Boundary
		}
		// Half-open in y, so a ray through a vertex counts it once.
		if (a.y > p.y) != (b.y > p.y) {
			side := cross(b - a, p - a)
			if (side > 0) == (b.y > a.y) {
				inside = !inside
			}
		}
	}
	return .Inside if inside else .Outside
}

/*
Locates `p` relative to a strictly convex counter-clockwise polygon in
O(log n), as `convex_hull` returns them. Hulls of fewer than three points (a
segment or a single point) are handled too.
*/
locate_point_convex :: proc "contextless" (hull: []Point, p: Point) -> Location {
	n := len(hull)
	switch n {
	case 0:
		return .Outside
	case 1:
		return .Boundary if p == hull[0] else .Outside
	case 2:
		return .Boundary if on_segment(p, {hull[0], hull[1]}) else .Outside
	}
	v0 := hull[0]
	if orient(v0, hull[1], p) == .Clockwise || orient(v0, hull[n - 1], p) == .Counter_Clockwise {
		return .Outside
	}
	// Find the fan triangle v0, hull[lo], hull[lo+1] containing p's direction.
	lo, hi := 1, n - 1
	for hi - lo > 1 {
		mid := (lo + hi) / 2
		if orient(v0, hull[mid], p) != .Clockwise {
			lo = mid
		} else {
			hi = mid
		}
	}
	switch orient(hull[lo], hull[lo + 1], p) {
	case .Clockwise:
		return .Outside
	case .Collinear:
		return .Boundary
	case .Counter_Clockwise:
	}
	if (lo == 1 && orient(v0, hull[1], p) == .Collinear) || (lo + 1 == n - 1 && orient(v0, hull[n - 1], p) == .Collinear) {
		return .Boundary
	}
	return .Inside
}

// How many full turns the edge directions make going round the polygon.
@(private)
winding_turns :: proc "contextless" (poly: []Point) -> int {
	// Count the edges whose direction crosses the +x axis heading
	// counter-clockwise; each full turn crosses it exactly once.
	n := len(poly)
	turns := 0
	for i in 0 ..< n {
		d0 := poly[(i + 1) % n] - poly[i]
		d1 := poly[(i + 2) % n] - poly[(i + 1) % n]
		if half(d0) == 1 && half(d1) == 0 {
			turns += 1
		}
	}
	return turns
}

// 0 for directions in [0, pi), 1 for [pi, 2pi).
@(private)
half :: proc "contextless" (d: Point) -> int {
	return 0 if d.y > 0 || (d.y == 0 && d.x > 0) else 1
}

@(private)
gcd :: proc "contextless" (a, b: i64) -> i64 {
	a, b := a, b
	for b != 0 {
		a, b = b, a % b
	}
	return a
}
