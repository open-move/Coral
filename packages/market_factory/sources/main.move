module market_factory::main;

use sui::clock::Clock;
use sui::coin::CoinMetadata;

use coral::market::{Self, MarketManagerCap};
use coral::registry::Registry;
use sui::package;
use sui::package::Publisher;

public struct SAFE() has drop;

public struct RISKY() has drop;

public struct MAIN() has drop;

const EInvalidPackagePublisher: u64 = 0;

fun init(otw: MAIN, ctx: &mut TxContext) {
    package::claim_and_keep(otw, ctx)
}

#[allow(lint(share_owned))]
public fun initialize<T>(publisher: Publisher, registry: &mut Registry, metadata: &CoinMetadata<T>, blob_id: ID, clock: &Clock, ctx: &mut TxContext): MarketManagerCap {
    assert!(publisher.from_package<MAIN>(), EInvalidPackagePublisher);

    let (market, manager_cap) = market::create(SAFE(), RISKY(), registry, metadata, blob_id, clock, ctx);
    transfer::public_share_object(market);
    publisher.burn();

    manager_cap
}

entry fun initialize_entry<T>(publisher: Publisher, registry: &mut Registry, metadata: &CoinMetadata<T>, blob_id: ID, clock: &Clock, ctx: &mut TxContext) {
    initialize(publisher, registry, metadata, blob_id, clock, ctx).transfer_cap(ctx.sender())
}