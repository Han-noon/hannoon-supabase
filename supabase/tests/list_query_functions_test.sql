BEGIN;
SELECT plan(24);

-- 테스트 데이터 삽입 (트랜잭션 종료 시 롤백)
INSERT INTO public.topics (category, title, summary) VALUES
  ('정치', '_test_list_정치_토픽1', '정치 관련 테스트 토픽'),
  ('정치', '_test_list_정치_토픽2', '정치 관련 테스트 토픽'),
  ('경제', '_test_list_경제_토픽',  '경제 관련 테스트 토픽'),
  ('사회', '_test_list_국회의원_토픽', '국회의원 검색 테스트용 토픽');

INSERT INTO public.events (topic_id, category, title, summary, article_count) VALUES
  ((SELECT id FROM public.topics WHERE title = '_test_list_정치_토픽1'), '정치', '_test_list_정치_이벤트1', '이벤트 요약', 0),
  ((SELECT id FROM public.topics WHERE title = '_test_list_경제_토픽'),  '경제', '_test_list_경제_이벤트1', '이벤트 요약', 0);


-- ============================================================
-- get_topics
-- ============================================================

SELECT ok(
  (public.get_topics(NULL, NULL, NULL, NULL))::jsonb
    ?& ARRAY['topics', 'page', 'size', 'total_count', 'total_pages'],
  'get_topics: 응답 최상위 필드 포함'
);

SELECT ok(
  (public.get_topics(NULL, NULL, 1, 9))::jsonb -> 'topics' -> 0
    ?& ARRAY['id', 'category', 'title', 'summary', 'created_at', 'updated_at', 'subscription_id', 'is_subscribed'],
  'get_topics: 아이템 필드 확인'
);

SELECT is(
  ((public.get_topics(NULL, NULL, NULL, NULL))::jsonb ->> 'page')::int,
  1,
  'get_topics: p_page null 시 default 1'
);

SELECT is(
  ((public.get_topics(NULL, NULL, NULL, NULL))::jsonb ->> 'size')::int,
  9,
  'get_topics: p_size null 시 default 9'
);

SELECT is(
  ((public.get_topics(NULL, NULL, 1, 200))::jsonb ->> 'size')::int,
  100,
  'get_topics: p_size > 100 시 100으로 클램핑'
);

SELECT is(
  ((public.get_topics(NULL, NULL, 1, 1))::jsonb ->> 'total_pages')::int,
  ((public.get_topics(NULL, NULL, 1, 1))::jsonb ->> 'total_count')::int,
  'get_topics: size=1 시 total_pages = total_count'
);

SELECT ok(
  ((public.get_topics(NULL, '정치', 1, 100))::jsonb ->> 'total_count')::int >= 2,
  'get_topics: 카테고리 필터 - 정치 토픽 2건 이상 반환'
);

SELECT ok(
  ((public.get_topics(NULL, '경제', 1, 100))::jsonb ->> 'total_count')::int <
  ((public.get_topics(NULL, NULL,   1, 100))::jsonb ->> 'total_count')::int,
  'get_topics: 카테고리 필터 시 전체보다 적은 결과'
);

SELECT ok(
  ((public.get_topics('국회의원', NULL, 1, 9))::jsonb ->> 'total_count')::int >= 1,
  'get_topics: 검색어 필터 - 매칭 결과 반환'
);

SELECT is(
  ((public.get_topics('', NULL, 1, 9))::jsonb ->> 'total_count')::int,
  ((public.get_topics(NULL, NULL, 1, 9))::jsonb ->> 'total_count')::int,
  'get_topics: 빈 문자열 검색어는 null과 동일 처리'
);

SELECT is(
  ((public.get_topics(NULL, NULL, 1, 1))::jsonb -> 'topics' -> 0 ->> 'subscription_id'),
  NULL,
  'get_topics: 비로그인 시 subscription_id = null'
);

SELECT is(
  ((public.get_topics(NULL, NULL, 1, 1))::jsonb -> 'topics' -> 0 ->> 'is_subscribed')::boolean,
  false,
  'get_topics: 비로그인 시 is_subscribed = false'
);

SELECT throws_ok(
  $$ SELECT public.get_topics(NULL, NULL, 0, NULL) $$,
  'page는 1 이상이어야 합니다',
  'get_topics: p_page < 1 시 예외 발생'
);

SELECT throws_ok(
  $$ SELECT public.get_topics(NULL, NULL, NULL, 0) $$,
  'size는 1 이상이어야 합니다',
  'get_topics: p_size < 1 시 예외 발생'
);


-- ============================================================
-- get_subscribed_topics
-- ============================================================

SELECT throws_ok(
  $$ SELECT public.get_subscribed_topics(NULL, NULL) $$,
  '로그인이 필요합니다',
  'get_subscribed_topics: 비로그인 시 예외 발생'
);


-- ============================================================
-- get_events
-- ============================================================

SELECT ok(
  (public.get_events(NULL, NULL, NULL, NULL))::jsonb
    ?& ARRAY['events', 'page', 'size', 'total_count', 'total_pages'],
  'get_events: 응답 최상위 필드 포함'
);

SELECT ok(
  (public.get_events(NULL, NULL, 1, 9))::jsonb -> 'events' -> 0
    ?& ARRAY['event_id', 'topic_id', 'category', 'title', 'summary', 'created_at', 'updated_at', 'subscription_id', 'is_subscribed'],
  'get_events: 아이템 필드 확인 (event_id 포함, id 아님)'
);

SELECT is(
  ((public.get_events(NULL, NULL, NULL, NULL))::jsonb ->> 'size')::int,
  9,
  'get_events: p_size null 시 default 9'
);

SELECT ok(
  ((public.get_events(NULL, '정치', 1, 100))::jsonb ->> 'total_count')::int >= 1,
  'get_events: 카테고리 필터 - 정치 이벤트 반환'
);

SELECT ok(
  ((public.get_events(NULL, '경제', 1, 100))::jsonb ->> 'total_count')::int <
  ((public.get_events(NULL, NULL,   1, 100))::jsonb ->> 'total_count')::int,
  'get_events: 카테고리 필터 시 전체보다 적은 결과'
);

SELECT ok(
  ((public.get_events('이벤트', NULL, 1, 9))::jsonb ->> 'total_count')::int >= 1,
  'get_events: 검색어 필터 - 매칭 결과 반환'
);

SELECT is(
  ((public.get_events('', NULL, 1, 9))::jsonb ->> 'total_count')::int,
  ((public.get_events(NULL, NULL, 1, 9))::jsonb ->> 'total_count')::int,
  'get_events: 빈 문자열 검색어는 null과 동일 처리'
);

SELECT is(
  ((public.get_events(NULL, NULL, 1, 1))::jsonb -> 'events' -> 0 ->> 'subscription_id'),
  NULL,
  'get_events: 비로그인 시 subscription_id = null'
);

SELECT is(
  ((public.get_events(NULL, NULL, 1, 1))::jsonb -> 'events' -> 0 ->> 'is_subscribed')::boolean,
  false,
  'get_events: 비로그인 시 is_subscribed = false'
);


SELECT * FROM finish();
ROLLBACK;
