# Daily Bible Verse Push — setup checklist

This adds a server-side sender for the site's existing 300 verses without changing their content or ordering.

## Not active until all steps are completed
1. Deploy supabase/functions/send-daily-verse/index.ts as an Edge Function.
2. Run supabase/daily_verse_push_subscriptions.sql in Supabase SQL Editor.
3. Configure Edge Function secrets: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT, and a strong random DAILY_VERSE_JOB_SECRET.
4. Add client-side opt-in to request notification permission, create a PushSubscription with the VAPID public key, and save it to the table. This client integration is not included in the sender file alone.
5. Schedule a daily POST at 09:00 Africa/Cairo to the function, passing x-job-secret. Store the secret in Supabase Vault or the scheduler's secret store; never hard-code it in frontend code or SQL.
6. Test on the actual phone with HTTPS, notification permission granted, and browser/PWA support.

The function returns sent/failed counts and deletes only subscriptions returning 404/410. Delivery varies by browser/OS. Do not claim active until subscription registration, deployment, scheduler, and a real-device test succeed.
