-- 004_wardrobe_items.sql
-- parent: 003_category_slots.sql
-- purpose: The digitized wardrobe (TRD §3 wardrobe_items), with the approved colour model and
--          soft delete, plus indexes and RLS.
-- down:   drop table wardrobe_items;
--
-- DEVIATIONS FROM TRD §3, both recorded in skills/README.md:
--   #4  colour is stored as a weighted palette + precomputed CIELAB, not a single `color_hex`.
--       A red-and-white striped shirt has no single dominant colour; averaging yields pink, a
--       colour the garment does not contain, which then drives the TRD §6 harmony rule.
--       `color_hex` is retained as palette[0] so the TRD contract still holds for display.
--   #7  `deleted_at` soft delete instead of a hard delete, so saved outfit history is never
--       silently mutated. PROVISIONAL — confirm before release.
-- Also: TRD §3 calls the field `thumbnail_url`; it stores an object PATH, not a URL. Signed URLs
-- expire, and a persisted expired URL is a permanently broken thumbnail. Renamed for honesty.

create table if not exists public.wardrobe_items (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references public.profiles (id) on delete cascade,

  category          fc_category not null,
  -- `style` (button-down, polo, A-line…) is open-ended by nature and is the one attribute that
  -- legitimately stays free text: no compatibility rule reads it, so drift is harmless.
  style             text,

  -- Colour ------------------------------------------------------------------
  -- Extracted by k-means over the garment's pixels, NOT by asking the vision model to name a hex.
  -- Deterministic, free, and exactly correct — the model is worse on all three counts.
  color_hex         text not null check (color_hex ~ '^#[0-9a-fA-F]{6}$'),
  color_palette     jsonb not null default '[]'::jsonb
                      check (jsonb_typeof(color_palette) = 'array'
                             and jsonb_array_length(color_palette) <= 3),
  -- CIELAB of the dominant colour, precomputed so harmony queries never convert at compare time.
  lab_l             real not null check (lab_l between 0 and 100),
  lab_a             real not null check (lab_a between -128 and 128),
  lab_b             real not null check (lab_b between -128 and 128),
  -- Human-readable names, for the UI and for the recommendation lookup tables (TRD §3, §7).
  primary_color     text not null,
  secondary_color   text,

  pattern           fc_pattern not null,
  fabric            text,
  sleeve_type       fc_sleeve_type,
  neckline          fc_neckline,
  fit               fc_fit not null,
  season            fc_season not null,
  occasion          fc_occasion not null,

  -- Storage object path: wardrobe-thumbnails/{user_id}/{item_id}.webp (TRD §4.5).
  thumbnail_path    text,

  -- Per-field confidence from the extractor, kept after review. Two uses: the review screen sorts
  -- low-confidence fields to the top (PRD §8 names that screen as the abandonment risk), and the
  -- pairing of (confidence, user correction) is the labelled data needed to ever move off the
  -- vision LLM. Nullable: hand-created items have no extraction.
  extraction_confidence jsonb,
  -- Which fields the user corrected during review. The highest-value training signal in the app,
  -- and it costs one column.
  corrected_fields  text[] not null default '{}',

  -- Written as 'pending_review' by the backend at extraction time and flipped to 'active' when the
  -- user confirms the review screen. This inverts TRD §4.7 (which has Flutter insert the row after
  -- review) and instead follows TRD §1's own recommendation that the backend persist, so the
  -- client never handles raw model output. It also makes an abandoned review a findable row rather
  -- than an orphaned storage object (see 007_storage.sql).
  status            fc_item_status not null default 'pending_review',

  deleted_at        timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

drop trigger if exists wardrobe_items_set_updated_at on public.wardrobe_items;
create trigger wardrobe_items_set_updated_at
  before update on public.wardrobe_items
  for each row execute function fc_set_updated_at();


-- Indexes ---------------------------------------------------------------------
-- Every index leads with user_id because RLS forces a user_id predicate onto every query; an index
-- without it will not be used. Every index is partial on `deleted_at is null and status='active'`
-- because BOTH predicates are on every wardrobe read (skills/database/SKILL.md §6). Any query that
-- forgets either one will both miss the index and return rows the user should not see: deleted
-- items reappearing in the grid, or half-extracted items appearing before review.

create index if not exists wardrobe_items_user_created_idx
  on public.wardrobe_items (user_id, created_at desc) where deleted_at is null and status = 'active';

create index if not exists wardrobe_items_user_category_idx
  on public.wardrobe_items (user_id, category) where deleted_at is null and status = 'active';

create index if not exists wardrobe_items_user_occasion_idx
  on public.wardrobe_items (user_id, occasion) where deleted_at is null and status = 'active';

create index if not exists wardrobe_items_user_season_idx
  on public.wardrobe_items (user_id, season) where deleted_at is null and status = 'active';


-- RLS -------------------------------------------------------------------------
alter table public.wardrobe_items enable row level security;

drop policy if exists wardrobe_items_select_own on public.wardrobe_items;
create policy wardrobe_items_select_own on public.wardrobe_items
  for select using (user_id = (select auth.uid()));

drop policy if exists wardrobe_items_insert_own on public.wardrobe_items;
create policy wardrobe_items_insert_own on public.wardrobe_items
  for insert with check (user_id = (select auth.uid()));

drop policy if exists wardrobe_items_update_own on public.wardrobe_items;
create policy wardrobe_items_update_own on public.wardrobe_items
  for update using (user_id = (select auth.uid()))
           with check (user_id = (select auth.uid()));

-- Present so the policy set is complete, but the app soft-deletes via UPDATE rather than DELETE.
-- Hard delete remains available for account-level cleanup.
drop policy if exists wardrobe_items_delete_own on public.wardrobe_items;
create policy wardrobe_items_delete_own on public.wardrobe_items
  for delete using (user_id = (select auth.uid()));
