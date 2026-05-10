begin;

alter table public.exercise_sets drop constraint if exists exercise_sets_weight_segments_len_check;
alter table public.strength_routine_sets drop constraint if exists strength_routine_sets_weight_segments_len_check;

alter table public.exercise_sets drop constraint if exists exercise_sets_weigth_segments_len_chk;
alter table public.exercise_sets drop constraint if exists exercise_sets_weight_segments_len_chk;
alter table public.exercise_sets
  add constraint exercise_sets_weight_segments_len_chk
  check (
    weight_segments is null
    or (
      jsonb_typeof(weight_segments) = 'array'
      and jsonb_array_length(weight_segments) >= 2
    )
  );

alter table public.strength_routine_sets drop constraint if exists strength_routine_sets_weigth_segments_len_chk;
alter table public.strength_routine_sets drop constraint if exists strength_routine_sets_weight_segments_len_chk;
alter table public.strength_routine_sets
  add constraint strength_routine_sets_weight_segments_len_chk
  check (
    weight_segments is null
    or (
      jsonb_typeof(weight_segments) = 'array'
      and jsonb_array_length(weight_segments) >= 2
    )
  );

commit;
