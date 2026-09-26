package hegel

import lh "libhegel"

/*
A value pool for stateful tests: rules add the values they create, and later
rules draw from it. The engine chooses which value to reuse and shrinks those
choices well, which plain `sampled_from` over a slice cannot.

Pools belong to the test case that made them and must not outlive it.
*/
Pool :: struct($T: typeid) {
	handle: ^lh.Pool,
	values: map[i64]T,
}

new_pool :: proc(tc: ^Test_Case, $T: typeid) -> ^Pool(T) {
	pool := new(Pool(T))
	pool.handle = new_engine_pool(tc)
	pool.values = make(map[i64]T)
	return pool
}

pool_add :: proc(tc: ^Test_Case, pool: ^Pool($T), value: T) {
	id := pool_add_variable(tc, pool.handle)
	if id in pool.values {
		usage_error(tc, "pool: the engine returned duplicate variable id %d", id)
	}
	pool.values[id] = value
}

pool_len :: proc(pool: ^Pool($T)) -> int {
	return len(pool.values)
}

/*
Draws values previously added to `pool`. With `consume`, a drawn value is
removed. Drawing from an empty pool rejects the test case (or, inside a state
machine, just the current rule).
*/
pool_values :: proc(pool: ^Pool($T), consume := false) -> Generator(T) {
	State :: struct {
		pool:    ^Pool(T),
		consume: bool,
	}
	generate :: proc(tc: ^Test_Case, data: rawptr) -> T {
		s := (^State)(data)
		id := pool_draw_variable(tc, s.pool.handle, s.consume)
		value, ok := s.pool.values[id]
		if !ok {
			usage_error(tc, "pool: the engine selected unknown variable id %d", id)
		}
		if s.consume {
			delete_key(&s.pool.values, id)
		}
		return value
	}
	return {generate, new_clone(State{pool, consume}), label_of("hegel_odin.pool_values")}
}

// A state-machine rule: an action the engine may apply to the machine.
Rule :: struct($M: typeid) {
	name:   string,
	action: proc(tc: ^Test_Case, machine: ^M),
	// Relative selection weight. Zero means 1.
	weight: f64,
}

// A state-machine invariant: a check of the machine's state.
Invariant :: struct($M: typeid) {
	name:         string,
	check:        proc(tc: ^Test_Case, machine: ^M),
	// Check after every step rather than at sampled points.
	always_check: bool,
}

// A state machine definition: the rules that act on a machine of type `M` and
// the invariants that must hold between them.
State_Machine :: struct($M: typeid) {
	rules:      []Rule(M),
	invariants: []Invariant(M),
	// The most rules run per test case. Zero means 50.
	step_count: int,
}

/*
Model-based testing: applies a sequence of engine-chosen rules from
`definition` to `machine`, checking invariants along the way. Every invariant
runs on the initial and the final state; in between, invariants flagged
`always_check` run after every step and the others at randomly sampled steps.

A rule that calls `assume(tc, false)` (or draws from an empty pool) is
skipped rather than rejecting the whole test case. On failure, the minimal
example lists the steps that led to it along with the values each drew.

	Stack :: struct { items: [dynamic]int, model_len: int }

	push :: proc(tc: ^hegel.Test_Case, s: ^Stack) {
		append(&s.items, hegel.draw(tc, hegel.integers(int), "value"))
		s.model_len += 1
	}
	pop :: proc(tc: ^hegel.Test_Case, s: ^Stack) {
		hegel.assume(tc, s.model_len > 0)
		pop(&s.items)
		s.model_len -= 1
	}
	lengths_agree :: proc(tc: ^hegel.Test_Case, s: ^Stack) {
		hegel.expect(tc, len(s.items) == s.model_len)
	}

	stack_machine := hegel.State_Machine(Stack){
		rules      = {{name = "push", action = push}, {name = "pop", action = pop}},
		invariants = {{name = "lengths_agree", check = lengths_agree}},
	}

	hegel.test(t, proc(tc: ^hegel.Test_Case) {
		stack: Stack
		hegel.run_state_machine(tc, &stack, stack_machine)
	})
*/
run_state_machine :: proc(tc: ^Test_Case, machine: ^$M, definition: State_Machine(M)) {
	Step :: struct {
		action:  proc(tc: ^Test_Case, machine: ^M),
		machine: ^M,
	}
	call_step :: proc(tc: ^Test_Case, data: rawptr) {
		step := (^Step)(data)
		step.action(tc, step.machine)
	}
	run_step :: proc(tc: ^Test_Case, action: proc(tc: ^Test_Case, machine: ^M), machine: ^M) -> (rejected: bool) {
		step := Step{action, machine}
		return invoke_step(tc, call_step, &step)
	}
	check_all :: proc(tc: ^Test_Case, invariants: []Invariant(M), machine: ^M, heading: string) {
		if len(invariants) > 0 {
			note(tc, heading)
		}
		for inv in invariants {
			run_step(tc, inv.check, machine)
		}
	}

	rules, invariants := definition.rules, definition.invariants
	spec := Machine_Spec {
		rule_names      = make([]string, len(rules)),
		rule_weights    = make([]f64, len(rules)),
		invariant_names = make([]string, len(invariants)),
		always_check    = make([]bool, len(invariants)),
		step_count      = definition.step_count if definition.step_count != 0 else 50,
	}
	for rule, i in rules {
		if rule.action == nil {
			usage_error(tc, "run_state_machine: rule %q has no action", rule.name)
		}
		spec.rule_names[i] = rule.name
		spec.rule_weights[i] = rule.weight if rule.weight != 0 else 1
	}
	for inv, i in invariants {
		if inv.check == nil {
			usage_error(tc, "run_state_machine: invariant %q has no check", inv.name)
		}
		spec.invariant_names[i] = inv.name
		spec.always_check[i] = inv.always_check
	}
	sm := new_machine(tc, spec)

	check_all(tc, invariants, machine, "Checking invariants on the initial state")
	step_number := 0
	for machine_next_round(tc, sm) {
		for index in machine_next_rule(tc, sm) {
			rule := rules[index]
			step_number += 1
			notef(tc, "Step %d: %s", step_number, rule.name)
			if run_step(tc, rule.action, machine) {
				machine_rule_rejected(tc, sm)
			}
		}
		for inv, i in invariants {
			if machine_should_check_invariant(tc, sm, i) {
				run_step(tc, inv.check, machine)
			}
		}
	}
	check_all(tc, invariants, machine, "Checking invariants on the final state")
}

@(private)
Machine_Spec :: struct {
	rule_names:      []string,
	rule_weights:    []f64,
	invariant_names: []string,
	always_check:    []bool,
	step_count:      int,
}

@(private)
new_machine :: proc(tc: ^Test_Case, spec: Machine_Spec) -> ^lh.State_Machine {
	if len(spec.rule_names) == 0 {
		usage_error(tc, "run_state_machine: at least one rule is required")
	}
	if spec.step_count < 1 {
		usage_error(tc, "run_state_machine: step_count must be positive, got %d", spec.step_count)
	}
	rule_names := make([]cstring, len(spec.rule_names))
	for name, i in spec.rule_names {
		rule_names[i] = cstr(name)
	}
	rule_groups := make([]i64, len(spec.rule_names))
	invariant_names := make([]cstring, len(spec.invariant_names))
	for name, i in spec.invariant_names {
		invariant_names[i] = cstr(name)
	}

	sm: ^lh.State_Machine
	concurrency: i64
	check(tc, lh.new_state_machine(
		tc._ctx,
		tc._handle,
		raw_data(rule_names),
		raw_data(rule_groups),
		raw_data(spec.rule_weights),
		len(rule_names),
		raw_data(invariant_names),
		raw_data(spec.always_check),
		len(invariant_names),
		1,
		1,
		i64(spec.step_count),
		&sm,
		&concurrency,
	))
	own(tc, sm)
	return sm
}

// Starts the next round of rules, or reports that the machine is done.
@(private)
machine_next_round :: proc(tc: ^Test_Case, sm: ^lh.State_Machine) -> bool {
	group: i64
	check(tc, lh.state_machine_next_group(tc._ctx, tc._handle, sm, &group))
	return group != lh.STATE_MACHINE_DONE
}

// The next rule of the round, as an iterator: `for index in machine_next_rule(tc, sm)`.
@(private)
machine_next_rule :: proc(tc: ^Test_Case, sm: ^lh.State_Machine) -> (index: int, ok: bool) {
	rule: i64
	check(tc, lh.state_machine_next_rule(tc._ctx, tc._handle, sm, 0, &rule))
	if rule == lh.STATE_MACHINE_DONE {
		return 0, false
	}
	return int(rule), true
}

@(private)
machine_rule_rejected :: proc(tc: ^Test_Case, sm: ^lh.State_Machine) {
	check(tc, lh.state_machine_rule_rejected(tc._ctx, tc._handle, sm, 0))
	note(tc, "    (rejected: an assumption failed)")
}

@(private)
machine_should_check_invariant :: proc(tc: ^Test_Case, sm: ^lh.State_Machine, index: int) -> (should_check: bool) {
	check(tc, lh.state_machine_should_check_invariant(tc._ctx, tc._handle, sm, i64(index), &should_check))
	return
}

/*
Runs one rule or invariant behind its own boundary, printing into an indented
block while a failure is replayed. A rejection is returned; anything else that
stops the step propagates.
*/
@(private)
invoke_step :: proc(tc: ^Test_Case, body: proc(tc: ^Test_Case, data: rawptr), data: rawptr) -> (rejected: bool) {
	step := tc^
	step._depth = 0
	if tc._case.capturing {
		check(tc, lh.test_case_block(tc._ctx, tc._handle, 4, &step._handle))
	}
	outcome := invoke(&step, body, data)
	if step._handle != tc._handle {
		lh.test_case_free(tc._ctx, step._handle)
	}
	#partial switch outcome.kind {
	case .Passed:
		return false
	case .Rejected:
		return true
	}
	abort_with(tc, outcome)
}

@(private)
new_engine_pool :: proc(tc: ^Test_Case) -> ^lh.Pool {
	handle: ^lh.Pool
	check(tc, lh.new_pool(tc._ctx, tc._handle, &handle))
	own(tc, handle)
	return handle
}

@(private)
pool_add_variable :: proc(tc: ^Test_Case, pool: ^lh.Pool) -> (id: i64) {
	check(tc, lh.pool_add(tc._ctx, tc._handle, pool, &id))
	return
}

@(private)
pool_draw_variable :: proc(tc: ^Test_Case, pool: ^lh.Pool, consume: bool) -> (id: i64) {
	check(tc, lh.pool_generate(tc._ctx, tc._handle, pool, consume, &id))
	return
}
