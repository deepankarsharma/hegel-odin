package geom_tests

import "core:testing"

import hg "../deps/hegel-odin/hegel"
import geom "../geom"

@(test) test_cross_is_antisymmetric_and_dot_symmetric :: proc(t: ^testing.T) { hg.test(t, cross_is_antisymmetric_and_dot_symmetric) }

cross_is_antisymmetric_and_dot_symmetric :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, points(), "a")
	b := hg.draw(tc, points(), "b")
	hg.expect_value(tc, geom.cross(a, b), -geom.cross(b, a))
	hg.expect_value(tc, geom.dot(a, b), geom.dot(b, a))
	hg.expect_value(tc, geom.cross(a, a), 0)
}

@(test) test_lagrange_identity :: proc(t: ^testing.T) { hg.test(t, lagrange_identity) }

// dot^2 + cross^2 = |a|^2 |b|^2, checked in i128 since the products
// overflow i64.
lagrange_identity :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, points(), "a")
	b := hg.draw(tc, points(), "b")
	d, c := i128(geom.dot(a, b)), i128(geom.cross(a, b))
	hg.expect_value(tc, d * d + c * c, i128(geom.length2(a)) * i128(geom.length2(b)))
}

@(test) test_rot90 :: proc(t: ^testing.T) { hg.test(t, rot90) }

rot90 :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, points(), "a")
	b := hg.draw(tc, points(), "b")
	r := geom.rot90(a)
	hg.expect_value(tc, geom.dot(a, r), 0)
	hg.expect_value(tc, geom.cross(a, r), geom.length2(a))
	hg.expect_value(tc, geom.length2(r), geom.length2(a))
	hg.expect_value(tc, geom.rot90(geom.rot90(a)), -a)
	hg.expect_value(tc, geom.rot90(geom.rot90(geom.rot90(r))), a)
	// Rotation preserves dot and cross products.
	hg.expect_value(tc, geom.dot(r, geom.rot90(b)), geom.dot(a, b))
	hg.expect_value(tc, geom.cross(r, geom.rot90(b)), geom.cross(a, b))
}

@(test) test_orientation_symmetries :: proc(t: ^testing.T) { hg.test(t, orientation_symmetries) }

orientation_symmetries :: proc(tc: ^hg.Test_Case) {
	limit :: geom.MAX_COORD / 2
	a := hg.draw(tc, points(limit), "a")
	b := hg.draw(tc, points(limit), "b")
	c := hg.draw(tc, points(limit), "c")
	shift := hg.draw(tc, points(limit), "shift")
	o := geom.orient(a, b, c)
	// Cyclic rotation keeps the orientation; a swap flips it.
	hg.expect_value(tc, geom.orient(b, c, a), o)
	hg.expect_value(tc, geom.orient(c, a, b), o)
	hg.expect_value(tc, geom.orient(b, a, c), geom.Orientation(-i8(o)))
	hg.expect_value(tc, geom.orient(a + shift, b + shift, c + shift), o)
	hg.expect_value(tc, geom.orient(geom.rot90(a), geom.rot90(b), geom.rot90(c)), o)
	// Mirroring in the x axis flips it.
	hg.expect_value(tc, geom.orient({a.x, -a.y}, {b.x, -b.y}, {c.x, -c.y}), geom.Orientation(-i8(o)))
}

@(test) test_points_along_a_direction_are_collinear :: proc(t: ^testing.T) { hg.test(t, points_along_a_direction_are_collinear) }

points_along_a_direction_are_collinear :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, points(1000), "a")
	d := hg.draw(tc, points(1000), "d")
	j := hg.draw(tc, hg.integers(i64, -100, 100), "j")
	k := hg.draw(tc, hg.integers(i64, -100, 100), "k")
	hg.expect_value(tc, geom.orient(a, a + j * d, a + k * d), geom.Orientation.Collinear)
}

@(test) test_distances :: proc(t: ^testing.T) { hg.test(t, distances) }

distances :: proc(tc: ^hg.Test_Case) {
	a := hg.draw(tc, points(), "a")
	b := hg.draw(tc, points(), "b")
	c := hg.draw(tc, points(), "c")
	hg.expect_value(tc, geom.dist2(a, b), geom.dist2(b, a))
	hg.expect(tc, (geom.dist2(a, b) == 0) == (a == b))
	hg.expect(tc, geom.manhattan(a, c) <= geom.manhattan(a, b) + geom.manhattan(b, c))
	// Euclidean distance never exceeds Manhattan, nor falls below
	// Manhattan / sqrt(2).
	m := f64(geom.manhattan(a, b))
	e := geom.distance(a, b)
	hg.expect(tc, e <= m && m <= e * 1.4142135623730951 * (1 + 1e-12))
	hg.expect(tc, geom.distance(a, c) <= (geom.distance(a, b) + geom.distance(b, c)) * (1 + 1e-12))
}
