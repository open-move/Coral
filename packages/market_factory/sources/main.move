module market_factory::main;

use sui::clock::Clock;

use coral::market::{Self, MarketManagerCap};
use sui::coin::CoinMetadata;

public struct SAFE has drop {}

public struct RISKY has drop {}

#[allow(lint(share_owned))]
public fun initialize<T>(metadata: &CoinMetadata<T>, blob_id: ID, clock: &Clock, ctx: &mut TxContext): MarketManagerCap {
    let (market, manager_cap) = market::create(SAFE {}, RISKY {}, metadata, blob_id, clock, ctx);
    transfer::public_share_object(market);

    manager_cap
}