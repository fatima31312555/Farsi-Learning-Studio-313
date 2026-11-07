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
-- Starter vocabulary from your original studio
insert into public.words (category, farsi, roman, meaning) values
('Greetings','سلام','salâm','hello'),
('Greetings','خداحافظ','khodâhâfez','goodbye'),
('Greetings','ممنون','mamnun','thank you'),
('Greetings','لطفاً','lotfan','please'),
('Greetings','ببخشید','bebakhshid','excuse me / sorry'),
('Greetings','خوش آمدید','khosh âmadid','welcome'),
('Greetings','صبح بخیر','sobh bekheyr','good morning'),
('Greetings','شب بخیر','shab bekheyr','good night'),
('Greetings','حالت چطوره؟','hâlet chetore?','how are you? (informal)'),
('Greetings','خوبم','khubam','I’m fine'),
('Greetings','خواهش می‌کنم','khâhesh mikonam','you’re welcome'),
('Greetings','اسم من … است','esm-e man … ast','my name is …'),
('Numbers','صفر','sefr','zero (۰)'),
('Numbers','یک','yek','one (۱)'),
('Numbers','دو','do','two (۲)'),
('Numbers','سه','se','three (۳)'),
('Numbers','چهار','chahâr','four (۴)'),
('Numbers','پنج','panj','five (۵)'),
('Numbers','شش','shesh','six (۶)'),
('Numbers','هفت','haft','seven (۷)'),
('Numbers','هشت','hasht','eight (۸)'),
('Numbers','نه','noh','nine (۹)'),
('Numbers','ده','dah','ten (۱۰)'),
('Family','مادر','mâdar','mother'),
('Family','پدر','pedar','father'),
('Family','برادر','barâdar','brother'),
('Family','خواهر','khâhar','sister'),
('Family','پسر','pesar','son / boy'),
('Family','دختر','dokhtar','daughter / girl'),
('Family','مادربزرگ','mâdarbozorg','grandmother'),
('Family','پدربزرگ','pedarbozorg','grandfather'),
('Family','عمو','amu','paternal uncle'),
('Family','خاله','khâle','maternal aunt'),
('Food and drink','نان','nân','bread'),
('Food and drink','برنج','berenj','rice'),
('Food and drink','آب','âb','water'),
('Food and drink','چای','châi','tea'),
('Food and drink','شیر','shir','milk'),
('Food and drink','سیب','sib','apple'),
('Food and drink','گوشت','gusht','meat'),
('Food and drink','مرغ','morgh','chicken'),
('Food and drink','ماست','mâst','yogurt'),
('Food and drink','میوه','mive','fruit'),
('Food and drink','کباب','kabâb','kebab'),
('Food and drink','شکر','shekar','sugar'),
('Colours','قرمز','ghermez','red'),
('Colours','آبی','âbi','blue'),
('Colours','سبز','sabz','green'),
('Colours','زرد','zard','yellow'),
('Colours','سیاه','siyâh','black'),
('Colours','سفید','sefid','white'),
('Colours','نارنجی','nârenji','orange'),
('Colours','بنفش','banafsh','purple'),
('Days','شنبه','shanbe','Saturday'),
('Days','یکشنبه','yekshanbe','Sunday'),
('Days','دوشنبه','doshanbe','Monday'),
('Days','سه‌شنبه','seshanbe','Tuesday'),
('Days','چهارشنبه','chahârshanbe','Wednesday'),
('Days','پنجشنبه','panjshanbe','Thursday'),
('Days','جمعه','jom’e','Friday'),
('Verbs','رفتن','raftan','to go'),
('Verbs','آمدن','âmadan','to come'),
('Verbs','خوردن','khordan','to eat / drink'),
('Verbs','نوشتن','neveshtan','to write'),
('Verbs','خواندن','khândan','to read'),
('Verbs','دیدن','didan','to see'),
('Verbs','گفتن','goftan','to say'),
('Verbs','داشتن','dâshtan','to have'),
('Verbs','بودن','budan','to be'),
('Verbs','خریدن','kharidan','to buy'),
('Verbs','دوست داشتن','dust dâshtan','to like / love'),
('Places','خانه','khâne','home'),
('Places','مدرسه','madrese','school'),
('Places','شهر','shahr','city'),
('Places','خیابان','khiyâbân','street'),
('Places','بازار','bâzâr','market'),
('Places','فرودگاه','forudgâh','airport'),
('Places','دانشگاه','dâneshgâh','university'),
('Places','بیمارستان','bimârestân','hospital'),
('Places','کتابخانه','ketâbkhâne','library'),
('Places','ایران','irân','Iran'),
('Classroom','معلم','moʼallem','teacher'),
('Classroom','دانش‌آموز','dânesh-âmuz','student'),
('Classroom','کتاب','ketâb','book'),
('Classroom','قلم','ghalam','pen'),
('Classroom','دفتر','daftar','notebook'),
('Classroom','کلاس','kelâs','class'),
('Classroom','درس','dars','lesson'),
('Classroom','تکلیف','taklif','homework'),
('Arif Sir: Words','این','in','یہ'),
('Arif Sir: Words','آن','ân','وہ'),
('Arif Sir: Words','اینها','inhâ','یہ لوگ / یہ چیزیں'),
('Arif Sir: Words','آنها','ânhâ','وہ لوگ / وہ چیزیں'),
('Arif Sir: Words','اینجا','injâ','یہاں'),
('Arif Sir: Words','آنجا','ânjâ','وہاں'),
('Arif Sir: Words','به این طرف','be in taraf','اس طرف / ادھر'),
('Arif Sir: Words','به آن طرف','be ân taraf','اُس طرف / اُدھر'),
('Arif Sir: Words','این‌طور','in-tor','ایسے'),
('Arif Sir: Words','آن‌طور','ân-tor','ویسے'),
('Arif Sir: Words','چطور؟','chetor?','کیسے؟'),
('Arif Sir: Words','چرا؟','cherâ?','کیوں؟'),
('Arif Sir: Words','چه؟','che?','کیا؟'),
('Arif Sir: Words','چه کسی؟','che kasi?','کون؟'),
('Arif Sir: Words','کجا؟','kojâ?','کہاں؟'),
('Arif Sir: Words','کی؟','key?','کب؟'),
('Arif Sir: Words','چقدر؟','cheghadr?','کتنا؟'),
('Arif Sir: Words','کدام؟','kodâm?','کون سا؟'),
('Arif Sir: Words','بله','bale','ہاں'),
('Arif Sir: Words','نه','na','نہیں'),
('Arif Sir: Words','شاید','shâyad','شاید'),
('Arif Sir: Words','حتماً','hatman','ضرور'),
('Arif Sir: Words','هم','ham','بھی'),
('Arif Sir: Words','فقط','faghat','صرف'),
('Arif Sir: Words','اما','ammâ','لیکن'),
('Arif Sir: Words','زیرا','zirâ','کیونکہ'),
('Arif Sir: Words','سپس','sepas','پھر / اس کے بعد'),
('Arif Sir: Words','حالا','hâlâ','اب'),
('Arif Sir: Words','دیروز','diruz','کل (گزرا ہوا)'),
('Arif Sir: Words','دیشب','dishab','گزشتہ رات'),
('Arif Sir: Words','صبح','sobh','صبح'),
('Arif Sir: Words','بعد از ظهر','bad az zohr','دوپہر کے بعد'),
('Arif Sir: Words','شب','shab','رات'),
('Arif Sir: Words','آن زمان','ân zamân','اس وقت'),
('Arif Sir: Words','وقتی','vaghti','جب');
