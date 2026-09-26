-- خدمة الأمير: إصلاح النقاط + أدوات تعديل المدير
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor.

-- =========================
-- النقاط
-- =========================
create table if not exists public.member_points (
  member_id uuid primary key references public.members(id) on delete cascade,
  points integer not null default 0 check (points >= -10 and points <= 1000000),
  updated_at timestamptz not null default now()
);

alter table public.member_points enable row level security;

drop policy if exists member_points_select_access on public.member_points;
create policy member_points_select_access on public.member_points
for select to authenticated
using (
  exists (
    select 1 from public.members m
    where m.id = member_id
      and public.can_access_class(m.class_id)
  )
);

grant select on public.member_points to authenticated;

create or replace function public.add_member_point(p_member_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_id uuid;
  v_points integer;
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  select class_id into v_class_id from public.members where id = p_member_id;
  if v_class_id is null then raise exception 'المخدوم غير موجود'; end if;
  if not public.can_access_class(v_class_id) then raise exception 'ليس لديك صلاحية على هذا المخدوم'; end if;

  insert into public.member_points(member_id, points, updated_at)
  values (p_member_id, 1, now())
  on conflict (member_id)
  do update set points = public.member_points.points + 1, updated_at = now()
  returning points into v_points;
  return v_points;
end;
$$;

grant execute on function public.add_member_point(uuid) to authenticated;

create or replace function public.remove_member_point(p_member_id uuid)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare
  v_class_id uuid;
  v_points integer;
begin
  if auth.uid() is null then raise exception 'غير مصرح'; end if;
  select class_id into v_class_id from public.members where id = p_member_id;
  if v_class_id is null then raise exception 'المخدوم غير موجود'; end if;
  if not public.can_access_class(v_class_id) then raise exception 'ليس لديك صلاحية على هذا المخدوم'; end if;

  insert into public.member_points(member_id, points, updated_at)
  values (p_member_id, -1, now())
  on conflict (member_id)
  do update set points = greatest(-10, public.member_points.points - 1), updated_at = now()
  returning points into v_points;
  return v_points;
end;
$$;

grant execute on function public.remove_member_point(uuid) to authenticated;

-- =========================
-- صلاحيات تعديل المدير
-- =========================
create or replace function public.manager_update_class(
  p_class_id uuid,
  p_name text,
  p_description text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_manager() then raise exception 'مدير الخدمة فقط'; end if;
  if nullif(trim(p_name),'') is null then raise exception 'اسم الفصل مطلوب'; end if;
  update public.classes
  set name = trim(p_name), description = nullif(trim(coalesce(p_description,'')),'')
  where id = p_class_id;
  if not found then raise exception 'الفصل غير موجود'; end if;
end;
$$;

grant execute on function public.manager_update_class(uuid,text,text) to authenticated;

create or replace function public.manager_delete_class(p_class_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_manager() then raise exception 'مدير الخدمة فقط'; end if;
  if exists(select 1 from public.members where class_id=p_class_id) then raise exception 'لا يمكن حذف فصل به مخدومون'; end if;
  delete from public.class_servants where class_id=p_class_id;
  delete from public.classes where id=p_class_id;
  if not found then raise exception 'الفصل غير موجود'; end if;
end;
$$;

grant execute on function public.manager_delete_class(uuid) to authenticated;

create or replace function public.manager_update_member(
  p_member_id uuid,
  p_full_name text,
  p_class_id uuid,
  p_birth_date date default null,
  p_address text default null,
  p_phone text default null,
  p_photo_url text default null
)
returns public.members
language plpgsql
security definer
set search_path = public
as $$
declare v_row public.members;
begin
  if not public.is_manager() then raise exception 'مدير الخدمة فقط'; end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'اسم المخدوم مطلوب'; end if;
  update public.members
  set full_name=trim(p_full_name), class_id=p_class_id, birth_date=p_birth_date,
      address=nullif(trim(coalesce(p_address,'')),''), phone=nullif(trim(coalesce(p_phone,'')),''),
      photo_url=case when p_photo_url is null then photo_url else p_photo_url end,
      updated_at=now()
  where id=p_member_id
  returning * into v_row;
  if not found then raise exception 'المخدوم غير موجود'; end if;
  return v_row;
end;
$$;

grant execute on function public.manager_update_member(uuid,text,uuid,date,text,text,text) to authenticated;

create or replace function public.manager_update_profile_name(
  p_user_id uuid,
  p_full_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_manager() then raise exception 'مدير الخدمة فقط'; end if;
  if nullif(trim(p_full_name),'') is null then raise exception 'الاسم مطلوب'; end if;
  update public.profiles set full_name=trim(p_full_name), updated_at=now() where id=p_user_id;
  if not found then raise exception 'الخادم غير موجود'; end if;
end;
$$;

grant execute on function public.manager_update_profile_name(uuid,text) to authenticated;

-- Realtime للنقاط والتعديلات
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.member_points;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
-- خدمة الأمير — إصلاح نهائي لحفظ الملاحظات
-- شغّل هذا الملف مرة واحدة في Supabase SQL Editor.

create table if not exists public.member_notes (
  member_id uuid primary key references public.members(id) on delete cascade,
  note_text text,
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

alter table public.member_notes enable row level security;

-- إزالة السياسات القديمة إن وجدت، ثم إنشاء صلاحيات القراءة والكتابة لأي حساب نشط.
drop policy if exists member_notes_select_active on public.member_notes;
drop policy if exists member_notes_insert_active on public.member_notes;
drop policy if exists member_notes_update_active on public.member_notes;
drop policy if exists member_notes_delete_active on public.member_notes;

create policy member_notes_select_active on public.member_notes
for select to authenticated
using (exists (select 1 from public.profiles p where p.id=auth.uid() and p.active=true));

create policy member_notes_insert_active on public.member_notes
for insert to authenticated
with check (exists (select 1 from public.profiles p where p.id=auth.uid() and p.active=true));

create policy member_notes_update_active on public.member_notes
for update to authenticated
using (exists (select 1 from public.profiles p where p.id=auth.uid() and p.active=true))
with check (exists (select 1 from public.profiles p where p.id=auth.uid() and p.active=true));

create policy member_notes_delete_active on public.member_notes
for delete to authenticated
using (exists (select 1 from public.profiles p where p.id=auth.uid() and p.active=true));

-- نسخ الملاحظات الموجودة من members.notes إن كانت هناك ملاحظات قديمة.
insert into public.member_notes(member_id,note_text,updated_at)
select m.id, nullif(trim(m.notes), ''), coalesce(m.updated_at, now())
from public.members m
where nullif(trim(coalesce(m.notes,'')), '') is not null
on conflict (member_id) do update
set note_text=excluded.note_text, updated_at=excluded.updated_at;

create or replace function public.save_service_note(p_member_id uuid, p_note text)
returns table(member_id uuid, note_text text, updated_at timestamptz)
language plpgsql
security definer
set search_path=''
as $fn$
begin
  if not exists (select 1 from public.profiles p where p.id=auth.uid() and p.active=true) then
    raise exception 'not authorized';
  end if;
  if not exists (
    select 1 from public.members m
    where m.id=p_member_id and public.can_access_class(m.class_id)
  ) then
    raise exception 'not authorized for this member';
  end if;
  insert into public.member_notes(member_id,note_text,updated_at,updated_by)
  values(p_member_id,nullif(trim(coalesce(p_note,'')),''),now(),auth.uid())
  on conflict(member_id) do update
  set note_text=excluded.note_text,updated_at=excluded.updated_at,updated_by=excluded.updated_by;
  return query
    select mn.member_id,mn.note_text,mn.updated_at
    from public.member_notes mn
    where mn.member_id=p_member_id;
end;
$fn$;

revoke all on function public.save_service_note(uuid,text) from public;
grant execute on function public.save_service_note(uuid,text) to authenticated;

create or replace function public.delete_service_note(p_member_id uuid)
returns void
language plpgsql
security definer
set search_path=''
as $fn$
begin
  if not exists (select 1 from public.profiles p where p.id=auth.uid() and p.active=true) then
    raise exception 'not authorized';
  end if;
  if not exists (
    select 1 from public.members m
    where m.id=p_member_id and public.can_access_class(m.class_id)
  ) then
    raise exception 'not authorized for this member';
  end if;
  delete from public.member_notes where member_id=p_member_id;
end;
$fn$;

revoke all on function public.delete_service_note(uuid) from public;
grant execute on function public.delete_service_note(uuid) to authenticated;


-- Compatibility wrapper for older page code.
create or replace function public.save_member_note(p_member_id uuid, p_note text)
returns table(member_id uuid, note_text text, updated_at timestamptz)
language sql
security invoker
as $fn$
  select * from public.save_service_note(p_member_id, p_note);
$fn$;
revoke all on function public.save_member_note(uuid,text) from public;
grant execute on function public.save_member_note(uuid,text) to authenticated;


create or replace function public.get_members_for_notes()
returns table (
  id uuid,
  class_id uuid,
  class_name text,
  full_name text,
  birth_date date,
  address text,
  phone text,
  photo_url text,
  notes text,
  active boolean,
  created_at timestamptz
)
language sql
security definer
set search_path=''
as $fn$
  select m.id,m.class_id,c.name,m.full_name,m.birth_date,m.address,m.phone,m.photo_url,
         coalesce(mn.note_text,m.notes) as notes,m.active,m.created_at
  from public.members m
  left join public.classes c on c.id=m.class_id
  left join public.member_notes mn on mn.member_id=m.id
  where m.active=true
    and public.can_access_class(m.class_id)
  order by m.created_at desc;
$fn$
revoke all on function public.get_members_for_notes() from public;
grant execute on function public.get_members_for_notes() to authenticated;

-- صلاحيات الجدول للدوال/المستخدمين.
grant select, insert, update, delete on public.member_notes to authenticated;

-- =========================
-- ملاحظات: قصر القراءة/الكتابة على المخدومين الذين يستطيع الحساب رؤيتهم
-- =========================
DROP POLICY IF EXISTS member_notes_select_active ON public.member_notes;
DROP POLICY IF EXISTS member_notes_insert_active ON public.member_notes;
DROP POLICY IF EXISTS member_notes_update_active ON public.member_notes;
DROP POLICY IF EXISTS member_notes_delete_active ON public.member_notes;

CREATE POLICY member_notes_select_active ON public.member_notes
FOR SELECT TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.members m ON m.id = member_notes.member_id
    WHERE p.id = auth.uid() AND p.active = true
      AND public.can_access_class(m.class_id)
  )
);

CREATE POLICY member_notes_insert_active ON public.member_notes
FOR INSERT TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.members m ON m.id = member_notes.member_id
    WHERE p.id = auth.uid() AND p.active = true
      AND public.can_access_class(m.class_id)
  )
);

CREATE POLICY member_notes_update_active ON public.member_notes
FOR UPDATE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.members m ON m.id = member_notes.member_id
    WHERE p.id = auth.uid() AND p.active = true
      AND public.can_access_class(m.class_id)
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.members m ON m.id = member_notes.member_id
    WHERE p.id = auth.uid() AND p.active = true
      AND public.can_access_class(m.class_id)
  )
);

CREATE POLICY member_notes_delete_active ON public.member_notes
FOR DELETE TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.members m ON m.id = member_notes.member_id
    WHERE p.id = auth.uid() AND p.active = true
      AND public.can_access_class(m.class_id)
  )
);

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.member_notes;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;
