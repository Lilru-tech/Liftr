begin;

create table if not exists public.pet_combat_dex_species (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  opponent_pet_type text not null references public.pet_types (name) on delete cascade,
  total_battles integer not null default 0,
  wins integer not null default 0,
  losses integer not null default 0,
  draws integer not null default 0,
  first_fought_at timestamptz not null default now(),
  last_fought_at timestamptz not null default now(),
  rarities_seen text[] not null default '{}'::text[],
  stages_seen text[] not null default '{}'::text[],
  primary key (user_id, opponent_pet_type)
);

create index if not exists pet_combat_dex_species_user_idx
  on public.pet_combat_dex_species (user_id);

create table if not exists public.pet_combat_dex_rarities (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  rarity text not null,
  first_seen_at timestamptz not null default now(),
  primary key (user_id, rarity),
  constraint pet_combat_dex_rarities_rarity_chk
    check (rarity = any (array['common','uncommon','rare','epic','legendary','mythic']::text[]))
);

create table if not exists public.pet_combat_dex_stages (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  evolution_stage text not null,
  first_seen_at timestamptz not null default now(),
  primary key (user_id, evolution_stage),
  constraint pet_combat_dex_stages_stage_chk
    check (evolution_stage = any (array['baby','kid','teen','adult','elder']::text[]))
);

create table if not exists public.pet_user_discovered_stages (
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  pet_type text not null references public.pet_types (name) on delete cascade,
  evolution_stage text not null,
  source text not null,
  discovered_at timestamptz not null default now(),
  primary key (user_id, pet_type, evolution_stage),
  constraint pet_user_discovered_stages_source_chk
    check (source = any (array['combat','own_pet']::text[])),
  constraint pet_user_discovered_stages_stage_chk
    check (evolution_stage = any (array['egg','baby','kid','teen','adult','elder']::text[]))
);

alter table public.pet_combat_dex_species enable row level security;
alter table public.pet_combat_dex_rarities enable row level security;
alter table public.pet_combat_dex_stages enable row level security;
alter table public.pet_user_discovered_stages enable row level security;

drop policy if exists pet_combat_dex_species_select_own on public.pet_combat_dex_species;
create policy pet_combat_dex_species_select_own on public.pet_combat_dex_species
  for select using (auth.uid() = user_id);

drop policy if exists pet_combat_dex_rarities_select_own on public.pet_combat_dex_rarities;
create policy pet_combat_dex_rarities_select_own on public.pet_combat_dex_rarities
  for select using (auth.uid() = user_id);

drop policy if exists pet_combat_dex_stages_select_own on public.pet_combat_dex_stages;
create policy pet_combat_dex_stages_select_own on public.pet_combat_dex_stages
  for select using (auth.uid() = user_id);

drop policy if exists pet_user_discovered_stages_select_own on public.pet_user_discovered_stages;
create policy pet_user_discovered_stages_select_own on public.pet_user_discovered_stages
  for select using (auth.uid() = user_id);

revoke insert, update, delete on public.pet_combat_dex_species from authenticated;
revoke insert, update, delete on public.pet_combat_dex_rarities from authenticated;
revoke insert, update, delete on public.pet_combat_dex_stages from authenticated;
revoke insert, update, delete on public.pet_user_discovered_stages from authenticated;

create or replace function public.liftr_pet_stages_up_to_rank(p_stage text)
returns text[]
language sql
immutable
set search_path to public
as $$
  select case lower(coalesce(p_stage, 'egg'))
    when 'elder' then array['egg','baby','kid','teen','adult','elder']::text[]
    when 'adult' then array['egg','baby','kid','teen','adult']::text[]
    when 'teen' then array['egg','baby','kid','teen']::text[]
    when 'kid' then array['egg','baby','kid']::text[]
    when 'baby' then array['egg','baby']::text[]
    else array['egg']::text[]
  end;
$$;

create or replace function public.liftr_pet_dex_record_opponent(
  p_user_id uuid,
  p_opponent_snapshot jsonb,
  p_won boolean,
  p_is_draw boolean,
  p_fought_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_pet_type text := lower(trim(coalesce(p_opponent_snapshot->>'pet_type', '')));
  v_stage text := lower(trim(coalesce(p_opponent_snapshot->>'evolution_stage', '')));
  v_rarity text := lower(trim(coalesce(p_opponent_snapshot->>'rarity', '')));
begin
  if p_user_id is null or v_pet_type = '' then
    return;
  end if;

  if not exists (select 1 from public.pet_types pt where pt.name = v_pet_type) then
    return;
  end if;

  insert into public.pet_combat_dex_species as d (
    user_id,
    opponent_pet_type,
    total_battles,
    wins,
    losses,
    draws,
    first_fought_at,
    last_fought_at,
    rarities_seen,
    stages_seen
  )
  values (
    p_user_id,
    v_pet_type,
    1,
    case when p_is_draw then 0 when p_won then 1 else 0 end,
    case when p_is_draw then 0 when p_won then 0 else 1 end,
    case when p_is_draw then 1 else 0 end,
    p_fought_at,
    p_fought_at,
    case when v_rarity <> '' then array[v_rarity]::text[] else '{}'::text[] end,
    case when v_stage <> '' then array[v_stage]::text[] else '{}'::text[] end
  )
  on conflict (user_id, opponent_pet_type) do update set
    total_battles = d.total_battles + 1,
    wins = d.wins + excluded.wins,
    losses = d.losses + excluded.losses,
    draws = d.draws + excluded.draws,
    first_fought_at = least(d.first_fought_at, excluded.first_fought_at),
    last_fought_at = greatest(d.last_fought_at, excluded.last_fought_at),
    rarities_seen = (
      select coalesce(array_agg(distinct x order by x), '{}'::text[])
      from unnest(d.rarities_seen || excluded.rarities_seen) x
      where x is not null and x <> ''
    ),
    stages_seen = (
      select coalesce(array_agg(distinct x order by x), '{}'::text[])
      from unnest(d.stages_seen || excluded.stages_seen) x
      where x is not null and x <> ''
    );

  if v_rarity <> '' and v_rarity = any (array['common','uncommon','rare','epic','legendary','mythic']::text[]) then
    insert into public.pet_combat_dex_rarities (user_id, rarity, first_seen_at)
    values (p_user_id, v_rarity, p_fought_at)
    on conflict (user_id, rarity) do nothing;
  end if;

  if v_stage = any (array['baby','kid','teen','adult','elder']::text[]) then
    insert into public.pet_combat_dex_stages (user_id, evolution_stage, first_seen_at)
    values (p_user_id, v_stage, p_fought_at)
    on conflict (user_id, evolution_stage) do nothing;
  end if;

  if v_stage <> '' then
    insert into public.pet_user_discovered_stages (user_id, pet_type, evolution_stage, source, discovered_at)
    values (p_user_id, v_pet_type, v_stage, 'combat', p_fought_at)
    on conflict (user_id, pet_type, evolution_stage) do nothing;
  end if;
end;
$$;

create or replace function public.liftr_pet_dex_record_own_stages(
  p_user_id uuid,
  p_pet_type text,
  p_evolution_stage text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stage text;
begin
  if p_user_id is null or coalesce(p_pet_type, '') = '' then
    return;
  end if;

  foreach v_stage in array public.liftr_pet_stages_up_to_rank(p_evolution_stage)
  loop
    insert into public.pet_user_discovered_stages (user_id, pet_type, evolution_stage, source, discovered_at)
    values (p_user_id, lower(p_pet_type), v_stage, 'own_pet', now())
    on conflict (user_id, pet_type, evolution_stage) do nothing;
  end loop;
end;
$$;

create or replace function public.trg_fn_pet_combat_dex_from_history()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_attacker_pet jsonb := new.battle_log->'attacker_pet';
  v_defender_pet jsonb := new.battle_log->'defender_pet';
  v_is_draw boolean := coalesce((new.battle_log->'result'->>'is_draw')::boolean, false);
  v_winner_user_id uuid := new.winner_user_id;
begin
  perform public.liftr_pet_dex_record_opponent(
    new.attacker_user_id,
    v_defender_pet,
    (not v_is_draw and v_winner_user_id = new.attacker_user_id),
    v_is_draw,
    new.created_at
  );

  perform public.liftr_pet_dex_record_opponent(
    new.defender_user_id,
    v_attacker_pet,
    (not v_is_draw and v_winner_user_id = new.defender_user_id),
    v_is_draw,
    new.created_at
  );

  perform public.check_and_unlock_achievements_for(new.attacker_user_id);
  perform public.check_and_unlock_achievements_for(new.defender_user_id);

  return new;
end;
$$;

drop trigger if exists trg_pet_combat_dex_from_history on public.pet_combat_history;
create trigger trg_pet_combat_dex_from_history
  after insert on public.pet_combat_history
  for each row
  execute function public.trg_fn_pet_combat_dex_from_history();

create or replace function public.trg_fn_pet_own_stage_discovery()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT'
     or (tg_op = 'UPDATE' and old.evolution_stage is distinct from new.evolution_stage) then
    perform public.liftr_pet_dex_record_own_stages(new.user_id, new.pet_type, new.evolution_stage);
  end if;
  return new;
end;
$$;

drop trigger if exists trg_pet_own_stage_discovery on public.pet_instances;
create trigger trg_pet_own_stage_discovery
  after insert or update of evolution_stage on public.pet_instances
  for each row
  execute function public.trg_fn_pet_own_stage_discovery();

insert into public.pet_combat_dex_species (
  user_id,
  opponent_pet_type,
  total_battles,
  wins,
  losses,
  draws,
  first_fought_at,
  last_fought_at,
  rarities_seen,
  stages_seen
)
select
  agg.user_id,
  agg.opponent_pet_type,
  agg.total_battles,
  agg.wins,
  agg.losses,
  agg.draws,
  agg.first_fought_at,
  agg.last_fought_at,
  agg.rarities_seen,
  agg.stages_seen
from (
  select
    e.user_id,
    e.opponent_pet_type,
    count(*)::integer as total_battles,
    count(*) filter (where e.won)::integer as wins,
    count(*) filter (where e.lost)::integer as losses,
    count(*) filter (where e.is_draw)::integer as draws,
    min(e.fought_at) as first_fought_at,
    max(e.fought_at) as last_fought_at,
    coalesce(array_agg(distinct e.rarity order by e.rarity) filter (where e.rarity <> ''), '{}'::text[]) as rarities_seen,
    coalesce(array_agg(distinct e.stage order by e.stage) filter (where e.stage <> ''), '{}'::text[]) as stages_seen
  from (
    select
      h.attacker_user_id as user_id,
      lower(h.battle_log->'defender_pet'->>'pet_type') as opponent_pet_type,
      lower(h.battle_log->'defender_pet'->>'rarity') as rarity,
      lower(h.battle_log->'defender_pet'->>'evolution_stage') as stage,
      h.created_at as fought_at,
      (not coalesce((h.battle_log->'result'->>'is_draw')::boolean, false)
        and h.winner_user_id = h.attacker_user_id) as won,
      (not coalesce((h.battle_log->'result'->>'is_draw')::boolean, false)
        and h.winner_user_id is not null
        and h.winner_user_id <> h.attacker_user_id) as lost,
      coalesce((h.battle_log->'result'->>'is_draw')::boolean, false) as is_draw
    from public.pet_combat_history h
    union all
    select
      h.defender_user_id as user_id,
      lower(h.battle_log->'attacker_pet'->>'pet_type') as opponent_pet_type,
      lower(h.battle_log->'attacker_pet'->>'rarity') as rarity,
      lower(h.battle_log->'attacker_pet'->>'evolution_stage') as stage,
      h.created_at as fought_at,
      (not coalesce((h.battle_log->'result'->>'is_draw')::boolean, false)
        and h.winner_user_id = h.defender_user_id) as won,
      (not coalesce((h.battle_log->'result'->>'is_draw')::boolean, false)
        and h.winner_user_id is not null
        and h.winner_user_id <> h.defender_user_id) as lost,
      coalesce((h.battle_log->'result'->>'is_draw')::boolean, false) as is_draw
    from public.pet_combat_history h
  ) e
  where e.user_id is not null
    and e.opponent_pet_type is not null
    and e.opponent_pet_type <> ''
    and exists (select 1 from public.pet_types pt where pt.name = e.opponent_pet_type)
  group by e.user_id, e.opponent_pet_type
) agg
on conflict (user_id, opponent_pet_type) do update set
  total_battles = excluded.total_battles,
  wins = excluded.wins,
  losses = excluded.losses,
  draws = excluded.draws,
  first_fought_at = excluded.first_fought_at,
  last_fought_at = excluded.last_fought_at,
  rarities_seen = excluded.rarities_seen,
  stages_seen = excluded.stages_seen;

insert into public.pet_combat_dex_rarities (user_id, rarity, first_seen_at)
select distinct
  e.user_id,
  e.rarity,
  min(e.fought_at)
from (
  select h.attacker_user_id as user_id, lower(h.battle_log->'defender_pet'->>'rarity') as rarity, h.created_at as fought_at
  from public.pet_combat_history h
  union all
  select h.defender_user_id, lower(h.battle_log->'attacker_pet'->>'rarity'), h.created_at
  from public.pet_combat_history h
) e
where e.rarity = any (array['common','uncommon','rare','epic','legendary','mythic']::text[])
group by e.user_id, e.rarity
on conflict (user_id, rarity) do nothing;

insert into public.pet_combat_dex_stages (user_id, evolution_stage, first_seen_at)
select distinct
  e.user_id,
  e.stage,
  min(e.fought_at)
from (
  select h.attacker_user_id as user_id, lower(h.battle_log->'defender_pet'->>'evolution_stage') as stage, h.created_at as fought_at
  from public.pet_combat_history h
  union all
  select h.defender_user_id, lower(h.battle_log->'attacker_pet'->>'evolution_stage'), h.created_at
  from public.pet_combat_history h
) e
where e.stage = any (array['baby','kid','teen','adult','elder']::text[])
group by e.user_id, e.stage
on conflict (user_id, evolution_stage) do nothing;

insert into public.pet_user_discovered_stages (user_id, pet_type, evolution_stage, source, discovered_at)
select distinct
  e.user_id,
  e.pet_type,
  e.stage,
  'combat',
  min(e.fought_at)
from (
  select h.attacker_user_id as user_id,
         lower(h.battle_log->'defender_pet'->>'pet_type') as pet_type,
         lower(h.battle_log->'defender_pet'->>'evolution_stage') as stage,
         h.created_at as fought_at
  from public.pet_combat_history h
  union all
  select h.defender_user_id,
         lower(h.battle_log->'attacker_pet'->>'pet_type'),
         lower(h.battle_log->'attacker_pet'->>'evolution_stage'),
         h.created_at
  from public.pet_combat_history h
) e
where e.pet_type is not null and e.pet_type <> ''
  and e.stage is not null and e.stage <> ''
  and exists (select 1 from public.pet_types pt where pt.name = e.pet_type)
group by e.user_id, e.pet_type, e.stage
on conflict (user_id, pet_type, evolution_stage) do nothing;

insert into public.pet_user_discovered_stages (user_id, pet_type, evolution_stage, source, discovered_at)
select
  pi.user_id,
  pi.pet_type,
  s.stage,
  'own_pet',
  coalesce(pi.updated_at, pi.created_at, now())
from public.pet_instances pi
cross join lateral unnest(public.liftr_pet_stages_up_to_rank(pi.evolution_stage)) as s(stage)
on conflict (user_id, pet_type, evolution_stage) do nothing;

create or replace function public.liftr_user_pet_dex_metrics(p_user_id uuid)
returns table (
  species_discovered integer,
  total_species integer,
  rarities_discovered integer,
  stages_discovered integer
)
language sql
stable
security definer
set search_path = public
as $$
  select
    coalesce((
      select count(*)::integer
      from public.pet_combat_dex_species d
      where d.user_id = p_user_id
        and d.total_battles > 0
    ), 0) as species_discovered,
    coalesce((select count(*)::integer from public.pet_types), 0) as total_species,
    coalesce((
      select count(*)::integer
      from public.pet_combat_dex_rarities r
      where r.user_id = p_user_id
    ), 0) as rarities_discovered,
    coalesce((
      select count(*)::integer
      from public.pet_combat_dex_stages s
      where s.user_id = p_user_id
    ), 0) as stages_discovered;
$$;

create or replace function public.get_my_pet_dex_v1()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_metrics record;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_metrics from public.liftr_user_pet_dex_metrics(v_user_id);

  return jsonb_build_object(
    'species_discovered', v_metrics.species_discovered,
    'total_species', v_metrics.total_species,
    'rarities_discovered', v_metrics.rarities_discovered,
    'total_rarities', 6,
    'stages_discovered', v_metrics.stages_discovered,
    'total_fightable_stages', 5,
    'species', coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'pet_type', pt.name,
          'display_name', pt.display_name,
          'description', pt.description,
          'image_egg', coalesce(pt.image_egg, public.liftr_pet_image_url_for_stage(pt.name, 'egg')),
          'is_discovered', coalesce(d.total_battles, 0) > 0,
          'total_battles', coalesce(d.total_battles, 0),
          'wins', coalesce(d.wins, 0),
          'losses', coalesce(d.losses, 0),
          'draws', coalesce(d.draws, 0),
          'first_fought_at', d.first_fought_at,
          'last_fought_at', d.last_fought_at,
          'rarities_seen', coalesce(to_jsonb(d.rarities_seen), '[]'::jsonb),
          'stages_seen', coalesce(to_jsonb(d.stages_seen), '[]'::jsonb)
        )
        order by pt.display_name
      )
      from public.pet_types pt
      left join public.pet_combat_dex_species d
        on d.user_id = v_user_id
       and d.opponent_pet_type = pt.name
    ), '[]'::jsonb)
  );
end;
$$;

create or replace function public.get_pet_species_detail_v1(p_pet_type text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid := auth.uid();
  v_type text := lower(trim(coalesce(p_pet_type, '')));
  v_row public.pet_types%rowtype;
  v_dex public.pet_combat_dex_species%rowtype;
begin
  if v_user_id is null then
    raise exception 'not_authenticated';
  end if;

  select * into v_row from public.pet_types pt where pt.name = v_type;
  if not found then
    raise exception 'unknown_pet_type';
  end if;

  select * into v_dex
  from public.pet_combat_dex_species d
  where d.user_id = v_user_id
    and d.opponent_pet_type = v_type;

  return jsonb_build_object(
    'pet_type', v_row.name,
    'display_name', v_row.display_name,
    'description', v_row.description,
    'image_egg', coalesce(v_row.image_egg, public.liftr_pet_image_url_for_stage(v_row.name, 'egg')),
    'image_baby', coalesce(v_row.image_baby, public.liftr_pet_image_url_for_stage(v_row.name, 'baby')),
    'image_kid', coalesce(v_row.image_kid, public.liftr_pet_image_url_for_stage(v_row.name, 'kid')),
    'image_teen', coalesce(v_row.image_teen, public.liftr_pet_image_url_for_stage(v_row.name, 'teen')),
    'image_adult', coalesce(v_row.image_adult, public.liftr_pet_image_url_for_stage(v_row.name, 'adult')),
    'image_elder', coalesce(v_row.image_elder, public.liftr_pet_image_url_for_stage(v_row.name, 'elder')),
    'discovered_stages', coalesce((
      select jsonb_agg(ds.evolution_stage order by public.liftr_pet_stage_rank(ds.evolution_stage))
      from public.pet_user_discovered_stages ds
      where ds.user_id = v_user_id
        and ds.pet_type = v_type
    ), '[]'::jsonb),
    'dex', case when v_dex.user_id is not null then jsonb_build_object(
      'total_battles', v_dex.total_battles,
      'wins', v_dex.wins,
      'losses', v_dex.losses,
      'draws', v_dex.draws,
      'first_fought_at', v_dex.first_fought_at,
      'last_fought_at', v_dex.last_fought_at,
      'rarities_seen', coalesce(to_jsonb(v_dex.rarities_seen), '[]'::jsonb),
      'stages_seen', coalesce(to_jsonb(v_dex.stages_seen), '[]'::jsonb)
    ) else null end
  );
end;
$$;

insert into public.achievements (
  code, name, description, category, requirement_type, requirement_value, coin_reward_tier, created_at
)
select * from (values
  (
    'pet_combat_all_rarities'::text,
    'Rarity Hunter'::text,
    'Fight an opponent pet of every rarity tier.'::text,
    'pet'::text,
    'count'::text,
    6,
    'gold'::text,
    now()
  ),
  (
    'pet_combat_all_species'::text,
    'Species Master'::text,
    'Fight every pet species in the arena.'::text,
    'pet'::text,
    'count'::text,
    66,
    'gold'::text,
    now()
  ),
  (
    'pet_combat_all_stages'::text,
    'Stage Explorer'::text,
    'Fight an opponent pet at every evolution stage.'::text,
    'pet'::text,
    'count'::text,
    5,
    'gold'::text,
    now()
  )
) as v(code, name, description, category, requirement_type, requirement_value, coin_reward_tier, created_at)
where not exists (
  select 1 from public.achievements a where a.code = v.code
);

create or replace function public.unlock_pet_achievements(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  m record;
  d record;
begin
  select * into m from public.liftr_user_pet_metrics(p_user_id);
  select * into d from public.liftr_user_pet_dex_metrics(p_user_id);

  if m.incubations >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_incubation_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.hatches >= 1 or m.max_stage_rank >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_hatched_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_feedings >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_feed_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_feedings >= 100 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_feed_100'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 2 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_kid'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 3 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_teen'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 4 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_adult'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_stage_rank >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_evolve_elder'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.current_level >= 50 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_level_50'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.current_level >= 100 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_level_100'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_rarity_sort >= 3 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_rarity_rare'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_rarity_sort >= 4 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_rarity_epic'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_rarity_sort >= 6 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_rarity_mythic'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.total_battles >= 1 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_first'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.wins >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_wins_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.best_win_streak >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_streak_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if d.rarities_discovered >= 6 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_all_rarities'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if d.species_discovered >= d.total_species and d.total_species > 0 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_all_species'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if d.stages_discovered >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_combat_all_stages'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.passive_pet_coins >= 1000 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_coins_passive_1000'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.workout_bonus_count >= 10 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_workout_bonus_10'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.reroll_count >= 5 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_egg_reroll_5'
    on conflict (user_id, achievement_id) do nothing;
  end if;

  if m.max_energy >= 7 then
    insert into public.user_achievements (user_id, achievement_id, unlocked_at)
    select p_user_id, id, now() from public.achievements where code = 'pet_energy_max_7'
    on conflict (user_id, achievement_id) do nothing;
  end if;
end;
$function$;

create or replace function public.liftr_achievement_progress_current(
  p_user_id uuid,
  p_code text,
  p_requirement_type text
)
returns double precision
language plpgsql
stable
security definer
set search_path = public
as $function$
declare
  m record;
  d record;
  v_lifetime bigint;
  v_pet_sources bigint;
begin
  if p_requirement_type is distinct from 'count' then
    return null;
  end if;

  if p_code like 'coins_%' then
    v_lifetime := public.liftr_user_lifetime_coins_earned(p_user_id);
    v_pet_sources :=
      public.liftr_user_coin_source_total(p_user_id, 'pet_coins')
      + public.liftr_user_coin_source_total(p_user_id, 'pet_combat')
      + public.liftr_user_coin_source_total(p_user_id, 'pet_workout_bonus');
    return case p_code
      when 'coins_earned_first' then v_lifetime::double precision
      when 'coins_earned_100' then v_lifetime::double precision
      when 'coins_earned_500' then v_lifetime::double precision
      when 'coins_earned_1000' then v_lifetime::double precision
      when 'coins_earned_5000' then v_lifetime::double precision
      when 'coins_earned_10000' then v_lifetime::double precision
      when 'coins_earned_25000' then v_lifetime::double precision
      when 'coins_earned_50000' then v_lifetime::double precision
      when 'coins_workouts_1000' then public.liftr_user_coin_source_total(p_user_id, 'workouts')::double precision
      when 'coins_social_500' then public.liftr_user_coin_source_total(p_user_id, 'social')::double precision
      when 'coins_nutrition_500' then public.liftr_user_coin_source_total(p_user_id, 'nutrition')::double precision
      when 'coins_pet_sources_1000' then v_pet_sources::double precision
      else null
    end;
  end if;

  if p_code like 'pet_%' then
    select * into m from public.liftr_user_pet_metrics(p_user_id);
    select * into d from public.liftr_user_pet_dex_metrics(p_user_id);
    return case p_code
      when 'pet_incubation_first' then m.incubations::double precision
      when 'pet_hatched_first' then greatest(m.hatches, case when m.max_stage_rank >= 1 then 1 else 0 end)::double precision
      when 'pet_feed_10' then m.total_feedings::double precision
      when 'pet_feed_100' then m.total_feedings::double precision
      when 'pet_evolve_kid' then case when m.max_stage_rank >= 2 then 1 else 0 end::double precision
      when 'pet_evolve_teen' then case when m.max_stage_rank >= 3 then 1 else 0 end::double precision
      when 'pet_evolve_adult' then case when m.max_stage_rank >= 4 then 1 else 0 end::double precision
      when 'pet_evolve_elder' then case when m.max_stage_rank >= 5 then 1 else 0 end::double precision
      when 'pet_level_50' then m.current_level::double precision
      when 'pet_level_100' then m.current_level::double precision
      when 'pet_rarity_rare' then case when m.max_rarity_sort >= 3 then 1 else 0 end::double precision
      when 'pet_rarity_epic' then case when m.max_rarity_sort >= 4 then 1 else 0 end::double precision
      when 'pet_rarity_mythic' then case when m.max_rarity_sort >= 6 then 1 else 0 end::double precision
      when 'pet_combat_first' then m.total_battles::double precision
      when 'pet_combat_wins_10' then m.wins::double precision
      when 'pet_combat_streak_5' then m.best_win_streak::double precision
      when 'pet_combat_all_rarities' then d.rarities_discovered::double precision
      when 'pet_combat_all_species' then d.species_discovered::double precision
      when 'pet_combat_all_stages' then d.stages_discovered::double precision
      when 'pet_coins_passive_1000' then m.passive_pet_coins::double precision
      when 'pet_workout_bonus_10' then m.workout_bonus_count::double precision
      when 'pet_egg_reroll_5' then m.reroll_count::double precision
      when 'pet_energy_max_7' then m.max_energy::double precision
      else null
    end;
  end if;

  return null;
end;
$function$;

grant execute on function public.get_my_pet_dex_v1() to authenticated;
grant execute on function public.get_pet_species_detail_v1(text) to authenticated;
grant execute on function public.liftr_user_pet_dex_metrics(uuid) to authenticated;

revoke all on function public.liftr_pet_dex_record_opponent(uuid, jsonb, boolean, boolean, timestamptz) from public;
revoke all on function public.liftr_pet_dex_record_own_stages(uuid, text, text) from public;
revoke all on function public.liftr_pet_stages_up_to_rank(text) from public;

commit;
