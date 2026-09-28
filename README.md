# DialGrow Workspace

Role-aware internal operating system for people, work, communication, knowledge, training and governance.

## Run locally

```bash
npm install
npm run dev
```

The local UI starts in the demo workspace so the product surface can be explored immediately. Supabase is configured through `.env.local` and the public publishable key. The database password is intentionally not stored in the repo or frontend.

## Supabase setup

1. Create or open the DialGrow project in Supabase.
2. Run [`supabase/schema.sql`](./supabase/schema.sql) in the SQL editor.
3. Configure Auth email/password or invite employees from the Admin center.
4. Seed the Main Admin and role records through a server-side/admin workflow.

Employee accounts should use the `@dialgrow.com` domain. Temporary passwords should be issued through the invitation flow and changed on first login.
