module coral::registry {
    use sui::event;
    use sui::table_vec::{Self, TableVec};

    // === Structs ===
    public struct Registry has key {
        id: UID,
        market_ids: TableVec<ID>,
    }

    public struct RegistryCap has key, store {
        id: UID,
    }

    // === Events ===
    public struct MarketRegistered has copy, drop {
        market_id: ID
    }

    public struct MarketRemoved has copy, drop {
        market_id: ID,
    }

    // === Public Functions ===
    fun init(ctx: &mut TxContext) {
        let registry = Registry {
            id: object::new(ctx),
            market_ids: table_vec::empty<ID>(ctx),
        };

        let cap = RegistryCap { id: object::new(ctx) };

        transfer::share_object(registry);
        transfer::transfer(cap, tx_context::sender(ctx));
    }

    public(package) fun register_market(registry: &mut Registry, market_id: ID) {        
        registry.market_ids.push_back(market_id);
        event::emit(MarketRegistered { market_id });
    }

    public fun get_total_markets(registry: &Registry): u64 {
        registry.market_ids.length()
    }

    // === Admin Functions ===

    public(package) fun remove_market(registry: &mut Registry, _cap: &RegistryCap, market_index: u64) {
        let market_id = registry.market_ids.swap_remove(market_index);
        event::emit(MarketRemoved {
            market_id,
        });
    }
}