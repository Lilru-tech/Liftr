-- Hyrox workout routine templates (parity with strength_routine_*).
-- Apply via Supabase CLI or SQL editor.

create table if not exists public.hyrox_routine_folders (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  sort_order int not null default 0,
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

create table if not exists public.hyrox_routines (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users (id) on delete cascade,
  name text not null,
  folder_id bigint references public.hyrox_routine_folders (id) on delete set null,
  sort_order int not null default 0,
  content_hash text,
  division text,
  category text,
  age_group text,
  official_time_sec int,
  penalty_time_sec int,
  no_reps int,
  rank_overall int,
  rank_category int,
  avg_hr int,
  max_hr int,
  updated_at timestamptz default now(),
  created_at timestamptz default now()
);

create table if not exists public.hyrox_routine_exercises (
  id bigint generated always as identity primary key,
  routine_id bigint not null references public.hyrox_routines (id) on delete cascade,
  exercise_code text not null,
  exercise_order int not null,
  distance_m int,
  reps int,
  weight_kg numeric,
  duration_sec int,
  height_cm int,
  implement_count int,
  notes text,
  exercise_display_name text
);

create index if not exists idx_hyrox_routine_folders_user_sort
  on public.hyrox_routine_folders (user_id, sort_order);

create index if not exists idx_hyrox_routines_user_folder_sort
  on public.hyrox_routines (user_id, folder_id, sort_order);

create index if not exists idx_hyrox_routine_exercises_routine_order
  on public.hyrox_routine_exercises (routine_id, exercise_order);

alter table public.hyrox_routine_folders enable row level security;
alter table public.hyrox_routines enable row level security;
alter table public.hyrox_routine_exercises enable row level security;

-- Folders: own rows only
create policy "hyrox_routine_folders_select_own"
  on public.hyrox_routine_folders for select
  using (auth.uid() = user_id);

create policy "hyrox_routine_folders_insert_own"
  on public.hyrox_routine_folders for insert
  with check (auth.uid() = user_id);

create policy "hyrox_routine_folders_update_own"
  on public.hyrox_routine_folders for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "hyrox_routine_folders_delete_own"
  on public.hyrox_routine_folders for delete
  using (auth.uid() = user_id);

-- Routines: own rows only
create policy "hyrox_routines_select_own"
  on public.hyrox_routines for select
  using (auth.uid() = user_id);

create policy "hyrox_routines_insert_own"
  on public.hyrox_routines for insert
  with check (auth.uid() = user_id);

create policy "hyrox_routines_update_own"
  on public.hyrox_routines for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "hyrox_routines_delete_own"
  on public.hyrox_routines for delete
  using (auth.uid() = user_id);

-- Exercises: via parent routine ownership
create policy "hyrox_routine_exercises_select_own"
  on public.hyrox_routine_exercises for select
  using (
    exists (
      select 1 from public.hyrox_routines r
      where r.id = routine_id and r.user_id = auth.uid()
    )
  );

create policy "hyrox_routine_exercises_insert_own"
  on public.hyrox_routine_exercises for insert
  with check (
    exists (
      select 1 from public.hyrox_routines r
      where r.id = routine_id and r.user_id = auth.uid()
    )
  );

create policy "hyrox_routine_exercises_update_own"
  on public.hyrox_routine_exercises for update
  using (
    exists (
      select 1 from public.hyrox_routines r
      where r.id = routine_id and r.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.hyrox_routines r
      where r.id = routine_id and r.user_id = auth.uid()
    )
  );

create policy "hyrox_routine_exercises_delete_own"
  on public.hyrox_routine_exercises for delete
  using (
    exists (
      select 1 from public.hyrox_routines r
      where r.id = routine_id and r.user_id = auth.uid()
    )
  );
