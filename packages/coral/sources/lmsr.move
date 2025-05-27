module coral::lmsr;

use interest_math::fixed18::{Self, Fixed18};

const ERR_EMPTY:      u64 = 1;
const ERR_ZERO_LIQ:   u64 = 2;
const ERR_UNDERFLOW:  u64 = 3;

const MAX_ITER:       u64 = 5;  // enough for ln on [1,2]

public fun exp_fixed18(x: Fixed18): Fixed18 {
    let mut sum  = fixed18::one();
    let mut term = fixed18::one();

    let mut i = 1;
    while (i <= MAX_ITER) {
        term = term.mul_down(x).div_down(fixed18::from_u64(i));
        sum = sum.add(term);
        i = i + 1;
    };

    sum
}

public fun ln_fixed18(x: Fixed18): Fixed18 {
    assert!(x.gte(fixed18::one()), ERR_UNDERFLOW);

    let mut y = x.sub(fixed18::one());
    let mut i = 0;

    while (i < MAX_ITER) {
        let e_y = exp_fixed18(y);
        let delta = e_y.sub(x).div_down(e_y);
        y = y.sub(delta);
        i = i + 1;
    };

    y
}

public fun cost(outcomes: vector<Fixed18>, b: Fixed18): Fixed18 {
    let len = vector::length(&outcomes);
    assert!(outcomes.length() > 0, ERR_EMPTY);
    assert!(!b.is_zero(), ERR_ZERO_LIQ);

    if (len == 1) return outcomes[0];

    // 1) find max(q)
    let mut max_q = outcomes[0];
    let mut j = 1;
    while (j < len) {
        let cur = *vector::borrow(&outcomes, j);
        if (cur.gt(max_q)) {
            max_q = cur;
        };

        j = j + 1;
    };

    // 2) compute exp_max = exp(max_q/b)
    let exp_max = exp_fixed18(max_q.div_down(b));

    // 3) sum_scaled = Σ exp(qᵢ/b) / exp_max
    let mut sum_scaled = fixed18::zero();
    len.do!(|i| {
        let q_i = outcomes[i];
        let divi = q_i.div_down(b);
        let scaled = exp_fixed18(divi).div_down(exp_max);
        sum_scaled = sum_scaled.add(scaled);
    });

    // 4) ln_sum and assemble
    let ln_sum = ln_fixed18(sum_scaled);
    max_q.add(b.mul_down(ln_sum))
}

public fun net_cost(mut outcomes: vector<Fixed18>, b: Fixed18, amount: Fixed18, outcome_index: u64): Fixed18 {
    let initial_cost = cost(outcomes, b);

    let outcome = &mut outcomes[outcome_index];
    *outcome = (*outcome).add(amount);

    let final_cost = cost(outcomes, b);
    return final_cost.sub(initial_cost)
}

public fun net_revenue(mut outcomes: vector<Fixed18>, b: Fixed18, amount: Fixed18, outcome_index: u64): Fixed18 {
    let initial_cost = cost(outcomes, b);

    let outcome = &mut outcomes[outcome_index];
    *outcome = (*outcome).sub(amount);

    let final_cost = cost(outcomes, b);
    return initial_cost.sub(final_cost)
}

