module market_factory::main;

use sui::clock::Clock;

use coral::market::{Self, MarketManagerCap};

public struct SAFE has drop {}

public struct RISKY has drop {}

#[allow(lint(share_owned))]
public fun initialize(blob_id: ID, clock: &Clock, ctx: &mut TxContext): MarketManagerCap {
    let (market, manager_cap) = market::create(SAFE {}, RISKY {}, blob_id, clock, ctx);
    transfer::public_share_object(market);

    manager_cap
}