-- Dars v3: monthly rewards + certificates. Safe to run again.
create table if not exists public.rewards (
  id uuid primary key default gen_random_uuid(),
  month text not null, title text not null, youtube_url text, note text,
  created_at timestamptz not null default now());
create table if not exists public.certificates (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  title text not null, month text, kind text not null default 'generated',
  file_path text, created_at timestamptz not null default now());
alter table public.rewards enable row level security;
alter table public.certificates enable row level security;
drop policy if exists rw_read on public.rewards;
create policy rw_read on public.rewards for select using (auth.role() = 'authenticated');
drop policy if exists rw_admin on public.rewards;
create policy rw_admin on public.rewards for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists ce_read on public.certificates;
create policy ce_read on public.certificates for select using (student_id = auth.uid() or public.is_admin());
drop policy if exists ce_admin on public.certificates;
create policy ce_admin on public.certificates for all using (public.is_admin()) with check (public.is_admin());

-- top 5 students by game XP this month (names only, safe to show to every student)
create or replace function public.top_students() returns table(student_id uuid, full_name text, xp bigint)
language sql security definer set search_path = public as $$
  select p.id, coalesce(nullif(p.full_name,''),'Student'), sum(g.xp)::bigint
  from public.game_plays g join public.profiles p on p.id = g.student_id
  where g.played_at >= date_trunc('month', now()) and auth.role() = 'authenticated'
  group by p.id, p.full_name order by 3 desc limit 5 $$;

insert into storage.buckets (id, name, public, file_size_limit) values ('certificates','certificates',false,10485760)
on conflict (id) do nothing;
drop policy if exists cert_admin on storage.objects;
create policy cert_admin on storage.objects for all to authenticated
  using (bucket_id = 'certificates' and public.is_admin()) with check (bucket_id = 'certificates' and public.is_admin());
drop policy if exists cert_own on storage.objects;
create policy cert_own on storage.objects for select to authenticated
  using (bucket_id = 'certificates' and (storage.foldername(name))[1] = auth.uid()::text);
