module coral::market;

use std::type_name::{Self, TypeName};

use sui::balance::{Supply, Balance};
use sui::vec_map::{Self, VecMap};
use sui::clock::Clock;
use sui::dynamic_field;
use sui::coin::Coin;
use sui::sui::SUI;

use interest_math::fixed18;

use coral::lmsr;
use sui::coin::CoinMetadata;
use sui::balance;

public struct Market has key {
    id: UID,
    blob_id: ID,
    created_at_ms: u64,
    config: MarketConfig,
    outcomes: vector<Outcome>,
    resolved_at_ms: Option<u64>,
    winning_outcome: Option<Outcome>
}

public struct MarketConfig has copy, store, drop {
    fee_bps: u64,
    coin_decimals: u64,
    liquidity_param: u64,
}

public struct MarketBalances<phantom T> has store {
    balance: Balance<T>,
    fee_balance: Balance<T>
}

public enum Outcome has copy, store, drop {
    SAFE(TypeName),
    RISKY(TypeName),
}

public struct OutcomeSupply<phantom T>(Supply<T>) has store;

public struct OutcomeSnapshot {
    market_id: ID,
    data: VecMap<Outcome, u64>,
}

public struct OutcomeSupplyKey<phantom T>() has copy, store, drop;
public struct MarketBalancesKey<phantom T>() has copy, store, drop;

const EOutcomeTypeMismatch: u64 = 2;
const EMarketIDSnapshotMismatch: u64 = 3;
const EInvalidOutcomeSnapshot: u64 = 4;
const EInsufficientPayment: u64 = 5;
const EDuplicateOutcome: u64 = 6;
const EInvalidOutcomeAmount: u64 = 7;
const EMarketTypeMismatch: u64 = 8;

const DEFAULT_FEE_BPS: u64 = 100;
const DEFAULT_OUTCOME_DECIMALS: u64 = 9;
const DEFAULT_LIQUIDITY_PARAM: u64 = 1000; 

public fun create<SAFE: drop, RISKY: drop>(safe: SAFE, risky: RISKY, blob_id: ID, clock: &Clock, ctx: &mut TxContext): Market {
    let safe_outcome = Outcome::SAFE(type_name::get<SAFE>());
    let risky_outcome = Outcome::RISKY(type_name::get<RISKY>());

    let mut market = Market {
        blob_id,
        id: object::new(ctx),
        resolved_at_ms: option::none(),
        winning_outcome: option::none(),
        created_at_ms: clock.timestamp_ms(),
        outcomes: vector[safe_outcome, risky_outcome],
        config: MarketConfig {
            fee_bps: DEFAULT_FEE_BPS,
            liquidity_param: DEFAULT_LIQUIDITY_PARAM,
            coin_decimals: DEFAULT_OUTCOME_DECIMALS,
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

    market
}

public fun update_blob_id(market: &mut Market, blob_id: ID) {
    market.blob_id = blob_id;
}

public fun update_market_fee_bps(market: &mut Market, fee_bps: u64) {
    assert!(fee_bps <= 1000, EMarketTypeMismatch);
    market.config.fee_bps = fee_bps;
}

public fun initialize_outcome_snapshot(market: &Market): OutcomeSnapshot {
    OutcomeSnapshot {
        data: vec_map::empty(),
        market_id: market.id.to_inner(),
    }
}

public fun add_outcome_snapshot_data<T>(market: &Market, snapshot: &mut OutcomeSnapshot, outcome: Outcome) {
    assert!(!snapshot.data.contains(&outcome), EDuplicateOutcome);
    assert!(type_name::get<T>() == outcome.outcome_type(), EOutcomeTypeMismatch);
    assert!(market.id.to_inner() == market.id.to_inner(), EMarketIDSnapshotMismatch);

    let supply = market.outcome_supply<T>();
    snapshot.data.insert(outcome, supply.0.supply_value());
}

public fun buy_outcome<T>(market: &mut Market, snapshot: OutcomeSnapshot, outcome: Outcome, amount: u64, metadata: &CoinMetadata<SUI>, payment: Coin<SUI>, ctx: &mut TxContext): (Coin<T>, Coin<SUI>) {
    assert!(amount > 0, EInvalidOutcomeAmount);
    assert!(type_name::get<T>() == outcome.outcome_type(), EOutcomeTypeMismatch);

    let OutcomeSnapshot { data, market_id } = snapshot;
    assert!(market.id.to_inner() == market_id, EMarketIDSnapshotMismatch);
    
    let (outcomes, balances) = data.into_keys_values();
    let (_, outcome_index) = outcomes.index_of(&outcome);
    assert!(outcomes.length() == 2 && balances.length() == 2, EInvalidOutcomeSnapshot);

    let outcome_amounts = balances.map!(|v| { fixed18::from_u64(v) });
    let liquidity_param = fixed18::from_u64(market.config.liquidity_param);
    let cost = lmsr::net_cost(outcome_amounts, liquidity_param, fixed18::from_u64(amount), outcome_index);

    assert!(cost.lte(fixed18::from_u64(payment.value())), EInsufficientPayment);
    deposit_internal<T>(market, amount, cost.to_u64(metadata.get_decimals()), payment, ctx)
}

public fun sell_outcome<T>(market: &mut Market, snapshot: OutcomeSnapshot, outcome: Outcome, coin: Coin<T>, ctx: &mut TxContext): Coin<SUI> {
    assert!(coin.value() > 0, EInvalidOutcomeAmount);
    assert!(type_name::get<T>() == outcome.outcome_type(), EOutcomeTypeMismatch);

    let OutcomeSnapshot { data, market_id } = snapshot;
    assert!(market.id.to_inner() == market_id, EMarketIDSnapshotMismatch);
    
    let (outcomes, balances) = data.into_keys_values();
    let (_, outcome_index) = outcomes.index_of(&outcome);
    assert!(outcomes.length() == 2 && balances.length() == 2, EInvalidOutcomeSnapshot);

    let outcome_amounts = balances.map!(|v| { fixed18::from_u64(v) });
    let liquidity_param = fixed18::from_u64(market.config.liquidity_param);
    let revenue = lmsr::net_revenue(outcome_amounts, liquidity_param, fixed18::from_u64(coin.value()), outcome_index);
    withdraw_internal<T>(market, revenue.to_u64(9), coin, ctx)
}

public fun redeem<T>(market: &mut Market, coin: Coin<T>, ctx: &mut TxContext): Coin<SUI> {
    assert!(market.resolved_at_ms.is_some(), EMarketTypeMismatch);
    market.winning_outcome.do!(|outcome| {
        assert!(type_name::get<T>() == outcome.outcome_type(), EOutcomeTypeMismatch);
    });

    withdraw_internal<T>(market, coin.value(), coin, ctx)
}

public fun resolve_market(market: &mut Market, outcome: Outcome, clock: &Clock) {
    assert!(market.resolved_at_ms.is_none(), EMarketTypeMismatch);
    assert!(market.outcomes.contains(&outcome), EOutcomeTypeMismatch);

    market.winning_outcome = option::some(outcome);
    market.resolved_at_ms = option::some(clock.timestamp_ms());
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

public fun outcome_type(outcome: &Outcome): &TypeName {
    match (outcome) {
        Outcome::SAFE(t) => t,
        Outcome::RISKY(t) => t
    }
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
    (amount * market.config.fee_bps) / 10000
}