CREATE OR REPLACE FUNCTION public.get_event(
  p_event_id bigint
)
RETURNS json
LANGUAGE plpgsql
STABLE
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
  ) e;

  IF v_event IS NULL THEN
    RAISE EXCEPTION '존재하지 않는 이벤트입니다';
  END IF;

  RETURN v_event;
END;
$$;
