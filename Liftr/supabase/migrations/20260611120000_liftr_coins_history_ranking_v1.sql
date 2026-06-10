begin;

create or replace function public.list_my_coin_transactions_v1(p_limit integer default 20)
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
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  return query
  select
    ct.id,
    ct.amount,
    ct.action_type,
    ct.reference_id,
    ct.created_at
  from public.coin_transactions ct
  where ct.user_id = v_uid
  order by ct.created_at desc
  limit least(greatest(coalesce(p_limit, 20), 1), 50);
end;
$$;

create or replace function public.clear_my_coin_history_v1()
returns integer
language plpgsql
security definer
set search_path to public
as $$
declare
  v_uid uuid := auth.uid();
  v_deleted integer;
begin
  if v_uid is null then
    raise exception 'not_authenticated';
  end if;

  delete from public.coin_transactions
  where user_id = v_uid;

  get diagnostics v_deleted = row_count;
  return v_deleted;
end;
$$;

create or replace function public.get_coins_leaderboard_v1(
  p_scope text,
  p_limit integer default 100,
  p_sex text default null,
  p_age_band text default null
)
returns table (
  rank integer,
  user_id uuid,
  username text,
  avatar_url text,
  coins_balance integer
)
language plpgsql
stable
security definer
set search_path to public
as $$
begin
  return query
  with scoped as (
    select
      pr.user_id as uid,
      pr.coins_balance as bal
    from public.profiles pr
    where pr.coins_balance > 0
      and (p_sex is null or p_sex = '' or pr.sex = p_sex::public.sex)
      and (
        p_age_band is null or p_age_band = ''
        or (
          case p_age_band
            when '18-24' then extract(year from age(current_date, pr.date_of_birth)) between 18 and 24
            when '25-34' then extract(year from age(current_date, pr.date_of_birth)) between 25 and 34
            when '35-44' then extract(year from age(current_date, pr.date_of_birth)) between 35 and 44
            when '45-54' then extract(year from age(current_date, pr.date_of_birth)) between 45 and 54
            when '55+' then extract(year from age(current_date, pr.date_of_birth)) >= 55
            else true
          end
        )
      )
      and (
        coalesce(p_scope, 'global') = 'global'
        or pr.user_id = auth.uid()
        or exists (
          select 1
          from public.follows f
          where f.follower_id = auth.uid()
            and f.followee_id = pr.user_id
        )
      )
  ),
  ordered as (
    select
      s.uid,
      s.bal,
      row_number() over (order by s.bal desc, s.uid) as rnk
    from scoped s
  )
  select
    o.rnk::integer as rank,
    o.uid as user_id,
    pr.username,
    pr.avatar_url,
    o.bal as coins_balance
  from ordered o
  inner join public.profiles pr on pr.user_id = o.uid
  where o.rnk <= greatest(1, coalesce(p_limit, 100))
  order by o.rnk;
end;
$$;

revoke all on function public.list_my_coin_transactions_v1(integer) from public;
revoke all on function public.list_my_coin_transactions_v1(integer) from anon;
grant execute on function public.list_my_coin_transactions_v1(integer) to authenticated;

revoke all on function public.clear_my_coin_history_v1() from public;
revoke all on function public.clear_my_coin_history_v1() from anon;
grant execute on function public.clear_my_coin_history_v1() to authenticated;

revoke all on function public.get_coins_leaderboard_v1(text, integer, text, text) from public;
revoke all on function public.get_coins_leaderboard_v1(text, integer, text, text) from anon;
grant execute on function public.get_coins_leaderboard_v1(text, integer, text, text) to authenticated;

commit;
