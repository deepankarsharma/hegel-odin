package hegel_tests

import "core:strings"
import "core:testing"

import hegel "../hegel"

Tree :: union {
	int,
	^Node,
}

Node :: struct {
	left, right: Tree,
}

trees :: proc(max_depth := 32, max_leaves := 100) -> hegel.Generator(Tree) {
	return hegel.recursive(
		hegel.mapped(hegel.integers(int, 0, 9), proc(n: int) -> Tree { return n }),
		proc(child: hegel.Generator(Tree)) -> hegel.Generator(Tree) {
			return hegel.composite_with_data(new_clone(child), proc(tc: ^hegel.Test_Case, child: ^hegel.Generator(Tree)) -> Tree {
				left := hegel.draw(tc, child^)
				right := hegel.draw(tc, child^)
				return new_clone(Node{left, right})
			})
		},
		max_depth,
		max_leaves,
	)
}

depth :: proc(tree: Tree) -> int {
	node, is_node := tree.(^Node)
	if !is_node {
		return 0
	}
	return 1 + max(depth(node.left), depth(node.right))
}

leaves :: proc(tree: Tree) -> int {
	node, is_node := tree.(^Node)
	if !is_node {
		return 1
	}
	return leaves(node.left) + leaves(node.right)
}

@(test)
test_recursive_respects_limits :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		tree := hegel.draw(tc, trees(max_depth = 3, max_leaves = 6))
		hegel.expect(tc, depth(tree) <= 3)
		hegel.expect(tc, leaves(tree) <= 6)
		leaf := hegel.draw(tc, trees(max_depth = 0))
		hegel.expect_value(tc, depth(leaf), 0)
	}, quiet(300))
}

@(test)
test_recursive_shrinks_to_small_trees :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		tree := hegel.draw(tc, trees(), "tree")
		hegel.expect(tc, leaves(tree) < 3)
	}, quiet(1000))
	defer hegel.destroy_run_result(&result)
	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "expected leaves(tree) < 3 to be true")
	expect_contains(t, failure.output, "tree: Tree = ")
}

@(test)
test_recursive_trees_are_found :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		tree := hegel.draw(tc, trees())
		hegel.expect(tc, depth(tree) < 2)
	}, quiet(1000))
	defer hegel.destroy_run_result(&result)
	_, ok := single_failure(t, result)
	testing.expect(t, ok)
}

@(test)
test_failures_inside_recursive_generators_propagate :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		gen := hegel.recursive(
			hegel.composite(proc(tc: ^hegel.Test_Case) -> int {
				n := hegel.draw(tc, hegel.integers(int, 0, 100))
				assert(n < 90, "leaf too large")
				return n
			}),
			proc(child: hegel.Generator(int)) -> hegel.Generator(int) {
				return hegel.mapped(hegel.lists(child, max_size = 3), proc(xs: []int) -> int {
					total := 0
					for x in xs {
						total += x
					}
					return total
				})
			},
		)
		hegel.draw(tc, gen)
	}, quiet(1000))
	defer hegel.destroy_run_result(&result)
	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	expect_contains(t, failure.message, "leaf too large")
}

// A stack with a bug: once it holds three items, pushes are silently dropped.
Bounded_Stack :: struct {
	items: [3]int,
	count: int,
	model: [dynamic]int,
}

stack_push :: proc(tc: ^hegel.Test_Case, s: ^Bounded_Stack) {
	value := hegel.draw(tc, hegel.integers(int, 0, 100), "value")
	if s.count < len(s.items) {
		s.items[s.count] = value
		s.count += 1
	}
	append(&s.model, value)
}

stack_pop :: proc(tc: ^hegel.Test_Case, s: ^Bounded_Stack) {
	hegel.assume(tc, len(s.model) > 0)
	expected := pop(&s.model)
	s.count -= 1
	hegel.expect_value(tc, s.items[s.count], expected)
}

stack_sizes_agree :: proc(tc: ^hegel.Test_Case, s: ^Bounded_Stack) {
	hegel.expect_value(tc, s.count, len(s.model))
}

bounded_stack_machine := hegel.State_Machine(Bounded_Stack) {
	rules      = {{name = "push", action = stack_push}, {name = "pop", action = stack_pop}},
	invariants = {{name = "sizes_agree", check = stack_sizes_agree, always_check = true}},
}

@(test)
test_state_machine_finds_bug :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		stack: Bounded_Stack
		hegel.run_state_machine(tc, &stack, bounded_stack_machine)
	}, quiet(1000))
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "expected s.count to be 4, got 3")
	testing.expect_value(t, strings.count(failure.output, ": push"), 4)
	expect_contains(t, failure.output, "Step 4: push\n    value: int = 0")
}

@(test)
test_state_machine_passes_for_correct_model :: proc(t: ^testing.T) {
	Counter :: struct {
		value: int,
		model: int,
	}
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		increment :: proc(tc: ^hegel.Test_Case, c: ^Counter) {
			c.value += 1
			c.model += 1
		}
		reset :: proc(tc: ^hegel.Test_Case, c: ^Counter) {
			c.value = 0
			c.model = 0
		}
		agree :: proc(tc: ^hegel.Test_Case, c: ^Counter) {
			hegel.expect(tc, c.value == c.model)
		}
		c: Counter
		hegel.run_state_machine(tc, &c, hegel.State_Machine(Counter) {
			rules      = {{name = "increment", action = increment}, {name = "reset", action = reset, weight = 0.1}},
			invariants = {{name = "agree", check = agree}},
			step_count = 20,
		})
	}, quiet())
}

@(test)
test_state_machine_without_rules_is_an_error :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		x: int
		hegel.run_state_machine(tc, &x, hegel.State_Machine(int){})
	}, quiet())
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Error)
	expect_contains(t, result.error, "at least one rule")
}

// Accounts whose transfers create money when the source and target coincide.
Bank :: struct {
	balances:  map[int]int,
	next_id:   int,
	accounts:  ^hegel.Pool(int),
	deposited: int,
}

bank_open :: proc(tc: ^hegel.Test_Case, b: ^Bank) {
	id := b.next_id
	b.next_id += 1
	deposit := hegel.draw(tc, hegel.integers(int, 0, 100), "deposit")
	b.balances[id] = deposit
	b.deposited += deposit
	hegel.pool_add(tc, b.accounts, id)
}

bank_transfer :: proc(tc: ^hegel.Test_Case, b: ^Bank) {
	from := hegel.draw(tc, hegel.pool_values(b.accounts), "from")
	to := hegel.draw(tc, hegel.pool_values(b.accounts), "to")
	amount := hegel.draw(tc, hegel.integers(int, 0, b.balances[from]), "amount")
	from_balance, to_balance := b.balances[from], b.balances[to]
	b.balances[from] = from_balance - amount
	b.balances[to] = to_balance + amount
}

bank_close :: proc(tc: ^hegel.Test_Case, b: ^Bank) {
	id := hegel.draw(tc, hegel.pool_values(b.accounts, consume = true), "id")
	b.deposited -= b.balances[id]
	delete_key(&b.balances, id)
}

bank_money_is_conserved :: proc(tc: ^hegel.Test_Case, b: ^Bank) {
	total := 0
	for _, balance in b.balances {
		total += balance
	}
	hegel.expect_value(tc, total, b.deposited)
}

bank_machine := hegel.State_Machine(Bank) {
	rules      = {
		{name = "open", action = bank_open},
		{name = "transfer", action = bank_transfer},
		{name = "close", action = bank_close},
	},
	invariants = {{name = "money_is_conserved", check = bank_money_is_conserved, always_check = true}},
}

@(test)
test_pools_in_state_machines :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		bank := Bank{balances = make(map[int]int), accounts = hegel.new_pool(tc, int)}
		hegel.run_state_machine(tc, &bank, bank_machine)
	}, quiet(1000))
	defer hegel.destroy_run_result(&result)

	failure, ok := single_failure(t, result)
	if !ok {
		return
	}
	testing.expect_value(t, failure.message, "expected total to be 1, got 2")
	expect_contains(t, failure.output, "Step 1: open\n    deposit: int = 1")
	expect_contains(t, failure.output, "Step 2: transfer\n    from: int = 0\n    to: int = 0\n    amount: int = 1")
}

@(test)
test_pools_track_values :: proc(t: ^testing.T) {
	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		pool := hegel.new_pool(tc, string)
		names := hegel.draw(tc, hegel.lists(hegel.text(max_size = 4), min_size = 1, max_size = 5))
		for name in names {
			hegel.pool_add(tc, pool, name)
		}
		hegel.expect_value(tc, hegel.pool_len(pool), len(names))
		reused := hegel.draw(tc, hegel.pool_values(pool))
		found := false
		for name in names {
			found ||= name == reused
		}
		hegel.expect(tc, found)
		hegel.draw(tc, hegel.pool_values(pool, consume = true))
		hegel.expect_value(tc, hegel.pool_len(pool), len(names) - 1)
	}, quiet())
}

@(test)
test_drawing_from_an_empty_pool_rejects :: proc(t: ^testing.T) {
	result := hegel.run(proc(tc: ^hegel.Test_Case) {
		pool := hegel.new_pool(tc, int)
		hegel.draw(tc, hegel.pool_values(pool))
	}, quiet())
	defer hegel.destroy_run_result(&result)
	testing.expect_value(t, result.status, hegel.Run_Status.Error)
	expect_contains(t, result.error, "Unsatisfiable")
}
