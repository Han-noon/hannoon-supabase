CREATE OR REPLACE FUNCTION public.increment_abusing_count()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  UPDATE public.events
  SET
    abusing_count = abusing_count + 1,
    article_count = article_count + 1  -- 추가
  WHERE id = NEW.event_id;

  RAISE LOG 'increment_abusing_count: event_id=%, article_id=%, type=%',
    NEW.event_id, NEW.article_id, NEW.type;

  RETURN NEW;
END;
$$;
