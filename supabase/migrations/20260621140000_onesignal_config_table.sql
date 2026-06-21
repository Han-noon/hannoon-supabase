-- OneSignal 트리거 설정 저장소
-- 커스텀 GUC는 ALTER DATABASE 설정에 superuser가 필요해 Supabase postgres role로는 불가.
-- 대신 설정을 일반 테이블에 두고 트리거가 읽는다. (private 스키마: API 미노출)

CREATE SCHEMA IF NOT EXISTS private;

CREATE TABLE IF NOT EXISTS private.app_config (
  key   text PRIMARY KEY,
  value text NOT NULL
);


-- 트리거 함수: current_setting() 대신 private.app_config에서 URL·시크릿을 읽는다.
CREATE OR REPLACE FUNCTION public.notify_onesignal_on_notification_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_url    text;
  v_secret text;
BEGIN
  SELECT value INTO v_url    FROM private.app_config WHERE key = 'edge_function_url';  -- 수정
  SELECT value INTO v_secret FROM private.app_config WHERE key = 'webhook_secret';     -- 수정

  RAISE NOTICE '[notify_onesignal] 트리거 실행: notification_id=%, user_id=%, topic_id=%',
    NEW.id, NEW.user_id, NEW.topic_id;

  -- net.http_post는 비동기(fire-and-forget): 호출 즉시 반환하므로 INSERT 트랜잭션을 블로킹하지 않는다.
  BEGIN
    PERFORM net.http_post(
      url     := coalesce(v_url, 'http://host.docker.internal:54321/functions/v1')  -- fallback URL (로컬 개발용)
                 || '/notify-onesignal',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        -- DB 트리거임을 Edge Function에서 검증하기 위한 공유 시크릿
        'Authorization', 'Bearer ' || v_secret
      ),
      body    := row_to_json(NEW)::jsonb
    );
    RAISE NOTICE '[notify_onesignal] HTTP 요청 전송 완료: notification_id=%', NEW.id;
  EXCEPTION WHEN OTHERS THEN
    -- net.http_post 호출 자체 실패 시 로그 (HTTP 4xx/5xx는 비동기이므로 net._http_response에서 확인)
    RAISE WARNING '[notify_onesignal] HTTP 요청 전송 실패: notification_id=%, error=%',
      NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;
