BEGIN;
SELECT plan(34);

-- 전제: db reset 상태(seed 기사는 2024년). as_of와 순위가 articles 테이블 전체를 보므로,
-- 로컬 DB에 now() - 1h 이후 기사나 최근 49시간 내 기사가 많은 실제 토픽이 있으면 실패할 수 있다.
--
-- 테스트 데이터 삽입 (트랜잭션 종료 시 롤백)
-- 시각은 모두 now() 기준 상대값. 가장 최신 기사가 now() - 1h 이므로
-- 기준 시각(as_of) = now() - 1h 가 되어야 한다(데이터 최신 시각 앵커).
INSERT INTO public.topics (category, title, summary) VALUES
  ('사회', '_home_topic_a', '핫 토픽 1위 예상'),
  ('경제', '_home_topic_b', '핫 토픽 2위 예상'),
  ('국제', '_home_topic_c', '24시간 창 밖 기사만 있는 토픽');

-- id 순서와 날짜 순서를 일부러 반대로 넣는다(ev_a2가 id는 가장 작고 날짜는 가장 최신).
-- created_at도 트랜잭션 안에서 전부 같으므로, 정렬은 기사 published_at으로만 가능하다.
INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_home_topic_a'), '사회', '_home_ev_a2',    '요약'),
  ((SELECT id FROM public.topics WHERE title = '_home_topic_a'), '사회', '_home_ev_a1',    '요약'),
  ((SELECT id FROM public.topics WHERE title = '_home_topic_a'), '사회', '_home_ev_a0',    '요약'),
  ((SELECT id FROM public.topics WHERE title = '_home_topic_a'), '사회', '_home_ev_a_old', '요약'),
  ((SELECT id FROM public.topics WHERE title = '_home_topic_a'), '사회', '_home_ev_a_empty', '기사 없는 이벤트'),
  ((SELECT id FROM public.topics WHERE title = '_home_topic_b'), '경제', '_home_ev_b1',    '요약'),
  ((SELECT id FROM public.topics WHERE title = '_home_topic_c'), '국제', '_home_ev_c1',    '요약'),
  (NULL,                                                         '사회', '_home_ev_null',  '토픽 미배정 이벤트');

-- (이벤트, 기사 수, published_at)
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
SELECT
  'https://feeds.test/home',
  'home-' || s.event_title || '-' || s.published_at || '-' || g,
  'https://test.com/home/' || s.event_title || '/' || s.published_at || '/' || g,
  '사회',
  '_home_article',
  s.event_title,              -- summary에 소속 이벤트를 적어 두고 아래 연결에 사용
  'rss',
  '테스트언론',
  s.published_at,
  '중도',
  'ready'
FROM (VALUES
  ('_home_ev_a2',    1, now()::timestamp - interval '1 hour'),   -- 기준 시각과 같은 시각 (창 경계 포함)
  ('_home_ev_a1',    3, now()::timestamp - interval '4 hours'),
  ('_home_ev_a0',    1, now()::timestamp - interval '49 hours'), -- 기준 시각 - 48h (48h 창 경계 미포함)
  ('_home_ev_a_old', 1, now()::timestamp - interval '73 hours'),
  ('_home_ev_b1',    2, now()::timestamp - interval '6 hours'),
  ('_home_ev_b1',    1, now()::timestamp - interval '30 hours'), -- b1은 MIN(-30h) ≠ MAX(-6h)
  ('_home_ev_c1',    5, now()::timestamp - interval '31 hours'),
  ('_home_ev_null',  6, now()::timestamp - interval '2 hours')
) AS s(event_title, n, published_at)
CROSS JOIN LATERAL generate_series(1, s.n) AS g;

INSERT INTO public.event_articles (event_id, article_id)
SELECT e.id, a.id
FROM public.articles a
JOIN public.events e ON e.title = a.summary
WHERE a.feed_url = 'https://feeds.test/home';


-- ── get_hot_topics ─────────────────────────────────────────────

SELECT ok(
  (public.get_hot_topics())::jsonb ?& ARRAY['as_of', 'window_hours', 'topics'],
  'get_hot_topics: 응답에 필수 필드 포함'
);

SELECT is(
  ((public.get_hot_topics())::jsonb ->> 'as_of')::timestamp,
  now()::timestamp - interval '1 hour',
  'get_hot_topics: 기준 시각은 now()가 아니라 가장 최신 기사 시각'
);

SELECT is(
  ((public.get_hot_topics())::jsonb ->> 'window_hours')::int,
  1,
  'get_hot_topics: p_window_hours NULL 시 디폴트 1 적용'
);

SELECT is(
  ((public.get_hot_topics())::jsonb -> 'topics' -> 0 ->> 'article_count')::int,
  1,
  'get_hot_topics: 디폴트 1시간 창에는 기준 시각의 기사만 포함'
);

SELECT is(
  ((public.get_hot_topics(100000))::jsonb ->> 'window_hours')::int,
  720,
  'get_hot_topics: p_window_hours 720 초과 시 클램핑'
);

SELECT ok(
  (public.get_hot_topics(24))::jsonb -> 'topics' -> 0 ?& ARRAY['rank', 'topic_id', 'title', 'category', 'article_count'],
  'get_hot_topics: 토픽 항목에 필수 필드 포함'
);

SELECT is(
  ((public.get_hot_topics(24))::jsonb -> 'topics' -> 0 ->> 'topic_id')::bigint,
  (SELECT id FROM public.topics WHERE title = '_home_topic_a'),
  'get_hot_topics: 창 안 기사 수가 가장 많은 토픽이 1위'
);

SELECT is(
  ((public.get_hot_topics(24))::jsonb -> 'topics' -> 0 ->> 'rank')::int,
  1,
  'get_hot_topics: 1위 rank = 1'
);

SELECT is(
  ((public.get_hot_topics(24))::jsonb -> 'topics' -> 0 ->> 'article_count')::int,
  4,
  'get_hot_topics: 기준 시각과 같은 시각의 기사는 포함, 창 밖 기사는 제외해 집계'
);

SELECT is(
  ((public.get_hot_topics(24))::jsonb -> 'topics' -> 1 ->> 'topic_id')::bigint,
  (SELECT id FROM public.topics WHERE title = '_home_topic_b'),
  'get_hot_topics: 2위 토픽'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM jsonb_array_elements((public.get_hot_topics(24, 100))::jsonb -> 'topics') x
    WHERE (x ->> 'topic_id')::bigint = (SELECT id FROM public.topics WHERE title = '_home_topic_c')
  ),
  'get_hot_topics: 창 밖 기사만 있는 토픽은 제외'
);

SELECT is(
  ((public.get_hot_topics(48))::jsonb -> 'topics' -> 0 ->> 'topic_id')::bigint,
  (SELECT id FROM public.topics WHERE title = '_home_topic_c'),
  'get_hot_topics: p_window_hours를 넓히면 창에 들어온 토픽이 순위에 반영'
);

SELECT is(
  ((public.get_hot_topics(48))::jsonb -> 'topics' -> 1 ->> 'article_count')::int,
  4,
  'get_hot_topics: 창 시작 시각과 같은 시각의 기사는 제외'
);

SELECT is(
  jsonb_array_length((public.get_hot_topics(24, 1))::jsonb -> 'topics'),
  1,
  'get_hot_topics: p_size만큼만 반환'
);

SELECT throws_ok(
  $$ SELECT public.get_hot_topics(0) $$,
  'window_hours는 1 이상이어야 합니다',
  'get_hot_topics: p_window_hours < 1 시 예외 발생'
);

SELECT throws_ok(
  $$ SELECT public.get_hot_topics(24, 0) $$,
  'size는 1 이상이어야 합니다',
  'get_hot_topics: p_size < 1 시 예외 발생'
);


-- ── get_live_topic_timeline ────────────────────────────────────

SELECT is(
  (public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'topic' ->> 'title',
  '_home_topic_a',
  'get_live_topic_timeline: 지정한 토픽 반환'
);

SELECT is(
  ARRAY(
    SELECT x ->> 'title'
    FROM jsonb_array_elements(
      (public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'events'
    ) WITH ORDINALITY AS t(x, ord)
    ORDER BY ord
  ),
  ARRAY['_home_ev_a0', '_home_ev_a1', '_home_ev_a2'],
  'get_live_topic_timeline: 기사 날짜 기준 최근 3개를 오래된 순으로 반환 (id·created_at 무관)'
);

SELECT is(
  ((public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'events' -> 0 ->> 'occurred_at')::timestamp,
  now()::timestamp - interval '49 hours',
  'get_live_topic_timeline: occurred_at = 기사 published_at'
);

SELECT is(
  ((public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_b')))::jsonb -> 'events' -> 0 ->> 'occurred_at')::timestamp,
  now()::timestamp - interval '30 hours',
  'get_live_topic_timeline: 기사 시각이 여러 개면 occurred_at = MIN(published_at)'
);

SELECT is(
  ((public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'events' -> 1 ->> 'article_count')::int,
  3,
  'get_live_topic_timeline: 이벤트별 기사 수'
);

SELECT is(
  ARRAY(
    SELECT (x ->> 'is_latest')::boolean
    FROM jsonb_array_elements(
      (public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'events'
    ) WITH ORDINALITY AS t(x, ord)
    ORDER BY ord
  ),
  ARRAY[false, false, true],
  'get_live_topic_timeline: 마지막 이벤트만 is_latest = true'
);

SELECT is(
  ((public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'events' -> 2 ->> 'is_active')::boolean,
  true,
  'get_live_topic_timeline: 최신 이벤트에 창 안 기사가 있으면 is_active = true'
);

SELECT is(
  ((public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_b'), 3, 24))::jsonb -> 'events' -> 0 ->> 'is_active')::boolean,
  true,
  'get_live_topic_timeline: is_active는 최신 이벤트의 가장 늦은 기사(MAX) 기준'
);

SELECT is(
  ((public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_b'), 3, 3))::jsonb -> 'events' -> 0 ->> 'is_active')::boolean,
  false,
  'get_live_topic_timeline: 최신 이벤트의 기사가 p_active_hours보다 오래됐으면 is_active = false'
);

SELECT is(
  ((public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_b'), 3, 5))::jsonb -> 'events' -> 0 ->> 'is_active')::boolean,
  false,
  'get_live_topic_timeline: 가장 늦은 기사가 활성 창 시작 시각과 같으면 is_active = false (경계 미포함)'
);

SELECT is(
  jsonb_array_length(
    (public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a'), 10))::jsonb -> 'events'
  ),
  4,
  'get_live_topic_timeline: 기사가 없는 이벤트는 제외'
);

SELECT is(
  (public.get_live_topic_timeline(999999))::jsonb - 'as_of',
  '{"topic": null, "events": []}'::jsonb,
  'get_live_topic_timeline: 존재하지 않는 토픽은 예외 대신 topic = null, events = []'
);

SELECT throws_ok(
  $$ SELECT public.get_live_topic_timeline(1, 0) $$,
  'size는 1 이상이어야 합니다',
  'get_live_topic_timeline: p_size < 1 시 예외 발생'
);

SELECT throws_ok(
  $$ SELECT public.get_live_topic_timeline(1, 3, 0) $$,
  'active_hours는 1 이상이어야 합니다',
  'get_live_topic_timeline: p_active_hours < 1 시 예외 발생'
);


-- ── 비로그인(anon) 호출: RLS 하에서도 같은 결과 ─────────────────

SET LOCAL ROLE anon;

SELECT is(
  ((public.get_hot_topics(24))::jsonb -> 'topics' -> 0 ->> 'topic_id')::bigint,
  (SELECT id FROM public.topics WHERE title = '_home_topic_a'),
  'anon: get_hot_topics 1위 동일'
);

SELECT is(
  jsonb_array_length(
    (public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'events'
  ),
  3,
  'anon: get_live_topic_timeline 이벤트 조회'
);

RESET ROLE;


-- ── 미래 시각 기사: 기준 시각은 now()를 넘지 않는다 (as_of가 바뀌므로 마지막에 둔다) ──

INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status)
VALUES ('https://feeds.test/home', 'home-future', 'https://test.com/home/future', '사회', '_home_article_future', '미래', 'rss', '테스트언론',
        now()::timestamp + interval '1 day', '중도', 'ready');

SELECT is(
  ((public.get_hot_topics())::jsonb ->> 'as_of')::timestamp,
  now()::timestamp,
  'get_hot_topics: 미래 시각 기사가 있어도 기준 시각은 now()'
);

-- 미래 시각 기사만 붙은 이벤트: 제외하지 않으면 occurred_at이 가장 늦어 최신 이벤트로 올라온다
INSERT INTO public.events (topic_id, category, title, summary) VALUES
  ((SELECT id FROM public.topics WHERE title = '_home_topic_a'), '사회', '_home_ev_a_future', '미래 시각 기사만 있는 이벤트');

INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '_home_ev_a_future'), (SELECT id FROM public.articles WHERE guid = 'home-future'));

SELECT is(
  (public.get_live_topic_timeline((SELECT id FROM public.topics WHERE title = '_home_topic_a')))::jsonb -> 'events' -> 2 ->> 'title',
  '_home_ev_a2',
  'get_live_topic_timeline: 기준 시각 이후(미래 시각) 기사는 제외해 최신 이벤트로 올라오지 않음'
);

SELECT * FROM finish();
ROLLBACK;
