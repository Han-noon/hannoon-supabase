BEGIN;
SELECT plan(5);

SELECT col_type_is('public', 'articles', 'embedding', 'extensions', 'vector(768)', 'articles.embedding은 vector(768)이어야 한다');
SELECT col_type_is('public', 'events', 'embedding', 'extensions', 'vector(768)', 'events.embedding은 vector(768)이어야 한다');
SELECT col_type_is('public', 'topic_causes', 'cause_embedding', 'extensions', 'vector(768)', 'topic_causes.cause_embedding은 vector(768)이어야 한다');
SELECT has_index('public', 'articles', 'articles_embedding_hnsw', 'articles.embedding hnsw 인덱스가 존재해야 한다');
SELECT col_type_is('public', 'articles', 'minor', 'jsonb', 'articles.minor는 jsonb여야 한다');

SELECT * FROM finish();
ROLLBACK;
