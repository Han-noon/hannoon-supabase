-- =============================================================
-- 조회 로그 + 실시간 인기 타임라인
-- =============================================================
-- 홈의 "실시간 인기 타임라인"은 최근 1시간 조회수 1위 토픽의 타임라인을 보여준다.
-- 이벤트 상세(/event-detail/:id)·토픽 페이지(/timeline/:topic_id)를 열 때마다 웹이
-- record_topic_view()를 호출해 한 줄씩 쌓는다. 비로그인 사용자는 브라우저 난수(viewer_key)가 있을 때만 기록한다.
--
-- viewed_events(최근 본 이벤트)를 재사용하지 않는 이유: 로그인 사용자만, 사람당 이벤트 1행이라
-- 조회수를 셀 수 없다.
--
-- topic_views는 anon/authenticated에 권한을 주지 않는다(원시 로그 노출 방지).
-- 기록·집계·정리는 아래 SECURITY DEFINER 함수로만 한다.
--
-- 보관: pg_cron이 매시간 purge_topic_views()를 실행해 7일 지난 로그를 지우고,
-- 1일 지난 행의 식별자(user_id, viewer_key)를 비운다. 식별자는 10분 중복 제한에만 쓴다.
--
-- 알려진 한계: anon 키로 누구나 호출할 수 있고 요청자(IP) 기준 제한이 없어, viewer_key를 바꿔 가며
-- 호출하면 조회수를 부풀릴 수 있다. 이벤트의 토픽이 나중에 바뀌어도 과거 조회는 조회 시점 토픽에 남는다.
-- =============================================================

CREATE TABLE public.topic_views (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  topic_id   bigint    NOT NULL REFERENCES public.topics(id)   ON DELETE CASCADE,
  event_id   bigint             REFERENCES public.events(id)   ON DELETE CASCADE,  -- NULL = 토픽 페이지 조회
  user_id    uuid               REFERENCES public.profiles(id) ON DELETE SET NULL, -- 로그인 사용자 (비로그인은 NULL)
  viewer_key text,                                                                  -- 비로그인 사용자 브라우저 난수 (중복 조회 제한용)
  viewed_at  timestamp NOT NULL DEFAULT now()
);

-- 인기 집계: viewed_at 범위 → topic_id 그룹
CREATE INDEX topic_views_viewed_at_topic_id_idx ON public.topic_views USING btree (viewed_at, topic_id);
-- 중복 조회 확인: 같은 토픽의 최근 10분
CREATE INDEX topic_views_topic_id_viewed_at_idx ON public.topic_views USING btree (topic_id, viewed_at);
-- 외래키: 이벤트 삭제(CASCADE)·회원 탈퇴(SET NULL) 시 전체 스캔 방지
CREATE INDEX topic_views_event_id_idx ON public.topic_views USING btree (event_id) WHERE event_id IS NOT NULL;
CREATE INDEX topic_views_user_id_idx  ON public.topic_views USING btree (user_id)  WHERE user_id IS NOT NULL;
-- 식별자 비우기 대상 (이미 비운 행은 인덱스에서 빠진다)
CREATE INDEX topic_views_identified_viewed_at_idx ON public.topic_views USING btree (viewed_at)
  WHERE user_id IS NOT NULL OR viewer_key IS NOT NULL;

-- 정책 없음: anon/authenticated는 직접 읽고 쓸 수 없고, 아래 함수로만 접근한다
ALTER TABLE public.topic_views ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.topic_views FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.topic_views TO service_role;


-- -------------------------------------------------------------
-- record_topic_view: 토픽 페이지 또는 이벤트 상세 조회 1건 기록
--   p_topic_id와 p_event_id 중 정확히 하나를 지정한다.
--   이벤트 조회는 그 이벤트가 속한 토픽의 조회로 센다.
--   비로그인인데 viewer_key가 없으면(빈 문자열 포함) 중복 제한을 할 수 없으므로 기록하지 않는다.
--   토픽 미배정 이벤트, 존재하지 않는 id는 조용히 기록하지 않는다(화면이 깨지지 않게).
--   같은 사람(로그인: user_id, 비로그인: viewer_key)이 같은 화면을 10분 안에 다시 열면 한 번만 센다.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.record_topic_view(
  p_topic_id   bigint DEFAULT NULL,
  p_event_id   bigint DEFAULT NULL,
  p_viewer_key text   DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'Asia/Seoul'  -- 요청 단위 타임존 지정으로 viewed_at·중복 확인 창이 어긋나지 않게
AS $$
DECLARE
  v_user_id  uuid := auth.uid();
  v_topic_id bigint;
BEGIN
  IF (p_topic_id IS NULL) = (p_event_id IS NULL) THEN
    RAISE EXCEPTION 'topic_id와 event_id 중 하나만 지정해야 합니다';
  END IF;

  IF length(p_viewer_key) > 64 THEN
    RAISE EXCEPTION 'viewer_key는 64자 이하여야 합니다';
  END IF;

  p_viewer_key := NULLIF(p_viewer_key, '');
  IF v_user_id IS NULL AND p_viewer_key IS NULL THEN
    RETURN;
  END IF;

  IF p_event_id IS NOT NULL THEN
    SELECT e.topic_id INTO v_topic_id FROM public.events e WHERE e.id = p_event_id;
  ELSE
    SELECT t.id INTO v_topic_id FROM public.topics t WHERE t.id = p_topic_id;
  END IF;

  IF v_topic_id IS NULL THEN
    RETURN;
  END IF;

  -- 같은 사람의 동시 호출(탭 여러 개, 연속 클릭)이 확인과 삽입 사이에서 둘 다 통과하지 않도록 직렬화
  PERFORM pg_advisory_xact_lock(
    hashtextextended(concat_ws(':', COALESCE(v_user_id::text, p_viewer_key), v_topic_id, p_event_id), 0)
  );

  IF EXISTS (
    SELECT 1
    FROM public.topic_views v
    WHERE v.topic_id = v_topic_id
      AND v.viewed_at > now()::timestamp - interval '10 minutes'
      AND v.event_id IS NOT DISTINCT FROM p_event_id
      AND CASE WHEN v_user_id IS NOT NULL THEN v.user_id = v_user_id
               ELSE v.viewer_key = p_viewer_key END
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.topic_views (topic_id, event_id, user_id, viewer_key)
  VALUES (
    v_topic_id,
    p_event_id,
    v_user_id,
    CASE WHEN v_user_id IS NULL THEN p_viewer_key END  -- 로그인 사용자는 viewer_key를 저장하지 않는다
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_topic_view(bigint, bigint, text) TO anon;
GRANT EXECUTE ON FUNCTION public.record_topic_view(bigint, bigint, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_topic_view(bigint, bigint, text) TO service_role;


-- -------------------------------------------------------------
-- get_popular_topic_timeline: 최근 p_window_hours 시간 조회수 1위 토픽의 타임라인
--   조회는 실제 사용자 행동이므로 기사 데이터 최신 시각(as_of)이 아니라
--   views_as_of = now() 기준 (views_as_of - window, views_as_of] 로 센다.
--   정렬: 조회수 DESC → 마지막 조회 시각 DESC → topic_id
--   이벤트 부분은 get_live_topic_timeline 결과를 그대로 쓴다(p_size, p_active_hours 전달).
--   조회가 없으면 기사 수 랭킹으로 대체하지 않고 { topic: null, events: [], view_count: 0 }.
--   반환: get_live_topic_timeline 반환 + { window_hours, view_count, views_as_of }
--
--   주의: SECURITY DEFINER 안에서 호출하므로 get_live_topic_timeline도 소유자 권한으로 실행되어
--   topics/events/articles/event_articles의 RLS를 적용받지 않는다. 지금은 네 테이블 모두 전체 공개
--   읽기라 노출 차이가 없지만, 이 테이블들에 제한 정책을 추가하면 이 함수도 함께 검토할 것.
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_popular_topic_timeline(
  p_window_hours int DEFAULT NULL,
  p_size         int DEFAULT NULL,
  p_active_hours int DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
SET timezone = 'Asia/Seoul'
AS $$
DECLARE
  v_views_as_of timestamp := now()::timestamp;
  v_topic_id    bigint;
  v_view_count  int;
BEGIN
  p_window_hours := COALESCE(p_window_hours, 1);

  IF p_window_hours < 1 THEN
    RAISE EXCEPTION 'window_hours는 1 이상이어야 합니다';
  END IF;
  p_window_hours := LEAST(p_window_hours, 24);

  SELECT v.topic_id, COUNT(*)::int
  INTO v_topic_id, v_view_count
  FROM public.topic_views v
  WHERE v.viewed_at >  v_views_as_of - make_interval(hours => p_window_hours)
    AND v.viewed_at <= v_views_as_of
  GROUP BY v.topic_id
  ORDER BY COUNT(*) DESC, MAX(v.viewed_at) DESC, v.topic_id
  LIMIT 1;

  RETURN (
    public.get_live_topic_timeline(v_topic_id, p_size, p_active_hours)::jsonb
    || jsonb_build_object(
         'window_hours', p_window_hours,
         'view_count',   COALESCE(v_view_count, 0),
         'views_as_of',  v_views_as_of
       )
  )::json;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_popular_topic_timeline(int, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_popular_topic_timeline(int, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_popular_topic_timeline(int, int, int) TO service_role;


-- -------------------------------------------------------------
-- purge_topic_views: 조회 로그 보관 기간 정리 (pg_cron이 매시간 실행)
--   7일 지난 로그 삭제 — 인기 집계 창 상한(24시간)보다 넉넉하게 보관
--   1일 지난 행의 user_id·viewer_key 비우기 — 식별자는 10분 중복 제한에만 쓰고 집계에는 필요 없다
--   반환: { deleted, anonymized }
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.purge_topic_views()
RETURNS json
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
SET timezone = 'Asia/Seoul'
AS $$
DECLARE
  v_deleted    int;
  v_anonymized int;
BEGIN
  DELETE FROM public.topic_views
  WHERE viewed_at < now()::timestamp - interval '7 days';
  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  UPDATE public.topic_views
  SET user_id = NULL, viewer_key = NULL
  WHERE viewed_at < now()::timestamp - interval '1 day'
    AND (user_id IS NOT NULL OR viewer_key IS NOT NULL);
  GET DIAGNOSTICS v_anonymized = ROW_COUNT;

  RETURN json_build_object('deleted', v_deleted, 'anonymized', v_anonymized);
END;
$$;

-- 함수의 PUBLIC EXECUTE는 Postgres 전역 기본값이라 스키마 단위 기본 권한 회수(20260501120000)로는 막히지 않는다
REVOKE EXECUTE ON FUNCTION public.purge_topic_views() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.purge_topic_views() TO service_role;

-- 매시 17분에 정리 (정각 몰림 회피). 같은 이름·같은 사용자로 다시 등록하면 cron.schedule이 기존 작업을 갱신한다.
CREATE EXTENSION IF NOT EXISTS pg_cron WITH SCHEMA pg_catalog;
SELECT cron.schedule('purge-topic-views', '17 * * * *', $$SELECT public.purge_topic_views()$$);
