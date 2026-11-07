# Dars · Farsi Class: website with admin panel

Pages: `index.html` (public home), `login.html`, `dashboard.html` (students), `admin.html` (teacher), `studio.html` (your original practice app, unchanged).
Stack: plain HTML/JS + Supabase (login and database) + Vercel (hosting). No build step.

## 1. Create the database (10 minutes)
1. Sign up at supabase.com and create a new project. Save the database password.
2. Open **SQL Editor > New query**, paste all of `schema.sql`, press **Run**.
3. New query again, paste `seed.sql`, **Run** (loads 124 starter words).
4. Open **Project Settings > API**. Copy the **Project URL** and the **anon public** key.
5. Paste both into `config.js`.
6. **Authentication > URL Configuration**: set Site URL to your final address (your Vercel URL first, your domain later) and add it under Redirect URLs.
7. Optional while testing: **Authentication > Providers > Email**, turn off "Confirm email" so sign-up is instant. Turn it back on for production.

## 2. Make yourself admin
1. Open the site, go to Create account, sign up with your email (or Google, once section 5 is done).
2. In Supabase SQL Editor run (use your email):
   `update public.profiles set role = 'admin' where email = 'you@example.com';`
3. Reload. An **Admin panel** link appears on your dashboard.

> If you already ran an earlier `schema.sql`, run the new one again. It is safe to re-run and adds the email-notification column.

## 3. Publish on Vercel
**Easiest (drag and drop):** vercel.com > Add New > Project > upload the `dars-site` folder.
**Better (GitHub):** push the folder to a GitHub repository, then Import it in Vercel. Every change you push redeploys automatically. Framework preset: Other. No build command, output directory is the root.

Then add your Vercel URL to Supabase Redirect URLs (step 1.6).

## 4. Your own domain
1. Vercel project > **Settings > Domains** > add `yourdomain.com` and `www.yourdomain.com`.
2. At your domain registrar, add the DNS records Vercel shows (usually an `A` record `76.76.21.21` for the root and a `CNAME` for `www`; use whatever Vercel displays).
3. Wait for DNS (minutes to a few hours). Vercel issues HTTPS automatically.
4. Update the Site URL and Redirect URLs in Supabase to the new domain.

## 5. Google sign-in
1. Go to console.cloud.google.com, create a project, then **APIs & Services > OAuth consent screen** (External, fill the app name and your email, save).
2. **Credentials > Create credentials > OAuth client ID > Web application**.
3. Under **Authorised redirect URIs** paste the callback URL shown in Supabase at **Authentication > Providers > Google** (it looks like `https://YOUR-PROJECT-ID.supabase.co/auth/v1/callback`).
4. Copy the **Client ID** and **Client secret** into that Supabase Google provider page, switch it on, save.
5. In Supabase **Authentication > URL Configuration**, make sure your site address is the Site URL and is in Redirect URLs.
6. While the consent screen is in "Testing", only test users you add can sign in. Press **Publish app** when ready for everyone.

## 6. Gmail notifications (email students about homework and announcements)
When you post homework or an announcement and tick "Email students", students who have notifications on get an email from your Gmail. Addresses are blind-copied, so students never see each other.
1. Turn on 2-Step Verification on your Google account, then create an **App Password**: myaccount.google.com/apppasswords. Copy the 16 characters.
2. Supabase **Edge Functions > Deploy a new function > Via Editor**. Name it exactly `notify`, paste the contents of `notify-function.ts`, deploy. Leave "Verify JWT" on.
3. **Edge Functions > Secrets**, add:
   - `GMAIL_USER` = your Gmail address
   - `GMAIL_APP_PASSWORD` = the 16-character app password
   - `SITE_URL` = your site address with no trailing slash, e.g. `https://yourdomain.com`
4. Post a test announcement in the admin panel with the box ticked.

Limits: a normal Gmail account can send about 500 emails a day. Gmail shows your own address as the sender. Emails may land in spam at first; ask students to mark them as "Not spam". For a large school, use a transactional email service instead.

## Login protection
- `dashboard.html`, `admin.html` and `studio.html` all check for a signed-in user and send visitors to the login page. After login, people return to the page they asked for.
- `admin.html` also requires the admin role.
- All data (words, homework, progress) is protected by the database rules, so it cannot be read without logging in even by calling the API directly.
- Honest limit: `studio.html` is a static file. Its login check runs in the browser, so someone who knows the exact file address and disables JavaScript could still download its text. It contains only the public vocabulary and games. Anything private belongs in the database, not in that file.

## How it is protected
- Row-level security in the database decides what each person can read or change, so hiding a button is not the only protection. Students cannot edit words, homework, roles, XP or other students' data.
- XP is only added through the `add_xp` function, capped at 50 per call.
- The anon key in `config.js` is meant to be public. Never put the `service_role` key anywhere in this folder.

## Known limits
- `studio.html` now needs login, but its progress still stays in the browser only (it is not linked to the database). The dashboard is the tracked experience.
- Removing a student in the admin panel deletes their profile and progress. Delete their login in Supabase > Authentication > Users too.
- XP is trusted from the browser (capped per call), fine for a class, not for competitions.
- Not yet built: file uploads, per-student private messages, class groups, browser push notifications (email is supported).
