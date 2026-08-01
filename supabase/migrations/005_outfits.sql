-- 005_outfits.sql
-- parent: 004_wardrobe_items.sql
-- purpose: Saved outfits and their item membership (TRD §3 outfits, outfit_items).
-- down:   drop table outfit_items; drop table outfits;

create table if not exists public.outfits (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references public.profiles (id) on delete cascade,
  name                text,
  occasion            fc_occasion not null,
  compatibility_score int not null check (compatibility_score between 0 and 100),

  -- TRD §3 calls this `ai_feedback`. It is produced by a deterministic rule engine, not a model,
  -- so the name is misleading; kept for contract compatibility with the TRD.
  ai_feedback         text,
  -- The item the engine identified as the weak link (PRD §4.4). Nullable: a good outfit has none.
  weak_item_id        uuid references public.wardrobe_items (id) on delete set null,

  source              fc_outfit_source not null,

  -- TRD §12 states plainly that the initial rule weights are a first draft needing tuning. Pinning
  -- the ruleset version to each row is what stops a later re-tune from silently changing the
  -- meaning of every historical score. See skills/backend/SKILL.md §3.
  ruleset_version     text not null,

  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

drop trigger if exists outfits_set_updated_at on public.outfits;
create trigger outfits_set_updated_at
  before update on public.outfits
  for each row execute function fc_set_updated_at();

create index if not exists outfits_user_created_idx
  on public.outfits (user_id, created_at desc);


-- Join table ------------------------------------------------------------------
-- TRD §3 defines this with no primary key. Without one the same item can be added to an outfit
-- twice and the compatibility engine scores a garment against itself, producing a perfect edge and
-- inflating the outfit score. The composite PK is the fix.
create table if not exists public.outfit_items (
  outfit_id        uuid not null references public.outfits (id) on delete cascade,
  wardrobe_item_id uuid not null references public.wardrobe_items (id) on delete restrict,
  primary key (outfit_id, wardrobe_item_id)
);

-- ON DELETE RESTRICT above pairs with wardrobe_items.deleted_at (issue #7): the app soft-deletes,
-- so this FK never actually fires in normal use. It exists as a backstop — if someone hard-deletes
-- an item that a saved outfit references, the delete is refused rather than silently rewriting the
-- user's outfit history.

create index if not exists outfit_items_outfit_idx
  on public.outfit_items (outfit_id);

-- Serves "is this item used in any outfit?", checked before offering a hard delete.
create index if not exists outfit_items_item_idx
  on public.outfit_items (wardrobe_item_id);


-- RLS -------------------------------------------------------------------------
alter table public.outfits enable row level security;

drop policy if exists outfits_select_own on public.outfits;
create policy outfits_select_own on public.outfits
  for select using (user_id = (select auth.uid()));

drop policy if exists outfits_insert_own on public.outfits;
create policy outfits_insert_own on public.outfits
  for insert with check (user_id = (select auth.uid()));

drop policy if exists outfits_update_own on public.outfits;
create policy outfits_update_own on public.outfits
  for update using (user_id = (select auth.uid()))
           with check (user_id = (select auth.uid()));

drop policy if exists outfits_delete_own on public.outfits;
create policy outfits_delete_own on public.outfits
  for delete using (user_id = (select auth.uid()));


-- outfit_items carries no user_id of its own, so ownership is derived through the parent outfit.
-- Both sides must be checked on insert: without the second EXISTS, a user could attach ANOTHER
-- user's wardrobe item to their own outfit and read its attributes back through the join.
alter table public.outfit_items enable row level security;

drop policy if exists outfit_items_select_own on public.outfit_items;
create policy outfit_items_select_own on public.outfit_items
  for select using (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  );

drop policy if exists outfit_items_insert_own on public.outfit_items;
create policy outfit_items_insert_own on public.outfit_items
  for insert with check (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
    and
    exists (select 1 from public.wardrobe_items w
             where w.id = wardrobe_item_id and w.user_id = (select auth.uid()))
  );

drop policy if exists outfit_items_update_own on public.outfit_items;
create policy outfit_items_update_own on public.outfit_items
  for update using (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  ) with check (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
    and
    exists (select 1 from public.wardrobe_items w
             where w.id = wardrobe_item_id and w.user_id = (select auth.uid()))
  );

drop policy if exists outfit_items_delete_own on public.outfit_items;
create policy outfit_items_delete_own on public.outfit_items
  for delete using (
    exists (select 1 from public.outfits o
             where o.id = outfit_id and o.user_id = (select auth.uid()))
  );
