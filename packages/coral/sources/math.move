module coral::math;

use interest_math::fixed18::{Self, Fixed18};
use interest_math::i256;
use interest_math::u256;

// Constants in Fixed18 format (scaled by 1e18)
const LN2: u256 = 693147180559945309; // ln(2) * 1e18
const ONE: u256 = 1_000_000_000_000_000_000; // 1e18

// Exponential function exp(x) for Fixed18
public fun exp(x: Fixed18): Fixed18 {
    let x_val = fixed18::raw_value(x);
    
    // Convert to i256 and scale down by using the i256 exp function
    // The i256 exp function expects input scaled by 2^96, we have 1e18
    // So we need to convert: x * 2^96 / 1e18
    let x_i256_scaled = u256::mul_div_down(x_val, 79228162514264337593543950336, ONE); // 2^96
    let x_i256 = i256::from_u256(x_i256_scaled);
    
    let result_i256 = i256::exp(x_i256);
    let result_u256 = i256::to_u256(result_i256);
    
    // Convert back from 2^96 scaling to 1e18 scaling
    let result_fixed = u256::mul_div_down(result_u256, ONE, 79228162514264337593543950336);
    
    fixed18::from_raw_u256(result_fixed)
}

// Natural logarithm ln(x) for Fixed18
public fun ln(x: Fixed18): Fixed18 {
    let x_val = fixed18::raw_value(x);
    
    assert!(x_val > 0, 1); // ln(0) undefined
    
    // Convert to i256 scaled by 2^96
    let x_i256_scaled = u256::mul_div_down(x_val, 79228162514264337593543950336, ONE);
    let x_i256 = i256::from_u256(x_i256_scaled);
    
    let result_i256 = i256::ln(x_i256);
    
    // The result might be negative if x < 1
    if (i256::is_negative(result_i256)) {
        // For negative ln values, we can't represent them in Fixed18
        // Return a very small positive value instead
        fixed18::from_raw_u256(1)
    } else {
        let result_u256 = i256::to_u256(result_i256);
        // Convert back from 2^96 scaling to 1e18 scaling
        let result_fixed = u256::mul_div_down(result_u256, ONE, 79228162514264337593543950336);
        fixed18::from_raw_u256(result_fixed)
    }
}

// Power of 2 function: 2^x for Fixed18
public fun pow2(x: Fixed18): Fixed18 {
    // 2^x = exp(x * ln(2))
    let x_ln2 = fixed18::mul_down(x, fixed18::from_raw_u256(LN2));
    exp(x_ln2)
}

// Binary logarithm: log2(x) for Fixed18
public fun log2(x: Fixed18): Fixed18 {
    // log2(x) = ln(x) / ln(2)
    let ln_x = ln(x);
    fixed18::div_down(ln_x, fixed18::from_raw_u256(LN2))
}