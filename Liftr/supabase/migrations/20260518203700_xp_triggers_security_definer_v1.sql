begin;

alter function public.apply_workout_xp(bigint)
  security definer
  set search_path to 'public';

alter function public.apply_weekly_diversity_bonus(bigint)
  security definer
  set search_path to 'public';

alter function public.trg_xp_on_workout_ins()
  security definer
  set search_path to 'public';

alter function public.trg_xp_on_workout_upd()
  security definer
  set search_path to 'public';

revoke all on function public.apply_workout_xp(bigint) from public;
revoke all on function public.apply_workout_xp(bigint) from anon;
revoke all on function public.apply_workout_xp(bigint) from authenticated;

revoke all on function public.apply_weekly_diversity_bonus(bigint) from public;
revoke all on function public.apply_weekly_diversity_bonus(bigint) from anon;
revoke all on function public.apply_weekly_diversity_bonus(bigint) from authenticated;

commit;
