# Dars site v2: setup in 4 steps

1. **Database (one paste).** Supabase > your project "Farsi learning Studio" > SQL Editor > New query. Open `setup.sql`, copy everything, paste, press Run. It builds students, words, homework, fees, recorded classes, private video storage and game tracking, and loads the 124 starter words. It is safe to run again.
2. **Sign up and make yourself admin.** Open the site, create your account, then in the SQL Editor run:
   `update public.profiles set role = 'admin' where email = 'YOUR-EMAIL';`
   Reload. The dashboard now shows **Admin panel**, and the admin panel has **Fees, classes, activity**.
3. **Put it online.** Upload all files in this folder to your GitHub repository (replace the old ones). Vercel redeploys by itself. Then in Supabase > Authentication > URL Configuration, set Site URL to your Vercel address and add it under Redirect URLs.
4. **Privacy settings.** Supabase > Authentication > Providers > Email: keep "Confirm email" ON. Supabase > Authentication > Passwords: turn on leaked-password protection and a minimum length of 8.

## What is new in v2
- **Fees** (admin2.html > Fees): add a fee for each student with a due date and a reminder date, record payments, see paid and remaining, and a "Send reminders today" list. The Remind button opens WhatsApp with a polite Urdu and English message already written.
- **Recorded classes** (admin2.html > Recorded classes): upload a video or paste an unlisted YouTube link, add a PDF, list the main topics and write notes. Choose exactly which students can watch each class.
- **Who is watching**: how far each student got in each class and whether they finished.
- **Game activity**: which games each student plays, how many rounds and how much XP.
- **Students** see their classes, notes, PDFs and their own fees at classroom.html.

## Privacy and limits (honest)
- Videos and PDFs sit in a private bucket. Only students you tick can open them, through links that expire after one hour. The database enforces this, not just the buttons.
- Nobody can fully stop a student from screen-recording a video they are allowed to watch.
- Free Supabase plan: 50 MB per file. Longer lectures: paste an unlisted YouTube link, or upgrade storage.
- Fee reminders are one tap on WhatsApp, not automatic. Automatic sending needs a scheduled server job (can be added later).
- Game tracking records one entry per scored round in the Practice studio.
