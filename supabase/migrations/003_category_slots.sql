-- 003_category_slots.sql
-- parent: 002_profiles.sql
-- purpose: category → outfit-slot lookup. Shared reference data, not user data.
-- down:   drop table category_slots;
--
-- Why a table and not a CASE in code: both the Dart client and the Python backend need this
-- mapping, and a table is the only copy both can read. Two hand-maintained copies drift, and the
-- drift is silent — the swap engine simply stops finding candidates.
-- See skills/database/SKILL.md §3.

create table if not exists public.category_slots (
  category fc_category primary key,
  slot     fc_slot not null,

  -- Whether a garment in this category counts as "bold" for the pattern-clash rule's purposes
  -- when patterned. A patterned dupatta reads very differently from a patterned shoe.
  bold_weight real not null default 1.0 check (bold_weight >= 0 and bold_weight <= 1)
);

insert into public.category_slots (category, slot, bold_weight) values
  ('shirt',     'top',       1.0),
  ('tshirt',    'top',       1.0),
  ('kurta',     'top',       1.0),
  ('kameez',    'top',       1.0),
  ('blouse',    'top',       1.0),

  ('frock',     'full_body', 1.0),
  ('dress',     'full_body', 1.0),
  ('abaya',     'full_body', 1.0),

  ('waistcoat', 'outerwear', 0.8),
  ('jacket',    'outerwear', 0.8),
  ('coat',      'outerwear', 0.8),
  ('sweater',   'outerwear', 0.8),

  ('trouser',   'bottom',    1.0),
  ('jeans',     'bottom',    1.0),
  ('shalwar',   'bottom',    1.0),
  ('skirt',     'bottom',    1.0),
  ('shorts',    'bottom',    1.0),

  ('dupatta',   'drape',     0.9),
  ('scarf',     'drape',     0.6),

  ('shoes',     'footwear',  0.3),
  ('sandals',   'footwear',  0.3),
  ('heels',     'footwear',  0.3),

  ('accessory', 'accessory', 0.2)
on conflict (category) do update
  set slot = excluded.slot,
      bold_weight = excluded.bold_weight;

-- Every enum value must have a slot, or an item of that category is invisible to the outfit
-- builder. Asserted here so a future enum addition that forgets this row fails at migration time
-- rather than at runtime.
do $$
declare missing text;
begin
  select string_agg(v::text, ', ')
    into missing
    from unnest(enum_range(null::fc_category)) v
   where v not in (select category from public.category_slots);
  if missing is not null then
    raise exception 'category_slots is missing rows for: %', missing;
  end if;
end $$;


-- RLS: reference data, readable by any authenticated user, writable by none. Without RLS enabled
-- this table would be readable by anon as well.
alter table public.category_slots enable row level security;

drop policy if exists category_slots_select_all on public.category_slots;
create policy category_slots_select_all on public.category_slots
  for select to authenticated using (true);

-- No insert/update/delete policies: this table is maintained by migration only. Deliberate.
