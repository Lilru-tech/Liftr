begin;

do $$
declare
  v_user uuid := gen_random_uuid();
  v_distinct_hp integer;
  v_avg_stats_up numeric;
  v_crit_zero_pct numeric;
  v_delta jsonb;
  i integer;
begin
  if to_regprocedure('public.compute_pet_level_stat_delta_v1(text, text, uuid)') is null then
    raise exception 'missing function compute_pet_level_stat_delta_v1';
  end if;

  if to_regprocedure('public.backfill_pet_level_stat_variance_v1()') is null then
    raise exception 'missing function backfill_pet_level_stat_variance_v1';
  end if;

  create temp table tmp_hp_rolls (hp integer) on commit drop;

  for i in 1..50 loop
    v_delta := public.compute_pet_level_stat_delta_v1('monkey', 'baby', v_user);
    insert into tmp_hp_rolls (hp) values (coalesce((v_delta ->> 'health')::integer, 0));
  end loop;

  select count(distinct hp) into v_distinct_hp from tmp_hp_rolls;

  if coalesce(v_distinct_hp, 0) <= 2 then
    raise exception 'expected more than 2 distinct monkey baby HP rolls, got %', v_distinct_hp;
  end if;

  create temp table tmp_chocobo_rolls (
    stats_up integer,
    crit_delta integer
  ) on commit drop;

  for i in 1..200 loop
    v_delta := public.compute_pet_level_stat_delta_v1('chocobo', 'baby', v_user);
    insert into tmp_chocobo_rolls (stats_up, crit_delta)
    values (
      (
        select count(*)
        from jsonb_each_text(v_delta) e
        where coalesce(e.value::integer, 0) > 0
      ),
      coalesce((v_delta ->> 'critical_rate')::integer, 0)
    );
  end loop;

  select round(avg(stats_up), 2) into v_avg_stats_up from tmp_chocobo_rolls;

  if coalesce(v_avg_stats_up, 0) < 3.5 then
    raise exception 'expected chocobo baby avg stats increased >= 3.5, got %', v_avg_stats_up;
  end if;

  select round(100.0 * count(*) filter (where crit_delta = 0) / count(*), 1)
  into v_crit_zero_pct
  from tmp_chocobo_rolls;

  raise notice 'pet_level_stat_variance_v1 verify passed: % distinct HP, chocobo avg stats up %, crit zero %% %',
    v_distinct_hp, v_avg_stats_up, v_crit_zero_pct;
end;
$$;

rollback;
