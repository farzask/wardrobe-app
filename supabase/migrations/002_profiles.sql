-- 002_profiles.sql
-- parent: 001_enums.sql
-- purpose: User profile (TRD §3 profiles), auto-created on signup, plus its RLS policies.
-- down:   drop trigger on_auth_user_created on auth.users;
--         drop function fc_handle_new_user(); drop table profiles;

create table if not exists public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,

  -- Nullable on purpose. The row is created by trigger at signup, but PRD §4.1 collects gender in
  -- a separate onboarding step. `gender is null` is exactly the signal the app uses to route a new
  -- user to onboarding, so this must NOT be NOT NULL.
  gender            fc_gender,

  -- PRD §4.1: asked only when gender = male. Gates the accessory recommendation path (PRD §4.5).
  wears_accessories boolean,

  display_name      text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),

  -- Integrity for the gate: a female profile must never carry an accessory preference, or the
  -- backend's gate condition becomes ambiguous.
  constraint profiles_accessories_male_only
    check (wears_accessories is null or gender = 'male')
);

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function fc_set_updated_at();


-- Create the profile row automatically at signup. Doing this client-side instead leaves an
-- account with no profile whenever the app is killed between signup and the first write.
create or replace function public.fc_handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, new.raw_user_meta_data ->> 'display_name')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.fc_handle_new_user();


-- RLS: enabled in the SAME migration that creates the table, so no window exists in which the
-- table is queryable without policies (skills/migrations/SKILL.md §2).
alter table public.profiles enable row level security;

drop policy if exists profiles_select_own on public.profiles;
create policy profiles_select_own on public.profiles
  for select using (id = (select auth.uid()));

-- WITH CHECK, not USING — USING alone on insert does not constrain the incoming row and would let
-- a user insert a profile owned by someone else (skills/database/SKILL.md §1.3).
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own on public.profiles
  for insert with check (id = (select auth.uid()));

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own on public.profiles
  for update using (id = (select auth.uid()))
           with check (id = (select auth.uid()));

-- Delete is denied to clients on purpose: profiles are removed only by cascade from auth.users,
-- so account deletion goes through Supabase Auth rather than leaving an orphaned auth user.
-- This is a deliberate absence, documented per skills/database/SKILL.md §1.2.
