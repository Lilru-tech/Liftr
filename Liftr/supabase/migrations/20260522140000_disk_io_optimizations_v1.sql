begin;

set local check_function_bodies = off;

create or replace function public._liftr_rls_expr_stable_uid(p_expr text)
  returns text
  language sql
  immutable
as $$
  select case
    when p_expr is null then null
    else regexp_replace(
      regexp_replace(
        regexp_replace(p_expr, '\(select auth\.uid\(\)\)', '___STABLE_UID___', 'gi'),
        'auth\.uid\(\)',
        '(select auth.uid())',
        'gi'
      ),
      '___STABLE_UID___',
      '(select auth.uid())',
      'gi'
    )
  end;
$$;

do $$
declare
  pol record;
  new_qual text;
  new_wc text;
begin
  for pol in
    select
      schemaname,
      tablename,
      policyname,
      qual::text as qual,
      with_check::text as wc
    from pg_policies
    where schemaname = 'public'
      and (
        (qual is not null and qual::text ~ 'auth\.uid\(\)')
        or (with_check is not null and with_check::text ~ 'auth\.uid\(\)')
      )
  loop
    new_qual := public._liftr_rls_expr_stable_uid(pol.qual);
    new_wc := public._liftr_rls_expr_stable_uid(pol.wc);

    if new_qual is not null and new_wc is not null then
      execute format(
        'alter policy %I on %I.%I using (%s) with check (%s)',
        pol.policyname,
        pol.schemaname,
        pol.tablename,
        new_qual,
        new_wc
      );
    elsif new_qual is not null then
      execute format(
        'alter policy %I on %I.%I using (%s)',
        pol.policyname,
        pol.schemaname,
        pol.tablename,
        new_qual
      );
    elsif new_wc is not null then
      execute format(
        'alter policy %I on %I.%I with check (%s)',
        pol.policyname,
        pol.schemaname,
        pol.tablename,
        new_wc
      );
    end if;
  end loop;
end
$$;

drop function if exists public._liftr_rls_expr_stable_uid(text);

drop policy if exists "Users can update their own notifications" on public.notifications;

create index if not exists territory_cells_last_workout_id_idx
  on public.territory_cells (last_workout_id);

create index if not exists follows_followee_id_idx
  on public.follows (followee_id);

create index if not exists workout_participants_workout_id_idx
  on public.workout_participants (workout_id);

create index if not exists messages_conversation_id_idx
  on public.messages (conversation_id);

create index if not exists segment_efforts_segment_id_idx
  on public.segment_efforts (segment_id);

delete from net._http_response
where created < now() - interval '7 days';

create or replace function public.get_territory_map_v1 (
  p_min_lat double precision,
  p_min_lon double precision,
  p_max_lat double precision,
  p_max_lon double precision,
  p_limit integer default 500
)
  returns table (
    cell_id text,
    cell_geojson jsonb,
    owner_user_id uuid,
    owner_username text,
    owner_avatar_url text,
    last_workout_id bigint,
    captured_at timestamptz,
    is_mine boolean
  )
  language sql
  stable
  security definer
  set search_path = public
as $$
  with
  effective_limit as (
    select greatest(least(coalesce(p_limit, 500), 5000), 1) as n
  ),
  bounds as (
    select
      p_min_lat <= -90
        and p_min_lon <= -180
        and p_max_lat >= 90
        and p_max_lon >= 180 as fetch_all,
      case
        when p_min_lat <= -90
          and p_min_lon <= -180
          and p_max_lat >= 90
          and p_max_lon >= 180
        then null::geography
        else st_makeenvelope(
          least(p_min_lon, p_max_lon),
          least(p_min_lat, p_max_lat),
          greatest(p_min_lon, p_max_lon),
          greatest(p_min_lat, p_max_lat),
          4326
        )::geography
      end as geog
  ),
  spatial_candidates as materialized (
    select
      tc.cell_id,
      tc.cell_geog,
      tc.owner_user_id,
      tc.last_workout_id,
      tc.captured_at,
      ((tc.owner_user_id = auth.uid ()) is true) as is_mine
    from public.territory_cells tc
      cross join bounds b
    where b.fetch_all or st_intersects(tc.cell_geog, b.geog)
  ),
  other_route_groups as (
    select
      sc.owner_user_id,
      coalesce(sc.last_workout_id::text, sc.cell_id) as route_key,
      max(sc.captured_at) as route_captured_at,
      count(*)::integer as route_size
    from spatial_candidates sc
    where not sc.is_mine
    group by sc.owner_user_id, coalesce(sc.last_workout_id::text, sc.cell_id)
  ),
  other_route_groups_ranked as (
    select
      org.*,
      row_number() over (
        partition by org.owner_user_id
        order by org.route_captured_at desc, org.route_key
      ) as owner_route_rank
    from other_route_groups org
  ),
  other_route_groups_budgeted as (
    select
      orgr.*,
      sum(orgr.route_size) over (
        order by orgr.owner_route_rank, orgr.route_captured_at desc, orgr.owner_user_id, orgr.route_key
      ) as running_cells
    from other_route_groups_ranked orgr
  ),
  selected_other_route_groups as (
    select orgb.owner_user_id, orgb.route_key
    from other_route_groups_budgeted orgb
      cross join effective_limit el
    where orgb.running_cells <= el.n
  ),
  selected_others as (
    select
      sc.cell_id,
      sc.cell_geog,
      sc.owner_user_id,
      sc.last_workout_id,
      sc.captured_at,
      sc.is_mine
    from spatial_candidates sc
      join selected_other_route_groups sorg
        on sorg.owner_user_id = sc.owner_user_id
       and sorg.route_key = coalesce(sc.last_workout_id::text, sc.cell_id)
    where not sc.is_mine
  ),
  selected_others_count as (
    select count(*)::integer as n
    from selected_others
  ),
  mine_ranked as (
    select
      sc.cell_id,
      sc.cell_geog,
      sc.owner_user_id,
      sc.last_workout_id,
      sc.captured_at,
      sc.is_mine,
      row_number() over (
        order by sc.captured_at desc, sc.cell_id
      ) as rank_in_budget
    from spatial_candidates sc
    where sc.is_mine
  ),
  selected_mine as (
    select
      m.cell_id,
      m.cell_geog,
      m.owner_user_id,
      m.last_workout_id,
      m.captured_at,
      m.is_mine
    from mine_ranked m
      cross join selected_others_count soc
      cross join effective_limit el
    where m.rank_in_budget <= greatest(el.n - soc.n, 0)
  ),
  selected_cells as (
    select * from selected_others
    union all
    select * from selected_mine
  )
  select
    sc.cell_id,
    st_asgeojson(sc.cell_geog::geometry)::jsonb as cell_geojson,
    sc.owner_user_id,
    p.username as owner_username,
    p.avatar_url as owner_avatar_url,
    sc.last_workout_id,
    sc.captured_at,
    sc.is_mine
  from selected_cells sc
    left join public.profiles p on p.user_id = sc.owner_user_id
  order by sc.is_mine asc, sc.captured_at desc, sc.cell_id;
$$;

create or replace function public.get_home_feed_page_v1(
  p_page integer default 0,
  p_page_size integer default 30,
  p_kind text default null
)
  returns jsonb
  language plpgsql
  stable
  security definer
  set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_page integer := greatest(coalesce(p_page, 0), 0);
  v_size integer := greatest(least(coalesce(p_page_size, 30), 50), 1);
  v_kind text := nullif(lower(trim(coalesce(p_kind, ''))), '');
  v_followees uuid[];
  v_participant_ids bigint[];
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  select coalesce(array_agg(f.followee_id), '{}'::uuid[])
  into v_followees
  from public.follows f
  where f.follower_id = v_uid;

  select coalesce(array_agg(distinct wp.workout_id), '{}'::bigint[])
  into v_participant_ids
  from public.workout_participants wp
  where wp.user_id = v_uid;

  return (
    with feed_workouts as (
      select
        w.id,
        w.user_id,
        w.kind::text as kind,
        w.title,
        w.started_at,
        w.ended_at,
        w.state::text as state,
        w.calories_kcal,
        (
          select cs.activity_code
          from public.cardio_sessions cs
          where cs.workout_id = w.id
          limit 1
        ) as cardio_activity_code,
        (
          select ss.sport::text
          from public.sport_sessions ss
          where ss.workout_id = w.id
          limit 1
        ) as sport
      from public.workouts w
      where (
        w.user_id = v_uid
        or w.id = any(v_participant_ids)
        or (w.user_id = any(v_followees) and w.state is distinct from 'planned')
      )
      and (v_kind is null or lower(w.kind::text) = v_kind)
      order by w.started_at desc nulls last, w.id desc
      offset v_page * v_size
      limit v_size
    ),
    page_ids as (
      select coalesce(array_agg(fw.id), '{}'::bigint[]) as ids
      from feed_workouts fw
    )
    select jsonb_build_object(
      'workouts',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'id', fw.id,
              'user_id', fw.user_id,
              'kind', fw.kind,
              'title', fw.title,
              'started_at', fw.started_at,
              'ended_at', fw.ended_at,
              'state', fw.state,
              'calories_kcal', fw.calories_kcal,
              'sport_sessions',
                case when fw.sport is null then '[]'::jsonb
                else jsonb_build_array(jsonb_build_object('sport', fw.sport))
                end,
              'cardio_sessions',
                case when fw.cardio_activity_code is null then '[]'::jsonb
                else jsonb_build_array(jsonb_build_object('activity_code', fw.cardio_activity_code))
                end
            )
            order by fw.started_at desc nulls last, fw.id desc
          )
          from feed_workouts fw
        ),
        '[]'::jsonb
      ),
      'scores',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'workout_id', s.workout_id,
              'score', s.total_score
            )
          )
          from (
            select ws.workout_id, sum(ws.score) as total_score
            from public.workout_scores ws
            cross join page_ids pi
            where ws.workout_id = any(pi.ids)
            group by ws.workout_id
          ) s
        ),
        '[]'::jsonb
      ),
      'likes',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'workout_id', wl.workout_id,
              'user_id', wl.user_id
            )
          )
          from public.workout_likes wl
          cross join page_ids pi
          where wl.workout_id = any(pi.ids)
        ),
        '[]'::jsonb
      ),
      'participants',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'workout_id', wp.workout_id,
              'user_id', wp.user_id
            )
          )
          from public.workout_participants wp
          cross join page_ids pi
          where wp.workout_id = any(pi.ids)
        ),
        '[]'::jsonb
      )
    )
  );
end;
$$;

revoke all on function public.get_home_feed_page_v1(integer, integer, text) from public;
grant execute on function public.get_home_feed_page_v1(integer, integer, text)
  to authenticated, service_role;

commit;
