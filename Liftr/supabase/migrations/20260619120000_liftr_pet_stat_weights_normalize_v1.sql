begin;

update public.pet_type_stat_weights as w
set
  health_weight = v.health_weight,
  strength_weight = v.strength_weight,
  defense_weight = v.defense_weight,
  speed_weight = v.speed_weight,
  intelligence_weight = v.intelligence_weight,
  agility_weight = v.agility_weight,
  stamina_weight = v.stamina_weight,
  critical_rate_weight = v.critical_rate_weight,
  resistance_weight = v.resistance_weight,
  exploration_weight = v.exploration_weight,
  happiness_weight = v.happiness_weight
from (
  values
    ('dragon', 6, 7, 4, 3, 3, 2, 4, 2, 3, 3, 3),
    ('unicorn', 4, 2, 4, 4, 5, 4, 3, 3, 3, 4, 4),
    ('phoenix', 3, 4, 3, 7, 5, 5, 3, 1, 1, 5, 3),
    ('tiger', 7, 6, 6, 4, 1, 4, 4, 1, 3, 1, 3),
    ('lion', 7, 7, 4, 3, 1, 3, 4, 1, 4, 3, 3),
    ('wolf', 4, 5, 4, 5, 3, 6, 3, 1, 3, 3, 3),
    ('monkey', 2, 3, 3, 5, 5, 6, 3, 1, 3, 5, 4),
    ('raccoon', 3, 3, 4, 4, 4, 6, 3, 2, 4, 4, 3),
    ('fox', 2, 4, 3, 7, 4, 7, 3, 1, 1, 4, 4),
    ('turtle', 7, 3, 7, 1, 3, 1, 4, 1, 6, 3, 4),
    ('panda', 7, 4, 6, 1, 3, 3, 4, 1, 4, 3, 4),
    ('chick', 3, 3, 3, 4, 4, 6, 3, 2, 2, 4, 6),
    ('bunny', 3, 3, 3, 6, 4, 7, 3, 1, 2, 4, 4),
    ('octopus', 4, 2, 4, 2, 7, 4, 4, 3, 3, 4, 3),
    ('dolphin', 3, 4, 3, 5, 7, 4, 3, 1, 3, 4, 3),
    ('tiranosaurus', 7, 7, 6, 1, 1, 1, 6, 1, 4, 3, 3),
    ('triceratops', 7, 4, 7, 1, 1, 3, 4, 1, 6, 3, 3),
    ('pterodactyl', 2, 4, 3, 7, 4, 5, 3, 1, 3, 4, 4),
    ('shark', 6, 6, 4, 3, 3, 3, 4, 1, 4, 3, 3),
    ('orca', 4, 4, 4, 3, 4, 3, 4, 3, 3, 4, 4),
    ('crocodile', 7, 5, 5, 1, 1, 3, 5, 2, 4, 3, 4),
    ('owl', 3, 3, 3, 5, 7, 6, 3, 1, 1, 4, 4),
    ('flamingo', 3, 3, 3, 5, 5, 5, 3, 1, 3, 5, 4),
    ('snake', 2, 4, 3, 7, 4, 7, 3, 1, 1, 4, 4),
    ('lynx', 4, 5, 4, 5, 3, 6, 3, 1, 3, 3, 3),
    ('griffin', 5, 5, 4, 4, 3, 3, 4, 1, 4, 4, 3),
    ('elephant', 7, 6, 7, 1, 1, 1, 6, 1, 4, 3, 3),
    ('leopard', 4, 7, 4, 5, 2, 5, 3, 1, 3, 3, 3),
    ('gorilla', 5, 7, 5, 2, 3, 3, 4, 1, 3, 3, 4),
    ('hippo', 7, 4, 7, 1, 3, 1, 4, 2, 4, 3, 4),
    ('koala', 4, 3, 4, 3, 5, 4, 4, 1, 3, 5, 4),
    ('kangaroo', 4, 5, 4, 4, 3, 5, 4, 1, 3, 3, 4),
    ('armadillo', 5, 3, 7, 1, 3, 3, 4, 1, 6, 3, 4),
    ('eagle', 2, 4, 3, 7, 4, 7, 3, 1, 1, 4, 4),
    ('crab', 5, 3, 7, 1, 3, 3, 4, 1, 6, 3, 4),
    ('sphinx', 4, 2, 4, 2, 7, 4, 4, 3, 3, 4, 3),
    ('chimera', 5, 5, 4, 4, 4, 4, 4, 1, 3, 3, 3),
    ('ice_phoenix', 2, 4, 3, 7, 7, 5, 3, 1, 1, 4, 3),
    ('godzilla', 7, 7, 7, 1, 1, 1, 5, 1, 4, 3, 3),
    ('cybercat', 2, 4, 4, 6, 6, 5, 2, 1, 1, 5, 4),
    ('mechadragon', 7, 7, 5, 2, 3, 1, 4, 1, 4, 3, 3),
    ('void_serpent', 4, 4, 4, 5, 6, 4, 2, 1, 3, 4, 3),
    ('holofox', 3, 3, 3, 6, 5, 6, 3, 1, 1, 5, 4),
    ('neon_panther', 4, 5, 4, 6, 2, 5, 3, 1, 3, 3, 4),
    ('astrowolf', 4, 4, 4, 5, 5, 5, 2, 1, 2, 4, 4),
    ('quantum_slime', 2, 3, 3, 4, 6, 5, 3, 1, 4, 5, 4),
    ('drone_beetle', 4, 4, 5, 4, 4, 4, 3, 1, 4, 4, 3),
    ('kitsune', 3, 4, 3, 6, 5, 6, 3, 1, 1, 4, 4),
    ('chocobo', 4, 4, 4, 6, 2, 5, 4, 1, 2, 4, 4),
    ('celestial_kirin', 3, 4, 4, 4, 6, 4, 4, 1, 2, 4, 4),
    ('skydasher', 3, 4, 3, 6, 4, 6, 3, 1, 1, 5, 4),
    ('soul_wisp', 3, 3, 3, 5, 7, 5, 3, 1, 1, 5, 4),
    ('oniricat', 4, 4, 3, 6, 5, 5, 3, 1, 1, 4, 4),
    ('drakeling', 5, 6, 4, 4, 3, 4, 4, 1, 3, 3, 3),
    ('mythochic', 4, 2, 4, 4, 5, 5, 4, 1, 3, 4, 4),
    ('zorgling', 4, 5, 4, 5, 3, 5, 3, 1, 3, 4, 3),
    ('xenopup', 2, 4, 4, 5, 5, 5, 3, 1, 3, 4, 4),
    ('starfishoid', 4, 4, 5, 2, 6, 3, 3, 1, 4, 4, 4),
    ('meteokko', 4, 5, 4, 4, 4, 4, 4, 1, 3, 4, 3),
    ('shadowbunny', 2, 4, 3, 7, 4, 7, 3, 1, 1, 4, 4),
    ('grim_pup', 4, 5, 4, 5, 4, 4, 3, 1, 3, 4, 3),
    ('spectrophant', 7, 3, 7, 1, 5, 1, 4, 1, 5, 3, 3),
    ('cryptocat', 3, 4, 3, 6, 5, 6, 3, 1, 1, 4, 4),
    ('witch_crow', 2, 3, 3, 5, 7, 5, 3, 1, 3, 4, 4),
    ('demon', 6, 6, 5, 4, 1, 3, 4, 1, 4, 3, 3),
    ('hellhound', 5, 7, 4, 5, 1, 4, 4, 1, 3, 3, 3)
) as v(
  pet_type,
  health_weight,
  strength_weight,
  defense_weight,
  speed_weight,
  intelligence_weight,
  agility_weight,
  stamina_weight,
  critical_rate_weight,
  resistance_weight,
  exploration_weight,
  happiness_weight
)
where w.pet_type = v.pet_type;

do $$
declare
  v_bad_count integer;
begin
  select count(*)
  into v_bad_count
  from public.pet_type_stat_weights
  where
    health_weight + strength_weight + defense_weight + speed_weight
    + intelligence_weight + agility_weight + stamina_weight
    + critical_rate_weight + resistance_weight + exploration_weight
    + happiness_weight <> 40
    or least(
      health_weight, strength_weight, defense_weight, speed_weight,
      intelligence_weight, agility_weight, stamina_weight,
      critical_rate_weight, resistance_weight, exploration_weight, happiness_weight
    ) < 1;

  if v_bad_count > 0 then
    raise exception 'pet_type_stat_weights normalization failed: % invalid rows', v_bad_count;
  end if;
end;
$$;

commit;
