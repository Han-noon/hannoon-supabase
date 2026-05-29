BEGIN;

SELECT plan(18);

SELECT has_table('public', 'viewed_events', 'viewed_events 테이블이 존재해야 한다');
SELECT has_column('public', 'viewed_events', 'user_id',   'viewed_events.user_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'viewed_events', 'event_id',  'viewed_events.event_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'viewed_events', 'viewed_at', 'viewed_events.viewed_at 컬럼이 존재해야 한다');

-- 테스트 데이터 시드
INSERT INTO public.topics (category, title, summary)
VALUES ('정치', '_test_viewed_topic', '최근 본 이벤트 테스트용 토픽');

SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'viewed_events_test@example.com');
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.events (topic_id, category, title, summary, article_count)
SELECT t.id, t.category, '_test_viewed_ev1', '이벤트1 요약', 0 FROM public.topics t WHERE t.title = '_test_viewed_topic'
UNION ALL
SELECT t.id, t.category, '_test_viewed_ev2', '이벤트2 요약', 0 FROM public.topics t WHERE t.title = '_test_viewed_topic'
UNION ALL
SELECT t.id, t.category, '_test_viewed_ev3', '이벤트3 요약', 0 FROM public.topics t WHERE t.title = '_test_viewed_topic';


-- ============================================================
-- get_event 내 조회 기록 (upsert)
-- ============================================================

SELECT set_config('request.jwt.claim.sub', 'eeeeeeee-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims',    '{"sub": "eeeeeeee-0000-0000-0000-000000000001"}', true);
SET LOCAL ROLE authenticated;

SELECT public.get_event((SELECT id FROM public.events WHERE title = '_test_viewed_ev1'));

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.viewed_events v
     WHERE v.user_id = 'eeeeeeee-0000-0000-0000-000000000001'
       AND v.event_id = (SELECT id FROM public.events WHERE title = '_test_viewed_ev1') $$,
  ARRAY[1],
  'get_event 호출 시 로그인 사용자의 조회 기록이 생성되어야 한다'
);

SELECT public.get_event((SELECT id FROM public.events WHERE title = '_test_viewed_ev1'));

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.viewed_events v
     WHERE v.user_id = 'eeeeeeee-0000-0000-0000-000000000001'
       AND v.event_id = (SELECT id FROM public.events WHERE title = '_test_viewed_ev1') $$,
  ARRAY[1],
  '같은 이벤트 재조회 시 기록이 중복 생성되지 않아야 한다 (upsert)'
);


-- ============================================================
-- get_viewed_events 응답 형태 및 파라미터
-- ============================================================

SELECT ok(
  (public.get_viewed_events(1, 9))::jsonb
    ?& ARRAY['events', 'page', 'size', 'total_count', 'total_pages'],
  'get_viewed_events: 응답 최상위 필드 포함'
);

SELECT ok(
  (public.get_viewed_events(1, 9))::jsonb -> 'events' -> 0
    ?& ARRAY['event_id', 'topic_id', 'topic_title', 'event_title', 'category', 'summary',
             'created_at', 'updated_at', 'viewed_at', 'subscription_id', 'is_subscribed'],
  'get_viewed_events: 아이템 필드 확인 (event_title/topic_title 구분)'
);

SELECT is(
  ((public.get_viewed_events())::jsonb ->> 'page')::int,
  1,
  'get_viewed_events: p_page default 1'
);

SELECT is(
  ((public.get_viewed_events())::jsonb ->> 'size')::int,
  9,
  'get_viewed_events: p_size default 9'
);

SELECT is(
  ((public.get_viewed_events(1, 200))::jsonb ->> 'size')::int,
  100,
  'get_viewed_events: p_size > 100 시 100으로 클램핑'
);

SELECT throws_ok(
  $$ SELECT public.get_viewed_events(0, 9) $$,
  'page는 1 이상이어야 합니다',
  'get_viewed_events: p_page < 1 시 예외 발생'
);

SELECT throws_ok(
  $$ SELECT public.get_viewed_events(1, 0) $$,
  'size는 1 이상이어야 합니다',
  'get_viewed_events: p_size < 1 시 예외 발생'
);


-- ============================================================
-- 최근 일주일 범위 및 정렬
-- ============================================================

RESET ROLE;

-- ev3: 1시간 전(범위 내), ev2: 8일 전(범위 밖)
INSERT INTO public.viewed_events (user_id, event_id, viewed_at)
VALUES
  ('eeeeeeee-0000-0000-0000-000000000001',
   (SELECT id FROM public.events WHERE title = '_test_viewed_ev3'), now() - interval '1 hour'),
  ('eeeeeeee-0000-0000-0000-000000000001',
   (SELECT id FROM public.events WHERE title = '_test_viewed_ev2'), now() - interval '8 days');

SET LOCAL ROLE authenticated;

SELECT is(
  ((public.get_viewed_events(1, 100))::jsonb ->> 'total_count')::int,
  2,
  'get_viewed_events: 최근 일주일 내 기록만 집계 (8일 전 기록 제외)'
);

SELECT is(
  ((public.get_viewed_events(1, 100))::jsonb -> 'events' -> 0 ->> 'event_id')::bigint,
  (SELECT id FROM public.events WHERE title = '_test_viewed_ev1'),
  'get_viewed_events: viewed_at DESC 정렬 (가장 최근 조회가 첫 번째)'
);

SELECT is(
  (SELECT count(*)::int
   FROM jsonb_array_elements((public.get_viewed_events(1, 100))::jsonb -> 'events') AS elem
   WHERE (elem ->> 'event_id')::bigint =
         (SELECT id FROM public.events WHERE title = '_test_viewed_ev2')),
  0,
  'get_viewed_events: 8일 전 조회한 이벤트는 결과에 포함되지 않아야 한다'
);


-- ============================================================
-- 비로그인 동작
-- ============================================================

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims',    '{}', true);

SELECT throws_ok(
  $$ SELECT public.get_viewed_events(1, 9) $$,
  '로그인이 필요합니다',
  'get_viewed_events: 비로그인 시 예외 발생'
);

SELECT public.get_event((SELECT id FROM public.events WHERE title = '_test_viewed_ev1'));

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.viewed_events v
     WHERE v.event_id = (SELECT id FROM public.events WHERE title = '_test_viewed_ev1') $$,
  ARRAY[1],
  'get_event: 비로그인 호출은 조회 기록을 생성하지 않아야 한다'
);


SELECT * FROM finish();

ROLLBACK;
