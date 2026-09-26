/*
A small exact computational geometry library over integer points.

Every predicate is exact: coordinates are `i64` and bounded by `MAX_COORD`, so
cross and dot products of differences cannot overflow. Only the procedures
returning `f64` (lengths, perimeters) round.
*/
package geom

import "core:math"

// Coordinates must lie in `[-MAX_COORD, MAX_COORD]`.
MAX_COORD :: 1 << 20

Point :: [2]i64

Orientation :: enum i8 {
	Clockwise         = -1,
	Collinear         = 0,
	Counter_Clockwise = 1,
}

dot :: proc "contextless" (a, b: Point) -> i64 {
	return a.x * b.x + a.y * b.y
}

// The z component of the 3D cross product: positive when `b` is
// counter-clockwise of `a`.
cross :: proc "contextless" (a, b: Point) -> i64 {
	return a.x * b.y - a.y * b.x
}

length2 :: proc "contextless" (a: Point) -> i64 {
	return dot(a, a)
}

dist2 :: proc "contextless" (a, b: Point) -> i64 {
	return length2(b - a)
}

distance :: proc "contextless" (a, b: Point) -> f64 {
	return math.sqrt(f64(dist2(a, b)))
}

manhattan :: proc "contextless" (a, b: Point) -> i64 {
	return abs(b.x - a.x) + abs(b.y - a.y)
}

// `a` rotated a quarter turn counter-clockwise about the origin.
rot90 :: proc "contextless" (a: Point) -> Point {
	return {-a.y, a.x}
}

// Lexicographic order, by x then y. Not "contextless", so that it can be
// passed to `slice.sort_by`.
less_xy :: proc(a, b: Point) -> bool {
	return a.x < b.x || (a.x == b.x && a.y < b.y)
}

// Which way the path `a -> b -> c` turns.
orient :: proc "contextless" (a, b, c: Point) -> Orientation {
	return Orientation(sign(cross(b - a, c - a)))
}

@(private)
sign :: proc "contextless" (x: i64) -> i8 {
	return 1 if x > 0 else -1 if x < 0 else 0
}
