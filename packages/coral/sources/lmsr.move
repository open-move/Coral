module coral::lmsr;

use interest_math::fixed18::{Self, Fixed18};

const ERR_EMPTY: u64 = 1;
const ERR_ZERO_LIQ: u64 = 2;
const ERR_UNDERFLOW: u64 = 3;

const MAX_ITER: u64 = 30; 
const LN_ITER: u64 = 20;  

public fun exp_fixed18(x: Fixed18): Fixed18 {
    let threshold = fixed18::from_u64(10);
    if (x.gt(threshold)) {
        let half = x.div_down(fixed18::from_u64(2));
        let exp_half = exp_fixed18(half);
        return exp_half.mul_down(exp_half)
    };
    
    let mut sum  = fixed18::one();
    let mut term = fixed18::one();
    let mut i = 1;

    while (i <= MAX_ITER) {
        term = term.mul_down(x).div_down(fixed18::from_u64(i));
        
        // Early termination if term becomes negligible (less than 0.000001)
        // Using division to create small value since from_raw not available
        let epsilon = fixed18::one().div_down(fixed18::from_u64(1000000));
        if (term.lt(epsilon)) break;

        sum = sum.add(term);
        i = i + 1;
    };

    sum
}

public fun ln_fixed18(x: Fixed18): Fixed18 {
    assert!(x.gt(fixed18::zero()), ERR_UNDERFLOW);

    let one = fixed18::one();
    let two = fixed18::from_u64(2);
    
    let lower_bound = one.div_down(two);
    let upper_bound = two;
    
    if (x.gte(lower_bound) && x.lte(upper_bound)) {
        let z = x.sub(one);
        let mut sum = fixed18::zero();
        let mut term = z;
        let mut sign = true; // positive
        
        let mut i = 1;
        while (i <= MAX_ITER) {
            let divisor = fixed18::from_u64(i);
            let contribution = term.div_down(divisor);
            
            if (sign) {
                sum = sum.add(contribution);
            } else {
                sum = sum.sub(contribution);
            };
            
            term = term.mul_down(z);
            sign = !sign;
            
            // Early termination if term becomes negligible
            let epsilon = one.div_down(fixed18::from_u64(1000000));
            if (contribution.lt(epsilon)) {
                break
            };
            
            i = i + 1;
        };
        
        return sum
    };

    let mut scaled_x = x;
    let mut scale_up = 0u64;
    let mut scale_down = 0u64;
    
    while (scaled_x.gt(two)) {
        scaled_x = scaled_x.div_down(two);
        scale_down = scale_down + 1;
    };
    
    while (scaled_x.lt(lower_bound)) {
        scaled_x = scaled_x.mul_down(two);
        scale_up = scale_up + 1;
    };
    
    let mut y = scaled_x.sub(one); // Initial guess
    let mut i = 0;
    
    while (i < LN_ITER) {
        let e_y = exp_fixed18(y);
        let delta = e_y.sub(scaled_x).div_down(e_y);
        
        // Check for convergence
        let epsilon = one.div_down(fixed18::from_u64(10000000));
        let abs_delta = if (delta.gt(fixed18::zero())) { delta } else { fixed18::zero().sub(delta) };
        if (abs_delta.lt(epsilon)) {
            break
        };
        
        y = y.sub(delta);
        i = i + 1;
    };
    
    let ln2_numerator = fixed18::from_u64(693147180559945309);
    let ln2_denominator = fixed18::from_u64(1000000000000000000);
    let ln2 = ln2_numerator.div_down(ln2_denominator);
    
    let mut result = y;
    if (scale_down > 0) {
        let k_fixed = fixed18::from_u64(scale_down);
        result = result.add(k_fixed.mul_down(ln2));
    };
    if (scale_up > 0) {
        let k_fixed = fixed18::from_u64(scale_up);
        result = result.sub(k_fixed.mul_down(ln2));
    };
    
    result
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
    assert!(final_cost.gte(initial_cost), ERR_UNDERFLOW);
    final_cost.sub(initial_cost)
}

public fun net_revenue(mut outcomes: vector<Fixed18>, b: Fixed18, amount: Fixed18, outcome_index: u64): Fixed18 {
    let initial_cost = cost(outcomes, b);

    let outcome = &mut outcomes[outcome_index];
    assert!((*outcome).gte(amount), ERR_UNDERFLOW);

    *outcome = (*outcome).sub(amount);
    initial_cost.sub(cost(outcomes, b))
}

