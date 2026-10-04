-- =============================================================
-- 토픽 타임라인(서브토픽) 조회 RPC
--   get_topic_subtopic_timeline(p_topic_id)
-- =============================================================
-- 웹 TimelinePage의 시연용 배열을 대체한다. 한 번 호출로 헤더·서브토픽 탭·타임라인 노드·이벤트 상세
-- 패널을 채운다. 상세 패널의 주요 보도는 get_articles_by_event(p_order = 'desc')를 그대로 쓴다.
-- 노드 클릭에 get_event를 쓰지 않는 것은 로그인 사용자 호출마다 viewed_events에 기록이 남기 때문이다.
--
-- 이벤트는 서브토픽 아래에 넣지 않고 한 번만 내리며 각 이벤트에 subtopic_ids를 붙인다.
-- 화면이 타임라인 하나에서 고른 서브토픽의 노드만 강조하고, 이벤트 하나가 여러 서브토픽에 속할 수 있어
-- (subtopic_events N:M) 서브토픽별로 넣으면 같은 이벤트가 여러 번 내려가기 때문이다.
--
-- 날짜·기사 수는 get_live_topic_timeline, get_topics와 같은 기준이다.
--   occurred_at = 소속 기사 MIN(published_at). event_articles(정상 기사)만 세고 미래 시각 기사는 뺀다.
--   기사가 없는 이벤트는 날짜를 정할 수 없어 뺀다. 서브토픽의 event_count·탭 순서도 화면에 나오는
--   이벤트로만 계산하고, 그런 이벤트가 하나도 없는 서브토픽은 내리지 않는다.
-- 그래서 20260930120000 헤더의 "같은 기사 수 정의가 네 곳"에 이 함수가 더해진다.
--
-- subtopics에 순서 컬럼이 없어 탭은 서브토픽의 첫 이벤트 날짜 → id 순이다.
-- subtopic_events의 같은 토픽 검사는 연결을 넣거나 바꿀 때만 돈다. 이벤트나 서브토픽의 topic_id가
-- 나중에 바뀌면 다른 토픽과의 연결이 남을 수 있어서, 이 토픽의 서브토픽·이벤트끼리의 연결만 센다.
-- =============================================================

CREATE OR REPLACE FUNCTION public.get_topic_subtopic_timeline(
  p_topic_id bigint
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_subscription_id bigint;
  v_topic           json;
  v_stats           json;
  v_subtopics       json;
  v_events          json;
BEGIN
  -- anon은 subscriptions 권한이 없어 참조만 해도 실패하므로, 구독 정보는 로그인일 때만 읽는다
  IF auth.uid() IS NOT NULL THEN
    SELECT s.id
    INTO v_subscription_id
    FROM public.subscriptions s
    WHERE s.topic_id = p_topic_id
      AND s.user_id = auth.uid();
  END IF;

  SELECT json_build_object(
    'id',              t.id,
    'title',           t.title,
    'category',        t.category,
    'summary',         t.summary,
    'ai_summary',      t.ai_summary,
    'subscription_id', v_subscription_id,
    'is_subscribed',   v_subscription_id IS NOT NULL
  )
  INTO v_topic
  FROM public.topics t
  WHERE t.id = p_topic_id;

  IF v_topic IS NULL THEN
    RAISE EXCEPTION '존재하지 않는 토픽입니다';
  END IF;

  WITH ta AS (
    SELECT e.id AS event_id, a.id AS article_id, a.published_at, a.bias_type
    FROM public.events e
    JOIN public.event_articles ea ON ea.event_id = e.id
    JOIN public.articles a        ON a.id = ea.article_id
    WHERE e.topic_id = p_topic_id
      AND a.published_at <= now()::timestamp
  ),
  ev AS (
    SELECT
      ta.event_id                                                              AS id,
      MIN(ta.published_at)                                                     AS occurred_at,
      COUNT(DISTINCT ta.article_id)::int                                       AS article_count,
      COUNT(DISTINCT ta.article_id) FILTER (WHERE ta.bias_type = '진보')::int AS left_count,
      COUNT(DISTINCT ta.article_id) FILTER (WHERE ta.bias_type = '중도')::int AS mid_count,
      COUNT(DISTINCT ta.article_id) FILTER (WHERE ta.bias_type = '보수')::int AS right_count
    FROM ta
    GROUP BY ta.event_id
  ),
  st AS (
    SELECT
      s.id,
      s.name,
      s.type,
      s.summary,
      COUNT(*)::int       AS event_count,
      MIN(ev.occurred_at) AS first_occurred_at
    FROM public.subtopics s
    JOIN public.subtopic_events se ON se.subtopic_id = s.id
    JOIN ev                        ON ev.id = se.event_id
    WHERE s.topic_id = p_topic_id
    GROUP BY s.id
  )
  SELECT
    (SELECT json_build_object(
       'first_published_at', MIN(ta.published_at),
       'last_published_at',  MAX(ta.published_at),
       'article_count',      COUNT(DISTINCT ta.article_id)::int,
       'event_count',        (SELECT COUNT(*)::int FROM ev)
     )
     FROM ta),
    (SELECT json_agg(json_build_object(
       'id',          st.id,
       'name',        st.name,
       'type',        st.type,
       'summary',     st.summary,
       'event_count', st.event_count
     ) ORDER BY st.first_occurred_at, st.id)
     FROM st),
    (SELECT json_agg(json_build_object(
       'id',            e.id,
       'title',         e.title,
       'short_summary', e.short_summary,
       'summary',       e.summary,
       'occurred_at',   ev.occurred_at,
       'subtopic_ids',  COALESCE(m.subtopic_ids, '[]'::json),
       'article_count', ev.article_count,
       'left_percent',  pct.left_percent,
       'mid_percent',   pct.mid_percent,
       'right_percent', pct.right_percent
     ) ORDER BY ev.occurred_at, ev.id)
     FROM ev
     JOIN public.events e ON e.id = ev.id
     CROSS JOIN LATERAL public.bias_percentages(ev.left_count, ev.mid_count, ev.right_count) pct
     LEFT JOIN LATERAL (
       SELECT json_agg(se.subtopic_id ORDER BY se.subtopic_id) AS subtopic_ids
       FROM public.subtopic_events se
       JOIN st ON st.id = se.subtopic_id
       WHERE se.event_id = ev.id
     ) m ON true)
  INTO v_stats, v_subtopics, v_events;

  RETURN json_build_object(
    'topic',     v_topic,
    'stats',     v_stats,
    'subtopics', COALESCE(v_subtopics, '[]'::json),
    'events',    COALESCE(v_events, '[]'::json)
  );
END;
$$;

-- 함수의 PUBLIC EXECUTE는 Postgres 기본값이라 회수한 뒤 역할별로 준다.
REVOKE EXECUTE ON FUNCTION public.get_topic_subtopic_timeline(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_topic_subtopic_timeline(bigint) TO anon;
GRANT EXECUTE ON FUNCTION public.get_topic_subtopic_timeline(bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_topic_subtopic_timeline(bigint) TO service_role;
