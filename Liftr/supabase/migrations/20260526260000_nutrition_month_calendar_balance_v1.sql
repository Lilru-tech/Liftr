set local check_function_bodies = off;

create or replace function public.get_nutrition_month_balance_v1(p_month date default date_trunc('month', current_date)::date)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_start date;
  v_end date;
  v_day date;
  v_rec jsonb;
  v_remaining numeric;
  v_count integer;
  v_rows jsonb := '[]'::jsonb;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  v_start := date_trunc('month', p_month)::date;
  v_end := (v_start + interval '1 month' - interval '1 day')::date;

  for v_day in
    select distinct l.log_date
    from public.nutrition_diary_logs l
    where l.user_id = v_uid
      and l.log_date between v_start and v_end
    order by 1
  loop
    select count(*)::integer
    into v_count
    from public.nutrition_diary_logs l
    where l.user_id = v_uid
      and l.log_date = v_day;

    v_rec := public.get_daily_nutrition_recommendation_v1(v_day);
    v_remaining := coalesce((v_rec->>'remaining_calories')::numeric, 0);

    v_rows := v_rows || jsonb_build_array(
      jsonb_build_object(
        'log_date', to_char(v_day, 'YYYY-MM-DD'),
        'meal_log_count', v_count,
        'remaining_calories', round(v_remaining, 1)
      )
    );
  end loop;

  return v_rows;
end;
$$;

revoke all on function public.get_nutrition_month_balance_v1(date) from public;
grant execute on function public.get_nutrition_month_balance_v1(date) to authenticated;

notify pgrst, 'reload schema';
