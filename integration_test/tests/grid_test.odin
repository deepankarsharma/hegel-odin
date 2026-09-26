package geom_tests

import "core:slice"
import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

/*
Model-based test of `Spatial_Grid`: the engine runs random sequences of
inserts, moves, removes and queries against both the grid and a plain map,
and checks that they always agree.
*/
Grid_Machine :: struct {
	grid:    geom.Spatial_Grid,
	model:   map[int]geom.Point,
	ids:     ^hg.Pool(int),
	next_id: int,
}

// Positions straddle zero and cell boundaries, where cell rounding goes wrong.
grid_points :: proc() -> hg.Generator(geom.Point) {
	return hg.arrays(hg.integers(i64, -200, 200), 2)
}

grid_insert_rule :: proc(tc: ^hg.Test_Case, m: ^Grid_Machine) {
	p := hg.draw(tc, grid_points(), "p")
	id := m.next_id
	m.next_id += 1
	hg.expect(tc, geom.grid_insert(&m.grid, id, p))
	hg.expect(tc, !geom.grid_insert(&m.grid, id, p))
	m.model[id] = p
	hg.pool_add(tc, m.ids, id)
}

grid_move_rule :: proc(tc: ^hg.Test_Case, m: ^Grid_Machine) {
	id := hg.draw(tc, hg.pool_values(m.ids), "id")
	p := hg.draw(tc, grid_points(), "p")
	hg.expect(tc, geom.grid_move(&m.grid, id, p))
	m.model[id] = p
}

grid_remove_rule :: proc(tc: ^hg.Test_Case, m: ^Grid_Machine) {
	id := hg.draw(tc, hg.pool_values(m.ids, consume = true), "id")
	hg.expect(tc, geom.grid_remove(&m.grid, id))
	hg.expect(tc, !geom.grid_remove(&m.grid, id))
	delete_key(&m.model, id)
}

grid_query_rule :: proc(tc: ^hg.Test_Case, m: ^Grid_Machine) {
	box := hg.draw(tc, hg.one_of(boxes(20), boxes(250)), "box")
	expected := make([dynamic]int)
	for id, p in m.model {
		if geom.aabb_contains(box, p) {
			append(&expected, id)
		}
	}
	slice.sort(expected[:])
	got := geom.grid_query(&m.grid, box)
	hg.expectf(tc, slice.equal(got, expected[:]), "grid_query returned %v, expected %v", got, expected[:])
}

grid_agrees_with_model :: proc(tc: ^hg.Test_Case, m: ^Grid_Machine) {
	hg.expect_value(tc, geom.grid_len(&m.grid), len(m.model))
	for id, p in m.model {
		got, ok := geom.grid_get(&m.grid, id)
		hg.expect(tc, ok && got == p)
	}
}

@(test) test_spatial_grid_matches_model :: proc(t: ^testing.T) { hg.test(t, spatial_grid_matches_model) }

spatial_grid_matches_model :: proc(tc: ^hg.Test_Case) {
	m: Grid_Machine
	cell_size := hg.draw(tc, hg.integers(i64, 1, 64), "cell_size")
	geom.grid_init(&m.grid, cell_size)
	m.model = make(map[int]geom.Point)
	m.ids = hg.new_pool(tc, int)
	hg.run_state_machine(tc, &m, hg.State_Machine(Grid_Machine) {
		rules = {
			{name = "insert", action = grid_insert_rule, weight = 3},
			{name = "move", action = grid_move_rule},
			{name = "remove", action = grid_remove_rule},
			{name = "query", action = grid_query_rule, weight = 2},
		},
		invariants = {{name = "agrees_with_model", check = grid_agrees_with_model}},
	})
}
