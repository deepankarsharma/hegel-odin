package geom

// The closed segment from `a` to `b`. `a == b` is a single point.
Segment :: struct {
	a, b: Point,
}

// Whether `p` lies on the closed segment `s`.
on_segment :: proc "contextless" (p: Point, s: Segment) -> bool {
	return orient(s.a, s.b, p) == .Collinear && in_span(p, s.a, s.b)
}

// Whether the closed segments share at least one point, touching included.
segments_intersect :: proc "contextless" (s, t: Segment) -> bool {
	o1 := orient(s.a, s.b, t.a)
	o2 := orient(s.a, s.b, t.b)
	o3 := orient(t.a, t.b, s.a)
	o4 := orient(t.a, t.b, s.b)
	if o1 != o2 && o3 != o4 && o1 != .Collinear && o2 != .Collinear && o3 != .Collinear && o4 != .Collinear {
		return true
	}
	return on_segment(t.a, s) || on_segment(t.b, s) || on_segment(s.a, t) || on_segment(s.b, t)
}

// Whether `p` is inside the bounding box of `a` and `b`.
@(private)
in_span :: proc "contextless" (p, a, b: Point) -> bool {
	return min(a.x, b.x) <= p.x && p.x <= max(a.x, b.x) && min(a.y, b.y) <= p.y && p.y <= max(a.y, b.y)
}
