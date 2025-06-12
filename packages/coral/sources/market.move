module coral::market;

use std::type_name::{Self, TypeName};

use sui::balance::{Self, Supply, Balance};
use sui::coin::{CoinMetadata, Coin};
use sui::dynamic_field;
use sui::clock::Clock;
use sui::event;

use interest_math::fixed18;

use coral::outcome::{Self, Outcome, OutcomeSnapshot};
use coral::registry::Registry;

public struct Market has key, store {
    id: UID,
    blob_id: ID,
    is_paused: bool,
    coin_decimals: u8,
    created_at_ms: u64,
    coin_type: TypeName,
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

// === Events ===

public struct MarketCreated has copy, drop {
    market_id: ID,
    blob_id: ID,
    coin_type: TypeName,
    coin_decimals: u8,
    created_at_ms: u64,
    fee_bps: u64,
    liquidity_param: u64,
    outcomes: vector<Outcome>
}

public struct OutcomePurchased has copy, drop {
    market_id: ID,
    buyer: address,
    outcome: Outcome,
    amount: u64,
    cost: u64,
    fee: u64,
    timestamp_ms: u64
}

public struct OutcomeSold has copy, drop {
    market_id: ID,
    seller: address,
    outcome: Outcome,
    amount: u64,
    revenue: u64,
    timestamp_ms: u64
}

public struct OutcomeRedeemed has copy, drop {
    market_id: ID,
    redeemer: address,
    outcome: Outcome,
    amount: u64,
    payout: u64,
    timestamp_ms: u64
}

public struct MarketResolved has copy, drop {
    market_id: ID,
    winning_outcome: Outcome,
    resolved_at_ms: u64
}

public struct MarketPaused has copy, drop {
    market_id: ID,
    timestamp_ms: u64
}

public struct MarketResumed has copy, drop {
    market_id: ID,
    timestamp_ms: u64
}

public struct MarketClosed has copy, drop {
    market_id: ID,
    timestamp_ms: u64
}

public struct MarketConfigUpdated has copy, drop {
    market_id: ID,
    old_fee_bps: u64,
    new_fee_bps: u64,
    timestamp_ms: u64
}

public struct BlobIdUpdated has copy, drop {
    market_id: ID,
    old_blob_id: ID,
    new_blob_id: ID,
    timestamp_ms: u64
}

public struct FeesWithdrawn has copy, drop {
    market_id: ID,
    amount: u64,
    recipient: address,
    timestamp_ms: u64
}

const EUnAuthorizedMarketAccess: u64 = 1;
const EOutcomeTypeMismatch: u64 = 2;
const EInsufficientPayment: u64 = 3;
const EZeroAmount: u64 = 4;
const EInvalidFeeValue: u64 = 5;
const EDuplicateBlobID: u64 = 6;
const EMarketResolved: u64 = 7;
const EMarketNotResolved: u64 = 8;
const ETooMuchCost: u64 = 9;
const ETooLittleRevenue: u64 = 10;
const EMarketPaused: u64 = 11;

const DEFAULT_FEE_BPS: u64 = 10;
const DEFAULT_LIQUIDITY_PARAM: u64 = 10000000000;

public use fun transfer_cap as MarketManagerCap.transfer;

public fun create<SAFE: drop, RISKY: drop, C>(safe: SAFE, risky: RISKY, registry: &mut Registry, metadata: &CoinMetadata<C>, blob_id: ID, clock: &Clock, ctx: &mut TxContext): (Market, MarketManagerCap) {
    let safe_outcome = outcome::safe(type_name::get<SAFE>());
    let risky_outcome = outcome::risky(type_name::get<RISKY>());

    let mut market = Market {
        blob_id,
        is_paused: false,
        id: object::new(ctx),
        resolved_at_ms: option::none(),
        coin_type: type_name::get<C>(),
        winning_outcome: option::none(),
        created_at_ms: clock.timestamp_ms(),
        coin_decimals: metadata.get_decimals(),
        outcomes: vector[safe_outcome, risky_outcome],
        config: MarketConfig {
            fee_bps: DEFAULT_FEE_BPS,
            liquidity_param: DEFAULT_LIQUIDITY_PARAM,
        },
    };

    let safe_supply = balance::create_supply<SAFE>(safe);
    let risky_supply = balance::create_supply<RISKY>(risky);

    dynamic_field::add(&mut market.id, OutcomeSupplyKey<SAFE>(), OutcomeSupply(safe_supply));
    dynamic_field::add(&mut market.id, OutcomeSupplyKey<RISKY>(), OutcomeSupply(risky_supply));
    dynamic_field::add(&mut market.id, MarketBalancesKey<C>(), MarketBalances {
        balance: balance::zero<C>(),
        fee_balance: balance::zero<C>(),
    });

    let market_id = market.id.to_inner();
    registry.register_market(market_id);
    
    event::emit(MarketCreated {
        blob_id,
        market_id,
        coin_type: type_name::get<C>(),
        coin_decimals: metadata.get_decimals(),
        created_at_ms: clock.timestamp_ms(),
        fee_bps: DEFAULT_FEE_BPS,
        liquidity_param: DEFAULT_LIQUIDITY_PARAM,
        outcomes: vector[safe_outcome, risky_outcome]
    });
    
    (market, MarketManagerCap { id: object::new(ctx), market_id })
}

public fun transfer_cap(cap: MarketManagerCap, recipient: address) {
    transfer::transfer(cap, recipient)
}

public fun update_blob_id(market: &mut Market, cap: &MarketManagerCap, blob_id: ID, clock: &Clock) {
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);
    assert!(market.blob_id != blob_id, EDuplicateBlobID);

    let old_blob_id = market.blob_id;
    market.blob_id = blob_id;
    
    event::emit(BlobIdUpdated {
        market_id: market.id.to_inner(),
        old_blob_id,
        new_blob_id: blob_id,
        timestamp_ms: clock.timestamp_ms()
    });
}

public fun update_market_fee_bps(market: &mut Market, cap: &MarketManagerCap, fee_bps: u64, clock: &Clock) {
    assert!(market.resolved_at_ms.is_none(), EMarketResolved);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    assert!(fee_bps <= 1000, EInvalidFeeValue);
    let old_fee_bps = market.config.fee_bps;
    market.config.fee_bps = fee_bps;
    
    event::emit(MarketConfigUpdated {
        market_id: market.id.to_inner(),
        old_fee_bps,
        new_fee_bps: fee_bps,
        timestamp_ms: clock.timestamp_ms()
    });
}

public fun resolve_market(market: &mut Market, cap: &MarketManagerCap, outcome: Outcome, clock: &Clock) {
    assert!(market.resolved_at_ms.is_none(), EMarketResolved);
    assert!(market.outcomes.contains(&outcome), EOutcomeTypeMismatch);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    let timestamp = clock.timestamp_ms();
    market.winning_outcome = option::some(outcome);
    market.resolved_at_ms = option::some(timestamp);
    
    event::emit(MarketResolved {
        market_id: market.id.to_inner(),
        winning_outcome: outcome,
        resolved_at_ms: timestamp
    });
}

public fun pause_market(market: &mut Market, cap: &MarketManagerCap, clock: &Clock) {
    assert!(market.resolved_at_ms.is_none(), EMarketResolved);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    market.is_paused = true;
    
    event::emit(MarketPaused {
        market_id: market.id.to_inner(),
        timestamp_ms: clock.timestamp_ms()
    });
}

public fun resume_market(market: &mut Market, cap: &MarketManagerCap, clock: &Clock) {
    assert!(market.resolved_at_ms.is_none(), EMarketResolved);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    market.is_paused = false;
    
    event::emit(MarketResumed {
        market_id: market.id.to_inner(),
        timestamp_ms: clock.timestamp_ms()
    });
}

public fun close_market(market: Market, cap: MarketManagerCap, clock: &Clock) {
    assert!(market.resolved_at_ms.is_some(), EMarketNotResolved);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    let market_id = market.id.to_inner();
    
    event::emit(MarketClosed {
        market_id,
        timestamp_ms: clock.timestamp_ms()
    });
    
    let Market { id, .. } = market;
    let MarketManagerCap { id: cap_id, .. } = cap;
    
    id.delete();
    cap_id.delete();
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

public fun buy_outcome<T, C>(market: &mut Market, snapshot: OutcomeSnapshot, payment: Coin<C>, outcome: Outcome, amount: u64, max_cost: u64, clock: &Clock, ctx: &mut TxContext): (Coin<T>, Coin<C>) {
    assert!(amount > 0, EZeroAmount);
    assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);

    let liquidity_param = fixed18::from_u64(market.config.liquidity_param);
    let cost = snapshot.net_cost(outcome, market.id.to_inner(), liquidity_param, fixed18::from_u64(amount));
    assert!(cost.lte(fixed18::from_u64(max_cost)), ETooMuchCost);
    assert!(cost.lte(fixed18::from_u64(payment.value())), EInsufficientPayment);

    let cost_u64 = cost.to_u64(0);
    let fee = market.calculate_fee(cost_u64);
    
    event::emit(OutcomePurchased {
        fee,
        amount,
        outcome,
        cost: cost_u64,
        buyer: ctx.sender(),
        market_id: market.id.to_inner(),
        timestamp_ms: clock.timestamp_ms()
    });

    deposit_internal<T, C>(market, amount, cost_u64, payment, ctx)
}

public fun sell_outcome<T, C>(market: &mut Market, snapshot: OutcomeSnapshot, coin: Coin<T>, outcome: Outcome, min_revenue: u64, clock: &Clock, ctx: &mut TxContext): Coin<C> {
    assert!(coin.value() > 0, EZeroAmount);
    assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);

    let amount = coin.value();
    let liquidity_param = fixed18::from_u64(market.config.liquidity_param);
    let revenue = snapshot.net_revenue(outcome, market.id.to_inner(), liquidity_param, fixed18::from_u64(amount));
  
    assert!(revenue.gte(fixed18::from_u64(min_revenue)), ETooLittleRevenue);
    let revenue_u64 = revenue.to_u64(0);
    
    event::emit(OutcomeSold {
        market_id: market.id.to_inner(),
        seller: ctx.sender(),
        outcome,
        amount,
        revenue: revenue_u64,
        timestamp_ms: clock.timestamp_ms()
    });
    
    withdraw_internal<T, C>(market, revenue_u64, coin, ctx)
}

public fun redeem<T, C>(market: &mut Market, coin: Coin<T>, clock: &Clock, ctx: &mut TxContext): Coin<C> {
    assert!(coin.value() > 0, EZeroAmount);
    assert!(market.is_paused, EMarketPaused);
    assert!(market.resolved_at_ms.is_some(), EMarketNotResolved);
    
    let amount = coin.value();
    let mut winning_outcome = outcome::safe(type_name::get<T>()); // Default, will be overwritten
    
    market.winning_outcome.do!(|outcome| {
        assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);
        winning_outcome = outcome;
    });

    event::emit(OutcomeRedeemed {
        market_id: market.id.to_inner(),
        redeemer: ctx.sender(),
        outcome: winning_outcome,
        amount,
        payout: amount, // 1:1 redemption for winning outcome
        timestamp_ms: clock.timestamp_ms()
    });

    withdraw_internal<T, C>(market, amount, coin, ctx)
}

public fun withdraw_fee<C>(market: &mut Market, cap: &MarketManagerCap, amount: u64, clock: &Clock, ctx: &mut TxContext): Coin<C> {
    assert!(amount > 0, EZeroAmount);
    assert!(market.resolved_at_ms.is_some(), EMarketNotResolved);
    assert!(market.id.to_inner() == cap.market_id, EUnAuthorizedMarketAccess);

    event::emit(FeesWithdrawn {
        market_id: market.id.to_inner(),
        amount,
        recipient: ctx.sender(),
        timestamp_ms: clock.timestamp_ms()
    });

    let market_balances_mut = market_balances_mut<C>(market);
    market_balances_mut.fee_balance.split(amount).into_coin(ctx)
}

fun deposit_internal<T, C>(market: &mut Market, amount: u64, cost: u64, mut coin: Coin<C>, ctx: &mut TxContext): (Coin<T>, Coin<C>) {
    {
        let payment = coin.split(cost, ctx);
        let fee = market.calculate_fee(payment.value());

        let market_balances_mut = market_balances_mut<C>(market);
        market_balances_mut.balance.join(payment.into_balance());
        market_balances_mut.fee_balance.join(coin.split(fee, ctx).into_balance());
    };

    let outcome_supply_mut = outcome_supply_mut<T>(market);
    let outcome_balance = outcome_supply_mut.0.increase_supply(amount);
    (outcome_balance.into_coin(ctx), coin)
}

fun withdraw_internal<T, C>(market: &mut Market, amount: u64, coin: Coin<T>, ctx: &mut TxContext): Coin<C> {
    let outcome_supply_mut = outcome_supply_mut<T>(market);
    outcome_supply_mut.0.decrease_supply(coin.into_balance());

    // let fee = market.calculate_fee(amount);
    let market_balances_mut = market_balances_mut<C>(market);

    let payment = market_balances_mut.balance.split(amount);
    // let fee = payment.split(fee);
    // market_balances_mut.fee_balance.join(fee);
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
    fixed18::from_u64(amount).mul_down(fixed18::from_u64(market.config.fee_bps)).div_down(fixed18::from_u64(10000)).to_u64(0)
}

public fun preview_buy_cost<T>(market: &Market, snapshot: &OutcomeSnapshot, outcome: Outcome, amount: u64): u64 {
    assert!(amount > 0, EZeroAmount);
    assert!(type_name::get<T>() == outcome.get_type(), EOutcomeTypeMismatch);

    let cloned = snapshot.clone_outcome_snapshot();
    let liquidity_param = fixed18::from_u64(market.config.liquidity_param);
    cloned.net_cost(outcome, market.id.to_inner(), liquidity_param, fixed18::from_u64(amount)).to_u64(0)
}


#[test_only]
public fun destroy_market_for_testing(market: Market) {
    let Market { id, .. } = market;
    id.delete();
}

#[test_only]
public fun destroy_cap_for_testing(cap: MarketManagerCap) {
    let MarketManagerCap { id, market_id: _ } = cap;
    id.delete();
}