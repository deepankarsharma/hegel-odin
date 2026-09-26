package hegel

import lh "libhegel"

/*
Recursively defined values such as trees and expressions.

`leaf` produces the smallest values. `branch` receives a generator for
sub-values and returns a generator that combines them into a bigger value.
The engine decides where to branch, keeps each value within `max_depth`
nested branches and `max_leaves` leaves, and shrinks towards leaves.

	Expr :: union { int, ^Add }
	Add  :: struct { left, right: Expr }

	exprs := hegel.recursive(
		hegel.mapped(hegel.integers(int, 0, 9), proc(n: int) -> Expr { return n }),
		proc(child: hegel.Generator(Expr)) -> hegel.Generator(Expr) {
			return hegel.composite_with_data(new_clone(child), proc(tc: ^hegel.Test_Case, child: ^hegel.Generator(Expr)) -> Expr {
				return new_clone(Add{hegel.draw(tc, child^), hegel.draw(tc, child^)})
			})
		},
	)
*/
recursive :: proc(
	leaf: Generator($T),
	branch: proc(child: Generator(T)) -> Generator(T),
	max_depth := 32,
	max_leaves := 100,
) -> Generator(T) {
	State :: struct {
		leaf:       Generator(T),
		branch:     proc(child: Generator(T)) -> Generator(T),
		max_depth:  int,
		max_leaves: int,
	}
	Scope :: struct {
		state:     ^State,
		recursion: ^lh.Recursion,
	}
	Subtree :: struct {
		scope: ^Scope,
		depth: u64,
	}
	Attempt :: struct {
		root:  Generator(T),
		value: T,
	}

	subtree :: proc(scope: ^Scope, depth: u64) -> Generator(T) {
		return {draw_subtree, new_clone(Subtree{scope, depth}), label_of("hegel_odin.recursive.subtree")}
	}

	draw_subtree :: proc(tc: ^Test_Case, data: rawptr) -> T {
		sub := (^Subtree)(data)
		scope := sub.scope
		value: T
		if recursion_branch(tc, scope.recursion, sub.depth) {
			value = draw(tc, scope.state.branch(subtree(scope, sub.depth + 1)))
		} else {
			recursion_leaf(tc, scope.recursion)
			value = draw(tc, scope.state.leaf)
		}
		if sub.depth == 0 {
			recursion_finish(tc, scope.recursion)
		}
		return value
	}

	draw_root :: proc(tc: ^Test_Case, data: rawptr) {
		attempt := (^Attempt)(data)
		attempt.value = draw(tc, attempt.root)
	}

	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		state := (^State)(data)
		recursion := new_recursion(tc, state.max_depth, state.max_leaves)
		scope := new_clone(Scope{state, recursion})

		for {
			attempt := Attempt{root = subtree(scope, 0)}
			outcome := invoke(tc, draw_root, &attempt)
			if outcome.kind == .Passed {
				return attempt.value
			}
			if outcome.kind != .Retry || outcome._scope != recursion {
				abort_with(tc, outcome)
			}
			if outcome.message == RETRY_LEAF_BUDGET {
				recursion_retry(tc, recursion)
			}
		}
	}

	state := State{leaf, branch, max_depth, max_leaves}
	return {generate, new_clone(state), combine_labels(label_of("hegel_odin.recursive"), leaf.label)}
}

@(private)
RETRY_LEAF_BUDGET :: "leaf budget exceeded"

@(private)
RETRY_MISPRICED :: "attempt mispriced"

@(private)
abort_retry :: proc(tc: ^Test_Case, recursion: ^lh.Recursion, reason: string, loc := #caller_location) -> ! {
	b := tc._boundary
	b.outcome = {kind = .Retry, message = reason, location = loc, _scope = recursion}
	longjmp_boundary(b)
}

@(private)
new_recursion :: proc(tc: ^Test_Case, max_depth, max_leaves: int) -> ^lh.Recursion {
	if max_depth < 0 || max_leaves < 0 {
		usage_error(tc, "recursive: max_depth and max_leaves must be non-negative, got %d and %d", max_depth, max_leaves)
	}
	recursion: ^lh.Recursion
	check(tc, lh.new_recursion(tc._ctx, tc._handle, u64(max_depth), u64(max_leaves), &recursion))
	own(tc, recursion)
	return recursion
}

@(private)
recursion_branch :: proc(tc: ^Test_Case, recursion: ^lh.Recursion, depth: u64) -> (is_branch: bool) {
	check(tc, lh.recursion_branch(tc._ctx, tc._handle, recursion, depth, &is_branch))
	return
}

// Counts a leaf against the budget, restarting the value when it is spent.
@(private)
recursion_leaf :: proc(tc: ^Test_Case, recursion: ^lh.Recursion) {
	rc := lh.recursion_leaf(tc._ctx, tc._handle, recursion)
	if rc == .Retry {
		abort_retry(tc, recursion, RETRY_LEAF_BUDGET)
	}
	check(tc, rc)
}

// Accepts the finished value, unless the engine discarded it as mispriced.
@(private)
recursion_finish :: proc(tc: ^Test_Case, recursion: ^lh.Recursion) {
	rc := lh.recursion_finish(tc._ctx, tc._handle, recursion)
	if rc == .Retry {
		abort_retry(tc, recursion, RETRY_MISPRICED)
	}
	check(tc, rc)
}

@(private)
recursion_retry :: proc(tc: ^Test_Case, recursion: ^lh.Recursion) {
	check(tc, lh.recursion_retry(tc._ctx, tc._handle, recursion))
}
