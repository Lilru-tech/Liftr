do $$
declare
  v_user uuid;
  v_slot record;
  v_cardio int := 0;
  v_sport int := 0;
  v_strength int := 0;
  v_rendered text;
  v_template public.task_templates;
  v_eligible boolean;
begin
  select public._user_tasks_render_copy(
    'Rack up {value} min of Hyrox',
    'hyrox_weekly_minutes',
    90,
    null
  ) into v_rendered;

  if v_rendered not like '%90%' then
    raise exception 'hyrox_weekly_minutes format should show 90, got %', v_rendered;
  end if;

  select public._user_tasks_render_copy(
    'Send {value} routes',
    'routes_sent',
    5,
    null
  ) into v_rendered;

  if v_rendered not like '%5%' then
    raise exception 'routes_sent format should show 5, got %', v_rendered;
  end if;

  select user_id into v_user from public.profiles where username = 'Lilru' limit 1;

  if v_user is not null then
    for v_slot in
      select * from public._user_tasks_weighted_menu_slots(v_user, 5)
      order by slot_index
    loop
      if v_slot.category = 'cardio' then
        v_cardio := v_cardio + 1;
      elsif v_slot.category = 'sport' then
        v_sport := v_sport + 1;
      elsif v_slot.category = 'strength' then
        v_strength := v_strength + 1;
      end if;
    end loop;

    if v_cardio + v_sport + v_strength <> 5 then
      raise exception 'Lilru slot allocation should sum to 5, got %/%/%',
        v_cardio, v_sport, v_strength;
    end if;

    if v_cardio < 2 then
      raise warning 'Lilru expected ~3 cardio slots, got %', v_cardio;
    end if;

    select t.* into v_template
    from public.task_templates t
    where t.code = 'sport_hyrox_weekly_stretch' and t.is_active;

    if v_template.id is not null then
      v_eligible := public._user_tasks_template_is_eligible(
        v_user, v_template, now() - interval '45 days'
      );
      if not v_eligible then
        raise warning 'hyrox weekly template not eligible for Lilru (may lack history)';
      end if;
    end if;

    select t.* into v_template
    from public.task_templates t
    where t.code = 'sport_padel_duration_beginner' and t.is_active;

    if v_template.id is null then
      select t.* into v_template
      from public.task_templates t
      where t.scope_sport = 'padel' and t.is_active
      limit 1;
    end if;

    if v_template.id is null then
      raise exception 'padel template missing after v4 migration';
    end if;

    perform public._user_tasks_ensure_weekly_for_user(v_user);
  end if;

  raise notice 'personal_weekly_tasks_v4 verify ok';
end;
$$;
