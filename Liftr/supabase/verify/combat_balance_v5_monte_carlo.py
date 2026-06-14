#!/usr/bin/env python3
import random
import sys
from itertools import combinations

SK = [
    "health", "strength", "defense", "speed", "intelligence", "agility",
    "stamina", "critical_rate", "resistance", "exploration", "happiness",
]

V5_WEIGHTS = {
    "chocobo": dict(
        health=4, strength=4, defense=4, speed=6, intelligence=2, agility=5,
        stamina=4, critical_rate=1, resistance=2, exploration=4, happiness=4,
    ),
    "griffin": dict(
        health=4, strength=4, defense=4, speed=5, intelligence=2, agility=4,
        stamina=4, critical_rate=1, resistance=5, exploration=3, happiness=4,
    ),
    "monkey": dict(
        health=4, strength=4, defense=3, speed=5, intelligence=4, agility=5,
        stamina=3, critical_rate=1, resistance=3, exploration=4, happiness=4,
    ),
    "neon_panther": dict(
        health=4, strength=4, defense=4, speed=6, intelligence=2, agility=5,
        stamina=3, critical_rate=1, resistance=3, exploration=4, happiness=4,
    ),
}

PRODUCTION_TYPES = ["chocobo", "griffin", "monkey", "neon_panther"]
FIGHTS_PER_PAIR = 2500
LEVEL = 5
MIN_PAIR_PCT = 40
MAX_PAIR_PCT = 60
MIN_OK_PAIRS = 5


class Pet:
    def __init__(self, name, stats):
        self.name = name
        self.stats = stats


def battle_hp(health):
    return (max(health, 1) * 8 + 9) // 10


def build_pet(pet_type, level=LEVEL):
    weights = V5_WEIGHTS[pet_type]
    total = sum(weights.values())
    base = 60
    stats = {
        k: (round(base * weights[k] / total) * 20 if k == "health" else round(base * weights[k] / total))
        for k in SK
    }
    for _ in range(level - 1):
        budget = random.randint(5, 10)
        for k in SK:
            raw = budget * 1.2 * (weights[k] / total) * (0.5 + random.random())
            stats[k] += max(0, int(raw * 20) if k == "health" else round(raw))
    return Pet(pet_type, stats)


def strikes_first(a, b):
    sa, sb = a.stats, b.stats
    if sa["speed"] != sb["speed"]:
        return sa["speed"] > sb["speed"]
    if sa["agility"] != sb["agility"]:
        return sa["agility"] > sb["agility"]
    return random.random() >= 0.5


def strike(attacker, defender, rnd, is_first_strike):
    s, d = attacker.stats, defender.stats
    dodge = min(
        0.28,
        max(0.03, (max(d["agility"], 0) - max(s["intelligence"], 0) / 2) * 0.02),
    )
    if random.random() < dodge:
        return 0
    crit = random.random() < min(0.5, max(s["critical_rate"], 0) / 100)
    crit_mult = min(2.25, 1.75 + max(s["intelligence"], 0) * 0.005) if crit else 1.0
    strength = (
        max(s["strength"], 1)
        + max(s["agility"], 0) * 0.22
        + max(s["intelligence"], 0) * 0.10
    )
    mitigation = strength / (
        strength + (max(d["defense"], 0) + max(d["resistance"], 0)) / 2
    )
    variance_floor = 0.85 + min(0.05, max(s["happiness"], 0) * 0.002)
    variance = variance_floor + random.random() * (1.15 - variance_floor)
    fatigue = 1.0 + max(0, rnd - 12) * max(0.01, 0.04 - max(d["stamina"], 0) * 0.001)
    first_strike = 1.0
    if is_first_strike:
        first_strike = 1.0 + min(0.03, max(s["exploration"], 0) * 0.002)
    return max(
        1,
        int(1.22 * strength * mitigation * variance * crit_mult * fatigue * first_strike),
    )


def fight(a, b):
    hp_a = battle_hp(a.stats["health"])
    hp_b = battle_hp(b.stats["health"])
    for rnd in range(1, 51):
        if hp_a <= 0 or hp_b <= 0:
            break
        order = [0, 1] if strikes_first(a, b) else [1, 0]
        for idx in order:
            if hp_a <= 0 or hp_b <= 0:
                break
            attacker, defender = (a, b) if idx == 0 else (b, a)
            dmg = strike(attacker, defender, rnd, False)
            if idx == 0:
                hp_b = max(0, hp_b - dmg)
            else:
                hp_a = max(0, hp_a - dmg)
    if hp_a > hp_b:
        return a.name
    if hp_b > hp_a:
        return b.name
    return None


def main():
    random.seed(42)
    h2h = {}
    for a, b in combinations(PRODUCTION_TYPES, 2):
        h2h[(a, b)] = 0
        h2h[(b, a)] = 0

    for _ in range(FIGHTS_PER_PAIR):
        pets = {t: build_pet(t) for t in PRODUCTION_TYPES}
        for a, b in combinations(PRODUCTION_TYPES, 2):
            winner = fight(pets[a], pets[b])
            if winner == a:
                h2h[(a, b)] += 1
            elif winner == b:
                h2h[(b, a)] += 1

    ok_pairs = 0
    failed = []
    for a, b in combinations(PRODUCTION_TYPES, 2):
        wins_a = h2h[(a, b)]
        wins_b = h2h[(b, a)]
        pct = 100 * wins_a / (wins_a + wins_b)
        in_range = MIN_PAIR_PCT <= pct <= MAX_PAIR_PCT
        if in_range:
            ok_pairs += 1
        else:
            failed.append(f"{a} vs {b}: {pct:.1f}%")
        print(f"  {a:14} vs {b:14} {pct:5.1f}%{' OK' if in_range else ''}")

    print(f"=> {ok_pairs}/{len(list(combinations(PRODUCTION_TYPES, 2)))} pairs in {MIN_PAIR_PCT}-{MAX_PAIR_PCT}%")
    if ok_pairs < MIN_OK_PAIRS:
        print("FAILED:", ", ".join(failed))
        sys.exit(1)
    print("PASSED")


if __name__ == "__main__":
    main()
