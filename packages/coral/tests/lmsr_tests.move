#[test_only]
module coral::lmsr_tests {
    use coral::lmsr;
    use interest_math::fixed18::{Self, Fixed18};

    #[test]
    fun test_exp_small_values() {
        // Test exp(0) = 1
        let zero = fixed18::zero();
        let exp_zero = lmsr::exp_fixed18(zero);
        assert!(exp_zero == fixed18::one(), 0);

        // Test exp(1) ≈ 2.718281828
        let one = fixed18::one();
        let exp_one = lmsr::exp_fixed18(one);

        // e ≈ 2.718281828, so we expect around 2.7
        let min_expected = fixed18::from_u64(2).add(fixed18::from_u64(7).div_down(fixed18::from_u64(10)));
        let max_expected = fixed18::from_u64(3);

        assert!(exp_one.gt(min_expected), 1);
        assert!(exp_one.lt(max_expected), 2);
    }

    #[test]
    fun test_exp_fractional_values() {
        // Test exp(0.5) ≈ 1.648721271
        let half = fixed18::one().div_down(fixed18::from_u64(2));
        let exp_half = lmsr::exp_fixed18(half);

        // exp(0.5) ≈ 1.648721271, so we expect between 1.5 and 1.8
        let min_expected = fixed18::from_u64(15).div_down(fixed18::from_u64(10));
        let max_expected = fixed18::from_u64(18).div_down(fixed18::from_u64(10));

        assert!(exp_half.gt(min_expected), 3);
        assert!(exp_half.lt(max_expected), 4);
    }

    #[test]
    fun test_exp_large_values() {
        // Test exp(10) - should handle large values properly
        let ten = fixed18::from_u64(10);
        let exp_ten = lmsr::exp_fixed18(ten);

        // exp(10) ≈ 22026.465794806718
        let min_expected = fixed18::from_u64(22000);
        assert!(exp_ten.gt(min_expected), 3);
    }

    #[test]
    fun test_ln_basic_values() {
        // Test ln(1) = 0
        let one = fixed18::one();
        let ln_one = lmsr::ln_fixed18(one);
        let tolerance = fixed18::from_u64(1000000000000); // 0.000001
        assert!(ln_one.lt(tolerance), 4);

        // Test ln(e) ≈ 1
        let e = fixed18::from_u64(2718281828459045235); // ≈ e
        let ln_e = lmsr::ln_fixed18(e);
        let expected = fixed18::one();
        let diff = if (ln_e.gt(expected)) {
            ln_e.sub(expected)
        } else {
            expected.sub(ln_e)
        };

        assert!(diff.lt(tolerance), 5);
    }

    #[test]
    fun test_ln_values_near_one() {
        // Test ln(1.5) using Taylor series
        let one_point_five = fixed18::from_u64(3).div_down(fixed18::from_u64(2));
        let ln_result = lmsr::ln_fixed18(one_point_five);

        // ln(1.5) ≈ 0.405465108, so we expect between 0.3 and 0.5
        let min_expected = fixed18::from_u64(3).div_down(fixed18::from_u64(10));
        let max_expected = fixed18::from_u64(5).div_down(fixed18::from_u64(10));

        assert!(ln_result.gt(min_expected), 5);
        assert!(ln_result.lt(max_expected), 6);
    }

    #[test]
    fun test_ln_large_values() {
        // Test ln(100) - should handle scaling properly
        let hundred = fixed18::from_u64(100);
        let ln_hundred = lmsr::ln_fixed18(hundred);

        // ln(100) ≈ 4.605170186
        let min_expected = fixed18::from_u64(4);
        let max_expected = fixed18::from_u64(5);

        assert!(ln_hundred.gt(min_expected), 7);
        assert!(ln_hundred.lt(max_expected), 8);
    }

    #[test]
    fun test_cost_function_stability() {
        // Test that the cost function doesn't underflow/overflow with large imbalances
        let mut outcomes = vector::empty<Fixed18>();
        vector::push_back(&mut outcomes, fixed18::from_u64(1000));
        vector::push_back(&mut outcomes, fixed18::from_u64(10));
        
        let b = fixed18::from_u64(100);
        let cost = lmsr::cost(outcomes, b);
        
        // Cost should be reasonable and not overflow
        assert!(cost.gt(fixed18::from_u64(500)), 9);
        assert!(cost.lt(fixed18::from_u64(2000)), 10);
    }
}