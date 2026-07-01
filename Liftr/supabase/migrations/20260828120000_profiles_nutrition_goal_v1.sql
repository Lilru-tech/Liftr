set local check_function_bodies = off;

alter table public.profiles
  add column if not exists nutrition_goal text not null default 'maintain',
  add column if not exists nutrition_goal_rate_kg_per_week numeric(4,2) null;

alter table public.profiles drop constraint if exists profiles_nutrition_goal_chk;
alter table public.profiles
  add constraint profiles_nutrition_goal_chk
  check (nutrition_goal in ('cut', 'bulk', 'maintain', 'recomp'));

alter table public.profiles drop constraint if exists profiles_nutrition_goal_rate_chk;
alter table public.profiles
  add constraint profiles_nutrition_goal_rate_chk
  check (
    nutrition_goal_rate_kg_per_week is null
    or (nutrition_goal_rate_kg_per_week >= 0.05 and nutrition_goal_rate_kg_per_week <= 1.0)
  );

notify pgrst, 'reload schema';
