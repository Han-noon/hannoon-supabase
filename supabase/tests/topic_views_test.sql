BEGIN;
SELECT plan(35);

-- 픽스처 시각(now()::timestamp)을 함수의 고정 타임존과 맞춘다
SET LOCAL timezone = 'Asia/Seoul';

-- 조회 로그는 트랜잭션 안에서 비우고 시작한다(ROLLBACK으로 되돌아가므로 실제 데이터에는 영향 없음).
DELETE FROM public.topic_views;

INSERT INTO public.topics (category, title, summary) VALUES
  ('사회', '_views_topic_x', '1시간 창 조회 1위 예상'),
  ('경제', '_views_topic_y', '3시간 창 조회 1위 예상');

INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_views_topic_x'), '사회', '_views_ev_x1',   '요약'),
  ((SELECT id FROM public.topics WHERE title = '_views_topic_y'), '경제', '_views_ev_y1',   '요약'),
  (NULL,                                                          '사회', '_views_ev_null', '토픽 미배정 이벤트');

-- 타임라인에 나오려면 이벤트에 기사가 있어야 한다
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.test/views', 'views-x1', 'https://test.com/views/x1', '사회', '_views_article_x1', '요약', 'rss', '테스트언론', '2024-03-01 09:00:00', '중도', 'ready'),
  ('https://feeds.test/views', 'views-y1', 'https://test.com/views/y1', '경제', '_views_article_y1', '요약', 'rss', '테스트언론', '2024-03-02 09:00:00', '중도', 'ready');

INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_views_ev_x1'), (SELECT id FROM public.articles WHERE guid = 'views-x1')),
  ((SELECT id FROM public.events WHERE title = '_views_ev_y1'), (SELECT id FROM public.articles WHERE guid = 'views-y1'));


-- ── get_popular_topic_timeline ─────────────────────────────────

SELECT is(
  (public.get_popular_topic_timeline())::jsonb - 'as_of' - 'views_as_of',
  '{"topic": null, "events": [], "window_hours": 1, "view_count": 0}'::jsonb,
  'get_popular_topic_timeline: 최근 1시간 조회가 없으면 빈 상태 (기사 수 랭킹으로 대체하지 않음)'
);

SELECT is(
  ((public.get_popular_topic_timeline())::jsonb ->> 'views_as_of')::timestamp,
  now()::timestamp,
  'get_popular_topic_timeline: 조회 집계 기준 시각 views_as_of = now()'
);

-- (토픽, 몇 분/시간 전, 건수)
-- 1시간 창: x 2건, y 1건(-5분) → x 1위.
--   y의 정확히 -1시간 조회를 포함하면 y 2건 동률 + 더 최근 → y 1위가 되므로 창 시작 경계를 판별한다.
--   y의 미래 시각 조회 3건을 포함하면 y 4건 → y 1위가 되므로 미래 시각 제외도 판별한다.
-- 3시간 창: y 7건(-5분, -1시간, -2시간×5) → y 1위.
INSERT INTO public.topic_views (topic_id, viewer_key, viewed_at)
SELECT (SELECT id FROM public.topics WHERE title = s.topic_title), 'fixture', now()::timestamp - s.ago
FROM (VALUES
  ('_views_topic_x', interval '10 minutes', 1),
  ('_views_topic_x', interval '20 minutes', 1),
  ('_views_topic_y', interval '5 minutes',  1),
  ('_views_topic_y', interval '1 hour',     1),  -- 1시간 창 시작 경계 (미포함)
  ('_views_topic_y', interval '2 hours',    5),
  ('_views_topic_y', interval '-1 hour',    3)   -- 미래 시각 (미포함)
) AS s(topic_title, ago, n)
CROSS JOIN LATERAL generate_series(1, s.n);

SELECT is(
  (public.get_popular_topic_timeline())::jsonb -> 'topic' ->> 'title',
  '_views_topic_x',
  'get_popular_topic_timeline: 최근 1시간 조회수 1위 토픽 (창 시작 시각·미래 시각 조회는 제외)'
);

SELECT is(
  ((public.get_popular_topic_timeline())::jsonb ->> 'view_count')::int,
  2,
  'get_popular_topic_timeline: 1위 토픽의 1시간 조회수'
);

SELECT is(
  (public.get_popular_topic_timeline())::jsonb -> 'events' -> 0 ->> 'title',
  '_views_ev_x1',
  'get_popular_topic_timeline: 1위 토픽의 이벤트 타임라인 포함'
);

SELECT is(
  (public.get_popular_topic_timeline(3))::jsonb -> 'topic' ->> 'title',
  '_views_topic_y',
  'get_popular_topic_timeline: p_window_hours를 넓히면 그 창의 1위'
);

SELECT is(
  ((public.get_popular_topic_timeline(3))::jsonb ->> 'view_count')::int,
  7,
  'get_popular_topic_timeline: 넓힌 창의 조회수'
);

SELECT is(
  ((public.get_popular_topic_timeline(100000))::jsonb ->> 'window_hours')::int,
  24,
  'get_popular_topic_timeline: p_window_hours 24 초과 시 클램핑'
);

SELECT throws_ok(
  $$ SELECT public.get_popular_topic_timeline(0) $$,
  'window_hours는 1 이상이어야 합니다',
  'get_popular_topic_timeline: p_window_hours < 1 시 예외 발생'
);

SELECT throws_ok(
  $$ SELECT public.get_popular_topic_timeline(1, 0) $$,
  'size는 1 이상이어야 합니다',
  'get_popular_topic_timeline: p_size < 1 시 예외 발생 (타임라인 함수 검증 그대로)'
);

SET LOCAL ROLE anon;

SELECT is(
  (public.get_popular_topic_timeline())::jsonb -> 'topic' ->> 'title',
  '_views_topic_x',
  'anon: 조회 로그 권한 없이도 get_popular_topic_timeline 결과 동일'
);

SELECT throws_ok(
  $$ SELECT * FROM public.topic_views $$,
  '42501',
  NULL,
  'anon: 조회 로그 테이블 직접 읽기 불가'
);

SELECT throws_ok(
  $$ INSERT INTO public.topic_views (topic_id) VALUES (1) $$,
  '42501',
  NULL,
  'anon: 조회 로그 테이블 직접 쓰기 불가'
);

-- 호출이 아니라 권한만 검사한다. CI(supabase CLI 2.95.4)에서 이 구문을 anon으로 실행하던 중
-- 백엔드가 죽어 pgTAP 실행이 통째로 무너졌다(run 36312613563). 검증 내용은 같다.
SELECT ok(
  NOT has_function_privilege('anon', 'public.purge_topic_views()', 'EXECUTE'),
  'anon: 로그 정리 함수 실행 불가'
);

RESET ROLE;


-- ── record_topic_view ──────────────────────────────────────────

SET LOCAL ROLE anon;

SELECT lives_ok(
  $$ SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_x'), p_viewer_key => 'k1') $$,
  'record_topic_view: 비로그인 사용자도 호출 가능'
);

SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_x'), p_viewer_key => 'k1');  -- 10분 안 같은 화면 재조회
SELECT public.record_topic_view(p_event_id => (SELECT id FROM public.events WHERE title = '_views_ev_x1'),   p_viewer_key => 'k1');  -- 같은 사람, 다른 화면
SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_x'), p_viewer_key => 'k2');  -- 다른 사람
SELECT public.record_topic_view(p_event_id => (SELECT id FROM public.events WHERE title = '_views_ev_null'), p_viewer_key => 'k3');  -- 토픽 미배정 이벤트
SELECT public.record_topic_view(p_event_id => 999999, p_viewer_key => 'k3');                                                           -- 없는 이벤트
SELECT public.record_topic_view(p_topic_id => 999999, p_viewer_key => 'k3');                                                           -- 없는 토픽
SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_y'));                         -- 키 없음
SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_y'), p_viewer_key => '');    -- 빈 키

RESET ROLE;

SELECT is(
  (SELECT count(*)::int FROM public.topic_views WHERE viewer_key = 'k1' AND event_id IS NULL),
  1,
  'record_topic_view: 같은 사람이 10분 안에 같은 화면을 다시 열면 한 번만 기록'
);

SELECT is(
  (SELECT topic_id FROM public.topic_views
   WHERE viewer_key = 'k1' AND event_id = (SELECT id FROM public.events WHERE title = '_views_ev_x1')),
  (SELECT id FROM public.topics WHERE title = '_views_topic_x'),
  'record_topic_view: 이벤트 상세 조회는 소속 토픽의 조회로 기록 (같은 사람이라도 다른 화면은 따로)'
);

SELECT is(
  (SELECT count(*)::int FROM public.topic_views WHERE viewer_key = 'k2'),
  1,
  'record_topic_view: 다른 사람의 조회는 따로 기록'
);

SELECT is(
  (SELECT count(*)::int FROM public.topic_views WHERE viewer_key = 'k3'),
  0,
  'record_topic_view: 토픽 미배정 이벤트와 없는 id는 기록하지 않음'
);

SELECT is(
  (SELECT count(*)::int FROM public.topic_views
   WHERE topic_id = (SELECT id FROM public.topics WHERE title = '_views_topic_y')
     AND user_id IS NULL AND (viewer_key IS NULL OR viewer_key = '')),
  0,
  'record_topic_view: 키가 없거나 빈 문자열인 비로그인 조회는 기록하지 않음'
);

-- 중복 제한 창 경계: 9분 전 조회가 있으면 다시 세지 않고, 정확히 10분 전이면 다시 센다
INSERT INTO public.topic_views (topic_id, viewer_key, viewed_at) VALUES
  ((SELECT id FROM public.topics WHERE title = '_views_topic_x'), 'k5', now()::timestamp - interval '9 minutes'),
  ((SELECT id FROM public.topics WHERE title = '_views_topic_x'), 'k6', now()::timestamp - interval '10 minutes');
SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_x'), p_viewer_key => 'k5');
SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_x'), p_viewer_key => 'k6');

SELECT is(
  (SELECT count(*)::int FROM public.topic_views WHERE viewer_key = 'k5'),
  1,
  'record_topic_view: 9분 전에 본 화면을 다시 열면 기록하지 않음'
);

SELECT is(
  (SELECT count(*)::int FROM public.topic_views WHERE viewer_key = 'k6'),
  2,
  'record_topic_view: 정확히 10분이 지나면 다시 기록'
);

-- 세션 타임존이 달라도 함수는 Asia/Seoul 기준으로 기록한다 (요청 단위 타임존 지정으로 viewed_at을 조작하지 못하게)
SET LOCAL timezone = 'UTC';
SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_x'), p_viewer_key => 'ktz');
SET LOCAL timezone = 'Asia/Seoul';

SELECT is(
  (SELECT viewed_at FROM public.topic_views WHERE viewer_key = 'ktz'),
  (now() AT TIME ZONE 'Asia/Seoul')::timestamp,
  'record_topic_view: 세션 타임존이 UTC여도 viewed_at은 Asia/Seoul 기준'
);

SELECT throws_ok(
  $$ SELECT public.record_topic_view(1, 1) $$,
  'topic_id와 event_id 중 하나만 지정해야 합니다',
  'record_topic_view: topic_id와 event_id를 둘 다 주면 예외'
);

SELECT throws_ok(
  $$ SELECT public.record_topic_view() $$,
  'topic_id와 event_id 중 하나만 지정해야 합니다',
  'record_topic_view: 둘 다 없으면 예외'
);

SELECT throws_ok(
  $$ SELECT public.record_topic_view(p_topic_id => 1, p_viewer_key => repeat('a', 65)) $$,
  'viewer_key는 64자 이하여야 합니다',
  'record_topic_view: viewer_key가 64자를 넘으면 예외'
);

-- 로그인 사용자
SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES ('eeeeeeee-0000-0000-0000-000000000001', 'topic_views_test@example.com');
SET LOCAL session_replication_role = DEFAULT;

SELECT set_config('request.jwt.claim.sub', 'eeeeeeee-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims', '{"sub": "eeeeeeee-0000-0000-0000-000000000001"}', true);
SET LOCAL ROLE authenticated;

SELECT throws_ok(
  $$ SELECT * FROM public.topic_views $$,
  '42501',
  NULL,
  'authenticated: 조회 로그 테이블 직접 읽기 불가'
);

SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_y'), p_viewer_key => 'kx');
SELECT public.record_topic_view(p_topic_id => (SELECT id FROM public.topics WHERE title = '_views_topic_y'), p_viewer_key => 'ky');  -- 키가 달라도 같은 사용자

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims', '{}', true);

SELECT is(
  (SELECT count(*)::int FROM public.topic_views WHERE user_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  1,
  'record_topic_view: 로그인 사용자는 viewer_key와 무관하게 user_id 기준으로 중복 제한'
);

SELECT is(
  (SELECT viewer_key FROM public.topic_views WHERE user_id = 'eeeeeeee-0000-0000-0000-000000000001'),
  NULL,
  'record_topic_view: 로그인 사용자는 viewer_key를 저장하지 않음'
);

DELETE FROM public.profiles WHERE id = 'eeeeeeee-0000-0000-0000-000000000001';

SELECT is(
  (SELECT count(*)::int FROM public.topic_views
   WHERE topic_id = (SELECT id FROM public.topics WHERE title = '_views_topic_y')
     AND user_id IS NULL AND viewer_key IS NULL),
  1,
  'topic_views: 회원 탈퇴(profiles 삭제) 시 조회 행은 남기고 user_id만 비움'
);


-- ── purge_topic_views ──────────────────────────────────────────

INSERT INTO public.topic_views (topic_id, viewer_key, viewed_at) VALUES
  ((SELECT id FROM public.topics WHERE title = '_views_topic_x'), 'p1', now()::timestamp - interval '8 days'),
  ((SELECT id FROM public.topics WHERE title = '_views_topic_x'), 'p2', now()::timestamp - interval '2 days'),
  ((SELECT id FROM public.topics WHERE title = '_views_topic_x'), 'p3', now()::timestamp - interval '23 hours');

SELECT is(
  (public.purge_topic_views())::jsonb,
  '{"deleted": 1, "anonymized": 1}'::jsonb,
  'purge_topic_views: 삭제·식별자 비우기 건수 반환'
);

SELECT is(
  (SELECT count(*)::int FROM public.topic_views WHERE viewed_at = now()::timestamp - interval '8 days'),
  0,
  'purge_topic_views: 7일 지난 로그 삭제'
);

SELECT is(
  (SELECT count(*)::int FROM public.topic_views
   WHERE viewed_at = now()::timestamp - interval '2 days' AND user_id IS NULL AND viewer_key IS NULL),
  1,
  'purge_topic_views: 1일 지난 행은 남기고 식별자만 비움'
);

SELECT is(
  (SELECT viewer_key FROM public.topic_views WHERE viewed_at = now()::timestamp - interval '23 hours'),
  'p3',
  'purge_topic_views: 1일이 안 지난 행의 식별자는 유지'
);

SELECT is(
  (SELECT count(*)::int FROM cron.job
   WHERE jobname = 'purge-topic-views' AND command LIKE '%public.purge_topic_views()%'),
  1,
  'pg_cron: purge-topic-views 정기 작업 등록'
);

SELECT * FROM finish();
ROLLBACK;
