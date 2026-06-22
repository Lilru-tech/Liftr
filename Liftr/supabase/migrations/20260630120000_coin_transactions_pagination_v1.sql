begin;

drop function if exists public.list_my_coin_transactions_v1(integer);

create or replace function public.list_my_coin_transactions_v1(
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  amount integer,
  action_type text,
  reference_id uuid,
  created_at timestamptz
)
language plpgsql
stable
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  v_limit integer;
  v_offset integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  v_limit := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset := greatest(coalesce(p_offset, 0), 0);

  return query
  select
    ct.id,
    ct.amount,
    ct.action_type,
    ct.reference_id,
    ct.created_at
  from public.coin_transactions ct
  where ct.user_id = v_uid
  order by ct.created_at desc, ct.id desc
  limit v_limit
  offset v_offset;
end;
$$;

revoke all on function public.list_my_coin_transactions_v1(integer, integer) from public;
revoke all on function public.list_my_coin_transactions_v1(integer, integer) from anon;
grant execute on function public.list_my_coin_transactions_v1(integer, integer) to authenticated;

commit;
