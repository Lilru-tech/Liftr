# Auth hardening (manual dashboard step)

Enable in Supabase Dashboard for project **Liftr** (`rjzhaafvkxmvlnpsikbi`):

1. **Authentication → Providers → Email** → enable **Leaked password protection** (HaveIBeenPwned).
2. **Authentication → MFA** → enable **TOTP** and any additional methods you want to offer.

These changes do not affect existing sessions or app data visibility.
