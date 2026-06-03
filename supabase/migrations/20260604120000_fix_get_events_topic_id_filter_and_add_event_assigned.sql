-- =============================================================
-- 1. article_ai_status enum에 event_assigned 추가
-- =============================================================
ALTER TYPE public.article_ai_status ADD VALUE 'event_assigned';


-- =============================================================
-- 2. get_event: topic_id IS NOT NULL 조건 추가
-- =============================================================
CREATE OR REPLACE FUNCTION public.get_event(
  p_event_id bigint
)
RETURNS json
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_event           json;
  v_subscription_id bigint;
  v_is_subscribed   boolean;
BEGIN
  IF auth.uid() IS NOT NULL THEN
    SELECT id INTO v_subscription_id
    FROM public.subscriptions
    WHERE topic_id = (SELECT topic_id FROM public.events WHERE id = p_event_id)
      AND user_id = auth.uid();
    v_is_subscribed := v_subscription_id IS NOT NULL;
  ELSE
    v_subscription_id := NULL;
    v_is_subscribed   := false;
  END IF;

  SELECT row_to_json(e) INTO v_event
  FROM (
    SELECT
      ev.topic_id,
      ev.id               AS event_id,
      t.title             AS topic_title,
      ev.title            AS event_title,
      ev.category,
      ev.summary,
      ev.article_count,
      ev.left_count,
      ev.mid_count,
      ev.right_count,
      ev.abusing_count,
      (
        SELECT jsonb_build_object(
          'left',  COALESCE(array_agg(DISTINCT a.publisher) FILTER (WHERE a.bias_type = '진보'), ARRAY[]::text[]),
          'mid',   COALESCE(array_agg(DISTINCT a.publisher) FILTER (WHERE a.bias_type = '중도'), ARRAY[]::text[]),
          'right', COALESCE(array_agg(DISTINCT a.publisher) FILTER (WHERE a.bias_type = '보수'), ARRAY[]::text[])
        )
        FROM public.event_articles ea
        JOIN public.articles a ON a.id = ea.article_id
        LEFT JOIN public.abusing_articles ab ON ab.article_id = ea.article_id AND ab.event_id = ea.event_id
        WHERE ea.event_id = ev.id
          AND ab.id IS NULL
      )                   AS publishers,
      ev.event_image_url,
      ev.created_at,
      ev.updated_at,
      ev.prev_event_id,
      ev.next_event_id,
      prev_ev.title       AS prev_event_title,
      next_ev.title       AS next_event_title,
      v_subscription_id   AS subscription_id,
      v_is_subscribed     AS is_subscribed
    FROM public.events ev
    LEFT JOIN public.topics t ON t.id = ev.topic_id
    LEFT JOIN public.events prev_ev ON prev_ev.id = ev.prev_event_id
    LEFT JOIN public.events next_ev ON next_ev.id = ev.next_event_id
    WHERE ev.id = p_event_id
      AND ev.topic_id IS NOT NULL  -- 추가
  ) e;

  IF v_event IS NULL THEN
    RAISE EXCEPTION '존재하지 않는 이벤트입니다';
  END IF;

  IF auth.uid() IS NOT NULL THEN
    INSERT INTO public.viewed_events (user_id, event_id)
    VALUES (auth.uid(), p_event_id)
    ON CONFLICT ON CONSTRAINT viewed_events_user_id_event_id_key
    DO UPDATE SET viewed_at = now();
  END IF;

  RETURN v_event;
END;
$$;

GRANT EXECUTE ON FUNCTION "public"."get_event"(bigint) TO "anon";
GRANT EXECUTE ON FUNCTION "public"."get_event"(bigint) TO "authenticated";
GRANT EXECUTE ON FUNCTION "public"."get_event"(bigint) TO "service_role";


-- =============================================================
-- 3. get_events: topic_id IS NOT NULL 조건 추가 (COUNT 쿼리 및 두 브랜치 모두)
-- =============================================================
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
    e.topic_id IS NOT NULL  -- 추가
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
