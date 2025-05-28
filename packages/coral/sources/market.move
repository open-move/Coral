module coral::market;

use std::type_name;

use sui::balance::{Self, Supply, Balance};
use sui::coin::Coin;
use sui::dynamic_field;
use sui::clock::Clock;
use sui::sui::SUI;

use interest_math::fixed18;

use coral::outcome::{Self, Outcome, OutcomeSnapshot};

public struct Market has key, store {
    id: UID,
    blob_id: ID,
    is_paused: bool,
    created_at_ms: u64,
    config: MarketConfig,
    outcomes: vector<Outcome>,
    resolved_at_ms: Option<u64>,
    winning_outcome: Option<Outcome>
}

public struct MarketManagerCap has key {
    id: UID,
    market_id: ID
}

public struct MarketConfig has copy, store, drop {
    fee_bps: u64,
    liquidity_param: u64,
}

public struct MarketBalances<phantom T> has store {
    balance: Balance<T>,
    fee_balance: Balance<T>
}

public struct OutcomeSupply<phantom T>(Supply<T>) has store;

public struct OutcomeSupplyKey<phantom T>() has copy, store, drop;
public struct MarketBalancesKey<phantom T>() has copy, store, drop;

const EUnAuthorizedMarketAccess: u64 = 1;
const EOutcomeTypeMismatch: u64 = 2;
const EInsufficientPayment: u64 = 3;
const EZeroAmount: u64 = 4;
const EMarketTypeMismatch: u64 = 5;
const EDuplicateBlobID: u64 = 6;
const EMarketResolved: u64 = 7;
const EMarketNotResolved: u64 = 8;
const ETooMuchCost: u64 = 9;
const ETooLittleRevenue: u64 = 10;
const EMarketPaused: u64 = 11;

const DEFAULT_FEE_BPS: u64 = 100;
const DEFAULT_LIQUIDITY_PARAM: u64 = 10000000000; 

public fun create<SAFE: drop, RISKY: drop>(safe: SAFE, risky: RISKY, blob_id: ID, clock: &Clock, ctx: &mut TxContext): (Market, MarketManagerCap) {
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let risky_outcome = outcome::risky(type_name::get<RISKY>());

    let mut market = Market {
        blob_id,
        is_paused: false,
        id: object::new(ctx),
        resolved_at_ms: option::none(),
        winning_outcome: option::none(),
        created_at_ms: clock.timestamp_ms(),
        outcomes: vector[safe_outcome, risky_outcome],
        config: MarketConfig {
            fee_bps: DEFAULT_FEE_BPS,
            liquidity_param: DEFAULT_LIQUIDITY_PARAM,
            // coin_decimals: DEFAULT_OUTCOME_DECIMALS,
        },
    };

    let safe_supply = balance::create_supply<SAFE>(safe);
    let risky_supply = balance::create_supply<RISKY>(risky);

    dynamic_field::add(&mut market.id, OutcomeSupplyKey<SAFE>(), OutcomeSupply(safe_supply));
    dynamic_field::add(&mut market.id, OutcomeSupplyKey<RISKY>(), OutcomeSupply(risky_supply));
    dynamic_field::add(&mut market.id, MarketBalancesKey<SUI>(), MarketBalances {
        balance: balance::zero<SUI>(),
        fee_balance: balance::zero<SUI>(),
    });

    let market_id = market.id.to_inner();
    (market, MarketManagerCap { id: object::new(ctx), market_id })
}

public fun transfer_cap(cap: MarketManagerCap, recipient: address) {
    transfer::transfer(cap, recipient)
}

public fun update_blob_id(market: &mut Market, cap: &MarketManagerCap, blob_id: ID) {
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);
    assert!(market.blob_id != blob_id, EDuplicateBlobID);

    market.blob_id = blob_id;
}

public fun update_market_fee_bps(market: &mut Market, cap: &MarketManagerCap, fee_bps: u64) {
    assert!(market.resolved_at_ms.is_none(), EMarketTypeMismatch);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    assert!(fee_bps <= 1000, EMarketTypeMismatch);
    market.config.fee_bps = fee_bps;
}

public fun resolve_market(market: &mut Market, cap: &MarketManagerCap, outcome: Outcome, clock: &Clock) {
    assert!(market.resolved_at_ms.is_none(), EMarketTypeMismatch);
    assert!(market.outcomes.contains(&outcome), EOutcomeTypeMismatch);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    market.winning_outcome = option::some(outcome);
    market.resolved_at_ms = option::some(clock.timestamp_ms());
}

public fun pause_market(market: &mut Market, cap: &MarketManagerCap) {
    assert!(market.resolved_at_ms.is_none(), EMarketTypeMismatch);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    market.is_paused = true;
}

public fun resume_market(market: &mut Market, cap: &MarketManagerCap) {
    assert!(market.resolved_at_ms.is_none(), EMarketTypeMismatch);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    market.is_paused = false;
}

public fun close_market(market: &mut Market, cap: &MarketManagerCap) {
    assert!(market.resolved_at_ms.is_some(), EMarketTypeMismatch);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    abort 0
}

public fun initialize_outcome_snapshot(market: &Market): OutcomeSnapshot {
    assert!(!market.is_paused, EMarketPaused);
    assert!(market.resolved_at_ms.is_none(), EMarketResolved);
    assert!(market.winning_outcome.is_none(), EMarketResolved);

    outcome::create_outcome_snapshot(market.id.to_inner())
}

public fun add_outcome_snapshot_data<T>(market: &Market, snapshot: &mut OutcomeSnapshot, outcome: Outcome) {
    assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);

    let supply = market.outcome_supply<T>();
    snapshot.add_outcome_snapshot_data(market.id.to_inner(), outcome, supply.0.supply_value());
}

public fun buy_outcome<T>(market: &mut Market, snapshot: OutcomeSnapshot, payment: Coin<SUI>, outcome: Outcome, amount: u64, max_cost: u64, ctx: &mut TxContext): (Coin<T>, Coin<SUI>) {
    assert!(amount > 0, EZeroAmount);
    assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);

    let liquidity_param = fixed18::from_raw_u64(market.config.liquidity_param);
    let cost = snapshot.net_cost(outcome, market.id.to_inner(), liquidity_param, fixed18::from_raw_u64(amount));
    assert!(cost.lte(fixed18::from_raw_u64(max_cost)), ETooMuchCost);
    assert!(cost.lte(fixed18::from_raw_u64(payment.value())), EInsufficientPayment);
    deposit_internal<T>(market, amount, cost.to_u64(9), payment, ctx)
}

public fun sell_outcome<T>(market: &mut Market, snapshot: OutcomeSnapshot, coin: Coin<T>, outcome: Outcome, min_revenue: u64, ctx: &mut TxContext): Coin<SUI> {
    assert!(coin.value() > 0, EZeroAmount);
    assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);

    let liquidity_param = fixed18::from_raw_u64(market.config.liquidity_param);
    let revenue = snapshot.net_revenue(outcome, market.id.to_inner(), liquidity_param, fixed18::from_raw_u64(coin.value()));
    assert!(revenue.gte(fixed18::from_raw_u64(min_revenue)), ETooLittleRevenue);
    withdraw_internal<T>(market, revenue.to_u64(9), coin, ctx)
}

public fun redeem<T>(market: &mut Market, coin: Coin<T>, ctx: &mut TxContext): Coin<SUI> {
    assert!(coin.value() > 0, EZeroAmount);
    assert!(market.is_paused, EMarketPaused);
    assert!(market.resolved_at_ms.is_some(), EMarketNotResolved);
    market.winning_outcome.do!(|outcome| {
        assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);
    });

    withdraw_internal<T>(market, coin.value(), coin, ctx)
}

public fun withdraw_fee(market: &mut Market, cap: &MarketManagerCap, amount: u64, ctx: &mut TxContext): Coin<SUI> {
    assert!(amount > 0, EZeroAmount);
    assert!(market.resolved_at_ms.is_some(), EMarketNotResolved);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    let market_balances_mut = market_balances_mut<SUI>(market);
    market_balances_mut.fee_balance.split(amount).into_coin(ctx)
}

fun deposit_internal<T>(market: &mut Market, amount: u64, cost: u64, mut coin: Coin<SUI>, ctx: &mut TxContext): (Coin<T>, Coin<SUI>) {
    {
        let payment = coin.split(cost, ctx);
        let fee = market.calculate_fee(payment.value());

        let market_balances_mut = market_balances_mut<SUI>(market);
        market_balances_mut.balance.join(payment.into_balance());
        market_balances_mut.fee_balance.join(coin.split(fee, ctx).into_balance());
    };

    let outcome_supply_mut = outcome_supply_mut<T>(market);
    let outcome_balance = outcome_supply_mut.0.increase_supply(amount);
    (outcome_balance.into_coin(ctx), coin)
}

fun withdraw_internal<T>(market: &mut Market, amount: u64, coin: Coin<T>, ctx: &mut TxContext): Coin<SUI> {
    let outcome_supply_mut = outcome_supply_mut<T>(market);
    outcome_supply_mut.0.decrease_supply(coin.into_balance());

    let fee = market.calculate_fee(amount);
    let market_balances_mut = market_balances_mut<SUI>(market);

    let mut payment = market_balances_mut.balance.split(amount);
    let fee = payment.split(fee);

    market_balances_mut.fee_balance.join(fee);
    payment.into_coin(ctx)
}

public fun outcome_supply<T>(market: &Market): &OutcomeSupply<T> {
    dynamic_field::borrow(&market.id, OutcomeSupplyKey<T>())
}

public fun outcome_supply_mut<T>(market: &mut Market): &mut OutcomeSupply<T> {
    dynamic_field::borrow_mut(&mut market.id, OutcomeSupplyKey<T>())
}

public fun market_balances<T>(market: &Market): &MarketBalances<T> {
    dynamic_field::borrow(&market.id, MarketBalancesKey<T>())
}

public fun market_balances_mut<T>(market: &mut Market): &mut MarketBalances<T> {
    dynamic_field::borrow_mut(&mut market.id, MarketBalancesKey<T>())
}

public fun calculate_fee(market: &Market, amount: u64): u64 {
    fixed18::from_raw_u64(amount).mul_down(fixed18::from_raw_u64(market.config.fee_bps)).to_u64(1)
}

public fun preview_buy_cost<T>(market: &Market, snapshot: &OutcomeSnapshot, outcome: Outcome, amount: u64): u64 {
    assert!(amount > 0, EZeroAmount);
    assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);

    let cloned = snapshot.clone_outcome_snapshot();
    let liquidity_param = fixed18::from_raw_u64(market.config.liquidity_param);
    cloned.net_cost(outcome, market.id.to_inner(), liquidity_param, fixed18::from_raw_u64(amount)).to_u64(9)
}


#[test_only]
public fun destroy_market_for_testing(market: Market) {
    let Market { id, blob_id: _, is_paused: _, created_at_ms: _, config: _, outcomes: _, resolved_at_ms: _, winning_outcome: _ } = market;
    id.delete();
}

#[test_only]
public fun destroy_cap_for_testing(cap: MarketManagerCap) {
    let MarketManagerCap { id, market_id: _ } = cap;
    id.delete();
}