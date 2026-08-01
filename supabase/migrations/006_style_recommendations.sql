-- 006_style_recommendations.sql
-- parent: 005_outfits.sql
-- purpose: Gender-conditional styling suggestions attached to an outfit (TRD §3, §7).
-- down:   drop table style_recommendations;

create table if not exists public.style_recommendations (
  id              uuid primary key default gen_random_uuid(),
  outfit_id       uuid not null references public.outfits (id) on delete cascade,
  type            fc_recommendation_type not null,
  suggestion_text text not null,

  -- Which lookup-table row produced this, so a curated-content change is traceable to the
  -- suggestions it generated. The tables are content, and content gets revised.
  lookup_key      text,
  created_at      timestamptz not null default now(),

  -- At most one suggestion of each type per outfit. Without this, a retried evaluation appends a
  -- second makeup suggestion and the result screen renders duplicates.
  unique (outfit_id, type)
);

create index if not exists style_recommendations_outfit_idx
  on public.style_recommendations (outfit_id);


-- RLS -------------------------------------------------------------------------
-- Ownership derives through the parent outfit; this table has no user_id of its own.
alter table public.style_recommendations enable row level security;

drop policy if exists style_recommendations_select_own on public.style_recommendations;
create policy style_recommendations_select_own on public.style_recommendations
  for select using (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  );

drop policy if exists style_recommendations_insert_own on public.style_recommendations;
create policy style_recommendations_insert_own on public.style_recommendations
  for insert with check (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  );

drop policy if exists style_recommendations_update_own on public.style_recommendations;
create policy style_recommendations_update_own on public.style_recommendations
  for update using (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  ) with check (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  );

drop policy if exists style_recommendations_delete_own on public.style_recommendations;
create policy style_recommendations_delete_own on public.style_recommendations
  for delete using (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  );

-- NOTE ON THE GATE (PRD §4.5): nothing here prevents a male-opted-out user's row from existing.
-- The gate is enforced server-side in the recommendation engine, which reads profiles.gender and
-- profiles.wears_accessories directly. Enforcing it as a DB constraint was considered and rejected:
-- it would require a cross-table check on every insert, and the gate is a product rule that will
-- change. The validation matrix asserts the gate at the API boundary instead
-- (skills/independent-validation/SKILL.md §4).
