-- v2: fees, recorded classes, access control, game activity. Safe to re-run.
alter table public.profiles add column if not exists phone text;
create table if not exists public.fee_records (
  id uuid primary key default gen_random_uuid(),
  student_id uuid not null references public.profiles(id) on delete cascade,
  title text not null default 'Monthly fee',
  amount_due numeric(10,2) not null check (amount_due >= 0),
  due_date date not null, reminder_date date,
  created_at timestamptz not null default now());
create table if not exists public.fee_payments (
  id uuid primary key default gen_random_uuid(),
  record_id uuid not null references public.fee_records(id) on delete cascade,
  student_id uuid not null references public.profiles(id) on delete cascade,
  amount numeric(10,2) not null check (amount > 0),
  paid_on date not null default current_date, method text, note text,
  created_at timestamptz not null default now());
create table if not exists public.lectures (
  id uuid primary key default gen_random_uuid(),
  title text not null, description text,
  topics text[] not null default '{}', notes text,
  video_path text, video_url text, pdf_path text,
  published boolean not null default true,
  created_at timestamptz not null default now());
create table if not exists public.lecture_access (
  lecture_id uuid references public.lectures(id) on delete cascade,
  student_id uuid references public.profiles(id) on delete cascade,
  granted_at timestamptz not null default now(),
  primary key (lecture_id, student_id));
create table if not exists public.lecture_views (
  lecture_id uuid references public.lectures(id) on delete cascade,
  student_id uuid references public.profiles(id) on delete cascade,
  seconds_watched int not null default 0, completed boolean not null default false,
  last_viewed timestamptz not null default now(),
  primary key (lecture_id, student_id));
create table if not exists public.game_plays (
  id bigint generated always as identity primary key,
  student_id uuid not null references public.profiles(id) on delete cascade,
  game text not null, xp int not null default 0,
  played_at timestamptz not null default now());
create index if not exists gp_student on public.game_plays (student_id, played_at desc);
create index if not exists fr_student on public.fee_records (student_id);
create index if not exists fp_record on public.fee_payments (record_id);

create or replace function public.has_lecture_access(lid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select public.is_admin() or exists (select 1 from public.lecture_access where lecture_id = lid and student_id = auth.uid())
$$;
create or replace function public.log_play(p_game text, p_xp int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.game_plays (student_id, game, xp) values (auth.uid(), left(coalesce(p_game,'game'),40), greatest(0, least(coalesce(p_xp,0), 50)));
end $$;
revoke execute on function public.log_play(text, int) from public, anon;
grant execute on function public.log_play(text, int) to authenticated;

create or replace view public.fee_balance with (security_invoker = on) as
  select r.*, coalesce(sum(p.amount),0) as paid, r.amount_due - coalesce(sum(p.amount),0) as balance
  from public.fee_records r left join public.fee_payments p on p.record_id = r.id group by r.id;
create or replace view public.play_summary with (security_invoker = on) as
  select student_id, game, count(*)::int as plays, sum(xp)::int as xp, max(played_at) as last_played
  from public.game_plays group by student_id, game;

alter table public.fee_records enable row level security;
alter table public.fee_payments enable row level security;
alter table public.lectures enable row level security;
alter table public.lecture_access enable row level security;
alter table public.lecture_views enable row level security;
alter table public.game_plays enable row level security;

drop policy if exists fr_read on public.fee_records;
create policy fr_read on public.fee_records for select using (student_id = auth.uid() or public.is_admin());
drop policy if exists fr_admin on public.fee_records;
create policy fr_admin on public.fee_records for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists fp_read on public.fee_payments;
create policy fp_read on public.fee_payments for select using (student_id = auth.uid() or public.is_admin());
drop policy if exists fp_admin on public.fee_payments;
create policy fp_admin on public.fee_payments for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists lec_read on public.lectures;
create policy lec_read on public.lectures for select using (public.is_admin() or (published and public.has_lecture_access(id)));
drop policy if exists lec_admin on public.lectures;
create policy lec_admin on public.lectures for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists la_read on public.lecture_access;
create policy la_read on public.lecture_access for select using (student_id = auth.uid() or public.is_admin());
drop policy if exists la_admin on public.lecture_access;
create policy la_admin on public.lecture_access for all using (public.is_admin()) with check (public.is_admin());
drop policy if exists lv_own on public.lecture_views;
create policy lv_own on public.lecture_views for all using (student_id = auth.uid())
  with check (student_id = auth.uid() and public.has_lecture_access(lecture_id));
drop policy if exists lv_admin on public.lecture_views;
create policy lv_admin on public.lecture_views for select using (public.is_admin());
drop policy if exists gp_read on public.game_plays;
create policy gp_read on public.game_plays for select using (student_id = auth.uid() or public.is_admin());

-- private storage for videos and PDFs (50 MB per file on the free plan)
insert into storage.buckets (id, name, public, file_size_limit) values ('lectures','lectures',false,52428800)
  on conflict (id) do update set public = false;
drop policy if exists lectures_admin on storage.objects;
create policy lectures_admin on storage.objects for all to authenticated
  using (bucket_id = 'lectures' and public.is_admin()) with check (bucket_id = 'lectures' and public.is_admin());
drop policy if exists lectures_student on storage.objects;
create policy lectures_student on storage.objects for select to authenticated
  using (bucket_id = 'lectures' and public.has_lecture_access(((storage.foldername(name))[1])::uuid));
