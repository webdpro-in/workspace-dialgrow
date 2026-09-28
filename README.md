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
3. In Supabase Auth, create the owner account with the email `business@dialgrow.com` and the private password you control.
4. Sign in once, then run the `bootstrap_dialgrow_workspace()` RPC from the authenticated owner session or expose it through an owner-only setup button.
5. The Admin employee flow uses the owner-only `create_employee_account` RPC from the schema to create confirmed Auth users, assign DG IDs and attach roles without public signup email throttling. The Edge Function version in `supabase/functions/create-employee` remains available for deployments that have service-role access.
6. Add `SUPABASE_SERVICE_ROLE_KEY`, `RESEND_API_KEY`, `DIALGROW_FROM_EMAIL`, and `WORKSPACE_URL=https://workspace.dialgrow.com` to any Edge Function secrets. Never place service-role or mail-provider secrets in `.env.local` or the browser bundle.
7. Deploy `send-team-update` and schedule it three times per week between 16:00 and 17:00 in the Supabase scheduler. Schedule the Friday invocation with `{ "fridayPrompt": true }`.
8. Deploy `enhance-caption`: `supabase functions deploy enhance-caption`. Add `OPENAI_API_KEY` to that function's secrets to enable the optional AI caption enhancement.

Production URL: `https://workspace.dialgrow.com`. Set this as the Supabase Auth Site URL and the password-reset redirect URL. Configure the DNS record for this host at the web app host.

Employee accounts receive a unique `dg-####` login ID. The Main Admin assigns the temporary password, and employees sign in with the DG ID plus that password. An optional `@dialgrow.com` Auth email can also be stored for the account.

The Admin center creates accounts through the owner-only database provisioner, assigns the selected role, records the action in `audit_logs`, and exposes the DG ID as the employee-facing credential. Login times are recorded on every successful session. Employees can update their name and work schedule from My profile. There is no employee self-sign-up or “first access” flow; only the Main Admin can create accounts.

The Admin center also includes the live Post Update workflow. Posters are stored in the `social-posts` Supabase Storage bucket, post records and selected recipients are stored in `social_posts` and `social_post_recipients`, and employees can review posts from Company posts. LinkedIn sharing opens LinkedIn's official share composer and copies the prepared caption. Direct API publishing and native engagement reporting require a LinkedIn OAuth application and organization permissions, which are intentionally not hardcoded.

The automated human-style reminder identity is `Priya Sharma`.
