BEGIN;
SELECT plan(16);

-- 테스트 데이터 삽입 (트랜잭션 종료 시 롤백)
INSERT INTO public.topics (category, title, summary) VALUES
  ('정치', '_test_topic_aa', '어뷰징 기사 테스트용 토픽');

INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_test_topic_aa'), '정치', '_test_event_abusing', '어뷰징 기사 조회 테스트용 이벤트'),
  ((SELECT id FROM public.topics WHERE title = '_test_topic_aa'), '정치', '_test_event_abusing_empty', '어뷰징 기사 없는 이벤트');

INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.test/aa', '8001', 'https://test.com/aa/1', '정치', '_test_abusing_article_1', '요약1', 'rss', '테스트언론', '2024-01-01 00:00:00', '진보',  'ready'),
  ('https://feeds.test/aa', '8002', 'https://test.com/aa/2', '정치', '_test_abusing_article_2', '요약2', 'rss', '테스트언론', '2024-01-02 00:00:00', '진보',  'ready'),
  ('https://feeds.test/aa', '8003', 'https://test.com/aa/3', '정치', '_test_abusing_article_3', '요약3', 'rss', '테스트언론', '2024-01-03 00:00:00', '중도',   'ready'),
  ('https://feeds.test/aa', '8004', 'https://test.com/aa/4', '정치', '_test_abusing_article_4', '요약4', 'rss', '테스트언론', '2024-01-04 00:00:00', '중도',   'ready'),
  ('https://feeds.test/aa', '8005', 'https://test.com/aa/5', '정치', '_test_abusing_article_5', '요약5', 'rss', '테스트언론', '2024-01-05 00:00:00', '보수', 'ready');

INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8001')),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8002')),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8003')),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8004')),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8005'));

INSERT INTO public.abusing_articles (event_id, article_id, type) VALUES
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8001'), 'title_content_mismatch'),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8002'), 'title_content_mismatch'),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8003'), 'title_content_mismatch'),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8004'), 'content_context_mismatch'),
  ((SELECT id FROM public.events WHERE title = '_test_event_abusing'), (SELECT id FROM public.articles WHERE guid = '8005'), 'content_context_mismatch');

-- 응답 필드 포함 확인
SELECT ok(
  (public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing')))::jsonb
    ?& ARRAY['articles', 'page', 'size', 'total_count', 'total_pages'],
  'get_abusing_articles_by_event: 응답에 필수 필드 포함'
);

-- 전체 조회 total_count
SELECT is(
  ((public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing')))::jsonb ->> 'total_count')::int,
  5,
  'get_abusing_articles_by_event: abusing_type 미지정 시 전체 건수 반환'
);

-- abusing_type=title_content_mismatch 필터
SELECT is(
  ((public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), 'title_content_mismatch'))::jsonb ->> 'total_count')::int,
  3,
  'get_abusing_articles_by_event: title_content_mismatch 필터 시 해당 건수 반환'
);

-- abusing_type=content_context_mismatch 필터
SELECT is(
  jsonb_array_length(
    (public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), 'content_context_mismatch'))::jsonb -> 'articles'
  ),
  2,
  'get_abusing_articles_by_event: content_context_mismatch 필터 시 해당 기사만 반환'
);

-- 페이지네이션 첫 페이지 건수
SELECT is(
  jsonb_array_length(
    (public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), NULL, 1, 2))::jsonb -> 'articles'
  ),
  2,
  'get_abusing_articles_by_event: 첫 페이지 p_size만큼 반환'
);

-- 마지막 페이지 나머지 건수
SELECT is(
  jsonb_array_length(
    (public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), NULL, 3, 2))::jsonb -> 'articles'
  ),
  1,
  'get_abusing_articles_by_event: 마지막 페이지 나머지 건수만 반환'
);

-- total_pages = CEIL(5 / 2) = 3
SELECT is(
  ((public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), NULL, 1, 2))::jsonb ->> 'total_pages')::int,
  3,
  'get_abusing_articles_by_event: total_pages = CEIL(total_count / size)'
);

-- desc 정렬: 나중에 삽입된 기사가 첫 번째
SELECT is(
  (public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), NULL, 1, 5))::jsonb -> 'articles' -> 0 ->> 'title',
  '_test_abusing_article_5',
  'get_abusing_articles_by_event: desc 정렬 시 마지막 삽입 기사가 첫 번째'
);

-- 기사 없는 이벤트 - 빈 배열 반환
SELECT is(
  (public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing_empty')))::jsonb -> 'articles',
  '[]'::jsonb,
  'get_abusing_articles_by_event: 어뷰징 기사 없는 이벤트 시 빈 배열 반환'
);

-- 기사 없는 이벤트 - total_count = 0
SELECT is(
  ((public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing_empty')))::jsonb ->> 'total_count')::int,
  0,
  'get_abusing_articles_by_event: 어뷰징 기사 없는 이벤트 시 total_count = 0'
);

-- p_page < 1 EXCEPTION
SELECT throws_ok(
  format($$ SELECT public.get_abusing_articles_by_event(%s, NULL, 0) $$,
    (SELECT id FROM public.events WHERE title = '_test_event_abusing')),
  'page는 1 이상이어야 합니다',
  'get_abusing_articles_by_event: p_page < 1 시 예외 발생'
);

-- p_size < 1 EXCEPTION
SELECT throws_ok(
  format($$ SELECT public.get_abusing_articles_by_event(%s, NULL, 1, 0) $$,
    (SELECT id FROM public.events WHERE title = '_test_event_abusing')),
  'size는 1 이상이어야 합니다',
  'get_abusing_articles_by_event: p_size < 1 시 예외 발생'
);

-- p_page NULL → default 1
SELECT is(
  ((public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), NULL, NULL))::jsonb ->> 'page')::int,
  1,
  'get_abusing_articles_by_event: p_page NULL 시 default 1 적용'
);

-- p_size NULL → default 4
SELECT is(
  ((public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), NULL, 1, NULL))::jsonb ->> 'size')::int,
  4,
  'get_abusing_articles_by_event: p_size NULL 시 default 4 적용'
);

-- p_size > 100 → 100으로 클램핑
SELECT is(
  ((public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing'), NULL, 1, 200))::jsonb ->> 'size')::int,
  100,
  'get_abusing_articles_by_event: p_size > 100 시 100으로 클램핑'
);

-- 기사 응답 필드 확인
SELECT ok(
  (public.get_abusing_articles_by_event((SELECT id FROM public.events WHERE title = '_test_event_abusing')))::jsonb -> 'articles' -> 0
    ?& ARRAY['link', 'title', 'summary', 'article_image_url', 'publisher', 'published_at'],
  'get_abusing_articles_by_event: 기사 응답에 필수 필드 포함'
);

SELECT * FROM finish();
ROLLBACK;
