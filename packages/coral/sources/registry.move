module coral::registry;

use sui::event;
use sui::table_vec::{Self, TableVec};

public struct Registry has key, store {
    id: UID,
    market_ids: TableVec<ID>,
}

public struct MarketRegistered has copy, drop {
    market_id: ID
}

fun init(ctx: &mut TxContext) {
    let registry = Registry {
        id: object::new(ctx),
        market_ids: table_vec::empty<ID>(ctx),
    };

    transfer::share_object(registry);
}

public(package) fun register_market(registry: &mut Registry, market_id: ID) {        
    registry.market_ids.push_back(market_id);
    event::emit(MarketRegistered { market_id });
}

public fun get_total_markets(registry: &Registry): u64 {
    registry.market_ids.length()
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
   init(ctx)
}