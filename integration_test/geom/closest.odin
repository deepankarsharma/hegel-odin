package geom

import "core:slice"

/*
The closest pair among `points` by divide and conquer, in O(n log n).

Returns indices `i < j` into `points` and their squared distance. `ok` is
false when there are fewer than two points.
*/
closest_pair :: proc(points: []Point) -> (i, j: int, d2: i64, ok: bool) {
	if len(points) < 2 {
		return
	}
	pts := make([]Indexed, len(points), context.temp_allocator)
	for p, k in points {
		pts[k] = {p, k}
	}
	slice.sort_by(pts, proc(a, b: Indexed) -> bool { return less_xy(a.p, b.p) })
	buf := make([]Indexed, len(points), context.temp_allocator)
	best := Best{d2 = max(i64)}
	closest_rec(pts, buf, &best)
	return best.i, best.j, best.d2, true
}

@(private)
Indexed :: struct {
	p:     Point,
	index: int,
}

@(private)
Best :: struct {
	i, j: int,
	d2:   i64,
}

// Finds the closest pair in `pts`, sorted by x, and leaves `pts` sorted by y.
@(private)
closest_rec :: proc(pts, buf: []Indexed, best: ^Best) {
	n := len(pts)
	if n <= 3 {
		for a in 0 ..< n {
			for b in a + 1 ..< n {
				consider(best, pts[a], pts[b])
			}
		}
		slice.sort_by(pts, less_y)
		return
	}

	mid := n / 2
	mid_x := pts[mid].p.x
	closest_rec(pts[:mid], buf, best)
	closest_rec(pts[mid:], buf, best)

	// Merge the halves by y.
	l, r, k := 0, mid, 0
	for l < mid || r < n {
		if r == n || (l < mid && less_y(pts[l], pts[r])) {
			buf[k] = pts[l]
			l += 1
		} else {
			buf[k] = pts[r]
			r += 1
		}
		k += 1
	}
	copy(pts, buf[:n])

	// Only points within the best distance of the dividing line can beat it,
	// and each needs comparing against a bounded number of strip neighbours.
	strip := 0
	for q in pts {
		dx := q.p.x - mid_x
		if dx * dx >= best.d2 {
			continue
		}
		for s := strip - 1; s >= 0; s -= 1 {
			dy := q.p.y - buf[s].p.y
			if dy * dy >= best.d2 {
				break
			}
			consider(best, q, buf[s])
		}
		buf[strip] = q
		strip += 1
	}
}

@(private)
consider :: proc(best: ^Best, a, b: Indexed) {
	d := dist2(a.p, b.p)
	if d < best.d2 {
		best^ = {min(a.index, b.index), max(a.index, b.index), d}
	}
}

@(private)
less_y :: proc(a, b: Indexed) -> bool {
	return a.p.y < b.p.y
}
