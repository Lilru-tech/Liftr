begin;

create or replace function public.get_pet_leaderboard_v1(
  p_metric text,
  p_scope text,
  p_limit integer default 100,
  p_sex text default null,
  p_age_band text default null
)
returns table (
  rank integer,
  user_id uuid,
  username text,
  avatar_url text,
  value numeric,
  battles integer,
  pet_name text,
  pet_level integer
)
language plpgsql
stable
security definer
set search_path to public
as $$
begin
  if p_metric is null or p_metric not in (
    'level', 'total_stats', 'health', 'strength', 'defense',
    'battles', 'wins', 'losses', 'win_rate',
    'max_damage_dealt', 'max_damage_taken',
    'total_damage_dealt', 'total_damage_taken'
  ) then
    raise exception 'invalid_metric';
  end if;

  return query
  with base as (
    select
      pr.user_id as uid,
      pi.id as pet_id,
      pi.evolution_stage as stage,
      pi.current_level as lvl,
      pi.current_xp as xp,
      coalesce(nullif(pi.custom_name, ''), pt.display_name) as pname,
      ps.health, ps.strength, ps.defense, ps.speed, ps.intelligence,
      ps.agility, ps.stamina, ps.critical_rate, ps.resistance,
      ps.exploration, ps.happiness,
      coalesce(cs.total_battles, 0) as total_battles,
      coalesce(cs.wins, 0) as wins,
      coalesce(cs.losses, 0) as losses,
      coalesce(cs.max_damage_dealt, 0) as max_damage_dealt,
      coalesce(cs.max_damage_taken, 0) as max_damage_taken,
      coalesce(cs.total_damage_dealt, 0) as total_damage_dealt,
      coalesce(cs.total_damage_taken, 0) as total_damage_taken
    from public.profiles pr
    left join public.pet_instances pi
      on pi.user_id = pr.user_id and pi.is_active = true
    left join public.pet_types pt on pt.name = pi.pet_type
    left join public.pet_instance_stats ps on ps.pet_instance_id = pi.id
    left join public.pet_combat_user_stats cs on cs.user_id = pr.user_id
    where (p_sex is null or p_sex = '' or pr.sex = p_sex::public.sex)
      and (
        p_age_band is null or p_age_band = ''
        or (
          case p_age_band
            when '18-24' then extract(year from age(current_date, pr.date_of_birth)) between 18 and 24
            when '25-34' then extract(year from age(current_date, pr.date_of_birth)) between 25 and 34
            when '35-44' then extract(year from age(current_date, pr.date_of_birth)) between 35 and 44
            when '45-54' then extract(year from age(current_date, pr.date_of_birth)) between 45 and 54
            when '55+' then extract(year from age(current_date, pr.date_of_birth)) >= 55
            else true
          end
        )
      )
      and (
        coalesce(p_scope, 'global') = 'global'
        or pr.user_id = auth.uid()
        or exists (
          select 1
          from public.follows f
          where f.follower_id = auth.uid()
            and f.followee_id = pr.user_id
        )
      )
  ),
  metric_rows as (
    select
      b.uid,
      b.pname,
      b.lvl,
      b.xp,
      b.total_battles as btl,
      case p_metric
        when 'level' then b.lvl::numeric
        when 'total_stats' then (
          b.health + b.strength + b.defense + b.speed + b.intelligence
          + b.agility + b.stamina + b.critical_rate + b.resistance
          + b.exploration + b.happiness
        )::numeric
        when 'health' then b.health::numeric
        when 'strength' then b.strength::numeric
        when 'defense' then b.defense::numeric
        when 'battles' then b.total_battles::numeric
        when 'wins' then b.wins::numeric
        when 'losses' then b.losses::numeric
        when 'win_rate' then round(b.wins::numeric * 100 / nullif(b.total_battles, 0), 1)
        when 'max_damage_dealt' then b.max_damage_dealt::numeric
        when 'max_damage_taken' then b.max_damage_taken::numeric
        when 'total_damage_dealt' then b.total_damage_dealt::numeric
        when 'total_damage_taken' then b.total_damage_taken::numeric
      end as val
    from base b
    where case
      when p_metric in ('level', 'total_stats', 'health', 'strength', 'defense')
        then b.pet_id is not null and b.stage <> 'egg'
      when p_metric = 'win_rate'
        then b.total_battles >= 5
      else b.total_battles > 0
    end
  ),
  ordered as (
    select
      m.uid,
      m.pname,
      m.lvl,
      m.btl,
      m.val,
      row_number() over (
        order by
          m.val desc,
          case when p_metric = 'level' then m.xp else m.btl end desc,
          m.uid
      ) as rnk
    from metric_rows m
    where m.val is not null
      and (p_metric = 'win_rate' or m.val > 0)
  )
  select
    o.rnk::integer as rank,
    o.uid as user_id,
    pr.username,
    pr.avatar_url,
    o.val as value,
    o.btl as battles,
    o.pname as pet_name,
    o.lvl as pet_level
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  where o.rnk <= greatest(1, coalesce(p_limit, 100))
  order by o.rnk;
end;
$$;

revoke all on function public.get_pet_leaderboard_v1(text, text, integer, text, text) from public;
revoke all on function public.get_pet_leaderboard_v1(text, text, integer, text, text) from anon;
grant execute on function public.get_pet_leaderboard_v1(text, text, integer, text, text) to authenticated;

commit;
