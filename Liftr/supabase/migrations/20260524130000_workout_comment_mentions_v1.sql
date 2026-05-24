set local check_function_bodies = off;

alter table public.workout_comments
  add column if not exists mentioned_user_ids uuid[] not null default '{}';

alter table public.user_notification_settings
  add column if not exists push_comment_mention boolean not null default true;

create or replace function public.wc_validate_mentioned_user_ids()
returns trigger
language plpgsql
as $$
declare
  v_uid uuid;
  v_count int;
begin
  if new.mentioned_user_ids is null then
    new.mentioned_user_ids := '{}'::uuid[];
  end if;

  select coalesce(array_length(new.mentioned_user_ids, 1), 0)
  into v_count;

  if v_count > 10 then
    raise exception 'too many mentions (max 10)';
  end if;

  if new.user_id = any (new.mentioned_user_ids) then
    raise exception 'cannot mention yourself';
  end if;

  foreach v_uid in array new.mentioned_user_ids
  loop
    if not exists (
      select 1
      from public.follows f
      where f.follower_id = new.user_id
        and f.followee_id = v_uid
    ) then
      raise exception 'mentioned user must be someone you follow';
    end if;
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_wc_validate_mentioned_user_ids on public.workout_comments;

create trigger trg_wc_validate_mentioned_user_ids
before insert or update of mentioned_user_ids, user_id
on public.workout_comments
for each row
execute function public.wc_validate_mentioned_user_ids();

create or replace function public.notify_comment_mentions()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_workout_owner uuid;
  v_parent_author uuid;
  v_commenter_name text;
  v_title text;
  v_body text;
  v_uid uuid;
begin
  if new.mentioned_user_ids is null or cardinality(new.mentioned_user_ids) = 0 then
    return new;
  end if;

  select w.user_id
  into v_workout_owner
  from public.workouts w
  where w.id = new.workout_id;

  if new.parent_id is not null then
    select c.user_id
    into v_parent_author
    from public.workout_comments c
    where c.id = new.parent_id;
  end if;

  select username
  into v_commenter_name
  from public.profiles
  where user_id = new.user_id;

  if v_commenter_name is null then
    v_commenter_name := 'Someone';
  end if;

  v_title := 'You were mentioned';
  v_body := v_commenter_name || ' mentioned you in a comment.';

  for v_uid in
    select distinct x
    from unnest(new.mentioned_user_ids) as x
  loop
    if v_uid is null or v_uid = new.user_id then
      continue;
    end if;

    if new.parent_id is null and v_uid = v_workout_owner then
      continue;
    end if;

    if new.parent_id is not null and v_uid = v_parent_author then
      continue;
    end if;

    perform public.create_notification(
      v_uid,
      'comment_mention',
      v_title,
      v_body,
      jsonb_build_object(
        'workout_id', new.workout_id::text,
        'comment_id', new.id::text,
        'commenter_id', new.user_id::text,
        'owner_id', coalesce(v_workout_owner::text, '')
      )
    );
  end loop;

  return new;
end;
$$;

drop trigger if exists trg_notify_comment_mentions on public.workout_comments;

create trigger trg_notify_comment_mentions
after insert on public.workout_comments
for each row
execute function public.notify_comment_mentions();
