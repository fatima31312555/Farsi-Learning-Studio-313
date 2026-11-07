-- Dars · Farsi Class Studio: database schema
-- Run this whole file once in Supabase: SQL Editor > New query > paste > Run.
-- Then run seed.sql to load the starter words.

create extension if not exists "pgcrypto";

-- ---------- tables ----------
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  email text,
  role text not null default 'student' check (role in ('student','admin')),
  level text not null default 'Beginner',
  xp integer not null default 0,
  streak integer not null default 0,
  last_active date,
  created_at timestamptz not null default now()
);

-- email notifications opt-in (safe to re-run on an existing database)
alter table public.profiles add column if not exists notify_email boolean not null default true;

create table if not exists public.words (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  farsi text not null,
  roman text not null,
  meaning text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.known_words (
  user_id uuid not null references public.profiles(id) on delete cascade,
  word_id uuid not null references public.words(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, word_id)
);

create table if not exists public.assignments (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  category text,
  note text,
  level text,            -- null = every level
  due_date date,
  created_at timestamptz not null default now()
);

create table if not exists public.announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text,
  created_at timestamptz not null default now()
);

-- ---------- helper: is the current user an admin? ----------
create or replace function public.is_admin()
returns boolean language sql security definer set search_path = public stable as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------- auto-create a profile when someone signs up ----------
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, notify_email)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data->>'full_name',''), nullif(new.raw_user_meta_data->>'name',''), split_part(new.email,'@',1)),
    coalesce((new.raw_user_meta_data->>'notify_email')::boolean, true)
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- students earn XP only through this function ----------
create or replace function public.add_xp(amount integer)
returns void language plpgsql security definer set search_path = public as $$
declare p public.profiles;
begin
  if amount < 0 or amount > 50 then raise exception 'bad amount'; end if;
  select * into p from public.profiles where id = auth.uid();
  if p.id is null then return; end if;
  update public.profiles set
    xp = xp + amount,
    streak = case
      when last_active = current_date then streak
      when last_active = current_date - 1 then streak + 1
      else 1 end,
    last_active = current_date
  where id = auth.uid();
end $$;

-- ---------- row level security ----------
alter table public.profiles      enable row level security;
alter table public.words         enable row level security;
alter table public.known_words   enable row level security;
alter table public.assignments   enable row level security;
alter table public.announcements enable row level security;

-- profiles
drop policy if exists "own or admin read" on public.profiles;
create policy "own or admin read" on public.profiles for select
  using (id = auth.uid() or public.is_admin());

drop policy if exists "own name update" on public.profiles;
create policy "own name update" on public.profiles for update
  using (id = auth.uid())
  with check (
    id = auth.uid()
    and role = (select role from public.profiles where id = auth.uid())
    and xp   = (select xp   from public.profiles where id = auth.uid())
    and streak = (select streak from public.profiles where id = auth.uid())
    and level  = (select level  from public.profiles where id = auth.uid())
  );

drop policy if exists "admin update profiles" on public.profiles;
create policy "admin update profiles" on public.profiles for update
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "admin delete profiles" on public.profiles;
create policy "admin delete profiles" on public.profiles for delete
  using (public.is_admin());

-- words: signed-in users read, admin writes
drop policy if exists "read words" on public.words;
create policy "read words" on public.words for select using (auth.role() = 'authenticated');
drop policy if exists "admin words" on public.words;
create policy "admin words" on public.words for all
  using (public.is_admin()) with check (public.is_admin());

-- known words: each student manages their own, admin can read all
drop policy if exists "own known" on public.known_words;
create policy "own known" on public.known_words for all
  using (user_id = auth.uid()) with check (user_id = auth.uid());
drop policy if exists "admin read known" on public.known_words;
create policy "admin read known" on public.known_words for select using (public.is_admin());

-- assignments and announcements
drop policy if exists "read assignments" on public.assignments;
create policy "read assignments" on public.assignments for select using (auth.role() = 'authenticated');
drop policy if exists "admin assignments" on public.assignments;
create policy "admin assignments" on public.assignments for all
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "read announcements" on public.announcements;
create policy "read announcements" on public.announcements for select using (auth.role() = 'authenticated');
drop policy if exists "admin announcements" on public.announcements;
create policy "admin announcements" on public.announcements for all
  using (public.is_admin()) with check (public.is_admin());

-- ---------- after YOU sign up, make yourself admin ----------
-- update public.profiles set role = 'admin' where email = 'YOUR-EMAIL-HERE';
