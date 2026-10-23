-- Storage for browser Push API subscriptions. Review and run in Supabase SQL Editor.
create table if not exists public.daily_verse_push_subscriptions (
  id bigint generated always as identity primary key,
  subscription jsonb not null,
  created_at timestamptz not null default now(),
  endpoint_hash text generated always as (md5(subscription->>'endpoint')) stored unique
);
alter table public.daily_verse_push_subscriptions enable row level security;
-- No anon/authenticated policies: Edge Function service_role access only.
