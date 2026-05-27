set local check_function_bodies = off;

create table if not exists public.user_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  status text not null,
  provider text not null,
  original_transaction_id text not null,
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint user_subscriptions_user_id_key unique (user_id),
  constraint user_subscriptions_original_transaction_id_key unique (original_transaction_id),
  constraint user_subscriptions_provider_check check (provider in ('apple', 'google')),
  constraint user_subscriptions_status_check check (
    status in ('active', 'trialing', 'canceled', 'expired')
  )
);

create index if not exists user_subscriptions_expires_at_idx
  on public.user_subscriptions (expires_at desc);

alter table public.user_subscriptions enable row level security;

drop policy if exists user_subscriptions_select_own on public.user_subscriptions;
create policy user_subscriptions_select_own
  on public.user_subscriptions
  for select
  to authenticated
  using (user_id = (select auth.uid()));

revoke insert, update, delete on public.user_subscriptions from anon, authenticated;
grant select on public.user_subscriptions to authenticated;

create or replace function public.touch_user_subscription_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists user_subscriptions_set_updated_at on public.user_subscriptions;
create trigger user_subscriptions_set_updated_at
before update on public.user_subscriptions
for each row
execute function public.touch_user_subscription_updated_at();

create or replace function public.get_user_premium_status_v1()
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_uid uuid;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  return exists (
    select 1
    from public.user_subscriptions s
    where s.user_id = v_uid
      and s.status in ('active', 'trialing')
      and s.expires_at > now()
  );
end;
$$;

revoke all on function public.get_user_premium_status_v1() from public;
grant execute on function public.get_user_premium_status_v1() to authenticated;
