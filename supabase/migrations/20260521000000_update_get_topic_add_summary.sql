CREATE OR REPLACE FUNCTION public.get_topic(
  p_topic_id bigint
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_topic json;
BEGIN
  SELECT row_to_json(t) INTO v_topic
  FROM (
    SELECT 
      id, 
      category, 
      title, 
      summary, 
      created_at, 
      updated_at
    FROM public.topics
    WHERE id = p_topic_id
  ) t;

  IF v_topic IS NULL THEN
    RAISE EXCEPTION '존재하지 않는 토픽입니다';
  END IF;

  RETURN v_topic;
END;
$$;
