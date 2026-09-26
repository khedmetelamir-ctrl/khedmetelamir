-- خدمة الأمير: إصلاح حفظ ملاحظات المخدومين + صلاحيات الحفظ والحذف
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor.
-- لا يحذف أي بيانات من الجداول الحالية.

create table if not exists public.member_notes (
  member_id uuid primary key references public.members(id) on delete cascade,
  note_text text,
  updated_by uuid references public.profiles(id) on delete set null,
  updated_at timestamptz not null default now()
);

alter table public.member_notes enable row level security;

drop policy if exists member_notes_select_active on public.member_notes;
drop policy if exists member_notes_insert_active on public.member_notes;
drop policy if exists member_notes_update_active on public.member_notes;
drop policy if exists member_notes_delete_active on public.member_notes;

create policy member_notes_select_active
on public.member_notes for select
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active = true
  )
);

create policy member_notes_insert_active
on public.member_notes for insert
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active = true
  )
);

create policy member_notes_update_active
on public.member_notes for update
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active = true
  )
)
with check (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active = true
  )
);

create policy member_notes_delete_active
on public.member_notes for delete
using (
  exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active = true
  )
);

-- أسماء كل المخدومين النشطين + الملاحظة الخاصة بكل اسم.
-- هذا RPC هو الذي تستخدمه صفحة "الملاحظات".
create or replace function public.get_members_for_notes()
returns table (
  id uuid,
  full_name text,
  phone text,
  class_id uuid,
  class_name text,
  birth_date date,
  address text,
  photo_url text,
  notes text,
  active boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.active = true
  ) then
    raise exception 'not authorized';
  end if;

  return query
  select
    m.id,
    m.full_name,
    m.phone,
    m.class_id,
    c.name as class_name,
    m.birth_date,
    m.address,
    m.photo_url,
    mn.note_text as notes,
    m.active,
    m.created_at
  from public.members m
  left join public.classes c on c.id = m.class_id
  left join public.member_notes mn on mn.member_id = m.id
  where m.active = true
  order by m.full_name asc;
end;
$$;

revoke all on function public.get_members_for_notes() from public;
grant execute on function public.get_members_for_notes() to authenticated;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'member_notes'
  ) then
    alter publication supabase_realtime add table public.member_notes;
  end if;
end $$;
