begin;

alter table public.exercise_sets
  add column if not exists order_index integer;

with ranked as (
  select
    id,
    row_number() over (
      partition by workout_exercise_id
      order by set_number asc, id asc
    ) as rn
  from public.exercise_sets
)
update public.exercise_sets es
set order_index = ranked.rn
from ranked
where es.id = ranked.id
  and es.order_index is null;

alter table public.exercise_sets
  alter column order_index set not null;

create or replace function public.trg_exercise_sets_order_index()
returns trigger
language plpgsql
set search_path to 'public'
as $function$
begin
  if new.order_index is null or new.order_index < 1 then
    select coalesce(max(es.order_index), 0) + 1
    into new.order_index
    from public.exercise_sets es
    where es.workout_exercise_id = new.workout_exercise_id;
  end if;

  return new;
end;
$function$;

drop trigger if exists exercise_sets_order_index_before_insert on public.exercise_sets;

create trigger exercise_sets_order_index_before_insert
before insert on public.exercise_sets
for each row
execute function public.trg_exercise_sets_order_index();

commit;
