# geom: an integration test for hegel-odin

A small computational geometry library whose only purpose is to be
property-tested with [hegel-odin](https://github.com/deepankarsharma/hegel-odin),
fetched from GitHub the way an outside user would get it.

## Run it

Requires Odin (see hegel-odin's README for the known-good version), git, and
cargo.

```
./setup.sh
odin test tests -vet -strict-style
```

`setup.sh` clones hegel-odin into `deps/hegel-odin` (git-ignored) and builds
its libhegel. `./setup.sh --update` pulls the latest `main` again; set
`HEGEL_ODIN_REF` to test a branch or tag instead.

## The library (`geom/`)

Exact integer geometry: `Point :: [2]i64` with coordinates bounded by
`MAX_COORD`, so no predicate ever rounds or overflows.

| File | What it provides |
| --- | --- |
| `vector.odin` | `dot`, `cross`, `length2`, `dist2`, `distance`, `manhattan`, `rot90`, `orient`, `less_xy` |
| `segment.odin` | `on_segment`, `segments_intersect` |
| `aabb.odin` | `bounding_box`, `aabb_contains`, `aabb_union`, `aabb_intersects`, `aabb_intersection`, `aabb_lattice_count` |
| `polygon.odin` | `signed_area2`, `perimeter`, `boundary_lattice_count`, `is_strictly_convex_ccw`, `locate_point` (ray casting), `locate_point_convex` (O(log n)) |
| `hull.odin` | `convex_hull` (monotone chain) |
| `closest.odin` | `closest_pair` (divide and conquer) |
| `grid.odin` | `Spatial_Grid`, a spatial hash with insert, move, remove, lookup, and box queries |

## The properties (`tests/`)

Each property is a plain procedure, registered with a one-line test. The
tests import hegel as `hg`:

```odin
@(test) test_hull_contains_every_point :: proc(t: ^testing.T) { hg.test(t, hull_contains_every_point) }

hull_contains_every_point :: proc(tc: ^hg.Test_Case) {
	pts := hg.draw(tc, point_lists(), "pts")
	hull := geom.convex_hull(pts)
	for p in pts {
		hg.expect(tc, geom.locate_point_convex(hull, p) != .Outside)
	}
}
```

Each technique below appears somewhere in the suite:

- **Algebraic laws**: cross products are antisymmetric, the Lagrange
  identity holds, and orientation is invariant under cyclic relabelling.
- **Invariance under motion**: translating or rotating the input
  translates or rotates the output (hull, area, point location, intersection).
- **Constructed answers**: segments `p ± d` and `p ± e` must meet at `p`, and
  a segment shifted off its own line must miss itself.
- **Differential testing**: `closest_pair` against brute force, and
  `locate_point_convex` against `locate_point`.
- **A theorem as an oracle**: Pick's theorem (`2A = 2I + B - 2`) checks
  area, point location, and boundary counting against each other on random
  lattice polygons.
- **Minimality**: removing any hull vertex puts it outside the new hull.
- **Stateful, model-based testing**: `Spatial_Grid` runs random sequences of
  operations alongside a plain map (`hg.run_state_machine`, `hg.Pool`).
- **Custom generators** (`generators.odin`): `one_of` biases coordinates
  towards tiny ranges so that duplicate and collinear points are common. Star
  polygons produce simple, non-convex polygons by construction.

`demo_test.odin` shows what a failure looks like. It plants a plausible bug, a
closest-pair search that only compares neighbours after sorting by x, and
logs Hegel's shrunk counterexample:

```
Property failed with minimal example:
    pts: [][2]i64 = {{0, 0}, {0, 2}, {1, 0}}
expected sorted_neighbours_closest(pts) to be 1, got 4
```
