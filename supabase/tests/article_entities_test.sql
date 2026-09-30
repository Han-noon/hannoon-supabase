BEGIN;
SELECT plan(9);

SELECT has_table('public', 'article_entities', 'article_entities 테이블이 존재해야 한다');
SELECT col_is_pk('public', 'article_entities', ARRAY['article_id', 'entity'], '(article_id, entity)가 Primary Key여야 한다');
SELECT has_index('public', 'article_entities', 'article_entities_entity_idx', 'entity 인덱스가 존재해야 한다');

SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE relname = 'article_entities' AND relnamespace = 'public'::regnamespace),
  'article_entities 테이블에 RLS가 활성화되어 있어야 한다'
);

-- 권한: 서버(service_role)만 접근
SELECT ok(
  NOT has_table_privilege('anon', 'public.article_entities', 'SELECT'),
  'anon은 article_entities에 SELECT 권한이 없어야 한다'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.article_entities', 'SELECT'),
  'authenticated는 article_entities에 SELECT 권한이 없어야 한다'
);

SELECT ok(
  has_table_privilege('service_role', 'public.article_entities', 'SELECT, INSERT, UPDATE, DELETE'),
  'service_role은 article_entities에 SELECT/INSERT/UPDATE/DELETE 권한이 있어야 한다'
);

-- 동작: 같은 (article_id, entity)는 한 번만 저장된다
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.test/entities', 'entities-1', 'https://test.com/entities/1', '사회', '_entities_article_1', '요약', 'rss', '테스트언론', '2024-03-01 09:00:00', '중도', 'ready');

INSERT INTO public.article_entities (article_id, entity) VALUES
  ((SELECT id FROM public.articles WHERE guid = 'entities-1'), '국회');

SELECT throws_ok(
  $$ INSERT INTO public.article_entities (article_id, entity)
     VALUES ((SELECT id FROM public.articles WHERE guid = 'entities-1'), '국회') $$,
  '23505',
  NULL,
  '같은 (article_id, entity)를 다시 넣으면 PK 위반'
);

SELECT lives_ok(
  $$ INSERT INTO public.article_entities (article_id, entity)
     VALUES ((SELECT id FROM public.articles WHERE guid = 'entities-1'), '국회') ON CONFLICT DO NOTHING $$,
  'ON CONFLICT DO NOTHING으로 재추출 적재는 중복 없이 통과'
);

SELECT * FROM finish();
ROLLBACK;
