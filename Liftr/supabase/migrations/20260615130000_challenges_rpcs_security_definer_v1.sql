begin;

-- list_active_challenges_v1 y get_challenge_instance_detail_v1 llaman a
-- _challenge_ensure_weekly_instances(), cuyo EXECUTE fue revocado a authenticated
-- por el db audit lockdown. Con SECURITY INVOKER toda llamada autenticada falla
-- con "permission denied for function _challenge_ensure_weekly_instances".

alter function public.list_active_challenges_v1() security definer;
alter function public.list_active_challenges_v1() set search_path to public;

alter function public.get_challenge_instance_detail_v1(uuid) security definer;
alter function public.get_challenge_instance_detail_v1(uuid) set search_path to public;

revoke all on function public.list_active_challenges_v1() from public;
revoke all on function public.list_active_challenges_v1() from anon;
grant execute on function public.list_active_challenges_v1() to authenticated;

revoke all on function public.get_challenge_instance_detail_v1(uuid) from public;
revoke all on function public.get_challenge_instance_detail_v1(uuid) from anon;
grant execute on function public.get_challenge_instance_detail_v1(uuid) to authenticated;

commit;
