# DialGrow Workspace

Role-aware internal operating system for people, work, communication, knowledge, training and governance. The browser now uses Supabase Auth and live Supabase records instead of a demo workspace.

## Run locally

```bash
npm install
npm run dev
```

The local UI starts at the public DialGrow landing page. Employees sign in with their own `@dialgrow.com` account. Supabase is configured through `.env.local` and the public publishable key. The database password is intentionally not stored in the repo or frontend.

## Supabase setup

1. Create or open the DialGrow project in Supabase.
2. Run [`supabase/schema.sql`](./supabase/schema.sql) in the SQL editor.
3. In Supabase Auth, create the owner account with the email `durga@dialgrow.com` and the private password you control.
4. Sign in once, then run the `bootstrap_dialgrow_workspace()` RPC from the authenticated owner session or expose it through an owner-only setup button.
5. Deploy the protected Edge Function: `supabase functions deploy create-employee`.
6. Add `SUPABASE_SERVICE_ROLE_KEY` to the Edge Function secrets. Never place it in `.env.local` or the browser bundle.
7. Deploy `send-team-update` and schedule it three times per week between 16:00 and 17:00 in the Supabase scheduler. Schedule the Friday invocation with `{ "fridayPrompt": true }`.

Employee accounts should use the `@dialgrow.com` domain. Temporary passwords should be issued through the invitation flow and changed on first login.

The Admin center creates accounts through the Edge Function, assigns the selected role, and records the action in `audit_logs`. Login times are recorded on every successful session. Employees can update their name and work schedule from My profile.
