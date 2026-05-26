-- pg_net 재활성화 (20260501105142에서 제거됨)
CREATE EXTENSION IF NOT EXISTS "pg_net" WITH SCHEMA "extensions";


CREATE OR REPLACE FUNCTION public.notify_onesignal_on_notification_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RAISE NOTICE '[notify_onesignal] 트리거 실행: notification_id=%, user_id=%, topic_id=%',
    NEW.id, NEW.user_id, NEW.topic_id;

  -- net.http_post는 비동기(fire-and-forget): 호출 즉시 반환하므로 INSERT 트랜잭션을 블로킹하지 않는다.
  BEGIN
    PERFORM net.http_post(
      url     := coalesce(
        current_setting('app.settings.edge_function_url', true),
        'http://host.docker.internal:54321/functions/v1'  -- fallback URL (로컬 개발용)
      ) || '/notify-onesignal',
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        -- DB 트리거임을 Edge Function에서 검증하기 위한 공유 시크릿
        'Authorization', 'Bearer ' || current_setting('app.settings.webhook_secret', true)
      ),
      body    := row_to_json(NEW)::jsonb
    );
    RAISE NOTICE '[notify_onesignal] HTTP 요청 전송 완료: notification_id=%', NEW.id;
  EXCEPTION WHEN OTHERS THEN
    -- net.http_post 호출 자체 실패 (URL 설정 누락, pg_net 오류 등) 시 로그
    -- HTTP 응답 수준 실패(4xx/5xx)는 비동기이므로 net._http_response 테이블에서 확인
    RAISE WARNING '[notify_onesignal] HTTP 요청 전송 실패: notification_id=%, error=%',
      NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;


CREATE TRIGGER notify_onesignal_after_notification_insert
AFTER INSERT ON public.notifications
FOR EACH ROW
EXECUTE FUNCTION public.notify_onesignal_on_notification_insert();
