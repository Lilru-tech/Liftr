do $$
declare
  v_volume numeric;
begin
  select total_volume_kg
  into v_volume
  from public.vw_workout_volume
  where workout_id = 2145;

  if v_volume is null then
    raise exception 'workout 2145 not found in vw_workout_volume';
  end if;

  if v_volume <> 16540.000 then
    raise exception 'workout 2145 volume expected 16540.000, got %', v_volume;
  end if;
end;
$$;

select
  workout_id,
  total_volume_kg
from public.vw_workout_volume
where workout_id = 2145;
