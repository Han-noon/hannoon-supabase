-- =============================================================
-- 토픽 카드: 성향 비율 + 키워드
--   get_topics, get_subscribed_topics에 left_percent, mid_percent, right_percent, keywords 추가
-- =============================================================
-- 20260930120000에서는 "비율은 화면이 계산한다"고 했지만, 카드마다 반올림이 달라지지 않게 DB가 내려준다.
--
-- 비율은 정수 %이고 세 값의 합이 항상 100이다(기사가 없으면 모두 0). 각각 반올림하면 합이 99나 101이
-- 될 수 있어서, 내림한 뒤 남는 %를 나머지가 큰 쪽부터 1씩 준다(최대 나머지 방식).
-- 성향 서비스라 진보·보수 어느 쪽도 이름 순서로 우대하지 않는다:
--   진보 = 보수 건수면 두 비율을 같게(반올림) 하고 남는 %는 중도에 준다. 정확히 .5인 경우 중도 오차가 1이 된다.
--   그 밖에 나머지가 같으면 중도 → 건수가 많은 쪽 순으로 준다.
--   그래서 중도와 한쪽 건수가 같으면 중도가 1%p 높을 수 있다(예: 1·1·4건 → 16/17/67).
-- 분모는 article_count(= 진보 + 중도 + 보수)이고, 건수 필드는 그대로 둔다.
-- 필드명을 *_ratio가 아니라 *_percent로 한 것은 값이 0~1이 아니라 0~100이기 때문이다.
--
-- keywords는 topics.keywords(20260928140000)다. 생성 작업 전에는 빈 배열이다.
--
-- 두 함수의 본문은 20260930120000과 같고 위 필드만 더했다. 시그니처가 같아 기존 권한이 유지된다.
-- =============================================================

-- 세 카운트를 합이 100인 정수 %로 바꾼다. 규칙은 위 헤더 참고.
CREATE OR REPLACE FUNCTION public.bias_percentages(p_left int, p_mid int, p_right int)
RETURNS TABLE (left_percent int, mid_percent int, right_percent int)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  v_total int := p_left + p_mid + p_right;
BEGIN
  IF LEAST(p_left, p_mid, p_right) < 0 THEN
    RAISE EXCEPTION '성향별 기사 수는 0 이상이어야 합니다';
  END IF;

  IF v_total = 0 THEN
    RETURN QUERY SELECT 0, 0, 0;
    RETURN;
  END IF;

  IF p_left = p_right THEN
    left_percent  := round(p_left * 100.0 / v_total);
    right_percent := left_percent;
    mid_percent   := 100 - 2 * left_percent;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT
    max(x.pct) FILTER (WHERE x.k = 'L'),
    max(x.pct) FILTER (WHERE x.k = 'M'),
    max(x.pct) FILTER (WHERE x.k = 'R')
  INTO left_percent, mid_percent, right_percent
  FROM (
    SELECT
      v.k,
      v.c * 100 / v_total + CASE
        WHEN row_number() OVER (ORDER BY v.c * 100 % v_total DESC, v.k = 'M' DESC, v.c DESC)
             <= 100 - sum(v.c * 100 / v_total) OVER ()
        THEN 1 ELSE 0
      END AS pct
    FROM (VALUES ('L', p_left), ('M', p_mid), ('R', p_right)) AS v(k, c)
  ) x;
  RETURN NEXT;
END;
$$;

-- 함수의 PUBLIC EXECUTE는 Postgres 기본값이라 회수한 뒤 역할별로 준다.
-- get_topics가 SECURITY INVOKER라 anon도 실행할 수 있어야 한다.
REVOKE EXECUTE ON FUNCTION public.bias_percentages(int, int, int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.bias_percentages(int, int, int) TO anon;
GRANT EXECUTE ON FUNCTION public.bias_percentages(int, int, int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bias_percentages(int, int, int) TO service_role;


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
      p.keywords,
      p.created_at,
      p.updated_at,
      (v_subs ->> p.id::text)::bigint      AS subscription_id,
      COALESCE(v_subs ? p.id::text, false) AS is_subscribed,
      st.article_count,
      st.left_count,
      st.mid_count,
      st.right_count,
      pct.left_percent,
      pct.mid_percent,
      pct.right_percent,
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
    CROSS JOIN LATERAL public.bias_percentages(st.left_count, st.mid_count, st.right_count) pct
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
      p.keywords,
      p.created_at,
      p.updated_at,
      p.subscription_id,
      true AS is_subscribed,
      st.article_count,
      st.left_count,
      st.mid_count,
      st.right_count,
      pct.left_percent,
      pct.mid_percent,
      pct.right_percent,
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
    CROSS JOIN LATERAL public.bias_percentages(st.left_count, st.mid_count, st.right_count) pct
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
