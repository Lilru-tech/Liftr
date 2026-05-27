# Liftr auth callback (deploy via settleit-auth)

This folder is the **source** for the password-reset bridge hosted at:

**https://settleit-auth.vercel.app/auth/callback**

Production deploys from the separate GitHub repo **`Lilru-tech/settleit-auth`** (connected to Vercel project **settleit-auth**). Do not create a new `liftr-auth` project.

## Sync to settleit-auth and deploy

1. Clone `Lilru-tech/settleit-auth` locally.
2. Copy files from this directory:

```bash
rsync -av --delete ./public/ /path/to/settleit-auth/public/
cp vercel.json /path/to/settleit-auth/vercel.json
```

3. Commit and push to `main`. Vercel redeploys automatically.

4. Verify: https://settleit-auth.vercel.app/auth/callback

5. Configure Supabase (Site URL, Redirect URLs, email template) — see [`docs/auth-password-reset.md`](../../docs/auth-password-reset.md).

## Local preview

```bash
npx serve public
```

Open `http://localhost:3000/auth/callback` (deep links only work on a device with Liftr installed).
