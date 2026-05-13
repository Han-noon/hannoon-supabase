CREATE EXTENSION IF NOT EXISTS pg_trgm SCHEMA extensions;

CREATE INDEX IF NOT EXISTS topics_title_trgm_idx   ON public.topics USING gin (title   extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS topics_summary_trgm_idx  ON public.topics USING gin (summary extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS events_title_trgm_idx   ON public.events USING gin (title   extensions.gin_trgm_ops);
CREATE INDEX IF NOT EXISTS events_summary_trgm_idx  ON public.events USING gin (summary extensions.gin_trgm_ops);


CREATE OR REPLACE FUNCTION public.get_topics(
  p_search   text            DEFAULT NULL,
  p_category public.category DEFAULT NULL,
  p_page     int             DEFAULT NULL,
  p_size     int             DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_total_count int;
  v_total_pages int;
  v_topics      json;
BEGIN
  p_page   := COALESCE(p_page, 1);
  p_size   := COALESCE(p_size, 9);
  p_search := NULLIF(TRIM(p_search), '');

  IF p_page < 1 THEN
    RAISE EXCEPTION 'page는 1 이상이어야 합니다';
  END IF;

  IF p_size < 1 THEN
    RAISE EXCEPTION 'size는 1 이상이어야 합니다';
  END IF;
  p_size := LEAST(p_size, 100);

  SELECT COUNT(*)
  INTO v_total_count
  FROM public.topics t
  WHERE
    (p_category IS NULL OR t.category = p_category)
    AND (p_search IS NULL
         OR extensions.word_similarity(p_search, t.title)   > 0.3
         OR extensions.word_similarity(p_search, t.summary) > 0.3);

  v_total_pages := CEIL(v_total_count::numeric / p_size);

  IF auth.uid() IS NOT NULL THEN
    SELECT array_to_json(array_agg(row_to_json(r)))
    INTO v_topics
    FROM (
      SELECT
        t.id,
        t.category,
        t.title,
        t.summary,
        t.created_at,
        t.updated_at,
        s.id             AS subscription_id,
        s.id IS NOT NULL AS is_subscribed
      FROM public.topics t
      LEFT JOIN public.subscriptions s
        ON s.topic_id = t.id AND s.user_id = auth.uid()
      WHERE
        (p_category IS NULL OR t.category = p_category)
        AND (p_search IS NULL
             OR extensions.word_similarity(p_search, t.title)   > 0.3
             OR extensions.word_similarity(p_search, t.summary) > 0.3)
      ORDER BY t.id DESC
      LIMIT  p_size
      OFFSET (p_page - 1) * p_size
    ) r;
  ELSE
    SELECT array_to_json(array_agg(row_to_json(r)))
    INTO v_topics
    FROM (
      SELECT
        t.id,
        t.category,
        t.title,
        t.summary,
        t.created_at,
        t.updated_at,
        NULL::bigint AS subscription_id,
        false        AS is_subscribed
      FROM public.topics t
      WHERE
        (p_category IS NULL OR t.category = p_category)
        AND (p_search IS NULL
             OR extensions.word_similarity(p_search, t.title)   > 0.3
             OR extensions.word_similarity(p_search, t.summary) > 0.3)
      ORDER BY t.id DESC
      LIMIT  p_size
      OFFSET (p_page - 1) * p_size
    ) r;
  END IF;

  RETURN json_build_object(
    'topics',      COALESCE(v_topics, '[]'::json),
    'page',        p_page,
    'size',        p_size,
    'total_count', v_total_count,
    'total_pages', v_total_pages
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_topics(text, public.category, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_topics(text, public.category, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_topics(text, public.category, int, int) TO service_role;


CREATE OR REPLACE FUNCTION public.get_subscribed_topics(
  p_page int DEFAULT NULL,
  p_size int DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_total_count int;
  v_total_pages int;
  v_topics      json;
BEGIN
  p_page := COALESCE(p_page, 1);
  p_size := COALESCE(p_size, 9);

  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION '로그인이 필요합니다';
  END IF;

  IF p_page < 1 THEN
    RAISE EXCEPTION 'page는 1 이상이어야 합니다';
  END IF;

  IF p_size < 1 THEN
    RAISE EXCEPTION 'size는 1 이상이어야 합니다';
  END IF;
  p_size := LEAST(p_size, 100);

  SELECT COUNT(*)
  INTO v_total_count
  FROM public.topics t
  INNER JOIN public.subscriptions s ON s.topic_id = t.id AND s.user_id = auth.uid();

  v_total_pages := CEIL(v_total_count::numeric / p_size);

  SELECT array_to_json(array_agg(row_to_json(r)))
  INTO v_topics
  FROM (
    SELECT
      t.id,
      t.category,
      t.title,
      t.summary,
      t.created_at,
      t.updated_at,
      s.id AS subscription_id,
      true AS is_subscribed
    FROM public.topics t
    INNER JOIN public.subscriptions s ON s.topic_id = t.id AND s.user_id = auth.uid()
    ORDER BY t.id DESC
    LIMIT  p_size
    OFFSET (p_page - 1) * p_size
  ) r;

  RETURN json_build_object(
    'topics',      COALESCE(v_topics, '[]'::json),
    'page',        p_page,
    'size',        p_size,
    'total_count', v_total_count,
    'total_pages', v_total_pages
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_subscribed_topics(int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_subscribed_topics(int, int) TO service_role;


CREATE OR REPLACE FUNCTION public.get_events(
  p_search   text            DEFAULT NULL,
  p_category public.category DEFAULT NULL,
  p_page     int             DEFAULT NULL,
  p_size     int             DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_total_count int;
  v_total_pages int;
  v_events      json;
BEGIN
  p_page   := COALESCE(p_page, 1);
  p_size   := COALESCE(p_size, 9);
  p_search := NULLIF(TRIM(p_search), '');

  IF p_page < 1 THEN
    RAISE EXCEPTION 'page는 1 이상이어야 합니다';
  END IF;

  IF p_size < 1 THEN
    RAISE EXCEPTION 'size는 1 이상이어야 합니다';
  END IF;
  p_size := LEAST(p_size, 100);

  SELECT COUNT(*)
  INTO v_total_count
  FROM public.events e
  WHERE
    (p_category IS NULL OR e.category = p_category)
    AND (p_search IS NULL
         OR extensions.word_similarity(p_search, e.title)   > 0.3
         OR extensions.word_similarity(p_search, e.summary) > 0.3);

  v_total_pages := CEIL(v_total_count::numeric / p_size);

  IF auth.uid() IS NOT NULL THEN
    SELECT array_to_json(array_agg(row_to_json(r)))
    INTO v_events
    FROM (
      SELECT
        e.id         AS event_id,
        e.topic_id,
        e.category,
        e.title,
        e.summary,
        e.created_at,
        e.updated_at,
        s.id             AS subscription_id,
        s.id IS NOT NULL AS is_subscribed
      FROM public.events e
      LEFT JOIN public.subscriptions s
        ON s.topic_id = e.topic_id AND s.user_id = auth.uid()
      WHERE
        (p_category IS NULL OR e.category = p_category)
        AND (p_search IS NULL
             OR extensions.word_similarity(p_search, e.title)   > 0.3
             OR extensions.word_similarity(p_search, e.summary) > 0.3)
      ORDER BY e.id DESC
      LIMIT  p_size
      OFFSET (p_page - 1) * p_size
    ) r;
  ELSE
    SELECT array_to_json(array_agg(row_to_json(r)))
    INTO v_events
    FROM (
      SELECT
        e.id         AS event_id,
        e.topic_id,
        e.category,
        e.title,
        e.summary,
        e.created_at,
        e.updated_at,
        NULL::bigint AS subscription_id,
        false        AS is_subscribed
      FROM public.events e
      WHERE
        (p_category IS NULL OR e.category = p_category)
        AND (p_search IS NULL
             OR extensions.word_similarity(p_search, e.title)   > 0.3
             OR extensions.word_similarity(p_search, e.summary) > 0.3)
      ORDER BY e.id DESC
      LIMIT  p_size
      OFFSET (p_page - 1) * p_size
    ) r;
  END IF;

  RETURN json_build_object(
    'events',      COALESCE(v_events, '[]'::json),
    'page',        p_page,
    'size',        p_size,
    'total_count', v_total_count,
    'total_pages', v_total_pages
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_events(text, public.category, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.get_events(text, public.category, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_events(text, public.category, int, int) TO service_role;
