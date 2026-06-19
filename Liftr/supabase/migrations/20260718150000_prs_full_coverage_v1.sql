begin;

create or replace view public.vw_user_prs as
select
  'strength'::text as kind,
  pr.user_id,
  e.name as label,
  pr.metric,
  pr.value,
  pr.achieved_at
from public.personal_records pr
join public.exercises e on e.id = pr.exercise_id
union all
select
  'cardio'::text as kind,
  er.user_id,
  er.modality as label,
  er.metric,
  er.value,
  er.achieved_at
from public.endurance_records er
union all
select
  'sport'::text as kind,
  sr.user_id,
  sr.sport as label,
  sr.metric,
  sr.value,
  sr.achieved_at
from public.sport_records sr;

create or replace function public.cardio_session_modality_key(
  p_activity_code text,
  p_modality text
)
returns text
language sql
immutable
as $$
  select coalesce(
    nullif(btrim(p_activity_code), ''),
    nullif(btrim(p_modality), ''),
    'cardio'
  );
$$;

create or replace function public.apply_cardio_session_prs(p_session_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  cs public.cardio_sessions%rowtype;
  v_user_id uuid;
  v_when timestamptz;
  v_modality text;
  v_cadence int;
  v_watts int;
  v_split500 int;
  t_cadence text;
  t_watts text;
  t_split500 text;
begin
  select * into cs from public.cardio_sessions where id = p_session_id;
  if not found then
    return;
  end if;

  select w.user_id, coalesce(w.started_at, now())
  into v_user_id, v_when
  from public.workouts w
  where w.id = cs.workout_id;

  if v_user_id is null then
    return;
  end if;

  v_modality := public.cardio_session_modality_key(cs.activity_code, cs.modality);

  if cs.distance_km is not null and cs.distance_km > 0 then
    perform public.upsert_endurance_record_max(v_user_id, v_modality, 'longest_distance_km', cs.distance_km, v_when);
  end if;

  if cs.duration_sec is not null and cs.duration_sec > 0 then
    perform public.upsert_endurance_record_max(v_user_id, v_modality, 'longest_duration_sec', cs.duration_sec, v_when);
  end if;

  if cs.avg_pace_sec_per_km is not null and cs.avg_pace_sec_per_km > 0 then
    perform public.upsert_endurance_record_min(v_user_id, v_modality, 'fastest_pace_sec_per_km', cs.avg_pace_sec_per_km, v_when);
  end if;

  if cs.max_hr is not null and cs.max_hr > 0 then
    perform public.upsert_endurance_record_max(v_user_id, v_modality, 'max_hr', cs.max_hr, v_when);
  end if;

  if cs.elevation_gain_m is not null and cs.elevation_gain_m > 0 then
    perform public.upsert_endurance_record_max(v_user_id, v_modality, 'max_elevation_m', cs.elevation_gain_m, v_when);
  end if;

  select s.stats->>'cadence_rpm',
         s.stats->>'watts_avg',
         s.stats->>'split_sec_per_500m'
  into t_cadence, t_watts, t_split500
  from public.cardio_session_stats s
  where s.session_id = cs.id;

  v_cadence := case when t_cadence is null or t_cadence = '' then null else t_cadence::int end;
  v_watts := case when t_watts is null or t_watts = '' then null else t_watts::int end;
  v_split500 := case when t_split500 is null or t_split500 = '' then null else t_split500::int end;

  if v_cadence is not null and v_cadence > 0 then
    perform public.upsert_endurance_record_max(v_user_id, v_modality, 'max_cadence_rpm', v_cadence, v_when);
  end if;

  if v_watts is not null and v_watts > 0 then
    perform public.upsert_endurance_record_max(v_user_id, v_modality, 'max_watts_avg', v_watts, v_when);
  end if;

  if v_split500 is not null and v_split500 > 0 then
    perform public.upsert_endurance_record_min(v_user_id, v_modality, 'min_split_sec_per_500m', v_split500, v_when);
  end if;
end;
$function$;

create or replace function public.apply_sport_session_prs(p_session_id bigint)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  ss public.sport_sessions%rowtype;
  v_user_id uuid;
  v_when timestamptz;
  v_sport text;
  v_sid int;
  fb_goals int; fb_assists int; fb_shots int; fb_saves int; fb_tackles int; fb_yellow int; fb_red int;
  bb_points int; bb_reb int; bb_ast int; bb_stl int; bb_blk int; bb_tov int; bb_fouls int;
  rk_sets_won int; rk_games_won int; rk_aces int; rk_df int; rk_winners int; rk_ue int; rk_bp_won int; rk_net_won int;
  vb_points int; vb_aces int; vb_blocks int; vb_digs int;
  hb_goals int; hb_assists int; hb_shots int; hb_saves int; hb_steals int; hb_blocks int;
  hk_goals int; hk_assists int; hk_sog int; hk_hits int; hk_blocks int; hk_saves int; hk_pim int;
  rb_tries int; rb_meters int; rb_tackles int; rb_offloads int; rb_turnovers int;
  hx_official int; hx_avg_hr int; hx_max_hr int;
  sk_distance numeric; sk_runs int; sk_vertical int; sk_max_speed numeric;
  cl_routes_sent int; cl_flashes int; cl_vertical int; cl_moving int;
begin
  select * into ss from public.sport_sessions where id = p_session_id;
  if not found then
    return;
  end if;

  select w.user_id into v_user_id from public.workouts w where w.id = ss.workout_id;
  if v_user_id is null then
    return;
  end if;

  v_when := coalesce(ss.updated_at, now());
  v_sport := ss.sport;
  v_sid := ss.id;

  if ss.duration_sec is not null and ss.duration_sec > 0 then
    perform public.upsert_sport_record_max(v_user_id, v_sport, 'longest_duration_sec', ss.duration_sec, v_when);
  end if;

  case lower(v_sport)
    when 'football' then
      select goals, assists, shots_on_target, saves, tackles, yellow_cards, red_cards
      into fb_goals, fb_assists, fb_shots, fb_saves, fb_tackles, fb_yellow, fb_red
      from public.football_session_stats where session_id = v_sid;

      if fb_goals is not null and fb_goals > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_goals', fb_goals, v_when); end if;
      if fb_assists is not null and fb_assists > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_assists', fb_assists, v_when); end if;
      if fb_shots is not null and fb_shots > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_shots_on_target', fb_shots, v_when); end if;
      if fb_saves is not null and fb_saves > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_saves', fb_saves, v_when); end if;
      if fb_tackles is not null and fb_tackles > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_tackles', fb_tackles, v_when); end if;
      if fb_yellow is not null and fb_yellow > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_yellow', fb_yellow, v_when); end if;
      if fb_red is not null and fb_red > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_red', fb_red, v_when); end if;

    when 'handball' then
      select goals, assists, shots_on_target, saves, steals, blocks
      into hb_goals, hb_assists, hb_shots, hb_saves, hb_steals, hb_blocks
      from public.handball_session_stats where session_id = v_sid;

      if hb_goals is not null and hb_goals > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_goals', hb_goals, v_when); end if;
      if hb_assists is not null and hb_assists > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_assists', hb_assists, v_when); end if;
      if hb_shots is not null and hb_shots > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_shots_on_target', hb_shots, v_when); end if;
      if hb_saves is not null and hb_saves > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_saves', hb_saves, v_when); end if;
      if hb_steals is not null and hb_steals > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_steals', hb_steals, v_when); end if;
      if hb_blocks is not null and hb_blocks > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_blocks', hb_blocks, v_when); end if;

    when 'hockey' then
      select goals, assists, shots_on_goal, hits, blocks, saves, penalty_minutes
      into hk_goals, hk_assists, hk_sog, hk_hits, hk_blocks, hk_saves, hk_pim
      from public.hockey_session_stats where session_id = v_sid;

      if hk_goals is not null and hk_goals > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_goals', hk_goals, v_when); end if;
      if hk_assists is not null and hk_assists > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_assists', hk_assists, v_when); end if;
      if hk_sog is not null and hk_sog > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_shots_on_goal', hk_sog, v_when); end if;
      if hk_hits is not null and hk_hits > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_hits', hk_hits, v_when); end if;
      if hk_blocks is not null and hk_blocks > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_blocks', hk_blocks, v_when); end if;
      if hk_saves is not null and hk_saves > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_saves', hk_saves, v_when); end if;
      if hk_pim is not null and hk_pim > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_penalty_minutes', hk_pim, v_when); end if;

    when 'rugby' then
      select tries, meters_gained, tackles_made, offloads, turnovers_won
      into rb_tries, rb_meters, rb_tackles, rb_offloads, rb_turnovers
      from public.rugby_session_stats where session_id = v_sid;

      if rb_tries is not null and rb_tries > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_tries', rb_tries, v_when); end if;
      if rb_meters is not null and rb_meters > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_meters_gained', rb_meters, v_when); end if;
      if rb_tackles is not null and rb_tackles > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_tackles_made', rb_tackles, v_when); end if;
      if rb_offloads is not null and rb_offloads > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_offloads', rb_offloads, v_when); end if;
      if rb_turnovers is not null and rb_turnovers > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_turnovers_won', rb_turnovers, v_when); end if;

    when 'basketball' then
      select points, rebounds, assists, steals, blocks, turnovers, fouls
      into bb_points, bb_reb, bb_ast, bb_stl, bb_blk, bb_tov, bb_fouls
      from public.basketball_session_stats where session_id = v_sid;

      if bb_points is not null and bb_points > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_points', bb_points, v_when); end if;
      if bb_reb is not null and bb_reb > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_rebounds', bb_reb, v_when); end if;
      if bb_ast is not null and bb_ast > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_assists', bb_ast, v_when); end if;
      if bb_stl is not null and bb_stl > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_steals', bb_stl, v_when); end if;
      if bb_blk is not null and bb_blk > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_blocks', bb_blk, v_when); end if;
      if bb_tov is not null and bb_tov > 0 then perform public.upsert_sport_record_min(v_user_id, v_sport, 'min_turnovers', bb_tov, v_when); end if;
      if bb_fouls is not null and bb_fouls > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_fouls', bb_fouls, v_when); end if;

    when 'padel', 'tennis', 'badminton', 'squash', 'table_tennis' then
      select sets_won, games_won, aces, double_faults, winners, unforced_errors, break_points_won, net_points_won
      into rk_sets_won, rk_games_won, rk_aces, rk_df, rk_winners, rk_ue, rk_bp_won, rk_net_won
      from public.racket_session_stats where session_id = v_sid;

      if rk_sets_won is not null and rk_sets_won > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_sets_won', rk_sets_won, v_when); end if;
      if rk_games_won is not null and rk_games_won > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_games_won', rk_games_won, v_when); end if;
      if rk_aces is not null and rk_aces > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_aces', rk_aces, v_when); end if;
      if rk_df is not null and rk_df > 0 then perform public.upsert_sport_record_min(v_user_id, v_sport, 'min_double_faults', rk_df, v_when); end if;
      if rk_winners is not null and rk_winners > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_winners', rk_winners, v_when); end if;
      if rk_ue is not null and rk_ue > 0 then perform public.upsert_sport_record_min(v_user_id, v_sport, 'min_unforced_errors', rk_ue, v_when); end if;
      if rk_bp_won is not null and rk_bp_won > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_break_points_won', rk_bp_won, v_when); end if;
      if rk_net_won is not null and rk_net_won > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_net_points_won', rk_net_won, v_when); end if;

    when 'volleyball' then
      select points, aces, blocks, digs
      into vb_points, vb_aces, vb_blocks, vb_digs
      from public.volleyball_session_stats where session_id = v_sid;

      if vb_points is not null and vb_points > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_points', vb_points, v_when); end if;
      if vb_aces is not null and vb_aces > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_aces', vb_aces, v_when); end if;
      if vb_blocks is not null and vb_blocks > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_blocks', vb_blocks, v_when); end if;
      if vb_digs is not null and vb_digs > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_digs', vb_digs, v_when); end if;

    when 'hyrox' then
      select official_time_sec, avg_hr, max_hr
      into hx_official, hx_avg_hr, hx_max_hr
      from public.hyrox_session_stats where session_id = v_sid;

      if hx_official is not null and hx_official > 0 then perform public.upsert_sport_record_min(v_user_id, v_sport, 'min_official_time_sec', hx_official, v_when); end if;
      if hx_avg_hr is not null and hx_avg_hr > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_avg_hr', hx_avg_hr, v_when); end if;
      if hx_max_hr is not null and hx_max_hr > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_hr', hx_max_hr, v_when); end if;

    when 'ski' then
      select total_distance_km, runs_count, vertical_drop_m, max_speed_kmh
      into sk_distance, sk_runs, sk_vertical, sk_max_speed
      from public.ski_session_stats where session_id = v_sid;

      if sk_distance is not null and sk_distance > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_total_distance_km', sk_distance, v_when); end if;
      if sk_runs is not null and sk_runs > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_runs_count', sk_runs, v_when); end if;
      if sk_vertical is not null and sk_vertical > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_vertical_drop_m', sk_vertical, v_when); end if;
      if sk_max_speed is not null and sk_max_speed > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_speed_kmh', sk_max_speed, v_when); end if;

    when 'climbing' then
      select routes_sent, flashes, total_vertical_m, moving_time_sec
      into cl_routes_sent, cl_flashes, cl_vertical, cl_moving
      from public.climbing_session_stats where session_id = v_sid;

      if cl_routes_sent is not null and cl_routes_sent > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_routes_sent', cl_routes_sent, v_when); end if;
      if cl_flashes is not null and cl_flashes > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_flashes', cl_flashes, v_when); end if;
      if cl_vertical is not null and cl_vertical > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_total_vertical_m', cl_vertical, v_when); end if;
      if cl_moving is not null and cl_moving > 0 then perform public.upsert_sport_record_max(v_user_id, v_sport, 'max_moving_time_sec', cl_moving, v_when); end if;

    else
      null;
  end case;
end;
$function$;

create or replace function public.trg_cardio_pr_from_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.apply_cardio_session_prs(NEW.id);
  return NEW;
end;
$function$;

create or replace function public.trg_sport_pr_from_session()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  perform public.apply_sport_session_prs(NEW.id);
  return NEW;
end;
$function$;

create or replace function public.rebuild_endurance_prs_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
begin
  delete from public.endurance_records where user_id = p_user_id;

  for r in
    select cs.id
    from public.cardio_sessions cs
    join public.workouts w on w.id = cs.workout_id
    where w.user_id = p_user_id
    order by cs.id
  loop
    perform public.apply_cardio_session_prs(r.id);
  end loop;
end;
$function$;

create or replace function public.rebuild_sport_prs_for_user(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
begin
  delete from public.sport_records where user_id = p_user_id;

  for r in
    select ss.id
    from public.sport_sessions ss
    join public.workouts w on w.id = ss.workout_id
    where w.user_id = p_user_id
    order by ss.id
  loop
    perform public.apply_sport_session_prs(r.id);
  end loop;
end;
$function$;

create or replace function public.rebuild_endurance_prs_all()
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
begin
  for r in
    select distinct w.user_id
    from public.workouts w
    where w.user_id is not null
      and w.kind::text = 'cardio'
  loop
    perform public.rebuild_endurance_prs_for_user(r.user_id);
  end loop;
end;
$function$;

create or replace function public.rebuild_sport_prs_all()
returns void
language plpgsql
security definer
set search_path = public
as $function$
declare
  r record;
begin
  for r in
    select distinct w.user_id
    from public.workouts w
    where w.user_id is not null
      and w.kind::text = 'sport'
  loop
    perform public.rebuild_sport_prs_for_user(r.user_id);
  end loop;
end;
$function$;

create or replace function public.trg_workout_pr_rebuild_on_delete()
returns trigger
language plpgsql
security definer
set search_path = public
as $function$
begin
  if OLD.user_id is null then
    return OLD;
  end if;

  if OLD.kind::text = 'strength' then
    perform public.rebuild_strength_prs_for_user(OLD.user_id);
  elsif OLD.kind::text = 'cardio' then
    perform public.rebuild_endurance_prs_for_user(OLD.user_id);
  elsif OLD.kind::text = 'sport' then
    perform public.rebuild_sport_prs_for_user(OLD.user_id);
  end if;

  return OLD;
end;
$function$;

drop trigger if exists trg_workout_pr_rebuild_on_delete on public.workouts;
create trigger trg_workout_pr_rebuild_on_delete
  after delete on public.workouts
  for each row
  execute function public.trg_workout_pr_rebuild_on_delete();

create or replace function public.get_user_prs(
  p_user_id uuid,
  p_kind text default null,
  p_search text default null
)
returns table (
  kind text,
  user_id uuid,
  label text,
  metric text,
  value double precision,
  achieved_at timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_kind text;
  v_search text;
begin
  if auth.uid() is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  if p_user_id is null then
    raise exception 'p_user_id is required' using errcode = '22023';
  end if;

  v_kind := nullif(lower(btrim(coalesce(p_kind, ''))), '');
  v_search := nullif(btrim(coalesce(p_search, '')), '');

  return query
  select
    v.kind,
    v.user_id,
    v.label,
    v.metric,
    v.value::double precision,
    v.achieved_at
  from public.vw_user_prs v
  where v.user_id = p_user_id
    and v.value > 0
    and (v_kind is null or v.kind = v_kind)
    and (
      v_search is null
      or v.label ilike '%' || v_search || '%'
      or v.metric ilike '%' || v_search || '%'
    )
  order by v.achieved_at desc nulls last;
end;
$$;

revoke all on function public.get_user_prs(uuid, text, text) from public;
grant execute on function public.get_user_prs(uuid, text, text) to authenticated;

delete from public.personal_records where value is null or value <= 0;
delete from public.endurance_records where value is null or value <= 0;
delete from public.sport_records where value is null or value <= 0;

do $cleanup$
declare
  r record;
begin
  for r in select distinct user_id from public.workouts where user_id is not null
  loop
    perform public.rebuild_strength_prs_for_user(r.user_id);
    perform public.rebuild_endurance_prs_for_user(r.user_id);
    perform public.rebuild_sport_prs_for_user(r.user_id);
  end loop;
end;
$cleanup$;

commit;
