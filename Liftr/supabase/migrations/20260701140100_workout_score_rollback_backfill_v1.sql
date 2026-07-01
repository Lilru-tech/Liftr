begin;

do $$
declare
  r record;
begin
  for r in
    select w.id
    from public.workouts w
    where w.state = 'published'
    order by w.id
  loop
    perform public.upsert_workout_score_v2(r.id);

    insert into public.score_recalc_audit(source, workout_id, extra)
    values ('migration:workout_score_rollback_refine_v1', r.id, null);
  end loop;
end;
$$;

commit;
