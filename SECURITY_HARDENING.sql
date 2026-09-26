-- خدمة الأمير — حزمة تقوية قاعدة البيانات
-- هذه الحزمة لا تحذف بيانات. نفّذها مرة واحدة في Supabase SQL Editor.
-- قبل التشغيل يُفضّل أخذ نسخة احتياطية من المشروع.

-- 1) إزالة السياسات القديمة المتعددة ثم وضع سياسة واحدة واضحة لكل عملية.
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT schemaname, tablename, policyname
    FROM pg_policies
    WHERE schemaname='public'
      AND tablename IN ('classes','members','class_servants','attendance','visits','notifications','member_points','member_notes','profiles')
  LOOP
    EXECUTE format('drop policy if exists %I on %I.%I',r.policyname,r.schemaname,r.tablename);
  END LOOP;
END $$;

ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_servants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_points ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.member_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- لا وصول مجهول.
REVOKE ALL ON public.classes,public.members,public.class_servants,public.attendance,
  public.visits,public.notifications,public.member_points,public.member_notes,public.profiles
FROM anon;

GRANT SELECT,INSERT,UPDATE,DELETE ON public.classes TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.members TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.class_servants TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.attendance TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.visits TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.notifications TO authenticated;
GRANT SELECT ON public.member_points TO authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON public.member_notes TO authenticated;
GRANT SELECT ON public.profiles TO authenticated;

-- الفصول
CREATE POLICY classes_select_access ON public.classes FOR SELECT TO authenticated
USING ((SELECT public.is_manager()) OR (SELECT public.can_access_class(id)));

CREATE POLICY classes_insert_manager ON public.classes FOR INSERT TO authenticated
WITH CHECK ((SELECT public.is_manager()));

CREATE POLICY classes_update_manager ON public.classes FOR UPDATE TO authenticated
USING ((SELECT public.is_manager())) WITH CHECK ((SELECT public.is_manager()));

CREATE POLICY classes_delete_manager ON public.classes FOR DELETE TO authenticated
USING ((SELECT public.is_manager()));

-- المخدومون: الخادم يستطيع الإضافة في فصل مسند إليه، والمدير هو من يعدل/يحذف.
CREATE POLICY members_select_access ON public.members FOR SELECT TO authenticated
USING ((SELECT public.can_access_class(class_id)));

CREATE POLICY members_insert_access ON public.members FOR INSERT TO authenticated
WITH CHECK ((SELECT public.can_access_class(class_id)));

CREATE POLICY members_update_manager ON public.members FOR UPDATE TO authenticated
USING ((SELECT public.is_manager())) WITH CHECK ((SELECT public.is_manager()));

CREATE POLICY members_delete_manager ON public.members FOR DELETE TO authenticated
USING ((SELECT public.is_manager()));

-- إسنادات الفصول: الإدارة فقط تغيّر الإسناد، والخادم يرى إسناداته.
CREATE POLICY class_servants_select_access ON public.class_servants FOR SELECT TO authenticated
USING ((SELECT public.is_manager()) OR user_id=(SELECT auth.uid()));

CREATE POLICY class_servants_insert_manager ON public.class_servants FOR INSERT TO authenticated
WITH CHECK ((SELECT public.is_manager()));

CREATE POLICY class_servants_update_manager ON public.class_servants FOR UPDATE TO authenticated
USING ((SELECT public.is_manager())) WITH CHECK ((SELECT public.is_manager()));

CREATE POLICY class_servants_delete_manager ON public.class_servants FOR DELETE TO authenticated
USING ((SELECT public.is_manager()));

-- الحضور
CREATE POLICY attendance_select_access ON public.attendance FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY attendance_insert_access ON public.attendance FOR INSERT TO authenticated
WITH CHECK (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY attendance_update_access ON public.attendance FOR UPDATE TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)))
WITH CHECK (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY attendance_delete_access ON public.attendance FOR DELETE TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

-- الزيارات
CREATE POLICY visits_select_access ON public.visits FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY visits_insert_access ON public.visits FOR INSERT TO authenticated
WITH CHECK (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY visits_update_access ON public.visits FOR UPDATE TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)))
WITH CHECK (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY visits_delete_access ON public.visits FOR DELETE TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

-- الإشعارات مرتبطة بالفصل.
CREATE POLICY notifications_select_access ON public.notifications FOR SELECT TO authenticated
USING ((SELECT public.is_manager()) OR public.can_access_class(class_id));

CREATE POLICY notifications_insert_access ON public.notifications FOR INSERT TO authenticated
WITH CHECK ((SELECT public.is_manager()) OR public.can_access_class(class_id));

CREATE POLICY notifications_update_access ON public.notifications FOR UPDATE TO authenticated
USING ((SELECT public.is_manager()) OR public.can_access_class(class_id))
WITH CHECK ((SELECT public.is_manager()) OR public.can_access_class(class_id));

CREATE POLICY notifications_delete_access ON public.notifications FOR DELETE TO authenticated
USING ((SELECT public.is_manager()) OR public.can_access_class(class_id));

-- النقاط: القراءة فقط مباشرة؛ التعديل عبر RPCs المحمية.
CREATE POLICY member_points_select_access ON public.member_points FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

-- الملاحظات
CREATE POLICY member_notes_select_access ON public.member_notes FOR SELECT TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY member_notes_insert_access ON public.member_notes FOR INSERT TO authenticated
WITH CHECK (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY member_notes_update_access ON public.member_notes FOR UPDATE TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)))
WITH CHECK (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

CREATE POLICY member_notes_delete_access ON public.member_notes FOR DELETE TO authenticated
USING (EXISTS (SELECT 1 FROM public.members m WHERE m.id=member_id AND public.can_access_class(m.class_id)));

-- الحسابات: كل مستخدم يرى نفسه، والمدير يرى الجميع.
CREATE POLICY profiles_select_access ON public.profiles FOR SELECT TO authenticated
USING (id=(SELECT auth.uid()) OR (SELECT public.is_manager()));

-- 2) منع بقاء النظام بلا مدير.
CREATE OR REPLACE FUNCTION public.manager_set_user_role(p_user_id uuid,p_role text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $fn$
DECLARE v_role text;
BEGIN
  IF NOT public.is_manager() THEN RAISE EXCEPTION 'مدير الخدمة فقط'; END IF;
  IF p_user_id=(SELECT auth.uid()) THEN RAISE EXCEPTION 'لا يمكن تغيير دور حسابك بنفسك'; END IF;
  IF p_role NOT IN ('manager','servant') THEN RAISE EXCEPTION 'الدور غير صالح'; END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id=p_user_id;
  IF v_role IS NULL THEN RAISE EXCEPTION 'الخادم غير موجود'; END IF;
  IF v_role='manager' AND p_role='servant'
     AND (SELECT count(*) FROM public.profiles WHERE role='manager' AND active=true)<=1
  THEN RAISE EXCEPTION 'لا يمكن إزالة آخر مدير نشط'; END IF;
  UPDATE public.profiles SET role=p_role,updated_at=now() WHERE id=p_user_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.manager_set_user_role(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.manager_set_user_role(uuid,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.manager_set_user_active(p_user_id uuid,p_active boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $fn$
DECLARE v_role text;
BEGIN
  IF NOT public.is_manager() THEN RAISE EXCEPTION 'مدير الخدمة فقط'; END IF;
  IF p_user_id=(SELECT auth.uid()) THEN RAISE EXCEPTION 'لا يمكن تعطيل حسابك بنفسك'; END IF;
  SELECT role INTO v_role FROM public.profiles WHERE id=p_user_id;
  IF v_role IS NULL THEN RAISE EXCEPTION 'الخادم غير موجود'; END IF;
  IF v_role='manager' AND p_active=false
     AND (SELECT count(*) FROM public.profiles WHERE role='manager' AND active=true)<=1
  THEN RAISE EXCEPTION 'لا يمكن تعطيل آخر مدير نشط'; END IF;
  UPDATE public.profiles SET active=p_active,updated_at=now() WHERE id=p_user_id;
END;
$fn$;

REVOKE ALL ON FUNCTION public.manager_set_user_active(uuid,boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.manager_set_user_active(uuid,boolean) TO authenticated;

-- 3) تنظيف سجلات المخدوم قبل حذفه حتى لا يفشل الحذف بسبب FK قديم.
CREATE OR REPLACE FUNCTION public.cleanup_member_children()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=''
AS $fn$
BEGIN
  DELETE FROM public.attendance WHERE member_id=OLD.id;
  DELETE FROM public.visits WHERE member_id=OLD.id;
  DELETE FROM public.notifications WHERE member_id=OLD.id;
  DELETE FROM public.member_points WHERE member_id=OLD.id;
  DELETE FROM public.member_notes WHERE member_id=OLD.id;
  RETURN OLD;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_cleanup_member_children ON public.members;
CREATE TRIGGER trg_cleanup_member_children
BEFORE DELETE ON public.members
FOR EACH ROW EXECUTE FUNCTION public.cleanup_member_children();

REVOKE ALL ON FUNCTION public.cleanup_member_children() FROM PUBLIC;

-- 4) صور المخدومين: خارج قاعدة البيانات في Storage.
-- bucket عام للصور فقط؛ الرفع/الحذف يظل محكومًا بسياسات Storage.
INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES ('member-photos','member-photos',true,1048576,ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET public=true,file_size_limit=1048576,allowed_mime_types=ARRAY['image/jpeg','image/png','image/webp'];

DROP POLICY IF EXISTS member_photos_insert_authenticated ON storage.objects;
DROP POLICY IF EXISTS member_photos_select_authenticated ON storage.objects;
DROP POLICY IF EXISTS member_photos_update_authenticated ON storage.objects;
DROP POLICY IF EXISTS member_photos_delete_manager ON storage.objects;

CREATE POLICY member_photos_insert_authenticated ON storage.objects
FOR INSERT TO authenticated
WITH CHECK (bucket_id='member-photos');

CREATE POLICY member_photos_select_authenticated ON storage.objects
FOR SELECT TO authenticated
USING (bucket_id='member-photos');

CREATE POLICY member_photos_update_authenticated ON storage.objects
FOR UPDATE TO authenticated
USING (bucket_id='member-photos')
WITH CHECK (bucket_id='member-photos');

CREATE POLICY member_photos_delete_manager ON storage.objects
FOR DELETE TO authenticated
USING (bucket_id='member-photos' AND (SELECT public.is_manager()));

-- 5) فهارس صغيرة للسياسات/التقارير.
CREATE INDEX IF NOT EXISTS idx_members_class_id ON public.members(class_id);
CREATE INDEX IF NOT EXISTS idx_attendance_member_date ON public.attendance(member_id,attendance_date);
CREATE INDEX IF NOT EXISTS idx_visits_member_date ON public.visits(member_id,visit_date);
CREATE INDEX IF NOT EXISTS idx_notifications_class_created ON public.notifications(class_id,created_at DESC);
CREATE INDEX IF NOT EXISTS idx_class_servants_user_class ON public.class_servants(user_id,class_id);
