-- =============================================================
-- get_hot_topics: 순위는 시간창, 표시 숫자는 누적으로 분리
-- =============================================================
-- 홈의 핫 토픽 카드는 "관련 기사 142개"처럼 토픽 누적 기사 수를 보여주는데,
-- 20260913120000의 article_count는 시간창 안 기사만 세서 훨씬 작은 값이 내려갔다.
--
--   article_count        = 토픽 누적 기사 수 (published_at <= as_of)  ← 화면 표시용
--   window_article_count = 시간창 안 기사 수                          ← 순위 근거
--
-- 순위와 창 밖 토픽 제외 동작은 그대로 유지한다.
-- =============================================================

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
        COUNT(DISTINCT a.id)::int                             AS article_count,
        COUNT(DISTINCT a.id) FILTER (WHERE w.in_window)::int  AS window_article_count,
        MAX(a.published_at)  FILTER (WHERE w.in_window)       AS last_published_at
      FROM public.articles a
      JOIN public.event_articles ea ON ea.article_id = a.id
      JOIN public.events e          ON e.id = ea.event_id
      CROSS JOIN LATERAL (
        SELECT a.published_at > v_as_of - make_interval(hours => p_window_hours)
      ) w(in_window)
      WHERE e.topic_id IS NOT NULL
        AND a.published_at <= v_as_of
      GROUP BY e.topic_id
      -- 창 안에 기사가 없는 토픽은 순위에 올리지 않는다
      HAVING COUNT(DISTINCT a.id) FILTER (WHERE w.in_window) > 0
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
