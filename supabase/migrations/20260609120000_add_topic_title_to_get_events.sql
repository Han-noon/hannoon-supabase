-- get_events: 응답에 topic_title 추가 (topics 테이블 JOIN)

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
    e.topic_id IS NOT NULL
    AND (p_category IS NULL OR e.category = p_category)
    AND (p_search IS NULL
         OR extensions.word_similarity(p_search, e.title)   > 0.3
         OR extensions.word_similarity(p_search, e.summary) > 0.3);

  v_total_pages := CEIL(v_total_count::numeric / p_size);

  IF auth.uid() IS NOT NULL THEN
    SELECT array_to_json(array_agg(row_to_json(r)))
    INTO v_events
    FROM (
      SELECT
        e.topic_id,
        e.id         AS event_id,
        t.title      AS topic_title,  -- 추가
        e.title      AS event_title,
        e.category,
        e.summary,
        e.created_at,
        e.updated_at,
        s.id             AS subscription_id,
        s.id IS NOT NULL AS is_subscribed
      FROM public.events e
      JOIN public.topics t ON t.id = e.topic_id
      LEFT JOIN public.subscriptions s
        ON s.topic_id = e.topic_id AND s.user_id = auth.uid()
      WHERE
        e.topic_id IS NOT NULL
        AND (p_category IS NULL OR e.category = p_category)
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
        e.topic_id,
        e.id         AS event_id,
        t.title      AS topic_title,  -- 추가
        e.title     AS event_title,
        e.category,
        e.summary,
        e.created_at,
        e.updated_at,
        NULL::bigint AS subscription_id,
        false        AS is_subscribed
      FROM public.events e
      JOIN public.topics t ON t.id = e.topic_id
      WHERE
        e.topic_id IS NOT NULL
        AND (p_category IS NULL OR e.category = p_category)
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
