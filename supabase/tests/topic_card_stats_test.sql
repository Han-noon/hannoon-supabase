BEGIN;
SELECT plan(26);

-- 픽스처 토픽 제목에 고유 토큰(zzcardstatszz)을 넣고 p_search로 걸러서, 시드나 로컬 데이터가
-- 있어도 픽스처끼리의 순서만 본다.
--
--   a: 진보 3 · 중도 2 · 보수 1 = 6건. 한 기사를 두 이벤트에 걸어 중복 집계를 막는지,
--      미래 시각 기사와 어뷰징 기사를 빼는지 함께 본다.
--   b: 중도 8건 (기사량 1위)
--   c: 이벤트 없음 (0건)
--   d: 보수 6건 (a와 기사 수 동률), created_at만 하루 이전
-- 같은 트랜잭션이라 a·b·c의 created_at은 같고 id는 a < b < c < d 순이다. d만 하루 당겨서
-- "기사 수 동률이면 created_at DESC"와 "created_at도 같으면 id DESC"를 함께 본다.
INSERT INTO public.topics (category, title, summary) VALUES
  ('사회', '_zzcardstatszz_a', '요약'),
  ('경제', '_zzcardstatszz_b', '요약'),
  ('국제', '_zzcardstatszz_c', '요약'),
  ('정치', '_zzcardstatszz_d', '요약');

UPDATE public.topics SET created_at = now()::timestamp - interval '1 day' WHERE title = '_zzcardstatszz_d';

INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_zzcardstatszz_a'), '사회', '_zzcardstatszz_ev_a1', '요약'),
  ((SELECT id FROM public.topics WHERE title = '_zzcardstatszz_a'), '사회', '_zzcardstatszz_ev_a2', '요약'),
  ((SELECT id FROM public.topics WHERE title = '_zzcardstatszz_b'), '경제', '_zzcardstatszz_ev_b1', '요약'),
  ((SELECT id FROM public.topics WHERE title = '_zzcardstatszz_d'), '정치', '_zzcardstatszz_ev_d1', '요약');

-- (소속 이벤트, 성향, 건수, published_at). summary에 이벤트 제목을 적어 아래 연결에 쓴다.
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
SELECT
  'https://feeds.test/card',
  'card-' || s.ev || '-' || s.bias || '-' || g,
  'https://test.com/card/' || s.ev || '/' || s.bias || '/' || g,
  '사회', '_card_article', s.ev, 'rss', '테스트언론', s.pub, s.bias::public.bias_type, 'ready'
FROM (VALUES
  ('_zzcardstatszz_ev_a1', '진보', 3, now()::timestamp - interval '2 days'),
  ('_zzcardstatszz_ev_a1', '중도', 2, now()::timestamp - interval '2 days'),
  ('_zzcardstatszz_ev_a2', '보수', 1, now()::timestamp - interval '5 days'),  -- a의 최초 보도
  ('_zzcardstatszz_ev_b1', '중도', 8, now()::timestamp - interval '1 day'),
  ('_zzcardstatszz_ev_d1', '보수', 6, now()::timestamp - interval '3 days')
) AS s(ev, bias, n, pub)
CROSS JOIN LATERAL generate_series(1, s.n) AS g;

INSERT INTO public.event_articles (event_id, article_id)
SELECT e.id, a.id
FROM public.articles a
JOIN public.events e ON e.title = a.summary
WHERE a.feed_url = 'https://feeds.test/card';

-- a1의 진보 기사 하나를 a2에도 건다 — 같은 토픽 안에서 한 번만 세야 한다
INSERT INTO public.event_articles (event_id, article_id) VALUES (
  (SELECT id FROM public.events WHERE title = '_zzcardstatszz_ev_a2'),
  (SELECT id FROM public.articles WHERE guid = 'card-_zzcardstatszz_ev_a1-진보-1')
);

-- 미래 시각 기사: 집계와 최초 보도일에서 빠져야 한다
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
VALUES ('https://feeds.test/card', 'card-future', 'https://test.com/card/future', '사회', '_card_article', '_zzcardstatszz_ev_a1',
        'rss', '테스트언론', now()::timestamp + interval '1 day', '진보', 'ready');
INSERT INTO public.event_articles (event_id, article_id) VALUES (
  (SELECT id FROM public.events WHERE title = '_zzcardstatszz_ev_a1'),
  (SELECT id FROM public.articles WHERE guid = 'card-future')
);

-- 어뷰징 기사: 파이프라인처럼 abusing_articles에만 넣는다. 트리거가 events.article_count(캐시)를
-- 올리지만 카드 집계에는 들어가면 안 된다.
-- 파이프라인은 삽입 전에 성향 카운트를 +1 해 decrement_bias_count의 -1을 상쇄한다. 여기선 그 단계를
-- 생략하므로 a1에 이미 있는 성향(진보)으로 넣어 CHECK(>= 0) 위반을 피한다.
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
VALUES ('https://feeds.test/card', 'card-abusing', 'https://test.com/card/abusing', '사회', '_card_article', '어뷰징',
        'rss', '테스트언론', now()::timestamp - interval '2 days', '진보', 'ready');
INSERT INTO public.abusing_articles (event_id, article_id, type) VALUES (
  (SELECT id FROM public.events WHERE title = '_zzcardstatszz_ev_a1'),
  (SELECT id FROM public.articles WHERE guid = 'card-abusing'),
  'title_content_mismatch'
);

-- 픽스처만 뽑아 쓰는 헬퍼: 토픽 제목 → 카드 항목
CREATE TEMP TABLE card AS
SELECT x->>'title' AS title, x AS item, ord
FROM jsonb_array_elements((public.get_topics('zzcardstatszz', NULL, 1, 100))::jsonb -> 'topics')
  WITH ORDINALITY AS t(x, ord);


-- ── 시그니처 ───────────────────────────────────────────────────

SELECT is(
  (SELECT count(*)::int FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'get_topics'),
  1,
  'get_topics: 오버로드 없이 하나만 존재 (4인자 호출이 모호해지지 않음)'
);

SELECT lives_ok(
  $$ SELECT public.get_topics(NULL, NULL, NULL, NULL) $$,
  'get_topics: 기존 4인자 위치 호출 유지'
);


-- ── 집계 필드 ───────────────────────────────────────────────────

SELECT ok(
  (SELECT item FROM card WHERE title = '_zzcardstatszz_a')
    ?& ARRAY['article_count', 'left_count', 'mid_count', 'right_count', 'first_published_at'],
  'get_topics: 카드 집계 필드 포함'
);

SELECT is(
  (SELECT (item->>'article_count')::int FROM card WHERE title = '_zzcardstatszz_a'),
  6,
  'get_topics: 두 이벤트에 걸린 기사는 한 번만, 미래 시각·어뷰징 기사는 빼고 셈'
);

SELECT results_eq(
  $$ SELECT (item->>'left_count')::int, (item->>'mid_count')::int, (item->>'right_count')::int
     FROM card WHERE title = '_zzcardstatszz_a' $$,
  $$ VALUES (3, 2, 1) $$,
  'get_topics: 성향별 기사 수'
);

SELECT is(
  (SELECT count(*)::int FROM card
   WHERE (item->>'left_count')::int + (item->>'mid_count')::int + (item->>'right_count')::int
         <> (item->>'article_count')::int),
  0,
  'get_topics: 진보 + 중도 + 보수 = article_count'
);

SELECT is(
  (SELECT (item->>'first_published_at')::timestamp FROM card WHERE title = '_zzcardstatszz_a'),
  now()::timestamp - interval '5 days',
  'get_topics: first_published_at = 가장 이른 기사 시각 (미래 시각 기사 제외)'
);

SELECT results_eq(
  $$ SELECT (item->>'article_count')::int, item->'first_published_at'
     FROM card WHERE title = '_zzcardstatszz_c' $$,
  $$ VALUES (0, 'null'::jsonb) $$,
  'get_topics: 기사 없는 토픽은 0건, first_published_at = null'
);

SELECT is(
  (SELECT (x->>'article_count')::int
   FROM jsonb_array_elements((public.get_hot_topics(168, 100))::jsonb -> 'topics') x
   WHERE x->>'title' = '_zzcardstatszz_a'),
  (SELECT (item->>'article_count')::int FROM card WHERE title = '_zzcardstatszz_a'),
  'get_topics: 핫 토픽 랭킹과 같은 기사 수'
);


-- ── 정렬 ────────────────────────────────────────────────────────

SELECT is(
  (SELECT array_agg(title ORDER BY ord) FROM card),
  ARRAY['_zzcardstatszz_c', '_zzcardstatszz_b', '_zzcardstatszz_a', '_zzcardstatszz_d'],
  'get_topics: p_order 생략 시 최신순 (created_at DESC, 같으면 id DESC)'
);

SELECT is(
  ARRAY(
    SELECT x->>'title'
    FROM jsonb_array_elements((public.get_topics('zzcardstatszz', NULL, 1, 100, 'articles'))::jsonb -> 'topics')
      WITH ORDINALITY AS t(x, ord)
    ORDER BY ord
  ),
  ARRAY['_zzcardstatszz_b', '_zzcardstatszz_a', '_zzcardstatszz_d', '_zzcardstatszz_c'],
  'get_topics: articles 정렬은 기사 수 DESC, 동률이면 created_at DESC'
);

SELECT is(
  (public.get_topics('zzcardstatszz', NULL, 1, 100, 'latest'))::jsonb -> 'topics',
  (public.get_topics('zzcardstatszz', NULL, 1, 100))::jsonb -> 'topics',
  'get_topics: latest는 생략과 같음'
);

SELECT throws_ok(
  $$ SELECT public.get_topics(NULL, NULL, NULL, NULL, 'article') $$,
  'order는 latest 또는 articles여야 합니다',
  'get_topics: 모르는 p_order는 예외 (오타가 최신순으로 조용히 떨어지지 않게)'
);

SELECT is(
  (public.get_topics(p_search => 'zzcardstatszz', p_page => 2, p_size => 2, p_order => 'articles'))::jsonb -> 'topics' -> 0 ->> 'title',
  '_zzcardstatszz_d',
  'get_topics: articles 정렬에서도 페이지네이션 (2페이지 첫 항목)'
);

SELECT is(
  ((public.get_topics(p_search => 'zzcardstatszz', p_order => 'articles'))::jsonb ->> 'total_count')::int,
  4,
  'get_topics: 정렬과 무관하게 total_count 동일'
);


-- ── 비로그인 ────────────────────────────────────────────────────

SET LOCAL ROLE anon;

SELECT is(
  (public.get_topics(p_search => 'zzcardstatszz', p_order => 'articles'))::jsonb -> 'topics' -> 0 ->> 'title',
  '_zzcardstatszz_b',
  'anon: p_order 포함 호출 가능'
);

SELECT is(
  ((public.get_topics(p_search => 'zzcardstatszz', p_order => 'articles'))::jsonb -> 'topics' -> 0 ->> 'article_count')::int,
  8,
  'anon: 집계 필드 조회 가능'
);

RESET ROLE;


-- ── 로그인 사용자 (get_topics 로그인 분기 + get_subscribed_topics) ───

SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES ('cccccccc-0000-0000-0000-000000000001', 'topic_card_stats_test@example.com');
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.subscriptions (user_id, topic_id) VALUES
  ('cccccccc-0000-0000-0000-000000000001', (SELECT id FROM public.topics WHERE title = '_zzcardstatszz_a'));

SELECT set_config('request.jwt.claim.sub', 'cccccccc-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub": "cccccccc-0000-0000-0000-000000000001"}', true);
SET LOCAL ROLE authenticated;

SELECT is(
  ARRAY(
    SELECT x->>'title'
    FROM jsonb_array_elements((public.get_topics('zzcardstatszz', NULL, 1, 100, 'articles'))::jsonb -> 'topics')
      WITH ORDINALITY AS t(x, ord)
    ORDER BY ord
  ),
  ARRAY['_zzcardstatszz_b', '_zzcardstatszz_a', '_zzcardstatszz_d', '_zzcardstatszz_c'],
  'authenticated: get_topics articles 정렬 동일'
);

SELECT results_eq(
  $$ SELECT (x->>'article_count')::int, (x->>'left_count')::int, (x->>'mid_count')::int, (x->>'right_count')::int,
            (x->>'is_subscribed')::boolean
     FROM jsonb_array_elements((public.get_topics('zzcardstatszz', NULL, 1, 100))::jsonb -> 'topics') x
     WHERE x->>'title' = '_zzcardstatszz_a' $$,
  $$ VALUES (6, 3, 2, 1, true) $$,
  'authenticated: get_topics 로그인 분기도 같은 집계 + 구독 여부'
);

SELECT is(
  (SELECT (x->>'subscription_id')::bigint
   FROM jsonb_array_elements((public.get_topics('zzcardstatszz', NULL, 1, 100))::jsonb -> 'topics') x
   WHERE x->>'title' = '_zzcardstatszz_a'),
  (SELECT s.id FROM public.subscriptions s
   WHERE s.topic_id = (SELECT id FROM public.topics WHERE title = '_zzcardstatszz_a')),
  'authenticated: subscription_id는 실제 구독 id'
);

SELECT results_eq(
  $$ SELECT x->'subscription_id', (x->>'is_subscribed')::boolean
     FROM jsonb_array_elements((public.get_topics('zzcardstatszz', NULL, 1, 100))::jsonb -> 'topics') x
     WHERE x->>'title' = '_zzcardstatszz_b' $$,
  $$ VALUES ('null'::jsonb, false) $$,
  'authenticated: 구독하지 않은 토픽은 subscription_id = null, is_subscribed = false'
);

SELECT is(
  (public.get_topics('qqxxnomatchxxqq', NULL, 1, 9))::jsonb -> 'topics',
  '[]'::jsonb,
  'authenticated: 결과가 없으면 topics = []'
);

SELECT ok(
  (public.get_subscribed_topics(1, 9))::jsonb -> 'topics' -> 0
    ?& ARRAY['article_count', 'left_count', 'mid_count', 'right_count', 'first_published_at'],
  'get_subscribed_topics: 카드 집계 필드 포함'
);

SELECT results_eq(
  $$ SELECT (x->>'article_count')::int, (x->>'left_count')::int, (x->>'mid_count')::int, (x->>'right_count')::int,
            (x->>'first_published_at')::timestamp
     FROM jsonb_array_elements((public.get_subscribed_topics(1, 9))::jsonb -> 'topics') x
     WHERE x->>'title' = '_zzcardstatszz_a' $$,
  $$ VALUES (6, 3, 2, 1, now()::timestamp - interval '5 days') $$,
  'get_subscribed_topics: get_topics와 같은 집계'
);

SELECT is(
  ((public.get_subscribed_topics(1, 9))::jsonb ->> 'total_count')::int,
  1,
  'get_subscribed_topics: 구독한 토픽만 반환 (기존 동작 유지)'
);

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

SELECT throws_ok(
  $$ SELECT public.get_topics(NULL, NULL, 0, NULL, 'articles') $$,
  'page는 1 이상이어야 합니다',
  'get_topics: p_order가 있어도 기존 검증 유지'
);

SELECT * FROM finish();
ROLLBACK;
