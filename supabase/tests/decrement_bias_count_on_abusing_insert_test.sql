BEGIN;

SELECT plan(7);

-- 테스트 데이터 삽입
INSERT INTO public.topics (category, title, summary) VALUES
  ('정치', '_test_topic_abusing', '어뷰징 트리거 테스트용 토픽');

INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_test_topic_abusing'),
   '정치', '_test_event_abusing', '어뷰징 트리거 테스트용 이벤트');

INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.test/a', 7001, 'https://test.com/a/1', '정치', '_test_abusing_left',  '요약1', 'rss', '테스트언론', '2024-01-01 00:00:00', 'left',  'ready'),
  ('https://feeds.test/a', 7002, 'https://test.com/a/2', '정치', '_test_abusing_mid',   '요약2', 'rss', '테스트언론', '2024-01-01 00:00:00', 'mid',   'ready'),
  ('https://feeds.test/a', 7003, 'https://test.com/a/3', '정치', '_test_abusing_right', '요약3', 'rss', '테스트언론', '2024-01-01 00:00:00', 'right', 'ready');

-- event_articles 삽입으로 left_count=1, mid_count=1, right_count=1 세팅
INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = 7001)),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = 7002)),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = 7003));

-- left 기사 어뷰징 삽입
INSERT INTO public.abusing_articles (event_id, article_id, type) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'),
   (SELECT id FROM public.articles WHERE guid = 7001),
   'title_content_mismatch');

SELECT is(
  (SELECT left_count FROM public.events WHERE title = '_test_event_abusing'),
  0,
  'decrement_bias_count: left 기사 어뷰징 삽입 후 left_count = 0'
);

SELECT is(
  (SELECT mid_count FROM public.events WHERE title = '_test_event_abusing'),
  1,
  'decrement_bias_count: left 기사 어뷰징 삽입 후 mid_count 변화 없음'
);

SELECT is(
  (SELECT right_count FROM public.events WHERE title = '_test_event_abusing'),
  1,
  'decrement_bias_count: left 기사 어뷰징 삽입 후 right_count 변화 없음'
);

-- mid 기사 어뷰징 삽입
INSERT INTO public.abusing_articles (event_id, article_id, type) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'),
   (SELECT id FROM public.articles WHERE guid = 7002),
   'content_context_mismatch');

SELECT is(
  (SELECT mid_count FROM public.events WHERE title = '_test_event_abusing'),
  0,
  'decrement_bias_count: mid 기사 어뷰징 삽입 후 mid_count = 0'
);

-- right 기사 어뷰징 삽입
INSERT INTO public.abusing_articles (event_id, article_id, type) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'),
   (SELECT id FROM public.articles WHERE guid = 7003),
   'title_content_mismatch');

SELECT is(
  (SELECT right_count FROM public.events WHERE title = '_test_event_abusing'),
  0,
  'decrement_bias_count: right 기사 어뷰징 삽입 후 right_count = 0'
);

-- 최종: 세 카운트 모두 0, abusing_count = 3
SELECT is(
  (SELECT ROW(left_count, mid_count, right_count)
   FROM public.events WHERE title = '_test_event_abusing'),
  ROW(0, 0, 0),
  'decrement_bias_count: 최종 left/mid/right_count 모두 0'
);

SELECT is(
  (SELECT abusing_count FROM public.events WHERE title = '_test_event_abusing'),
  3,
  'increment_abusing_count: abusing_count = 3'
);

SELECT * FROM finish();

ROLLBACK;
