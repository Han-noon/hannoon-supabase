-- =============================================================
-- 홈 위젯 RPC: 오늘의 핫 토픽 랭킹 / 실시간 이슈 타임라인
-- =============================================================
-- 기준 시각(as_of) = LEAST(now(), MAX(articles.published_at))
--   수집이 멈췄거나 과거 기사 코퍼스로 시연할 때 now() 기준 시간창이
--   비는 것을 막는다. 수집이 정상 가동 중이면 now()와 거의 같다.
--
-- 이벤트 날짜 = 소속 기사의 MIN(published_at)
--   events.created_at은 파이프라인 적재 시각이라, 과거 기사를 백필하면
--   사건 날짜가 전부 적재일로 찍힌다.
-- =============================================================

-- 시간창 집계용 인덱스 (event_articles에는 event_id 인덱스만 있었다)
CREATE INDEX IF NOT EXISTS articles_published_at_idx     ON public.articles       USING btree (published_at);
CREATE INDEX IF NOT EXISTS event_articles_article_id_idx ON public.event_articles USING btree (article_id);


-- -------------------------------------------------------------
-- get_hot_topics: 기준 시각 직전 p_window_hours 시간 동안
-- 기사 수가 많은 토픽 순위
--   순위는 시간창 안 기사 수(window_article_count)로 매기고,
--   화면에 찍는 숫자는 토픽 누적 기사 수(article_count)다. 홈 카드가 "관련 기사 142개"처럼
--   누적을 보여주면서 순위는 최근 보도량을 따르기 때문에 두 숫자를 나눠서 반환한다.
--   반환: { as_of, window_hours,
--           topics: [ { rank, topic_id, title, category, article_count, window_article_count } ] }
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_hot_topics(
  p_window_hours int DEFAULT NULL,
  p_size         int DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_as_of  timestamp;
  v_topics json;
BEGIN
  p_window_hours := COALESCE(p_window_hours, 1);
  p_size         := COALESCE(p_size, 5);

  IF p_window_hours < 1 THEN
    RAISE EXCEPTION 'window_hours는 1 이상이어야 합니다';
  END IF;
  p_window_hours := LEAST(p_window_hours, 720);

  IF p_size < 1 THEN
    RAISE EXCEPTION 'size는 1 이상이어야 합니다';
  END IF;
  p_size := LEAST(p_size, 100);

  -- LEAST는 NULL을 무시하므로 기사가 하나도 없으면 now()
  SELECT LEAST(now()::timestamp, MAX(a.published_at))
  INTO v_as_of
  FROM public.articles a;

  SELECT array_to_json(array_agg(row_to_json(r) ORDER BY r.rank))
  INTO v_topics
  FROM (
    SELECT
      ROW_NUMBER() OVER (
        ORDER BY c.window_article_count DESC, c.last_published_at DESC, c.topic_id
      )                      AS rank,
      c.topic_id,
      t.title,
      t.category,
      c.article_count,
      c.window_article_count
    FROM (
      SELECT
        e.topic_id,
        COUNT(DISTINCT a.id)::int                       AS article_count,
        COUNT(DISTINCT a.id) FILTER (WHERE v_in_window)::int AS window_article_count,
        MAX(a.published_at)  FILTER (WHERE v_in_window)      AS last_published_at
      FROM public.articles a
      JOIN public.event_articles ea ON ea.article_id = a.id
      JOIN public.events e          ON e.id = ea.event_id
      CROSS JOIN LATERAL (
        SELECT a.published_at > v_as_of - make_interval(hours => p_window_hours)
      ) w(v_in_window)
      WHERE e.topic_id IS NOT NULL
        AND a.published_at <= v_as_of
      GROUP BY e.topic_id
      -- 창 안에 기사가 없는 토픽은 순위에 올리지 않는다
      HAVING COUNT(DISTINCT a.id) FILTER (WHERE v_in_window) > 0
    ) c
    JOIN public.topics t ON t.id = c.topic_id
    ORDER BY rank
    LIMIT p_size
  ) r;

  RETURN json_build_object(
    'as_of',        v_as_of,
    'window_hours', p_window_hours,
    'topics',       COALESCE(v_topics, '[]'::json)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_hot_topics(int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_hot_topics(int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_hot_topics(int, int) TO service_role;


-- -------------------------------------------------------------
-- get_live_topic_timeline: 지정 토픽의 최근 이벤트 p_size개 (오래된 → 최신)
--   is_latest: 가장 최근 이벤트
--   is_active: 가장 최근 이벤트에 기준 시각 직전 p_active_hours 시간 내 기사가 있음
--   기사가 없는 이벤트는 날짜를 정할 수 없으므로 제외한다.
--   기준 시각 이후(미래 시각) 기사는 get_hot_topics와 같이 제외한다.
--   토픽이 없으면 예외 대신 { topic: null, events: [] } — 홈 위젯이 깨지지 않게.
--   반환: { as_of, topic: { id, title, category } | null,
--           events: [ { id, title, occurred_at, article_count, is_latest, is_active } ] }
-- -------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_live_topic_timeline(
  p_topic_id     bigint,
  p_size         int DEFAULT NULL,
  p_active_hours int DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_as_of  timestamp;
  v_topic  json;
  v_events json;
BEGIN
  p_size         := COALESCE(p_size, 3);
  p_active_hours := COALESCE(p_active_hours, 24);

  IF p_size < 1 THEN
    RAISE EXCEPTION 'size는 1 이상이어야 합니다';
  END IF;
  p_size := LEAST(p_size, 100);

  IF p_active_hours < 1 THEN
    RAISE EXCEPTION 'active_hours는 1 이상이어야 합니다';
  END IF;
  p_active_hours := LEAST(p_active_hours, 720);

  SELECT LEAST(now()::timestamp, MAX(a.published_at))
  INTO v_as_of
  FROM public.articles a;

  SELECT json_build_object('id', t.id, 'title', t.title, 'category', t.category)
  INTO v_topic
  FROM public.topics t
  WHERE t.id = p_topic_id;

  IF v_topic IS NULL THEN
    RETURN json_build_object(
      'as_of',  v_as_of,
      'topic',  NULL,
      'events', '[]'::json
    );
  END IF;

  SELECT array_to_json(array_agg(row_to_json(r) ORDER BY r.occurred_at, r.id))
  INTO v_events
  FROM (
    SELECT
      x.id,
      x.title,
      x.occurred_at,
      x.article_count,
      x.rn = 1 AS is_latest,
      x.rn = 1
        AND x.last_published_at > v_as_of - make_interval(hours => p_active_hours) AS is_active
    FROM (
      SELECT
        e.id,
        e.title,
        MIN(a.published_at)       AS occurred_at,
        MAX(a.published_at)       AS last_published_at,
        COUNT(DISTINCT a.id)::int AS article_count,
        ROW_NUMBER() OVER (ORDER BY MIN(a.published_at) DESC, e.id DESC) AS rn
      FROM public.events e
      JOIN public.event_articles ea ON ea.event_id = e.id
      JOIN public.articles a        ON a.id = ea.article_id
      WHERE e.topic_id = p_topic_id
        AND a.published_at <= v_as_of
      GROUP BY e.id, e.title
    ) x
    WHERE x.rn <= p_size
  ) r;

  RETURN json_build_object(
    'as_of',  v_as_of,
    'topic',  v_topic,
    'events', COALESCE(v_events, '[]'::json)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_live_topic_timeline(bigint, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_live_topic_timeline(bigint, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_live_topic_timeline(bigint, int, int) TO service_role;
