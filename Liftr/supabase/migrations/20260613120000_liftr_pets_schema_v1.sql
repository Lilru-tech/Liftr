begin;

do $$
begin
  if not exists (select 1 from pg_type where typname = 'pet_rarity') then
    create type public.pet_rarity as enum (
      'common', 'uncommon', 'rare', 'epic', 'legendary', 'mythic'
    );
  end if;
end $$;

create table if not exists public.pet_types (
  name text primary key,
  display_name text not null default '',
  description text not null default ''
);

create table if not exists public.pet_levels (
  level integer primary key,
  required_exp integer not null
);

create table if not exists public.pet_type_stat_weights (
  pet_type text primary key references public.pet_types (name),
  health_weight integer not null,
  strength_weight integer not null,
  defense_weight integer not null,
  speed_weight integer not null,
  intelligence_weight integer not null,
  agility_weight integer not null,
  stamina_weight integer not null,
  critical_rate_weight integer not null,
  resistance_weight integer not null,
  exploration_weight integer not null,
  happiness_weight integer not null
);

create table if not exists public.pet_stage_rewards (
  stage text primary key,
  coins_min_per_hour integer not null,
  stats_min_per_level integer not null,
  stats_max_per_level integer not null,
  coins_max_per_hour integer
);

create table if not exists public.pet_food_experience (
  item_type text not null,
  pet_stage text not null,
  min_exp integer not null,
  max_exp integer not null,
  primary key (item_type, pet_stage)
);

create table if not exists public.pet_rarity_config (
  rarity public.pet_rarity primary key,
  display_name text not null,
  color_hex text not null,
  drop_weight integer not null,
  coin_multiplier numeric(4, 2) not null,
  stat_multiplier numeric(4, 2) not null,
  sort_order integer not null
);

create table if not exists public.pet_market_items (
  item_type text primary key,
  display_name text not null,
  description text not null default '',
  price integer not null check (price >= 0),
  category text not null,
  image_path text,
  is_active boolean not null default true
);

create table if not exists public.pet_instances (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  pet_type text not null references public.pet_types (name),
  custom_name text,
  evolution_stage text not null default 'egg'
    check (evolution_stage in ('egg', 'baby', 'kid', 'teen', 'adult', 'elder')),
  current_xp integer not null default 0,
  current_level integer not null default 1,
  rarity public.pet_rarity not null default 'common',
  hatch_at timestamptz,
  is_equipped boolean not null default true,
  is_active boolean not null default true,
  reroll_count integer not null default 0,
  total_feedings integer not null default 0,
  last_coins_generated_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists pet_instances_one_active_per_user_idx
  on public.pet_instances (user_id)
  where is_active = true;

create index if not exists pet_instances_user_id_idx
  on public.pet_instances (user_id);

create table if not exists public.pet_instance_stats (
  pet_instance_id uuid primary key references public.pet_instances (id) on delete cascade,
  health integer not null default 100,
  strength integer not null default 10,
  defense integer not null default 10,
  speed integer not null default 10,
  intelligence integer not null default 10,
  agility integer not null default 10,
  stamina integer not null default 100,
  critical_rate integer not null default 5,
  resistance integer not null default 5,
  exploration integer not null default 5,
  happiness integer not null default 50
);

create table if not exists public.user_inventory (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  item_type text not null,
  quantity integer not null default 0 check (quantity >= 0),
  acquired_at timestamptz not null default now(),
  unique (user_id, item_type)
);

create index if not exists user_inventory_user_id_idx
  on public.user_inventory (user_id);

create table if not exists public.pet_logs (
  id bigserial primary key,
  user_id uuid not null references public.profiles (user_id) on delete cascade,
  pet_instance_id uuid references public.pet_instances (id) on delete set null,
  event_type text not null,
  item_type text,
  exp_gained integer not null default 0,
  new_level integer,
  stats_delta jsonb,
  details jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists pet_logs_user_created_idx
  on public.pet_logs (user_id, created_at desc);

insert into public.coin_reward_rules (action_type, amount, enabled) values
  ('pet_market_purchase', 0, true),
  ('pet_egg_reroll', 0, true),
  ('pet_coins_generated', 0, true)
on conflict (action_type) do nothing;

alter table public.pet_types enable row level security;
alter table public.pet_levels enable row level security;
alter table public.pet_type_stat_weights enable row level security;
alter table public.pet_stage_rewards enable row level security;
alter table public.pet_food_experience enable row level security;
alter table public.pet_rarity_config enable row level security;
alter table public.pet_market_items enable row level security;
alter table public.pet_instances enable row level security;
alter table public.pet_instance_stats enable row level security;
alter table public.user_inventory enable row level security;
alter table public.pet_logs enable row level security;

drop policy if exists pet_types_read on public.pet_types;
create policy pet_types_read on public.pet_types for select using (true);

drop policy if exists pet_levels_read on public.pet_levels;
create policy pet_levels_read on public.pet_levels for select using (true);

drop policy if exists pet_type_stat_weights_read on public.pet_type_stat_weights;
create policy pet_type_stat_weights_read on public.pet_type_stat_weights for select using (true);

drop policy if exists pet_stage_rewards_read on public.pet_stage_rewards;
create policy pet_stage_rewards_read on public.pet_stage_rewards for select using (true);

drop policy if exists pet_food_experience_read on public.pet_food_experience;
create policy pet_food_experience_read on public.pet_food_experience for select using (true);

drop policy if exists pet_rarity_config_read on public.pet_rarity_config;
create policy pet_rarity_config_read on public.pet_rarity_config for select using (true);

drop policy if exists pet_market_items_read on public.pet_market_items;
create policy pet_market_items_read on public.pet_market_items for select using (true);

drop policy if exists pet_instances_select_own on public.pet_instances;
create policy pet_instances_select_own on public.pet_instances
  for select using (auth.uid() = user_id);

drop policy if exists pet_instance_stats_select_own on public.pet_instance_stats;
create policy pet_instance_stats_select_own on public.pet_instance_stats
  for select using (
    exists (
      select 1
      from public.pet_instances pi
      where pi.id = pet_instance_id
        and pi.user_id = auth.uid()
    )
  );

drop policy if exists user_inventory_select_own on public.user_inventory;
create policy user_inventory_select_own on public.user_inventory
  for select using (auth.uid() = user_id);

drop policy if exists pet_logs_select_own on public.pet_logs;
create policy pet_logs_select_own on public.pet_logs
  for select using (auth.uid() = user_id);

create or replace function public.liftr_pet_remove_incubator_on_hatch()
returns trigger
language plpgsql
security definer
set search_path to public
as $$
begin
  if new.evolution_stage = 'baby' and old.evolution_stage = 'egg' then
    update public.user_inventory
    set quantity = 0
    where user_id = new.user_id
      and item_type = 'incubator';

    delete from public.user_inventory
    where user_id = new.user_id
      and item_type = 'incubator'
      and quantity <= 0;
  end if;
  return new;
end;
$$;

drop trigger if exists trg_liftr_pet_remove_incubator_on_hatch on public.pet_instances;
create trigger trg_liftr_pet_remove_incubator_on_hatch
  after update of evolution_stage on public.pet_instances
  for each row
  execute function public.liftr_pet_remove_incubator_on_hatch();

insert into storage.buckets (id, name, public)
values ('pets', 'pets', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists pets_storage_public_read on storage.objects;
create policy pets_storage_public_read on storage.objects
  for select
  using (bucket_id = 'pets');

commit;
