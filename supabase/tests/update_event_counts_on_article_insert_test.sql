BEGIN;
SELECT plan(9);

-- 테스트 데이터 삽입 (트랜잭션 종료 시 롤백)
INSERT INTO public.topics (category, title, summary) VALUES
  ('정치', '_test_topic_trigger', '트리거 테스트용 토픽');

INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_test_topic_trigger'), '정치', '_test_event_trigger', '카운트 트리거 테스트용 이벤트');

INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.test/t', 8001, 'https://test.com/t/1', '정치', '_test_trigger_left',  '요약', 'rss', '테스트언론', '2024-01-01 00:00:00', 'left',  'ready'),
  ('https://feeds.test/t', 8002, 'https://test.com/t/2', '정치', '_test_trigger_mid',   '요약', 'rss', '테스트언론', '2024-01-02 00:00:00', 'mid',   'ready'),
  ('https://feeds.test/t', 8003, 'https://test.com/t/3', '정치', '_test_trigger_right', '요약', 'rss', '테스트언론', '2024-01-03 00:00:00', 'right', 'ready');

-- left 기사 삽입
INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_trigger'), (SELECT id FROM public.articles WHERE guid = 8001));

SELECT is(
  (SELECT article_count FROM public.events WHERE title = '_test_event_trigger'),
  1,
  'trigger: left 기사 삽입 후 article_count = 1'
);

SELECT is(
  (SELECT left_count FROM public.events WHERE title = '_test_event_trigger'),
  1,
  'trigger: left 기사 삽입 후 left_count = 1'
);

SELECT is(
  (SELECT mid_count FROM public.events WHERE title = '_test_event_trigger'),
  0,
  'trigger: left 기사 삽입 후 mid_count = 0'
);

SELECT is(
  (SELECT right_count FROM public.events WHERE title = '_test_event_trigger'),
  0,
  'trigger: left 기사 삽입 후 right_count = 0'
);

-- mid 기사 삽입
INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_trigger'), (SELECT id FROM public.articles WHERE guid = 8002));

SELECT is(
  (SELECT article_count FROM public.events WHERE title = '_test_event_trigger'),
  2,
  'trigger: mid 기사 추가 삽입 후 article_count = 2'
);

SELECT is(
  (SELECT mid_count FROM public.events WHERE title = '_test_event_trigger'),
  1,
  'trigger: mid 기사 추가 삽입 후 mid_count = 1'
);

-- right 기사 삽입
INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_trigger'), (SELECT id FROM public.articles WHERE guid = 8003));

SELECT is(
  (SELECT article_count FROM public.events WHERE title = '_test_event_trigger'),
  3,
  'trigger: right 기사 추가 삽입 후 article_count = 3'
);

SELECT is(
  (SELECT right_count FROM public.events WHERE title = '_test_event_trigger'),
  1,
  'trigger: right 기사 추가 삽입 후 right_count = 1'
);

-- 최종 상태: left=1, mid=1, right=1
SELECT is(
  (SELECT ROW(left_count, mid_count, right_count) FROM public.events WHERE title = '_test_event_trigger'),
  ROW(1, 1, 1),
  'trigger: 최종 left_count=1, mid_count=1, right_count=1'
);

SELECT * FROM finish();
ROLLBACK;
