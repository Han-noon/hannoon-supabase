BEGIN;
SELECT plan(24);

-- ── bias_percentages: 합이 100인 정수 % ────────────────────────

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(0, 0, 0) $$,
  $$ VALUES (0, 0, 0) $$,
  'bias_percentages: 기사가 없으면 모두 0'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(1, 2, 1) $$,
  $$ VALUES (25, 50, 25) $$,
  'bias_percentages: 나누어떨어지면 그대로'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(3, 2, 1) $$,
  $$ VALUES (50, 33, 17) $$,
  'bias_percentages: 남는 1%는 나머지가 큰 쪽(16.67 → 17)'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(1, 1, 1) $$,
  $$ VALUES (33, 34, 33) $$,
  'bias_percentages: 진보 = 보수면 같은 비율, 남는 1%는 중도'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(1, 4, 1) $$,
  $$ VALUES (17, 66, 17) $$,
  'bias_percentages: 진보 = 보수면 남는 %가 둘 중 한쪽으로 가지 않음 (16.67 → 17·17)'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(1, 6, 1) $$,
  $$ VALUES (13, 74, 13) $$,
  'bias_percentages: 진보 = 보수가 정확히 .5면 둘 다 올림, 중도가 맞춤'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(0, 5, 0) $$,
  $$ VALUES (0, 100, 0) $$,
  'bias_percentages: 중도만 있으면 중도 100%'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(2, 1, 0) $$,
  $$ VALUES (67, 33, 0) $$,
  'bias_percentages: 0건인 성향은 0%'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(0, 0, 5) $$,
  $$ VALUES (0, 0, 100) $$,
  'bias_percentages: 한 성향뿐이면 100%'
);

SELECT is(
  (SELECT count(*)::int
   FROM generate_series(0, 12) l, generate_series(0, 12) m, generate_series(0, 12) r,
        LATERAL public.bias_percentages(l, m, r) p
   WHERE l + m + r > 0 AND p.left_percent + p.mid_percent + p.right_percent <> 100),
  0,
  'bias_percentages: 0~12건 모든 조합에서 합이 100'
);

SELECT is(
  (SELECT count(*)::int
   FROM generate_series(0, 12) l, generate_series(0, 12) m, generate_series(0, 12) r,
        LATERAL public.bias_percentages(l, m, r) p
   WHERE l + m + r > 0
     AND (abs(p.left_percent  - l * 100.0 / (l + m + r)) >= 1
       OR abs(p.right_percent - r * 100.0 / (l + m + r)) >= 1
       OR abs(p.mid_percent   - m * 100.0 / (l + m + r)) >  1)),
  0,
  'bias_percentages: 0~12건 모든 조합에서 진보·보수 오차 < 1%, 중도 오차 ≤ 1%'
);

SELECT is(
  (SELECT count(*)::int
   FROM generate_series(0, 12) l, generate_series(0, 12) m, generate_series(0, 12) r,
        LATERAL public.bias_percentages(l, m, r) p
   WHERE l = r AND l + m + r > 0 AND p.left_percent <> p.right_percent),
  0,
  'bias_percentages: 0~12건 모든 조합에서 진보 = 보수 건수면 진보 = 보수 비율'
);

SELECT is(
  (SELECT count(*)::int
   FROM generate_series(0, 12) l, generate_series(0, 12) m, generate_series(0, 12) r,
        LATERAL public.bias_percentages(l, m, r) p,
        LATERAL (VALUES (l, p.left_percent), (m, p.mid_percent), (r, p.right_percent)) AS got(c, pct),
        LATERAL (VALUES (l, p.left_percent), (m, p.mid_percent), (r, p.right_percent)) AS miss(c, pct)
   WHERE l <> r AND l + m + r > 0
     AND got.pct  > got.c  * 100 / (l + m + r)
     AND miss.pct = miss.c * 100 / (l + m + r)
     AND got.c * 100 % (l + m + r) < miss.c * 100 % (l + m + r)),
  0,
  'bias_percentages: 1%를 더 받은 쪽의 나머지가 못 받은 쪽보다 작지 않음 (최대 나머지)'
);

SELECT results_eq(
  $$ SELECT * FROM public.bias_percentages(1, 0, 7) $$,
  $$ VALUES (12, 0, 88) $$,
  'bias_percentages: 진보·보수 나머지가 같으면 건수가 많은 쪽 (12.5·87.5 → 12·88)'
);

SELECT is(
  (SELECT count(*)::int
   FROM generate_series(0, 12) l, generate_series(0, 12) m, generate_series(0, 12) r,
        LATERAL public.bias_percentages(l, m, r) p,
        LATERAL public.bias_percentages(r, m, l) q
   WHERE (p.left_percent, p.mid_percent, p.right_percent)
      <> (q.right_percent, q.mid_percent, q.left_percent)),
  0,
  'bias_percentages: 진보·보수 건수를 맞바꾸면 비율도 맞바뀜 (이름 순서로 우대하지 않음)'
);

SELECT throws_ok(
  $$ SELECT * FROM public.bias_percentages(-1, 1, 1) $$,
  '성향별 기사 수는 0 이상이어야 합니다',
  'bias_percentages: 음수 입력은 예외'
);


-- ── get_topics / get_subscribed_topics ────────────────────────

-- 제목에 고유 토큰을 넣고 p_search로 걸러 시드나 로컬 데이터와 섞이지 않게 한다.
--   a: 진보 3 · 중도 2 · 보수 1, 키워드 있음
--   b: 기사 없음, 키워드 없음(기본값 '{}')
INSERT INTO public.topics (category, title, summary) VALUES
  ('사회', '_zzpercentzz_a', '요약'),
  ('경제', '_zzpercentzz_b', '요약');

UPDATE public.topics SET keywords = ARRAY['의대정원', '전공의'] WHERE title = '_zzpercentzz_a';

INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_zzpercentzz_a'), '사회', '_zzpercentzz_ev_a', '요약');

INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
SELECT
  'https://feeds.test/percent',
  'percent-' || s.bias || '-' || g,
  'https://test.com/percent/' || s.bias || '/' || g,
  '사회', '_percent_article', '요약', 'rss', '테스트언론', now()::timestamp - interval '1 day', s.bias::public.bias_type, 'ready'
FROM (VALUES ('진보', 3), ('중도', 2), ('보수', 1)) AS s(bias, n)
CROSS JOIN LATERAL generate_series(1, s.n) AS g;

INSERT INTO public.event_articles (event_id, article_id)
SELECT (SELECT id FROM public.events WHERE title = '_zzpercentzz_ev_a'), a.id
FROM public.articles a
WHERE a.feed_url = 'https://feeds.test/percent';

CREATE TEMP TABLE card AS
SELECT x->>'title' AS title, x AS item
FROM jsonb_array_elements((public.get_topics('zzpercentzz', NULL, 1, 100))::jsonb -> 'topics') AS x;

SELECT ok(
  (SELECT item FROM card WHERE title = '_zzpercentzz_a')
    ?& ARRAY['left_percent', 'mid_percent', 'right_percent', 'keywords', 'left_count', 'article_count'],
  'get_topics: 비율·키워드 필드 포함 (건수 필드도 유지)'
);

SELECT results_eq(
  $$ SELECT (item->>'left_percent')::int, (item->>'mid_percent')::int, (item->>'right_percent')::int
     FROM card WHERE title = '_zzpercentzz_a' $$,
  $$ VALUES (50, 33, 17) $$,
  'get_topics: 성향 비율 (3·2·1건 → 50·33·17%)'
);

SELECT results_eq(
  $$ SELECT (item->>'left_percent')::int, (item->>'mid_percent')::int, (item->>'right_percent')::int
     FROM card WHERE title = '_zzpercentzz_b' $$,
  $$ VALUES (0, 0, 0) $$,
  'get_topics: 기사 없는 토픽은 비율 0'
);

SELECT is(
  (SELECT item->'keywords' FROM card WHERE title = '_zzpercentzz_a'),
  '["의대정원", "전공의"]'::jsonb,
  'get_topics: keywords는 topics.keywords 배열'
);

SELECT is(
  (SELECT item->'keywords' FROM card WHERE title = '_zzpercentzz_b'),
  '[]'::jsonb,
  'get_topics: 키워드가 없으면 빈 배열'
);

SET LOCAL ROLE anon;

SELECT results_eq(
  $$ SELECT (x->>'left_percent')::int, (x->>'mid_percent')::int, (x->>'right_percent')::int, x->'keywords'
     FROM jsonb_array_elements((public.get_topics('zzpercentzz', NULL, 1, 100))::jsonb -> 'topics') x
     WHERE x->>'title' = '_zzpercentzz_a' $$,
  $$ VALUES (50, 33, 17, '["의대정원", "전공의"]'::jsonb) $$,
  'anon: 같은 비율·키워드 조회 가능'
);

RESET ROLE;

-- 로그인 사용자: get_subscribed_topics
SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES ('dddddddd-0000-0000-0000-000000000002', 'topic_card_percent_test@example.com');
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.subscriptions (user_id, topic_id) VALUES
  ('dddddddd-0000-0000-0000-000000000002', (SELECT id FROM public.topics WHERE title = '_zzpercentzz_a'));

SELECT set_config('request.jwt.claim.sub', 'dddddddd-0000-0000-0000-000000000002', true);
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-0000-0000-0000-000000000002"}', true);
SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$ SELECT (x->>'left_percent')::int, (x->>'mid_percent')::int, (x->>'right_percent')::int, x->'keywords'
     FROM jsonb_array_elements((public.get_subscribed_topics(1, 9))::jsonb -> 'topics') x
     WHERE x->>'title' = '_zzpercentzz_a' $$,
  $$ VALUES (50, 33, 17, '["의대정원", "전공의"]'::jsonb) $$,
  'get_subscribed_topics: get_topics와 같은 비율·키워드'
);

SELECT is(
  ((public.get_subscribed_topics(1, 9))::jsonb ->> 'total_count')::int,
  1,
  'get_subscribed_topics: 구독한 토픽만 반환 (기존 동작 유지)'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
