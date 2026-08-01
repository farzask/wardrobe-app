-- 007_storage.sql
-- parent: 006_style_recommendations.sql
-- purpose: Private thumbnail bucket and its per-user path policies (TRD §4.5, §9).
-- down:   delete from storage.objects where bucket_id = 'wardrobe-thumbnails';
--         delete from storage.buckets where id = 'wardrobe-thumbnails';
--         (drop the four policies by name)

-- PRIVATE bucket. A public bucket would make every user's thumbnails enumerable by URL and would
-- defeat every RLS policy in 002–006 — the attributes would be protected while the images were not.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'wardrobe-thumbnails',
  'wardrobe-thumbnails',
  false,
  262144,                      -- 256 KB hard ceiling; TRD §4.4 targets ≤30 KB, so this is a
                               -- backstop against a broken encoder, not the working limit.
  array['image/webp']
)
on conflict (id) do update
  set public             = excluded.public,
      file_size_limit    = excluded.file_size_limit,
      allowed_mime_types = excluded.allowed_mime_types;


-- Path convention: wardrobe-thumbnails/{user_id}/{item_id}.webp
-- storage.foldername(name) splits the object path; element 1 is the first segment, i.e. the owner.
drop policy if exists thumbnails_select_own on storage.objects;
create policy thumbnails_select_own on storage.objects
  for select to authenticated
  using (
    bucket_id = 'wardrobe-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists thumbnails_insert_own on storage.objects;
create policy thumbnails_insert_own on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'wardrobe-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists thumbnails_update_own on storage.objects;
create policy thumbnails_update_own on storage.objects
  for update to authenticated
  using (
    bucket_id = 'wardrobe-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  )
  with check (
    bucket_id = 'wardrobe-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

drop policy if exists thumbnails_delete_own on storage.objects;
create policy thumbnails_delete_own on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'wardrobe-thumbnails'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ORPHAN THUMBNAILS (skills/database/SKILL.md §7)
-- TRD §4 uploads the thumbnail (step 5) before the row is written (step 7). If the user abandons
-- the review screen, the object leaks with no wardrobe_items row pointing at it.
-- FitCheck resolves this by writing the row FIRST: the backend inserts a wardrobe_items row at
-- extraction time and the review screen updates it, so an abandoned review leaves a row the reaper
-- below can find. Nothing here runs automatically — this is the query to run manually, or from a
-- scheduled job, once that is set up.
--
--   select o.name
--     from storage.objects o
--    where o.bucket_id = 'wardrobe-thumbnails'
--      and o.created_at < now() - interval '24 hours'
--      and not exists (
--            select 1 from public.wardrobe_items w
--             where w.thumbnail_path = o.name
--          );
