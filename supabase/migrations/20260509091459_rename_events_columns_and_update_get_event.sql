ALTER TABLE public.events RENAME COLUMN prev_event TO prev_event_id;
ALTER TABLE public.events RENAME COLUMN next_event TO next_event_id;


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
  v_event json;
BEGIN
  IF auth.uid() IS NOT NULL THEN
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
        ARRAY(
          SELECT DISTINCT a.publisher
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
        s.id                AS subscription_id,
        s.id IS NOT NULL    AS is_subscribed
      FROM public.events ev
      LEFT JOIN public.topics t ON t.id = ev.topic_id
      LEFT JOIN public.subscriptions s ON s.topic_id = ev.topic_id AND s.user_id = auth.uid()
      LEFT JOIN public.events prev_ev ON prev_ev.id = ev.prev_event_id
      LEFT JOIN public.events next_ev ON next_ev.id = ev.next_event_id
      WHERE ev.id = p_event_id
    ) e;
  ELSE
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
        ARRAY(
          SELECT DISTINCT a.publisher
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
        NULL::bigint        AS subscription_id,
        false               AS is_subscribed
      FROM public.events ev
      LEFT JOIN public.topics t ON t.id = ev.topic_id
      LEFT JOIN public.events prev_ev ON prev_ev.id = ev.prev_event_id
      LEFT JOIN public.events next_ev ON next_ev.id = ev.next_event_id
      WHERE ev.id = p_event_id
    ) e;
  END IF;

  IF v_event IS NULL THEN
    RAISE EXCEPTION '존재하지 않는 이벤트입니다';
  END IF;

  RETURN v_event;
END;
$$;
