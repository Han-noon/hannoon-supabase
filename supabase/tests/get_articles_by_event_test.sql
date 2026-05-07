BEGIN;
SELECT plan(17);

-- 테스트 데이터 삽입 (트랜잭션 종료 시 롤백)
INSERT INTO public.topics (category, title, summary) VALUES
  ('정치', '_test_topic_ea', '이벤트-기사 테스트용 토픽');

INSERT INTO public.events (topic_id, category, title, summary, article_count) VALUES
  ((SELECT id FROM public.topics WHERE title = '_test_topic_ea'), '정치', '_test_event_articles', '기사 조회 테스트용 이벤트', 0),
  ((SELECT id FROM public.topics WHERE title = '_test_topic_ea'), '정치', '_test_event_empty',    '기사 없는 이벤트',         0);

INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.test/a', 9001, 'https://test.com/a/1', '정치', '_test_article_1', '요약1', 'rss', '테스트언론', '2024-01-01 00:00:00', '진보',  'ready'),
  ('https://feeds.test/a', 9002, 'https://test.com/a/2', '정치', '_test_article_2', '요약2', 'rss', '테스트언론', '2024-01-02 00:00:00', '진보',  'ready'),
  ('https://feeds.test/a', 9003, 'https://test.com/a/3', '정치', '_test_article_3', '요약3', 'rss', '테스트언론', '2024-01-03 00:00:00', '중도',   'ready'),
  ('https://feeds.test/a', 9004, 'https://test.com/a/4', '정치', '_test_article_4', '요약4', 'rss', '테스트언론', '2024-01-04 00:00:00', '중도',   'ready'),
  ('https://feeds.test/a', 9005, 'https://test.com/a/5', '정치', '_test_article_5', '요약5', 'rss', '테스트언론', '2024-01-05 00:00:00', '보수', 'ready');

INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_articles'), (SELECT id FROM public.articles WHERE guid = 9001)),
  ((SELECT id FROM public.events WHERE title = '_test_event_articles'), (SELECT id FROM public.articles WHERE guid = 9002)),
  ((SELECT id FROM public.events WHERE title = '_test_event_articles'), (SELECT id FROM public.articles WHERE guid = 9003)),
  ((SELECT id FROM public.events WHERE title = '_test_event_articles'), (SELECT id FROM public.articles WHERE guid = 9004)),
  ((SELECT id FROM public.events WHERE title = '_test_event_articles'), (SELECT id FROM public.articles WHERE guid = 9005));

-- 응답 필드 포함 확인
SELECT ok(
  (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles')))::jsonb
    ?& ARRAY['articles', 'page', 'size', 'total_count', 'total_pages'],
  'get_articles_by_event: 응답에 필수 필드 포함'
);

-- 전체 조회 total_count
SELECT is(
  ((public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles')))::jsonb ->> 'total_count')::int,
  5,
  'get_articles_by_event: bias_type 미지정 시 전체 기사 수 반환'
);

-- bias_type=진보 필터
SELECT is(
  ((public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), '진보'))::jsonb ->> 'total_count')::int,
  2,
  'get_articles_by_event: bias_type=진보 필터 시 진보 기사 수 반환'
);

-- bias_type=보수 필터
SELECT is(
  jsonb_array_length(
    (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), '보수'))::jsonb -> 'articles'
  ),
  1,
  'get_articles_by_event: bias_type=보수 필터 시 보수 기사만 반환'
);

-- 페이지네이션 첫 페이지 건수
SELECT is(
  jsonb_array_length(
    (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 1, 2))::jsonb -> 'articles'
  ),
  2,
  'get_articles_by_event: 첫 페이지 p_size만큼 반환'
);

-- 페이지네이션 두 번째 페이지 건수
SELECT is(
  jsonb_array_length(
    (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 2, 2))::jsonb -> 'articles'
  ),
  2,
  'get_articles_by_event: 두 번째 페이지 p_size만큼 반환'
);

-- 마지막 페이지 나머지 건수
SELECT is(
  jsonb_array_length(
    (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 3, 2))::jsonb -> 'articles'
  ),
  1,
  'get_articles_by_event: 마지막 페이지 나머지 건수만 반환'
);

-- total_pages = CEIL(5 / 2) = 3
SELECT is(
  ((public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 1, 2))::jsonb ->> 'total_pages')::int,
  3,
  'get_articles_by_event: total_pages = CEIL(total_count / size)'
);

-- asc 정렬: 첫 번째 기사가 가장 오래된 것
SELECT is(
  (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 1, 5, 'asc'))::jsonb -> 'articles' -> 0 ->> 'title',
  '_test_article_1',
  'get_articles_by_event: asc 정렬 시 가장 오래된 기사가 첫 번째'
);

-- desc 정렬: 첫 번째 기사가 가장 최신 것
SELECT is(
  (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 1, 5, 'desc'))::jsonb -> 'articles' -> 0 ->> 'title',
  '_test_article_5',
  'get_articles_by_event: desc 정렬 시 가장 최신 기사가 첫 번째'
);

-- 기사 없는 이벤트 - 빈 배열 반환
SELECT is(
  (public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_empty')))::jsonb -> 'articles',
  '[]'::jsonb,
  'get_articles_by_event: 기사 없는 이벤트 시 빈 배열 반환'
);

-- 기사 없는 이벤트 - total_count = 0
SELECT is(
  ((public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_empty')))::jsonb ->> 'total_count')::int,
  0,
  'get_articles_by_event: 기사 없는 이벤트 시 total_count = 0'
);

-- p_page < 1 EXCEPTION
SELECT throws_ok(
  format($$ SELECT public.get_articles_by_event(%s, NULL, 0) $$,
    (SELECT id FROM public.events WHERE title = '_test_event_articles')),
  '페이지는 1 이상이어야 합니다',
  'get_articles_by_event: p_page < 1 시 예외 발생'
);

-- p_size < 1 EXCEPTION
SELECT throws_ok(
  format($$ SELECT public.get_articles_by_event(%s, NULL, 1, 0) $$,
    (SELECT id FROM public.events WHERE title = '_test_event_articles')),
  'size는 1 이상이어야 합니다',
  'get_articles_by_event: p_size < 1 시 예외 발생'
);

-- p_page NULL → default 1
SELECT is(
  ((public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, NULL))::jsonb ->> 'page')::int,
  1,
  'get_articles_by_event: p_page NULL 시 default 1 적용'
);

-- p_size NULL → default 3
SELECT is(
  ((public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 1, NULL))::jsonb ->> 'size')::int,
  3,
  'get_articles_by_event: p_size NULL 시 default 3 적용'
);

-- p_size > 100 → 100으로 클램핑
SELECT is(
  ((public.get_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_articles'), NULL, 1, 200))::jsonb ->> 'size')::int,
  100,
  'get_articles_by_event: p_size > 100 시 100으로 클램핑'
);

SELECT * FROM finish();
ROLLBACK;
