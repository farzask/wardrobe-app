-- 001_enums.sql
-- parent: (root)
-- purpose: Closed vocabularies shared by the database, the Flutter client, and the Python backend.
-- down:   drop type fc_recommendation_type, fc_outfit_source, fc_slot, fc_neckline,
--         fc_sleeve_type, fc_fit, fc_season, fc_pattern, fc_occasion, fc_category, fc_gender;
--
-- NOTE ON TRANSACTIONS: the Supabase CLI applies each migration file atomically, so these files
-- deliberately contain no explicit BEGIN/COMMIT. Adding one conflicts with the wrapper. Verify this
-- on first `supabase db push` (see supabase/SETUP.md, step 5) rather than trusting this comment.
--
-- NOTE ON ENUM CHANGES: `ALTER TYPE ... ADD VALUE` cannot be used in the same transaction that then
-- uses the new value. Enum additions therefore get their own migration file, never bundled with a
-- migration that reads the new value. See skills/migrations/SKILL.md §2.

-- CREATE TYPE has no IF NOT EXISTS, so each type is guarded for re-runnability.

do $$ begin
  create type fc_gender as enum ('male', 'female');
exception when duplicate_object then null; end $$;

-- Decision: "Western + South Asian" vocabulary (issue #6, skills/README.md).
-- TRD §3 ended this list with "etc."; the set is now closed. Adding a value is a migration.
do $$ begin
  create type fc_category as enum (
    -- tops
    'shirt', 'tshirt', 'kurta', 'kameez', 'blouse',
    -- full body
    'frock', 'dress', 'abaya',
    -- outerwear
    'waistcoat', 'jacket', 'coat', 'sweater',
    -- bottoms
    'trouser', 'jeans', 'shalwar', 'skirt', 'shorts',
    -- drape
    'dupatta', 'scarf',
    -- footwear
    'shoes', 'sandals', 'heels',
    -- other
    'accessory'
  );
exception when duplicate_object then null; end $$;

-- TRD §3 wrote the fourth value as "religious/cultural"; "/" is not a usable enum label, so the
-- value is 'cultural'. Same meaning.
do $$ begin
  create type fc_occasion as enum ('casual', 'formal', 'party', 'cultural');
exception when duplicate_object then null; end $$;

do $$ begin
  create type fc_pattern as enum ('solid', 'striped', 'plaid', 'floral', 'printed');
exception when duplicate_object then null; end $$;

do $$ begin
  create type fc_season as enum ('summer', 'winter', 'all_season');
exception when duplicate_object then null; end $$;

do $$ begin
  create type fc_fit as enum ('slim', 'regular', 'loose');
exception when duplicate_object then null; end $$;

do $$ begin
  create type fc_sleeve_type as enum ('full', 'half', 'sleeveless');
exception when duplicate_object then null; end $$;

do $$ begin
  create type fc_neckline as enum ('round', 'v_neck', 'collar');
exception when duplicate_object then null; end $$;

-- The compatibility engine reasons over slots, not categories: 'shirt' and 'kurta' are both 'top',
-- so "find another item that could go here" is expressible. See skills/database/SKILL.md §3.
do $$ begin
  create type fc_slot as enum (
    'top', 'bottom', 'full_body', 'outerwear', 'footwear', 'drape', 'accessory'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type fc_outfit_source as enum ('wardrobe_build', 'photo_upload');
exception when duplicate_object then null; end $$;

-- Lifecycle of a wardrobe item. The backend inserts the row at extraction time (before the user
-- reviews it) so that an abandoned review leaves a findable row rather than an orphaned storage
-- object — see 007_storage.sql. 'pending_review' rows are excluded from every wardrobe read.
do $$ begin
  create type fc_item_status as enum ('pending_review', 'active');
exception when duplicate_object then null; end $$;

do $$ begin
  create type fc_recommendation_type as enum ('makeup', 'jewelry', 'accessory');
exception when duplicate_object then null; end $$;


-- Shared trigger function for updated_at. Maintained by the database, never by the client
-- (skills/database/SKILL.md §1.6).
create or replace function fc_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
