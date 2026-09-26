package geom

// An axis-aligned box, closed on every side, with `min <= max` per axis.
AABB :: struct {
	min, max: Point,
}

// The smallest box containing `points`; `ok` is false when there are none.
bounding_box :: proc "contextless" (points: []Point) -> (box: AABB, ok: bool) {
	if len(points) == 0 {
		return
	}
	box = {points[0], points[0]}
	for p in points[1:] {
		box.min = {min(box.min.x, p.x), min(box.min.y, p.y)}
		box.max = {max(box.max.x, p.x), max(box.max.y, p.y)}
	}
	return box, true
}

aabb_contains :: proc "contextless" (box: AABB, p: Point) -> bool {
	return box.min.x <= p.x && p.x <= box.max.x && box.min.y <= p.y && p.y <= box.max.y
}

// The smallest box containing both boxes.
aabb_union :: proc "contextless" (a, b: AABB) -> AABB {
	return {{min(a.min.x, b.min.x), min(a.min.y, b.min.y)}, {max(a.max.x, b.max.x), max(a.max.y, b.max.y)}}
}

aabb_intersects :: proc "contextless" (a, b: AABB) -> bool {
	return a.min.x <= b.max.x && b.min.x <= a.max.x && a.min.y <= b.max.y && b.min.y <= a.max.y
}

// The overlap of the boxes; `ok` is false when they are disjoint.
aabb_intersection :: proc "contextless" (a, b: AABB) -> (box: AABB, ok: bool) {
	box = {{max(a.min.x, b.min.x), max(a.min.y, b.min.y)}, {min(a.max.x, b.max.x), min(a.max.y, b.max.y)}}
	if box.min.x > box.max.x || box.min.y > box.max.y {
		return {}, false
	}
	return box, true
}

// The number of lattice points in the box.
aabb_lattice_count :: proc "contextless" (box: AABB) -> i64 {
	return (box.max.x - box.min.x + 1) * (box.max.y - box.min.y + 1)
}
