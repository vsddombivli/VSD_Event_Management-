# VSD Event Checklist — Setup Guide

Total setup time: ~15-20 minutes. Do this today so incharges can start using it before Saturday.

## 1. Create a Supabase project
1. Go to https://supabase.com → Sign up / log in → **New project**.
2. Pick any name (e.g. `vsd-event-checklist`), set a database password (save it somewhere), choose the region closest to India (e.g. Mumbai/Singapore), click **Create**. Takes ~2 minutes to provision.

## 2. Run the database schema
1. In your project, open **SQL Editor** → **New query**.
2. Paste the entire contents of `schema.sql` and click **Run**.
3. This creates all tables, security rules, and the two storage policies — but you still need to create the storage bucket itself (next step).

## 3. Expose the custom schema
This app's tables live in a schema called `vsd`, not the default `public` schema.
1. Go to **Project Settings** → **API** → find **Exposed schemas** (sometimes called "Data API settings").
2. Add `vsd` to the list (alongside `public`), then save.
Without this step, the app will get "schema not found" errors even though the SQL ran fine.

## 4. Create the photo storage bucket
1. Go to **Storage** → **New bucket**.
2. Name it exactly: `event-photos`
3. Toggle **Public bucket** = ON. Click Create.
   (The two storage policies from schema.sql already restrict uploads to logged-in users; public just means photos can be viewed via a direct link.)

## 5. Turn on magic link email login
1. Go to **Authentication** → **Providers** → **Email**. Make sure Email provider is enabled.
2. Go to **Authentication** → **URL Configuration**. Add the URL where you'll host this app (see step 7) to **Redirect URLs**. If you're just testing locally first, add `http://localhost:*` temporarily.

> **Important — do this before sharing the link with incharges:** Supabase's built-in email sender is rate-limited (roughly 2-4 emails/hour on the free tier) — it's meant for testing, not real logins. With 10+ incharges signing in around the same time, most magic links will get delayed or dropped.

### Connect Resend as your SMTP provider (you already have an API key)
1. In Resend, go to **Domains** and make sure you have a **verified sending domain** (not just the default `onboarding@resend.dev` — that one is fine for testing but has low deliverability/limits for real use). If you don't have a verified domain yet, do that first; it takes a few minutes plus DNS propagation, so start it now if you haven't.
2. In Supabase, go to **Authentication → Settings → SMTP Settings** and enter:
   - **Host:** `smtp.resend.com`
   - **Port:** `587`
   - **Username:** `resend`
   - **Password:** your Resend API key
   - **Sender email:** an address on your verified domain (e.g. `noreply@yourdomain.org`)
   - **Sender name:** e.g. `VSD Events`
3. Save, then send yourself a test magic link to confirm it arrives.

This removes the rate limit entirely — Resend's free tier covers 100 emails/day / 3,000/month, more than enough for this event.

## 6. Add yourself as admin
In SQL Editor, run (replace with your real email):
```sql
insert into vsd.admins (email) values ('your-email@example.com');
```
You can add more admins the same way.

## 7. Get your API keys and plug them into the app
1. Go to **Project Settings** → **API**.
2. Copy the **Project URL** and the **anon public** key (NOT the service_role key — never put that in frontend code).
3. Open `index.html`, find this near the top of the `<script>` section:
   ```js
   const SUPABASE_URL = "YOUR_SUPABASE_PROJECT_URL";
   const SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY";
   ```
4. Replace both placeholder values with what you copied.

## 8. Host the app (pick the fastest option for you)
**Easiest: Netlify Drop**
1. Go to https://app.netlify.com/drop
2. Drag the `index.html` file onto the page. You'll instantly get a live URL like `https://random-name.netlify.app`.
3. Go back to Supabase → Authentication → URL Configuration → add that URL to **Redirect URLs**.

**Alternative:** Vercel, GitHub Pages, or any static host works the same way — it's a single static HTML file.

## 10. Deploy the assignment email Edge Function
This sends an email to an incharge the moment they're assigned to an area, and is reusable for future events with no code changes — it reads whatever event/area/checklist data exists at call time.

1. Install the Supabase CLI if you don't have it (no global install needed — `npx` works):
   ```bash
   npx supabase login
   ```
2. From the folder containing `supabase/functions/send-notification/index.ts`, link this project (find your project ref in the Supabase dashboard URL, e.g. `abcd1234`):
   ```bash
   npx supabase link --project-ref YOUR_PROJECT_REF
   ```
3. Set the secrets the function needs (your Resend API key, a verified sender address, and your hosted app URL from step 8):
   ```bash
   npx supabase secrets set RESEND_API_KEY=re_your_key_here
   npx supabase secrets set SENDER_EMAIL=noreply@yourdomain.org
   npx supabase secrets set SENDER_NAME="VSD Events"
   npx supabase secrets set APP_URL=https://your-app-url.netlify.app
   ```
4. Deploy it:
   ```bash
   npx supabase functions deploy send-notification
   ```
5. Test: in the app's admin Setup tab, assign an incharge to an area — they should get an email within seconds. If it fails, check **Edge Functions → send-notification → Logs** in the dashboard, and confirm your Resend sending domain is verified.

Once deployed, every future event automatically gets assignment emails — nothing in the function is specific to this event. To add reminder emails later (due-today, overdue), extend the `switch` in `index.ts` with a new case; the client, RLS, and notification_log audit trail already support it.

## 11. Use it
1. Open the hosted URL yourself, sign in with your admin email → you'll land on the **Setup** tab.
2. Create the event (name + date) — this automatically creates the 8-item checklist.
3. Add each area (temple group) and assign its incharge (name + email) and helpers.
4. Share the app link with each incharge (WhatsApp/email/SMS — whatever's fastest) *or* just rely on the assignment email from step 10, which includes the app link and their checklist. They open it, enter their email, and get a magic sign-in link automatically from Supabase.
5. Check the **Overview** tab any time to see every area's progress in one grid.

## What's intentionally left out of this V1
- No automated "assignment" or "due today" emails (that needs an Edge Function + Resend — can add after Saturday if useful going forward).
- No individual helper logins — only the incharge updates status, as you specified.
- No task deadlines — everything is due by the event date.

These can be layered on for future events without changing the data model.
