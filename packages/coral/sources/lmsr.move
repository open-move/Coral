module coral::lmsr;

use interest_math::fixed18::{Self, Fixed18};
use interest_math::i256;
use interest_math::u256;

const ERR_UNDERFLOW: u64 = 1;

// Constants
const ONE: u256 = 1_000_000_000_000_000_000; // 1e18
const I256_SCALE: u256 = 79228162514264337593543950336; // 2^96

public fun net_cost(mut outcomes: vector<Fixed18>, b: Fixed18, amount: Fixed18, outcome_index: u64): Fixed18 {
    let initial_cost = lmsr_cost(outcomes, b);

    let outcome = &mut outcomes[outcome_index];
    *outcome = (*outcome).add(amount);

    let final_cost = lmsr_cost(outcomes, b);
    assert!(final_cost.gte(initial_cost), ERR_UNDERFLOW);
    final_cost.sub(initial_cost)
}

public fun net_revenue(mut outcomes: vector<Fixed18>, b: Fixed18, amount: Fixed18, outcome_index: u64): Fixed18 {
    let initial_cost = lmsr_cost(outcomes, b);

    let outcome = &mut outcomes[outcome_index];
    assert!((*outcome).gte(amount), ERR_UNDERFLOW);

    *outcome = (*outcome).sub(amount);
    initial_cost.sub(lmsr_cost(outcomes, b))
}


// Numerically stable LMSR cost function using log-sum-exp trick
// Cost(q) = m + b × ln(sum of e^((q_i - m) / b))
// where m = max(q_i)
public fun lmsr_cost(quantities: vector<Fixed18>, b: Fixed18): Fixed18 {
    let len = quantities.length();
    assert!(!fixed18::is_zero(b), 2);
    

    let max_q = find_max(&quantities);
    let b_raw = fixed18::raw_value(b);
    let max_q_raw = fixed18::raw_value(max_q);
    
    // Compute sum of e^((q_i - max) / b)
    let  (mut sum_exp, mut i) = (0u256, 0);
    while (i < len) {
        let q_i = quantities[i];
        let q_i_raw = fixed18::raw_value(q_i);
        
        // Compute (q_i - max_q) / b
        // This will be negative or zero, so we need signed arithmetic
        let diff = if (q_i_raw >= max_q_raw) {
            // Should only be equal, not greater
            i256::from_u256(0)
        } else {
            // q_i < max_q, so this is negative
            i256::negative_from_u256(max_q_raw - q_i_raw)
        };
        
        // Scale to i256 format (2^96 scaling)
        let diff_scaled = if (i256::is_negative(diff)) {
            let abs_val = i256::to_u256(i256::abs(diff));
            let scaled = u256::mul_div_down(abs_val, I256_SCALE, ONE);
            i256::negative_from_u256(scaled)
        } else {
            i256::from_u256(0)
        };
        
        // Divide by b (in i256 scale)
        let b_scaled = u256::mul_div_down(b_raw, I256_SCALE, ONE);
        let b_i256 = i256::from_u256(b_scaled);
        let exponent = i256::div(diff_scaled, b_i256);
        
        // Compute e^((q_i - max_q) / b)
        let exp_val = i256::exp(exponent);
        let exp_u256 = i256::to_u256(exp_val);
        
        // Convert back to Fixed18 scale
        let exp_fixed = u256::mul_div_down(exp_u256, ONE, I256_SCALE);
        sum_exp = sum_exp + exp_fixed;
        
        i = i + 1;
    };
    
    // Compute ln(sum_exp)
    // Convert sum_exp to i256 scale for ln calculation
    let sum_scaled = u256::mul_div_down(sum_exp, I256_SCALE, ONE);
    let sum_i256 = i256::from_u256(sum_scaled);
    let ln_sum = i256::ln(sum_i256);
    
    // Convert ln result back to Fixed18
    let ln_sum_u256 = i256::to_u256(ln_sum);
    let ln_sum_fixed = u256::mul_div_down(ln_sum_u256, ONE, I256_SCALE);
    
    // Compute b * ln(sum_exp)
    let b_ln_sum = u256::mul_div_down(b_raw, ln_sum_fixed, ONE);
    
    // Final result: max_q + b * ln(sum_exp)
    let result = max_q_raw + b_ln_sum;
    fixed18::from_raw_u256(result)
}

// Helper function to find maximum value in vector
fun find_max(quantities: &vector<Fixed18>): Fixed18 {
    let len = quantities.length();
    assert!(len > 0, 3);
    
    let mut max = quantities[0];
    let mut i = 1;
    
    while (i < len) {
        let current = quantities[i];
        if (fixed18::gt(current, max)) {
            max = current;
        };
        i = i + 1;
    };
    
    max
}

// Alternative implementation that accepts raw u256 values (already in Fixed18 format)
public fun lmsr_cost_raw(quantities: vector<u256>, b: u256): u256 {
    let mut fixed_quantities = vector::empty<Fixed18>();
    let len = quantities.length();
    let mut i = 0;
    
    while (i < len) {
        fixed_quantities.push_back(fixed18::from_raw_u256(quantities[i]));
        i = i + 1;
    };
    
    let result = lmsr_cost(fixed_quantities, fixed18::from_raw_u256(b));
    fixed18::raw_value(result)
}

// Compute the price of outcome i given current quantities
// Price_i = e^(q_i / b) / sum(e^(q_j / b) for all j)
public fun lmsr_price(quantities: vector<Fixed18>, b: Fixed18, outcome_index: u64): Fixed18 {
    let len = quantities.length();
    assert!(outcome_index < len, 4);
    assert!(!fixed18::is_zero(b), 5);
    
    // Use log-sum-exp trick here too
    let max_q = find_max(&quantities);
    let max_q_raw = fixed18::raw_value(max_q);
    let b_raw = fixed18::raw_value(b);
    
    // Compute sum of e^((q_j - max) / b) and e^((q_i - max) / b)
    let mut sum_exp = 0u256;
    let mut exp_i = 0u256;
    let mut j = 0;
    
    while (j < len) {
        let q_j = quantities[j];
        let q_j_raw = fixed18::raw_value(q_j);
        
        // Compute (q_j - max_q) / b
        let diff = if (q_j_raw >= max_q_raw) {
            i256::from_u256(0)
        } else {
            i256::negative_from_u256(max_q_raw - q_j_raw)
        };
        
        // Scale and divide by b
        let diff_scaled = if (i256::is_negative(diff)) {
            let abs_val = i256::to_u256(i256::abs(diff));
            let scaled = u256::mul_div_down(abs_val, I256_SCALE, ONE);
            i256::negative_from_u256(scaled)
        } else {
            i256::from_u256(0)
        };
        
        let b_scaled = u256::mul_div_down(b_raw, I256_SCALE, ONE);
        let b_i256 = i256::from_u256(b_scaled);
        let exponent = i256::div(diff_scaled, b_i256);
        
        // Compute e^((q_j - max_q) / b)
        let exp_val = i256::exp(exponent);
        let exp_u256 = i256::to_u256(exp_val);
        let exp_fixed = u256::mul_div_down(exp_u256, ONE, I256_SCALE);
        
        sum_exp = sum_exp + exp_fixed;
        
        if (j == outcome_index) {
            exp_i = exp_fixed;
        };
        
        j = j + 1;
    };
    
    // Price = exp_i / sum_exp
    let price = u256::mul_div_down(exp_i, ONE, sum_exp);
    fixed18::from_raw_u256(price)
}