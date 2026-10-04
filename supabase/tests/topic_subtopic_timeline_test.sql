BEGIN;
SELECT plan(19);

SELECT has_function(
  'public', 'get_topic_subtopic_timeline', ARRAY['bigint'],
  'get_topic_subtopic_timeline(bigint) 함수가 존재해야 한다'
);

SELECT throws_ok(
  $$ SELECT public.get_topic_subtopic_timeline(-1) $$,
  '존재하지 않는 토픽입니다',
  '없는 토픽은 예외'
);

-- ── 시드 ───────────────────────────────────────────────────────
-- 제목·이름에 고유 토큰을 넣어 시드나 로컬 데이터와 섞이지 않게 한다.
--   ev1: 진보 2 · 중도 1 (10일 전, 9일 전), 같은 기사 매핑 중복 1행 → A
--   ev2: 보수 1 (5일 전)                         → A, B
--   ev3: 기사 없음                               → C   (보이는 이벤트가 없어 C도 빠짐)
--   ev4: 미래 기사만                             → A   (A의 event_count에 들어가지 않아야 함)
--   ev5: 중도 1 (3일 전) + 미래 기사 1 + ev_moved와 공유한 기사 1 → 없음
--   ev_moved: 진보 1 (2일 전). other 토픽 서브토픽 X에 연결된 뒤 main으로 옮겨짐
--   ev_out: 중도 1 (1일 전). main 서브토픽 A에 연결된 뒤 other로 옮겨짐 (A의 event_count에 들어가지 않아야 함)
-- B를 A보다 먼저 넣어 B.id < A.id — 탭 순서가 id가 아니라 첫 이벤트 날짜임을 확인한다.
-- 이벤트별 기사 수의 합은 7(3+1+2+1)이고 토픽 기사 수는 6 — 공유 기사를 한 번만 센다.

INSERT INTO public.topics (category, title, summary) VALUES
  ('사회', '_zzsubtl_main',  '분류 요약'),
  ('사회', '_zzsubtl_other', '요약'),
  ('사회', '_zzsubtl_empty', '요약');

UPDATE public.topics SET ai_summary = 'AI 요약' WHERE title = '_zzsubtl_main';

INSERT INTO public.events (topic_id, category, title, summary)
SELECT t.id, '사회', v.title, '이벤트 요약'
FROM (VALUES
  ('_zzsubtl_main',  '_zzsubtl_ev1'),
  ('_zzsubtl_main',  '_zzsubtl_ev2'),
  ('_zzsubtl_main',  '_zzsubtl_ev3'),
  ('_zzsubtl_main',  '_zzsubtl_ev4'),
  ('_zzsubtl_main',  '_zzsubtl_ev5'),
  ('_zzsubtl_other', '_zzsubtl_ev_moved'),
  ('_zzsubtl_main',  '_zzsubtl_ev_out')
) AS v(topic, title)
JOIN public.topics t ON t.title = v.topic;

-- 기사 제목을 이벤트 제목과 같게 두고 그 제목으로 event_articles를 잇는다
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
SELECT
  'https://feeds.test/subtl',
  'subtl-' || v.n,
  'https://test.com/subtl/' || v.n,
  '사회', v.ev, '요약', 'rss', '테스트언론', now()::timestamp + v.offs, v.bias::public.bias_type, 'ready'
FROM (VALUES
  (1, '_zzsubtl_ev1',      '진보', interval '-10 days'),
  (2, '_zzsubtl_ev1',      '진보', interval '-9 days'),
  (3, '_zzsubtl_ev1',      '중도', interval '-9 days'),
  (4, '_zzsubtl_ev2',      '보수', interval '-5 days'),
  (5, '_zzsubtl_ev4',      '중도', interval '1 day'),
  (6, '_zzsubtl_ev5',      '중도', interval '-3 days'),
  (7, '_zzsubtl_ev5',      '보수', interval '1 day'),
  (8, '_zzsubtl_ev_moved', '진보', interval '-2 days'),
  (9, '_zzsubtl_ev_out',   '중도', interval '-1 day')
) AS v(n, ev, bias, offs);

INSERT INTO public.event_articles (event_id, article_id)
SELECT e.id, a.id
FROM public.articles a
JOIN public.events e ON e.title = a.title
WHERE a.feed_url = 'https://feeds.test/subtl';

-- ev1: 같은 (event_id, article_id) 중복 매핑 — event_articles에 UNIQUE가 없어 들어올 수 있다
-- ev5: ev_moved의 기사를 함께 가짐(기사 공유)
INSERT INTO public.event_articles (event_id, article_id)
SELECT e.id, a.id
FROM public.events e, public.articles a
WHERE a.feed_url = 'https://feeds.test/subtl'
  AND (e.title, a.guid) IN (('_zzsubtl_ev1', 'subtl-1'), ('_zzsubtl_ev5', 'subtl-8'));

INSERT INTO public.subtopics (topic_id, name, type)
SELECT id, '_zzsubtl_B', 'FOCAL_POINT' FROM public.topics WHERE title = '_zzsubtl_main';

INSERT INTO public.subtopics (topic_id, name, type, summary)
SELECT id, '_zzsubtl_A', 'PROCESS', 'A 요약' FROM public.topics WHERE title = '_zzsubtl_main';

INSERT INTO public.subtopics (topic_id, name, type)
SELECT id, '_zzsubtl_C', 'RECURRING_ISSUE' FROM public.topics WHERE title = '_zzsubtl_main';

INSERT INTO public.subtopics (topic_id, name, type)
SELECT id, '_zzsubtl_X', 'FOCAL_POINT' FROM public.topics WHERE title = '_zzsubtl_other';

INSERT INTO public.subtopic_events (subtopic_id, event_id)
SELECT s.id, e.id
FROM (VALUES
  ('_zzsubtl_A', '_zzsubtl_ev1'),
  ('_zzsubtl_A', '_zzsubtl_ev2'),
  ('_zzsubtl_A', '_zzsubtl_ev4'),
  ('_zzsubtl_A', '_zzsubtl_ev_out'),
  ('_zzsubtl_B', '_zzsubtl_ev2'),
  ('_zzsubtl_C', '_zzsubtl_ev3'),
  ('_zzsubtl_X', '_zzsubtl_ev_moved')
) AS v(sub, ev)
JOIN public.subtopics s ON s.name = v.sub
JOIN public.events e    ON e.title = v.ev;

UPDATE public.events
SET topic_id = (SELECT id FROM public.topics WHERE title = '_zzsubtl_main')
WHERE title = '_zzsubtl_ev_moved';

UPDATE public.events
SET topic_id = (SELECT id FROM public.topics WHERE title = '_zzsubtl_other')
WHERE title = '_zzsubtl_ev_out';

CREATE TEMP TABLE res AS
SELECT public.get_topic_subtopic_timeline(id)::jsonb AS j
FROM public.topics
WHERE title = '_zzsubtl_main';


-- ── events ─────────────────────────────────────────────────────

SELECT is(
  (SELECT array_agg(x->>'title' ORDER BY ord)
   FROM res, jsonb_array_elements(j->'events') WITH ORDINALITY AS t(x, ord)),
  ARRAY['_zzsubtl_ev1', '_zzsubtl_ev2', '_zzsubtl_ev5', '_zzsubtl_ev_moved'],
  'events: 기사가 있는 이벤트만 날짜순 (기사 없는 이벤트·미래 기사만 있는 이벤트 제외)'
);

SELECT ok(
  (SELECT bool_and(x ?& ARRAY['id', 'title', 'short_summary', 'summary', 'occurred_at', 'subtopic_ids',
                              'article_count', 'left_percent', 'mid_percent', 'right_percent'])
   FROM res, jsonb_array_elements(j->'events') x),
  'events: 화면 계약 필드 포함'
);

SELECT results_eq(
  $$ SELECT (x->>'occurred_at')::timestamp, (x->>'article_count')::int,
            (x->>'left_percent')::int, (x->>'mid_percent')::int, (x->>'right_percent')::int
     FROM res, jsonb_array_elements(j->'events') x
     WHERE x->>'title' = '_zzsubtl_ev1' $$,
  $$ VALUES (now()::timestamp - interval '10 days', 3, 67, 33, 0) $$,
  'events: occurred_at은 기사 MIN(published_at), 기사 수와 성향 비율(2·1·0건 → 67·33·0%)'
);

SELECT results_eq(
  $$ SELECT (x->>'occurred_at')::timestamp, (x->>'article_count')::int
     FROM res, jsonb_array_elements(j->'events') x
     WHERE x->>'title' = '_zzsubtl_ev5' $$,
  $$ VALUES (now()::timestamp - interval '3 days', 2) $$,
  'events: 미래 시각 기사는 기사 수에서 제외, 다른 이벤트와 공유한 기사는 이 이벤트에서도 셈'
);

SELECT is(
  (SELECT x->'subtopic_ids' FROM res, jsonb_array_elements(j->'events') x
   WHERE x->>'title' = '_zzsubtl_ev2'),
  (SELECT jsonb_agg(id ORDER BY id) FROM public.subtopics WHERE name IN ('_zzsubtl_A', '_zzsubtl_B')),
  'events: 여러 서브토픽에 속한 이벤트는 subtopic_ids에 모두 (id 순)'
);

SELECT is(
  (SELECT x->'subtopic_ids' FROM res, jsonb_array_elements(j->'events') x
   WHERE x->>'title' = '_zzsubtl_ev5'),
  '[]'::jsonb,
  'events: 서브토픽이 없으면 빈 배열'
);

SELECT is(
  (SELECT x->'subtopic_ids' FROM res, jsonb_array_elements(j->'events') x
   WHERE x->>'title' = '_zzsubtl_ev_moved'),
  '[]'::jsonb,
  'events: 토픽이 바뀐 이벤트에 남은 다른 토픽 서브토픽 연결은 넣지 않음'
);


-- ── subtopics / stats / topic ──────────────────────────────────

SELECT results_eq(
  $$ SELECT x->>'name', (x->>'event_count')::int, x->>'type', x->>'summary'
     FROM res, jsonb_array_elements(j->'subtopics') WITH ORDINALITY AS t(x, ord)
     ORDER BY ord $$,
  $$ VALUES ('_zzsubtl_A', 2, 'PROCESS', 'A 요약'),
            ('_zzsubtl_B', 1, 'FOCAL_POINT', NULL::text) $$,
  'subtopics: 첫 이벤트 날짜순(id 순 아님), event_count는 보이는 이벤트만, 보이는 이벤트가 없는 C와 다른 토픽의 X는 제외'
);

SELECT results_eq(
  $$ SELECT (j->'stats'->>'first_published_at')::timestamp, (j->'stats'->>'last_published_at')::timestamp,
            (j->'stats'->>'article_count')::int, (j->'stats'->>'event_count')::int
     FROM res $$,
  $$ VALUES (now()::timestamp - interval '10 days', now()::timestamp - interval '2 days', 6, 4) $$,
  'stats: 기간·기사 수·이벤트 수는 미래 시각 기사를 뺀 기준, 기사 수는 이벤트별 합(7)이 아닌 COUNT(DISTINCT)'
);

SELECT results_eq(
  $$ SELECT j->'topic'->>'title', j->'topic'->>'summary', j->'topic'->>'ai_summary',
            (j->'topic'->>'is_subscribed')::boolean, j->'topic'->'subscription_id'
     FROM res $$,
  $$ VALUES ('_zzsubtl_main', '분류 요약', 'AI 요약', false, 'null'::jsonb) $$,
  'topic: 분류 요약과 AI 요약을 따로 내림, 비로그인은 구독 안 함'
);

SELECT is(
  (SELECT public.get_topic_subtopic_timeline(id)::jsonb - 'topic'
   FROM public.topics WHERE title = '_zzsubtl_empty'),
  '{"stats": {"first_published_at": null, "last_published_at": null, "article_count": 0, "event_count": 0},
    "subtopics": [], "events": []}'::jsonb,
  '이벤트가 없는 토픽은 빈 배열과 0'
);


-- ── 동률 정렬 ──────────────────────────────────────────────────
-- 같은 시각 기사 하나씩을 가진 이벤트 2개와, 그 이벤트를 하나씩 가진 서브토픽 2개.
-- 제목·이름 순서와 id 순서를 반대로 넣어, 동률이 제목이 아니라 id로 풀리는지 확인한다.

INSERT INTO public.topics (category, title, summary) VALUES ('사회', '_zzsubtl_tie', '요약');

INSERT INTO public.events (topic_id, category, title, summary)
SELECT id, '사회', '_zzsubtl_tie_ev_b', '요약' FROM public.topics WHERE title = '_zzsubtl_tie';

INSERT INTO public.events (topic_id, category, title, summary)
SELECT id, '사회', '_zzsubtl_tie_ev_a', '요약' FROM public.topics WHERE title = '_zzsubtl_tie';

INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
SELECT
  'https://feeds.test/subtl-tie', 'subtl-tie-' || v.ev, 'https://test.com/subtl-tie/' || v.ev,
  '사회', v.ev, '요약', 'rss', '테스트언론', date_trunc('day', now()::timestamp) - interval '1 day', '중도', 'ready'
FROM (VALUES ('_zzsubtl_tie_ev_a'), ('_zzsubtl_tie_ev_b')) AS v(ev);

INSERT INTO public.event_articles (event_id, article_id)
SELECT e.id, a.id
FROM public.articles a
JOIN public.events e ON e.title = a.title
WHERE a.feed_url = 'https://feeds.test/subtl-tie';

INSERT INTO public.subtopics (topic_id, name, type)
SELECT id, '_zzsubtl_tie_s_b', 'PROCESS' FROM public.topics WHERE title = '_zzsubtl_tie';

INSERT INTO public.subtopics (topic_id, name, type)
SELECT id, '_zzsubtl_tie_s_a', 'PROCESS' FROM public.topics WHERE title = '_zzsubtl_tie';

INSERT INTO public.subtopic_events (subtopic_id, event_id)
SELECT s.id, e.id
FROM (VALUES ('_zzsubtl_tie_s_a', '_zzsubtl_tie_ev_a'), ('_zzsubtl_tie_s_b', '_zzsubtl_tie_ev_b')) AS v(sub, ev)
JOIN public.subtopics s ON s.name = v.sub
JOIN public.events e    ON e.title = v.ev;

CREATE TEMP TABLE tie AS
SELECT public.get_topic_subtopic_timeline(id)::jsonb AS j
FROM public.topics
WHERE title = '_zzsubtl_tie';

SELECT is(
  (SELECT array_agg(x->>'title' ORDER BY ord)
   FROM tie, jsonb_array_elements(j->'events') WITH ORDINALITY AS t(x, ord)),
  ARRAY['_zzsubtl_tie_ev_b', '_zzsubtl_tie_ev_a'],
  'events: 같은 occurred_at이면 id 순'
);

SELECT is(
  (SELECT array_agg(x->>'name' ORDER BY ord)
   FROM tie, jsonb_array_elements(j->'subtopics') WITH ORDINALITY AS t(x, ord)),
  ARRAY['_zzsubtl_tie_s_b', '_zzsubtl_tie_s_a'],
  'subtopics: 첫 이벤트 날짜가 같으면 id 순'
);


-- ── 권한 ───────────────────────────────────────────────────────

SELECT ok(
  NOT EXISTS (
    SELECT 1
    -- proacl이 NULL이면 기본 ACL(PUBLIC EXECUTE 포함)이 적용되므로 acldefault로 펼친다
    FROM aclexplode((SELECT COALESCE(proacl, acldefault('f', proowner)) FROM pg_proc
                     WHERE oid = 'public.get_topic_subtopic_timeline(bigint)'::regprocedure))
    WHERE grantee = 0
  ),
  'PUBLIC EXECUTE는 회수되어 있어야 한다'
);


-- ── 역할별 ─────────────────────────────────────────────────────

SET LOCAL ROLE anon;

SELECT results_eq(
  $$ SELECT jsonb_array_length(r.j -> 'events'), jsonb_array_length(r.j -> 'subtopics'),
            (r.j -> 'stats' ->> 'article_count')::int
     FROM (SELECT public.get_topic_subtopic_timeline(id)::jsonb AS j
           FROM public.topics WHERE title = '_zzsubtl_main') r $$,
  $$ VALUES (4, 2, 6) $$,
  'anon: 호출 가능, 같은 이벤트·서브토픽·기사 수 조회'
);

RESET ROLE;

SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES ('dddddddd-0000-0000-0000-000000000004', 'topic_subtopic_timeline_test@example.com');
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.subscriptions (user_id, topic_id) VALUES
  ('dddddddd-0000-0000-0000-000000000004', (SELECT id FROM public.topics WHERE title = '_zzsubtl_main'));

SELECT set_config('request.jwt.claim.sub', 'dddddddd-0000-0000-0000-000000000004', true);
SELECT set_config('request.jwt.claims', '{"sub": "dddddddd-0000-0000-0000-000000000004"}', true);
SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$ SELECT (r.j->>'is_subscribed')::boolean, (r.j->>'subscription_id')::bigint
     FROM (SELECT public.get_topic_subtopic_timeline(id)::jsonb -> 'topic' AS j
           FROM public.topics WHERE title = '_zzsubtl_main') r $$,
  $$ SELECT true, s.id FROM public.subscriptions s
     WHERE s.user_id = 'dddddddd-0000-0000-0000-000000000004' $$,
  'authenticated: 구독한 토픽이면 is_subscribed와 subscription_id'
);

SELECT results_eq(
  $$ SELECT (r.j->>'is_subscribed')::boolean, r.j->'subscription_id'
     FROM (SELECT public.get_topic_subtopic_timeline(id)::jsonb -> 'topic' AS j
           FROM public.topics WHERE title = '_zzsubtl_other') r $$,
  $$ VALUES (false, 'null'::jsonb) $$,
  'authenticated: 구독하지 않은 토픽은 is_subscribed = false'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
