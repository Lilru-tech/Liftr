do $$
declare
  v_user uuid;
  v_rendered text;
begin
  select public._user_tasks_render_copy(
    'Rack up {value} min playing',
    'sport_weekly_minutes',
    218,
    null
  ) into v_rendered;

  if v_rendered not like '%218%' then
    raise exception 'sport_weekly_minutes format should show 218, got %', v_rendered;
  end if;

  select user_id into v_user from public.profiles where username = 'Lilru' limit 1;
  if v_user is not null then
  perform public._user_tasks_ensure_weekly_for_user(v_user);
  end if;

  raise notice 'personal_weekly_tasks_v3 verify ok';
end;
$$;
