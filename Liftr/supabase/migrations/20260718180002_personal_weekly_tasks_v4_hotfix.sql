begin;

create or replace function public._user_tasks_weighted_menu_slots(
  p_user_id uuid,
  p_slots int default 5
)
returns table (
  slot_index int,
  category text,
  scope_activity_code text,
  scope_sport text,
  scope_muscle_primary text
)
language plpgsql
volatile
security definer
set search_path to public
as $$
declare
  v_since timestamptz := now() - interval '45 days';
  v_total int;
  v_cold boolean;
  v_alloc record;
  v_remaining int;
  v_slot int := 0;
  v_cat text;
  v_defaults text[] := array['cardio', 'strength', 'sport', 'cardio', 'strength'];
  v_i int;
begin
  select
    public._user_tasks_count_category_workouts(p_user_id, 'cardio', v_since)
    + public._user_tasks_count_category_workouts(p_user_id, 'strength', v_since)
    + public._user_tasks_count_category_workouts(p_user_id, 'sport', v_since)
  into v_total;

  v_cold := coalesce(v_total, 0) < 3;

  if v_cold then
    for v_i in 1..least(p_slots, array_length(v_defaults, 1)) loop
      v_cat := v_defaults[v_i];
      slot_index := v_i;
      category := v_cat;
      scope_activity_code := case when v_cat = 'cardio' then
        case v_i when 1 then 'walk' when 4 then 'run' else null end
      else null end;
      scope_sport := case when v_cat = 'sport' then 'football' else null end;
      scope_muscle_primary := null;
      return next;
    end loop;
    return;
  end if;

  create temp table if not exists _tmp_menu_alloc (
    category text primary key,
    base_slots int not null default 0,
    remainder numeric not null default 0
  ) on commit drop;

  truncate _tmp_menu_alloc;

  insert into _tmp_menu_alloc (category, base_slots, remainder)
  select
    cat,
    floor((cnt::numeric / v_total::numeric) * p_slots)::int,
    (cnt::numeric / v_total::numeric) * p_slots - floor((cnt::numeric / v_total::numeric) * p_slots)
  from (
    select 'cardio'::text as cat, public._user_tasks_count_category_workouts(p_user_id, 'cardio', v_since) as cnt
    union all
    select 'strength', public._user_tasks_count_category_workouts(p_user_id, 'strength', v_since)
    union all
    select 'sport', public._user_tasks_count_category_workouts(p_user_id, 'sport', v_since)
  ) x
  where cnt > 0;

  select p_slots - coalesce(sum(t.base_slots), 0) into v_remaining from _tmp_menu_alloc t;

  for v_alloc in
    select a.category
    from _tmp_menu_alloc a
    where a.remainder > 0
    order by a.remainder desc, a.category
    limit greatest(v_remaining, 0)
  loop
    update _tmp_menu_alloc t
    set base_slots = t.base_slots + 1,
        remainder = -1
    where t.category = v_alloc.category;
    v_remaining := v_remaining - 1;
  end loop;

  for v_alloc in
    select a.category, a.base_slots
    from _tmp_menu_alloc a
    where a.base_slots > 0
    order by a.category
  loop
    for v_i in 1..v_alloc.base_slots loop
      v_slot := v_slot + 1;
      slot_index := v_slot;
      category := v_alloc.category;
      if v_alloc.category = 'cardio' then
        scope_activity_code := public._user_tasks_weighted_pick_cardio_activity(p_user_id, v_since);
        scope_sport := null;
        scope_muscle_primary := null;
      elsif v_alloc.category = 'sport' then
        scope_activity_code := null;
        scope_sport := public._user_tasks_weighted_pick_sport(p_user_id, v_since);
        scope_muscle_primary := null;
      else
        scope_activity_code := null;
        scope_sport := null;
        scope_muscle_primary := public._user_tasks_weighted_pick_muscle(p_user_id, v_since);
      end if;
      return next;
    end loop;
  end loop;

  while v_slot < p_slots loop
    v_slot := v_slot + 1;
    select a.category into v_cat from _tmp_menu_alloc a order by a.base_slots desc, a.category limit 1;
    slot_index := v_slot;
    category := coalesce(v_cat, 'cardio');
    scope_activity_code := case when coalesce(v_cat, 'cardio') = 'cardio'
      then public._user_tasks_weighted_pick_cardio_activity(p_user_id, v_since) else null end;
    scope_sport := case when v_cat = 'sport'
      then public._user_tasks_weighted_pick_sport(p_user_id, v_since) else null end;
    scope_muscle_primary := case when v_cat = 'strength'
      then public._user_tasks_weighted_pick_muscle(p_user_id, v_since) else null end;
    return next;
  end loop;
end;
$$;

commit;
