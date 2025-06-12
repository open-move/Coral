#[test_only]
module coral::market_tests;

use std::type_name;
use std::unit_test::assert_eq;

use sui::test_scenario::{Self, Scenario};
use sui::test_scenario::TransactionEffects;
use sui::clock::{Self, Clock};
use sui::coin::{Self, Coin};

use coral::market::{Self, Market, MarketManagerCap};
use coral::registry::{Self, Registry};
use coral::tusd::{Self, TUSD};
use coral::outcome;

public struct Test {
    clock: Clock,
    scenario: Scenario,
}

const BLOB_ID: address = @0xB10B1D;
const MANAGER: address = @0xFaDeee;

const DEPOSIT_AMOUNT: u64 = 100;

const TUSD_DECIMALS: u8 = 9;


public struct SAFE has drop {}

public struct RISKY has drop {}

public fun start_test(sender: address): Test {
    let mut scenario = test_scenario::begin(sender);
    let clock = clock::create_for_testing(scenario.ctx());

    Test {
        clock,
        scenario,
    }
}

public fun end(test: Test): TransactionEffects {
   let Test { clock, scenario } = test;

    clock.destroy_for_testing();
    test_scenario::end(scenario)
}

fun create_market(test: &mut Test): (Market, MarketManagerCap) {
    let blob_id = object::id_from_address(BLOB_ID);
    let (treasury_cap, metadata) = tusd::create_tusd(test.scenario.ctx());

    registry::init_for_testing(test.scenario.ctx());
    test.scenario.next_tx(MANAGER);

    let mut registry = test.scenario.take_shared<Registry>();
    let (market, mgmt_cap) = market::create<SAFE, RISKY, TUSD>(SAFE {}, RISKY {}, &mut registry, &metadata, blob_id, &test.clock, test.scenario.ctx());

    transfer::public_share_object(registry);
    // transfer::public_share_object(metadata);
    transfer::public_transfer(metadata, test.scenario.sender());
    transfer::public_transfer(treasury_cap, test.scenario.sender());

    (market, mgmt_cap)
}

fun mint_tusd(amount: u64, test: &mut Test): Coin<TUSD> {
    coin::mint_for_testing<TUSD>(amount, test.scenario.ctx())
}

#[test]
fun test_create_market() {
    let mut test = start_test(MANAGER);
    let (market, cap) = create_market(&mut test);
    
    market.destroy_market_for_testing();
    cap.destroy_cap_for_testing();
    test.end();
}

#[test]
fun test_update_blob_id() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    let new_blob_id = object::id_from_address(@0xDEADBEEF);
    market.update_blob_id(&cap, new_blob_id, &test.clock);
    
    market.destroy_market_for_testing();
    cap.destroy_cap_for_testing();
    test.end();
}

#[test, expected_failure(abort_code = market::EDuplicateBlobID)]
fun test_update_blob_id_duplicate_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    let blob_id = object::id_from_address(BLOB_ID);
    market.update_blob_id(&cap, blob_id, &test.clock);

    market.destroy_market_for_testing();
    cap.destroy_cap_for_testing();
    test.end();
}

#[test]
fun test_update_market_fee_bps() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    market.update_market_fee_bps(&cap, 500, &test.clock);
    
    market.destroy_market_for_testing();
    cap.destroy_cap_for_testing();
    test.end();
}

#[test, expected_failure(abort_code = market::EInvalidFeeValue)]
fun test_update_fee_too_high_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    market.update_market_fee_bps(&cap, 1001, &test.clock);

    market.destroy_market_for_testing();
    cap.destroy_cap_for_testing();
    test.end();
}

#[test]
fun test_buy_safe_outcome() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let risky_outcome = outcome::risky(type_name::get<RISKY>());

    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, safe_outcome);
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, risky_outcome);

    let safe_amount = DEPOSIT_AMOUNT * 10u64.pow(TUSD_DECIMALS);
    let previewed_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, safe_amount);
    let fee_amount = market.calculate_fee(previewed_cost);

    let payment_coin = mint_tusd(previewed_cost + fee_amount, &mut test);
    let (safe_coin, change) = market.buy_outcome<SAFE, TUSD>(
        snapshot,
        payment_coin,
        safe_outcome,
        safe_amount,
        previewed_cost,
        &test.clock,
        test.scenario.ctx()
    );

    assert_eq!(safe_coin.value(), safe_amount);
    assert_eq!(change.value(), 0);
    
    safe_coin.burn_for_testing();
    change.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test]
fun test_buy_risky_outcome() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let risky_outcome = outcome::risky(type_name::get<RISKY>());

    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, safe_outcome);
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, risky_outcome);

    let risky_amount = DEPOSIT_AMOUNT * 10u64.pow(TUSD_DECIMALS);
    let previewed_cost = market.preview_buy_cost<RISKY>(&snapshot, risky_outcome, risky_amount);
    let fee_amount = market.calculate_fee(previewed_cost);

    let payment_coin = mint_tusd(previewed_cost + fee_amount, &mut test);
    let (risky_coin, change) = market.buy_outcome<RISKY, TUSD>(
        snapshot,
        payment_coin,
        risky_outcome,
        risky_amount,
        previewed_cost,
        &test.clock,
        test.scenario.ctx()
    );

    assert_eq!(risky_coin.value(), risky_amount);
    assert_eq!(change.value(), 0);
    
    risky_coin.burn_for_testing();
    change.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test]
fun test_sell_outcome() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let risky_outcome = outcome::risky(type_name::get<RISKY>());

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, safe_outcome);
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, risky_outcome);

    let safe_amount = DEPOSIT_AMOUNT * 10u64.pow(TUSD_DECIMALS);
    let previewed_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, safe_amount);
    let fee_amount = market.calculate_fee(previewed_cost);

    let payment_coin = mint_tusd(previewed_cost + fee_amount, &mut test);
    let (safe_coin, change) = market.buy_outcome<SAFE, TUSD>(
        snapshot,
        payment_coin,
        safe_outcome,
        safe_amount,
        previewed_cost,
        &test.clock,
        test.scenario.ctx()
    );

    let min_revenue = previewed_cost; // original amount deposit
    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, safe_outcome);
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, risky_outcome);

    let tusd_coin = market.sell_outcome<SAFE, TUSD>(snapshot, safe_coin, safe_outcome, min_revenue, &test.clock, test.scenario.ctx());

    tusd_coin.burn_for_testing();
    change.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test]
fun test_resolve_market() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    market.resolve_market(&cap, safe_outcome, &test.clock);
    
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test]
fun test_pause_and_resume_market() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    market.pause_market(&cap, &test.clock);
    market.resume_market(&cap, &test.clock);
    
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test, expected_failure(abort_code = market::EMarketPaused)]
fun test_buy_when_paused_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    market.pause_market(&cap, &test.clock);
    let _snapshot = market.initialize_outcome_snapshot();
    abort
}

#[test, expected_failure(abort_code = market::EZeroAmount)]
fun test_buy_zero_amount_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, _cap) = create_market(&mut test);

    let coin = mint_tusd(DEPOSIT_AMOUNT, &mut test);
    
    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let (_safe_coin, _change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, 0, 100, &test.clock, test.scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = market::EZeroAmount)]
fun test_sell_zero_amount_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, _cap) = create_market(&mut test);

    let coin = coin::zero<SAFE>(test.scenario.ctx());
    
    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let _sui_coin = market.sell_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, 0, &test.clock, test.scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = market::EOutcomeTypeMismatch)]
fun test_buy_wrong_outcome_type_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, _cap) = create_market(&mut test);

    let coin = mint_tusd(DEPOSIT_AMOUNT, &mut test);
    
    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let risky_outcome = outcome::risky(type_name::get<RISKY>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let (_safe_coin, _change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, risky_outcome, amount, 100, &test.clock, test.scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = market::ETooMuchCost)]
fun test_buy_exceeds_max_cost_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, _cap) = create_market(&mut test);

    
    let mut snapshot = market.initialize_outcome_snapshot();
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let risky_outcome = outcome::risky(type_name::get<RISKY>());

    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, safe_outcome);
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, risky_outcome);

    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let previewed_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee = market.calculate_fee(previewed_cost);
    let coin = mint_tusd(previewed_cost + fee, &mut test);
    let (_safe_coin, _change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, previewed_cost - 1, &test.clock, test.scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = market::EInsufficientPayment)]
fun test_buy_insufficient_payment_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, _cap) = create_market(&mut test);

    
    let mut snapshot = market.initialize_outcome_snapshot();
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let risky_outcome = outcome::risky(type_name::get<RISKY>());

    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, safe_outcome);
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, risky_outcome);

    let amount = DEPOSIT_AMOUNT * 10u64.pow(TUSD_DECIMALS);
    let previewed_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    // Provide less than the cost
    let coin = mint_tusd(previewed_cost - 1, &mut test);
    let (_safe_coin, _change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, previewed_cost, &test.clock, test.scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = market::ETooLittleRevenue)]
fun test_sell_below_min_revenue_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, _cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    let (safe_coin, _change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());

    let mut sell_snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut sell_snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut sell_snapshot, outcome::risky(type_name::get<RISKY>()));
    
    let _sui_coin = market.sell_outcome<SAFE, TUSD>(sell_snapshot, safe_coin, safe_outcome, 1000 * 10u64.pow(TUSD_DECIMALS), &test.clock, test.scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = market::EMarketResolved)]
fun test_buy_after_resolve_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    market.resolve_market(&cap, safe_outcome, &test.clock);
    
    let _coin = mint_tusd(DEPOSIT_AMOUNT, &mut test);
    let mut _snapshot = market.initialize_outcome_snapshot();
    abort
}

#[test, expected_failure(abort_code = market::EMarketResolved)]
fun test_update_fee_after_resolve_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    market.resolve_market(&cap, safe_outcome, &test.clock);
    
    market.update_market_fee_bps(&cap, 200, &test.clock);
    abort
}

#[test, expected_failure(abort_code = market::EMarketResolved)]
fun test_pause_after_resolve_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    market.resolve_market(&cap, safe_outcome, &test.clock);
    
    market.pause_market(&cap, &test.clock);
    abort
}

#[test, expected_failure(abort_code = market::EUnAuthorizedMarketAccess)]
fun test_unauthorized_cap_access_fails() {
    let mut test = start_test(MANAGER);
    let (mut market1, _cap1) = create_market(&mut test);
    let (mut _market2, cap2) = create_market(&mut test);
    
    market1.update_market_fee_bps(&cap2, 200, &test.clock);
    abort
}

#[test]
fun test_withdraw_fee() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    
    // Mint enough for cost + fee
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    let (safe_coin, change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());

    let risky_outcome = outcome::risky(type_name::get<RISKY>());
    market.resolve_market(&cap, risky_outcome, &test.clock);
    
    // Withdraw the fee that was collected
    let fee_coin = market.withdraw_fee<TUSD>(&cap, fee_amount, &test.clock, test.scenario.ctx());
    
    assert!(fee_coin.value() == fee_amount);
    
    fee_coin.burn_for_testing();
    safe_coin.burn_for_testing();
    change.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test, expected_failure(abort_code = market::EMarketNotResolved)]
fun test_withdraw_fee_before_resolve_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);
    
    let _fee_coin = market.withdraw_fee<TUSD>(&cap, 100, &test.clock, test.scenario.ctx());
    abort
}

#[test]
fun test_large_buy_sell_cycle() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount = 1000 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    let (safe_coin, change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());

    let mut sell_snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut sell_snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut sell_snapshot, outcome::risky(type_name::get<RISKY>()));
    
    let sui_coin = market.sell_outcome<SAFE, TUSD>(sell_snapshot, safe_coin, safe_outcome, 0, &test.clock, test.scenario.ctx());
    
    assert!(sui_coin.value() <= preview_cost);
    
    sui_coin.burn_for_testing();
    change.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test]
fun test_multiple_buys_different_outcomes() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot1 = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot1, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot1, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount1 = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost1 = market.preview_buy_cost<SAFE>(&snapshot1, safe_outcome, amount1);
    let fee_amount1 = market.calculate_fee(preview_cost1);
    let coin1 = mint_tusd(preview_cost1 + fee_amount1, &mut test);
    let (safe_coin, change1) = market.buy_outcome<SAFE, TUSD>(snapshot1, coin1, safe_outcome, amount1, preview_cost1, &test.clock, test.scenario.ctx());

    let mut snapshot2 = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot2, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot2, outcome::risky(type_name::get<RISKY>()));

    let risky_outcome = outcome::risky(type_name::get<RISKY>());
    let amount2 = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost2 = market.preview_buy_cost<RISKY>(&snapshot2, risky_outcome, amount2);
    let fee_amount2 = market.calculate_fee(preview_cost2);
    let coin2 = mint_tusd(preview_cost2 + fee_amount2, &mut test);
    let (risky_coin, change2) = market.buy_outcome<RISKY, TUSD>(snapshot2, coin2, risky_outcome, amount2, preview_cost2, &test.clock, test.scenario.ctx());

    assert!(safe_coin.value() == amount1);
    assert!(risky_coin.value() == amount2);
    
    safe_coin.burn_for_testing();
    risky_coin.burn_for_testing();
    change1.burn_for_testing();
    change2.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test]
fun test_redeem_winning_outcome() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    let (safe_coin, change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());

    market.pause_market(&cap, &test.clock);
    market.resolve_market(&cap, safe_outcome, &test.clock);
    
    let redeemed = market.redeem<SAFE, TUSD>(safe_coin, &test.clock, test.scenario.ctx());
    
    assert!(redeemed.value() == amount);
    
    redeemed.burn_for_testing();
    change.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test, expected_failure(abort_code = market::EOutcomeTypeMismatch)]
fun test_redeem_losing_outcome_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let risky_outcome = outcome::risky(type_name::get<RISKY>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<RISKY>(&snapshot, risky_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    let (risky_coin, _change) = market.buy_outcome<RISKY, TUSD>(snapshot, coin, risky_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    market.pause_market(&cap, &test.clock);
    market.resolve_market(&cap, safe_outcome, &test.clock);
    
    let _redeemed = market.redeem<RISKY, TUSD>(risky_coin, &test.clock, test.scenario.ctx());
    abort

}

#[test, expected_failure(abort_code = market::EMarketNotResolved)]
fun test_redeem_before_resolve_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    let (safe_coin, _change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());

    market.pause_market(&cap, &test.clock);
    
    let _redeemed = market.redeem<SAFE, TUSD>(safe_coin, &test.clock, test.scenario.ctx());
    abort
}

#[test, expected_failure(abort_code = market::EMarketPaused)]
fun test_redeem_not_paused_fails() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    let (safe_coin, _change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());

    market.resolve_market(&cap, safe_outcome, &test.clock);
    
    let _redeemed = market.redeem<SAFE, TUSD>(safe_coin, &test.clock, test.scenario.ctx());
    abort
}

#[test]
fun test_calculate_fee() {
    let mut test = start_test(MANAGER);
    let (market, cap) = create_market(&mut test);
    
    let fee = market.calculate_fee(10000);
    assert!(fee == 10);
    
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}

#[test]
fun test_preview_buy_cost_matches_actual() {
    let mut test = start_test(MANAGER);
    let (mut market, cap) = create_market(&mut test);

    let mut snapshot = market.initialize_outcome_snapshot();
    market.add_outcome_snapshot_data<SAFE>(&mut snapshot, outcome::safe(type_name::get<SAFE>()));
    market.add_outcome_snapshot_data<RISKY>(&mut snapshot, outcome::risky(type_name::get<RISKY>()));

    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let amount = 10 * 10u64.pow(TUSD_DECIMALS);
    let preview_cost = market.preview_buy_cost<SAFE>(&snapshot, safe_outcome, amount);
    let fee_amount = market.calculate_fee(preview_cost);
    let coin = mint_tusd(preview_cost + fee_amount, &mut test);
    
    let initial_balance = coin.value();
    let (safe_coin, change) = market.buy_outcome<SAFE, TUSD>(snapshot, coin, safe_outcome, amount, preview_cost, &test.clock, test.scenario.ctx());
    let actual_cost = initial_balance - change.value();
    
    assert!(actual_cost <= preview_cost + market.calculate_fee(preview_cost));
    
    safe_coin.burn_for_testing();
    change.burn_for_testing();
    cap.destroy_cap_for_testing();
    market.destroy_market_for_testing();
    test.end();
}