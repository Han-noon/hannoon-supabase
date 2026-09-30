-- =============================================================
-- 토픽 카드 집계 필드 + 기사량 순 정렬
--   get_topics:            p_order('latest' | 'articles') 추가, 집계 필드 추가
--   get_subscribed_topics: 집계 필드 추가 (마이페이지도 같은 ThemeCard를 쓴다)
-- =============================================================
-- 카드에 "관련 기사 N개 · 진보/중도/보수 비율 · 최초 보도일"을 그리기 위한 필드:
--   article_count, left_count, mid_count, right_count, first_published_at(KST, 시간대 없음), topic_image_url
--
-- topic_image_url은 토픽의 대표 이미지다. topics에는 이미지가 없어서, 이미지가 있는 이벤트 중 가장 최근
-- 이벤트의 event_image_url을 쓴다(날짜는 get_live_topic_timeline과 같은 기사 MIN(published_at)). 없으면 null.
-- 시연 코퍼스 수집 도구는 이미지가 없으면 ''를 넣으므로 NULL과 함께 거른다.
--
-- 집계는 get_hot_topics와 같은 기준이다. event_articles(정상 기사)만 세고 미래 시각 기사는 뺀다.
-- 어뷰징 기사는 abusing_articles에만 들어가므로 자연히 빠진다. bias_type이 NOT NULL이고 값이
-- 진보·중도·보수 셋뿐이라 left_count + mid_count + right_count = article_count가 성립한다.
--
-- 이벤트 상세(get_event)의 기사 수와는 기준이 다르다. 그쪽은 트리거가 어뷰징 기사까지 더하는
-- 캐시 컬럼 events.article_count를 그대로 내려준다.
--
-- 비율(%)은 내려주지 않는다. 반올림 방식은 화면이 세 카운트로 정한다.
-- 같은 기사 수 정의가 네 곳에 있다. 기준을 바꿀 때 함께 고칠 것:
--   get_topics의 정렬용 c와 카드용 st, get_subscribed_topics의 st, get_hot_topics(20260928120000)
-- =============================================================

-- 파라미터를 추가하므로 기존 시그니처를 지운다. 남겨 두면 오버로드가 생겨
-- 4인자 호출 get_topics(NULL, NULL, NULL, NULL)이 어느 함수인지 정할 수 없다.
DROP FUNCTION IF EXISTS public.get_topics(text, public.category, int, int);

CREATE OR REPLACE FUNCTION public.get_topics(
  p_search   text            DEFAULT NULL,
  p_category public.category DEFAULT NULL,
  p_page     int             DEFAULT NULL,
  p_size     int             DEFAULT NULL,
  p_order    text            DEFAULT NULL
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
  v_subs        jsonb;  -- 로그인 사용자의 { topic_id: subscription_id }
BEGIN
  p_page   := COALESCE(p_page, 1);
  p_size   := COALESCE(p_size, 9);
  p_search := NULLIF(TRIM(p_search), '');
  p_order  := COALESCE(p_order, 'latest');

  IF p_page < 1 THEN
    RAISE EXCEPTION 'page는 1 이상이어야 합니다';
  END IF;

  IF p_size < 1 THEN
    RAISE EXCEPTION 'size는 1 이상이어야 합니다';
  END IF;
  p_size := LEAST(p_size, 100);

  -- 정렬 키 오타('article' 등)가 조용히 최신순으로 떨어지면 화면 버그가 드러나지 않는다
  IF p_order NOT IN ('latest', 'articles') THEN
    RAISE EXCEPTION 'order는 latest 또는 articles여야 합니다';
  END IF;

  SELECT COUNT(*)
  INTO v_total_count
  FROM public.topics t
  WHERE
    (p_category IS NULL OR t.category = p_category)
    AND (p_search IS NULL
         OR extensions.word_similarity(p_search, t.title)   > 0.3
         OR extensions.word_similarity(p_search, t.summary) > 0.3);

  v_total_pages := CEIL(v_total_count::numeric / p_size);

  -- anon은 subscriptions 권한이 없어 참조만 해도 실패하므로, 구독 정보는 로그인일 때만 따로 읽는다
  IF auth.uid() IS NOT NULL THEN
    SELECT jsonb_object_agg(s.topic_id, s.id)
    INTO v_subs
    FROM public.subscriptions s
    WHERE s.user_id = auth.uid();
  END IF;

  -- 페이지를 먼저 자르고 카드 집계는 잘린 토픽에만 한다.
  SELECT array_to_json(array_agg(row_to_json(r)))
  INTO v_topics
  FROM (
    SELECT
      p.id,
      p.category,
      p.title,
      p.summary,
      p.created_at,
      p.updated_at,
      (v_subs ->> p.id::text)::bigint      AS subscription_id,
      COALESCE(v_subs ? p.id::text, false) AS is_subscribed,
      st.article_count,
      st.left_count,
      st.mid_count,
      st.right_count,
      st.first_published_at,
      img.topic_image_url
    FROM (
      SELECT t.*, COALESCE(c.article_count, 0) AS sort_count
      FROM public.topics t
      -- 전체 토픽의 기사 수는 articles 정렬일 때만 한 번에 센다(st.article_count와 같은 정의).
      -- 조건이 파라미터뿐이라 latest면 이 하위 트리를 아예 실행하지 않는다.
      -- 토픽마다 상관 서브쿼리로 세면 토픽 수만큼 인덱스를 타서 오히려 느리다.
      LEFT JOIN (
        SELECT e.topic_id, COUNT(DISTINCT a.id) AS article_count
        FROM public.events e
        JOIN public.event_articles ea ON ea.event_id = e.id
        JOIN public.articles a        ON a.id = ea.article_id
        WHERE p_order = 'articles'
          AND e.topic_id IS NOT NULL
          AND a.published_at <= now()::timestamp
        GROUP BY e.topic_id
      ) c ON c.topic_id = t.id
      WHERE
        (p_category IS NULL OR t.category = p_category)
        AND (p_search IS NULL
             OR extensions.word_similarity(p_search, t.title)   > 0.3
             OR extensions.word_similarity(p_search, t.summary) > 0.3)
      ORDER BY sort_count DESC, t.created_at DESC, t.id DESC
      LIMIT  p_size
      OFFSET (p_page - 1) * p_size
    ) p
    CROSS JOIN LATERAL (
      SELECT
        COUNT(DISTINCT a.id)::int                                     AS article_count,
        COUNT(DISTINCT a.id) FILTER (WHERE a.bias_type = '진보')::int AS left_count,
        COUNT(DISTINCT a.id) FILTER (WHERE a.bias_type = '중도')::int AS mid_count,
        COUNT(DISTINCT a.id) FILTER (WHERE a.bias_type = '보수')::int AS right_count,
        MIN(a.published_at)                                           AS first_published_at
      FROM public.events e
      JOIN public.event_articles ea ON ea.event_id = e.id
      JOIN public.articles a        ON a.id = ea.article_id
      WHERE e.topic_id = p.id
        AND a.published_at <= now()::timestamp
    ) st
    -- 카드 이미지: 이미지가 있는 이벤트 중 가장 최근 것 (위 헤더 참고)
    LEFT JOIN LATERAL (
      SELECT e.event_image_url AS topic_image_url
      FROM public.events e
      JOIN public.event_articles ea ON ea.event_id = e.id
      JOIN public.articles a        ON a.id = ea.article_id
      WHERE e.topic_id = p.id
        AND e.event_image_url <> ''
        AND a.published_at <= now()::timestamp
      GROUP BY e.id
      ORDER BY MIN(a.published_at) DESC, e.id DESC
      LIMIT 1
    ) img ON true
    ORDER BY p.sort_count DESC, p.created_at DESC, p.id DESC
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

GRANT EXECUTE ON FUNCTION public.get_topics(text, public.category, int, int, text) TO anon;
GRANT EXECUTE ON FUNCTION public.get_topics(text, public.category, int, int, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_topics(text, public.category, int, int, text) TO service_role;


-- -------------------------------------------------------------
-- get_subscribed_topics: 시그니처·정렬(id DESC)은 그대로, 집계 필드만 추가
-- -------------------------------------------------------------
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
      p.id,
      p.category,
      p.title,
      p.summary,
      p.created_at,
      p.updated_at,
      p.subscription_id,
      true AS is_subscribed,
      st.article_count,
      st.left_count,
      st.mid_count,
      st.right_count,
      st.first_published_at,
      img.topic_image_url
    FROM (
      SELECT t.*, s.id AS subscription_id
      FROM public.topics t
      INNER JOIN public.subscriptions s ON s.topic_id = t.id AND s.user_id = auth.uid()
      ORDER BY t.id DESC
      LIMIT  p_size
      OFFSET (p_page - 1) * p_size
    ) p
    CROSS JOIN LATERAL (
      SELECT
        COUNT(DISTINCT a.id)::int                                     AS article_count,
        COUNT(DISTINCT a.id) FILTER (WHERE a.bias_type = '진보')::int AS left_count,
        COUNT(DISTINCT a.id) FILTER (WHERE a.bias_type = '중도')::int AS mid_count,
        COUNT(DISTINCT a.id) FILTER (WHERE a.bias_type = '보수')::int AS right_count,
        MIN(a.published_at)                                           AS first_published_at
      FROM public.events e
      JOIN public.event_articles ea ON ea.event_id = e.id
      JOIN public.articles a        ON a.id = ea.article_id
      WHERE e.topic_id = p.id
        AND a.published_at <= now()::timestamp
    ) st
    -- 카드 이미지: 이미지가 있는 이벤트 중 가장 최근 것 (위 헤더 참고)
    LEFT JOIN LATERAL (
      SELECT e.event_image_url AS topic_image_url
      FROM public.events e
      JOIN public.event_articles ea ON ea.event_id = e.id
      JOIN public.articles a        ON a.id = ea.article_id
      WHERE e.topic_id = p.id
        AND e.event_image_url <> ''
        AND a.published_at <= now()::timestamp
      GROUP BY e.id
      ORDER BY MIN(a.published_at) DESC, e.id DESC
      LIMIT 1
    ) img ON true
    ORDER BY p.id DESC
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
