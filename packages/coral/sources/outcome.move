module coral::outcome;

use std::type_name::TypeName;
use sui::vec_map::{Self, VecMap};

public enum Outcome has copy, store, drop {
    SAFE(TypeName),
    RISKY(TypeName),
}

public struct OutcomeSnapshot {
    market_id: ID,
    data: VecMap<Outcome, u64>,
}

const EDuplicateOutcome: u64 = 1;

public fun safe(outcome_type: TypeName): Outcome {
    Outcome::SAFE(outcome_type)
}

public fun risky(outcome_type: TypeName): Outcome {
    Outcome::RISKY(outcome_type)
}

public fun get_type(outcome: &Outcome): &TypeName {
    match (outcome) {
        Outcome::SAFE(t) => t,
        Outcome::RISKY(t) => t
    }
}

public(package) fun create_outcome_snapshot(market_id: ID): OutcomeSnapshot {
    OutcomeSnapshot {
        market_id,
        data: vec_map::empty(),
    }
}

public(package) fun add_outcome_snapshot_data(snapshot: &mut OutcomeSnapshot, outcome: Outcome, supply: u64) {
    assert!(!snapshot.data.contains(&outcome), EDuplicateOutcome);
    snapshot.data.insert(outcome, supply);
}

public(package) fun destroy_outcome_snapshot(snapshot: OutcomeSnapshot): (ID, VecMap<Outcome, u64>) {
    let OutcomeSnapshot { market_id, data } = snapshot;
    (market_id, data)
}