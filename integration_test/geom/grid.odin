package geom

import "base:runtime"
import "core:slice"

/*
A spatial hash: a set of points keyed by integer id, bucketed into square
cells of side `cell_size` so that box queries only visit nearby cells.

	grid: geom.Spatial_Grid
	geom.grid_init(&grid, cell_size = 16)
	defer geom.grid_destroy(&grid)
	geom.grid_insert(&grid, 7, {3, -40})
	ids := geom.grid_query(&grid, {{0, -50}, {10, 0}})
*/
Spatial_Grid :: struct {
	cell_size: i64,
	cells:     map[Point][dynamic]Grid_Entry,
	positions: map[int]Point,
	allocator: runtime.Allocator,
}

// A point in one of the grid's cells.
Grid_Entry :: struct {
	id: int,
	p:  Point,
}

grid_init :: proc(g: ^Spatial_Grid, cell_size: i64, allocator := context.allocator) {
	assert(cell_size > 0, "cell_size must be positive")
	g^ = {
		cell_size = cell_size,
		cells     = make(map[Point][dynamic]Grid_Entry, allocator),
		positions = make(map[int]Point, allocator),
		allocator = allocator,
	}
}

grid_destroy :: proc(g: ^Spatial_Grid) {
	for _, bucket in g.cells {
		delete(bucket)
	}
	delete(g.cells)
	delete(g.positions)
	g^ = {}
}

grid_len :: proc(g: ^Spatial_Grid) -> int {
	return len(g.positions)
}

// Adds point `id` at `p`. Returns false, changing nothing, if `id` exists.
grid_insert :: proc(g: ^Spatial_Grid, id: int, p: Point) -> bool {
	if id in g.positions {
		return false
	}
	g.positions[id] = p
	key := cell_of(g, p)
	bucket, found := &g.cells[key]
	if !found {
		g.cells[key] = make([dynamic]Grid_Entry, g.allocator)
		bucket = &g.cells[key]
	}
	append(bucket, Grid_Entry{id, p})
	return true
}

// Removes point `id`. Returns false if there is no such point.
grid_remove :: proc(g: ^Spatial_Grid, id: int) -> bool {
	p, found := g.positions[id]
	if !found {
		return false
	}
	delete_key(&g.positions, id)
	key := cell_of(g, p)
	bucket := &g.cells[key]
	for e, i in bucket {
		if e.id == id {
			unordered_remove(bucket, i)
			break
		}
	}
	if len(bucket) == 0 {
		delete(bucket^)
		delete_key(&g.cells, key)
	}
	return true
}

// Moves point `id` to `p`. Returns false if there is no such point.
grid_move :: proc(g: ^Spatial_Grid, id: int, p: Point) -> bool {
	grid_remove(g, id) or_return
	return grid_insert(g, id, p)
}

// The position of point `id`.
grid_get :: proc(g: ^Spatial_Grid, id: int) -> (p: Point, ok: bool) {
	return g.positions[id]
}

// The ids of the points inside `box`, in ascending order.
grid_query :: proc(g: ^Spatial_Grid, box: AABB, allocator := context.allocator) -> []int {
	out := make([dynamic]int, allocator)
	lo, hi := cell_of(g, box.min), cell_of(g, box.max)
	span := (hi - lo) + 1
	if span.x * span.y > i64(len(g.cells)) {
		// The box covers more cells than are occupied: scan those instead.
		for _, bucket in g.cells {
			collect(&out, bucket[:], box)
		}
	} else {
		for cy in lo.y ..= hi.y {
			for cx in lo.x ..= hi.x {
				if bucket, found := g.cells[{cx, cy}]; found {
					collect(&out, bucket[:], box)
				}
			}
		}
	}
	slice.sort(out[:])
	return out[:]
}

@(private)
collect :: proc(out: ^[dynamic]int, bucket: []Grid_Entry, box: AABB) {
	for e in bucket {
		if aabb_contains(box, e.p) {
			append(out, e.id)
		}
	}
}

@(private)
cell_of :: proc(g: ^Spatial_Grid, p: Point) -> Point {
	return {floor_div(p.x, g.cell_size), floor_div(p.y, g.cell_size)}
}

// Division rounding towards negative infinity, so cells tile the plane
// evenly across zero.
@(private)
floor_div :: proc "contextless" (a, b: i64) -> i64 {
	q := a / b
	if (a % b != 0) && ((a < 0) != (b < 0)) {
		q -= 1
	}
	return q
}
