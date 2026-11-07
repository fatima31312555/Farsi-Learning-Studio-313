// Supabase Edge Function: emails students through your Gmail account.
// Only a signed-in admin can call it. Students who switched notifications off are skipped.
//
// Secrets to set (Edge Functions > Secrets):
//   GMAIL_USER          your Gmail address, e.g. teacher@gmail.com
//   GMAIL_APP_PASSWORD  a 16-character Google App Password (not your normal password)
//   SITE_URL            your site address, e.g. https://yourdomain.com
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided automatically.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { SMTPClient } from "https://deno.land/x/denomailer@1.6.0/mod.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
const esc = (s: string) =>
  s.replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]!));
const clip = (v: unknown, n: number) => String(v ?? "").slice(0, n);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  try {
    const url = Deno.env.get("SUPABASE_URL")!;
    const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    });
    const { data: { user } } = await userClient.auth.getUser();
    if (!user) return json({ error: "Not signed in" }, 401);

    const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
    const { data: me } = await admin.from("profiles").select("role").eq("id", user.id).single();
    if (me?.role !== "admin") return json({ error: "Admins only" }, 403);

    const gmailUser = Deno.env.get("GMAIL_USER");
    const gmailPass = Deno.env.get("GMAIL_APP_PASSWORD");
    if (!gmailUser || !gmailPass) return json({ error: "GMAIL_USER / GMAIL_APP_PASSWORD secrets are not set" }, 500);
    const siteUrl = Deno.env.get("SITE_URL") ?? "";

    const b = await req.json();
    const kind = b.kind === "homework" ? "homework" : "announcement";
    const title = clip(b.title, 150);
    const body = clip(b.body, 3000);
    if (!title) return json({ error: "Title is required" }, 400);

    let q = admin.from("profiles").select("email").eq("notify_email", true).eq("role", "student").not("email", "is", null);
    if (kind === "homework" && b.level) q = q.eq("level", clip(b.level, 30));
    const { data: rows, error } = await q;
    if (error) return json({ error: error.message }, 500);
    const emails = (rows ?? []).map((r: { email: string }) => r.email).filter(Boolean);
    if (!emails.length) return json({ sent: 0, note: "No students to email" });

    const subject = (kind === "homework" ? "New homework: " : "Announcement: ") + title;
    const extra: string[] = [];
    if (kind === "homework") {
      if (b.category) extra.push("Topic: " + clip(b.category, 80));
      if (b.due_date) extra.push("Due: " + clip(b.due_date, 20));
    }
    const text = [title, "", ...extra, body, "", siteUrl ? "Open your dashboard: " + siteUrl + "/dashboard.html" : "",
      "", "You can switch these emails off in your dashboard settings."].join("\n");
    const html = `<div style="font-family:Arial,sans-serif;max-width:560px;margin:auto;color:#14224A">
      <div style="background:#1B2A6B;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0"><b>Dars · Farsi Class</b></div>
      <div style="border:1px solid #CFDCDA;border-top:0;padding:20px;border-radius:0 0 12px 12px">
        <h2 style="margin:0 0 8px">${esc(title)}</h2>
        ${extra.map((e) => `<p style="margin:0 0 4px;color:#5B6A8A">${esc(e)}</p>`).join("")}
        <p style="white-space:pre-wrap">${esc(body)}</p>
        ${siteUrl ? `<p><a href="${esc(siteUrl)}/dashboard.html" style="background:#17707A;color:#fff;padding:10px 16px;border-radius:8px;text-decoration:none;display:inline-block">Open my dashboard</a></p>` : ""}
        <p style="font-size:12px;color:#5B6A8A">You can switch these emails off in your dashboard settings.</p>
      </div></div>`;

    const client = new SMTPClient({
      connection: { hostname: "smtp.gmail.com", port: 465, tls: true, auth: { username: gmailUser, password: gmailPass } },
    });
    let sent = 0;
    try {
      // Blind-copy in batches so students never see each other's addresses.
      for (let i = 0; i < emails.length; i += 40) {
        const batch = emails.slice(i, i + 40);
        await client.send({
          from: `Dars Farsi Class <${gmailUser}>`,
          to: gmailUser,
          bcc: batch,
          subject,
          content: text,
          html,
        });
        sent += batch.length;
      }
    } finally {
      await client.close();
    }
    return json({ sent });
  } catch (e) {
    return json({ error: String((e as Error).message ?? e) }, 500);
  }
});
