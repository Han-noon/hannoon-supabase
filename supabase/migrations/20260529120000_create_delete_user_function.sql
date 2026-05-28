-- 회원 탈퇴: auth.users 삭제 시 profiles → subscriptions/notifications 까지 연쇄 삭제되도록
-- 두 FK를 ON DELETE CASCADE 로 변경하고, 본인 계정 삭제용 delete_user() 함수를 추가한다.

alter table "public"."subscriptions" drop constraint "subscriptions_user_id_fkey";
alter table "public"."subscriptions" add constraint "subscriptions_user_id_fkey"
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

alter table "public"."notifications" drop constraint "notifications_user_id_fkey";
alter table "public"."notifications" add constraint "notifications_user_id_fkey"
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


CREATE OR REPLACE FUNCTION public.delete_user()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_user_id uuid := auth.uid();
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다.';
  END IF;

  -- profiles 는 auth.users 에 ON DELETE CASCADE 로 연결되어 있고,
  -- subscriptions/notifications 도 profiles 에 ON DELETE CASCADE 로 연결되어 있으므로
  -- auth.users 한 행만 삭제하면 관련 데이터가 모두 연쇄 삭제된다.
  DELETE FROM auth.users WHERE id = v_user_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.delete_user() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_user() TO authenticated;
