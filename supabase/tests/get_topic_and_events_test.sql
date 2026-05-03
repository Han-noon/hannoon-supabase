BEGIN;
SELECT plan(14);

-- 테스트 데이터 삽입 (트랜잭션 종료 시 롤백)
INSERT INTO public.topics (category, title, summary) VALUES
  ('정치', '_test_topic_pagination', '페이지네이션 테스트용 토픽'),
  ('경제', '_test_topic_small',      '소규모 이벤트 토픽');

INSERT INTO public.events (topic_id, category, title, summary, article_count) VALUES
  ((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), '정치', '이벤트1', '요약1', 0),
  ((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), '정치', '이벤트2', '요약2', 0),
  ((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), '정치', '이벤트3', '요약3', 0),
  ((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), '정치', '이벤트4', '요약4', 0),
  ((SELECT id FROM public.topics WHERE title = '_test_topic_small'), '경제', '이벤트A', '요약A', 0),
  ((SELECT id FROM public.topics WHERE title = '_test_topic_small'), '경제', '이벤트B', '요약B', 0);

-- get_topic
SELECT is(
  (public.get_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination')))::jsonb ->> 'title',
  '_test_topic_pagination',
  'get_topic: 올바른 title 반환'
);

SELECT is(
  (public.get_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination')))::jsonb ->> 'category',
  '정치',
  'get_topic: 올바른 category 반환'
);

SELECT ok(
  (public.get_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination')))::jsonb ?& ARRAY['id', 'created_at', 'updated_at'],
  'get_topic: id, created_at, updated_at 필드 포함'
);

SELECT throws_ok(
  $$ SELECT public.get_topic(999999) $$,
  'topic not found',
  'get_topic: 존재하지 않는 topic_id 시 예외 발생'
);

-- get_events_by_topic: asc 첫 페이지
SELECT is(
  jsonb_array_length(
    (public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), NULL, 3, 'asc'))::jsonb -> 'events'
  ),
  3,
  'get_events_by_topic: 첫 페이지 p_size만큼 반환'
);

SELECT is(
  ((public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), NULL, 3, 'asc'))::jsonb ->> 'has_more')::boolean,
  true,
  'get_events_by_topic: 다음 페이지 존재 시 has_more = true'
);

SELECT ok(
  (public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), NULL, 3, 'asc'))::jsonb ->> 'next_cursor' IS NOT NULL,
  'get_events_by_topic: has_more = true 시 next_cursor 설정'
);

-- get_events_by_topic: asc 두 번째 페이지
SELECT is(
  jsonb_array_length(
    (WITH first AS (
      SELECT ((public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), NULL, 3, 'asc'))::jsonb ->> 'next_cursor')::bigint AS cursor
    )
    SELECT public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), (SELECT cursor FROM first), 3, 'asc'))::jsonb -> 'events'
  ),
  1,
  'get_events_by_topic: 마지막 페이지에서 나머지 건수만 반환'
);

SELECT is(
  ((WITH first AS (
    SELECT ((public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), NULL, 3, 'asc'))::jsonb ->> 'next_cursor')::bigint AS cursor
  )
  SELECT public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_pagination'), (SELECT cursor FROM first), 3, 'asc'))::jsonb ->> 'has_more')::boolean,
  false,
  'get_events_by_topic: 마지막 페이지 has_more = false'
);

-- get_events_by_topic: 전체 건수가 p_size 이하인 토픽
SELECT is(
  ((public.get_events_by_topic((SELECT id FROM public.topics WHERE title = '_test_topic_small'), NULL, 3, 'asc'))::jsonb ->> 'has_more')::boolean,
  false,
  'get_events_by_topic: 전체 건수 <= p_size 시 has_more = false'
);

-- get_event
SELECT is(
  (public.get_event((SELECT id FROM public.events WHERE title = '이벤트1')))::jsonb ->> 'title',
  '이벤트1',
  'get_event: 올바른 title 반환'
);

SELECT is(
  ((public.get_event((SELECT id FROM public.events WHERE title = '이벤트1')))::jsonb ->> 'topic_id')::bigint,
  (SELECT id FROM public.topics WHERE title = '_test_topic_pagination'),
  'get_event: 올바른 topic_id 반환'
);

SELECT ok(
  (public.get_event((SELECT id FROM public.events WHERE title = '이벤트1')))::jsonb
    ?& ARRAY['id', 'topic_id', 'category', 'title', 'summary',
             'article_count', 'left_count', 'mid_count', 'right_count', 'abusing_count',
             'event_image_url', 'created_at', 'updated_at', 'prev_event', 'next_event'],
  'get_event: 모든 컬럼 포함'
);

SELECT throws_ok(
  $$ SELECT public.get_event(999999) $$,
  'event not found',
  'get_event: 존재하지 않는 event_id 시 예외 발생'
);

SELECT * FROM finish();
ROLLBACK;
