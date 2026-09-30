BEGIN;

SELECT plan(76);

-- ============================================================
-- 1. events.subtopic_processed_at
-- ============================================================

SELECT has_column(
  'public', 'events', 'subtopic_processed_at',
  'events.subtopic_processed_at 컬럼이 존재해야 한다'
);

SELECT col_type_is(
  'public', 'events', 'subtopic_processed_at', 'timestamp without time zone',
  'events.subtopic_processed_at은 timestamp without time zone 타입이어야 한다'
);


-- ============================================================
-- 2. event_profiles
-- ============================================================

SELECT has_table('public', 'event_profiles', 'event_profiles 테이블이 존재해야 한다');

SELECT has_column('public', 'event_profiles', 'id',             'event_profiles.id 컬럼이 존재해야 한다');
SELECT has_column('public', 'event_profiles', 'event_id',       'event_profiles.event_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'event_profiles', 'event_summary',  'event_profiles.event_summary 컬럼이 존재해야 한다');
SELECT has_column('public', 'event_profiles', 'anchors',        'event_profiles.anchors 컬럼이 존재해야 한다');
SELECT has_column('public', 'event_profiles', 'input_hash',     'event_profiles.input_hash 컬럼이 존재해야 한다');
SELECT has_column('public', 'event_profiles', 'prompt_version', 'event_profiles.prompt_version 컬럼이 존재해야 한다');
SELECT has_column('public', 'event_profiles', 'created_at',     'event_profiles.created_at 컬럼이 존재해야 한다');
SELECT has_column('public', 'event_profiles', 'updated_at',     'event_profiles.updated_at 컬럼이 존재해야 한다');

SELECT hasnt_column(
  'public', 'event_profiles', 'model',
  'event_profiles에는 model 컬럼이 없어야 한다'
);

SELECT col_type_is('public', 'event_profiles', 'event_id',      'bigint', 'event_profiles.event_id는 bigint 타입이어야 한다');
SELECT col_type_is('public', 'event_profiles', 'event_summary', 'text',   'event_profiles.event_summary는 text 타입이어야 한다');
SELECT col_type_is('public', 'event_profiles', 'anchors',       'jsonb',  'event_profiles.anchors는 jsonb 타입이어야 한다');

SELECT col_is_pk('public', 'event_profiles', 'id', 'event_profiles.id는 Primary Key여야 한다');
SELECT col_not_null('public', 'event_profiles', 'event_id',      'event_profiles.event_id는 NOT NULL이어야 한다');
SELECT col_not_null('public', 'event_profiles', 'event_summary', 'event_profiles.event_summary는 NOT NULL이어야 한다');
SELECT col_not_null('public', 'event_profiles', 'anchors',       'event_profiles.anchors는 NOT NULL이어야 한다');

SELECT has_index(
  'public', 'event_profiles', 'event_profiles_event_id_key',
  'event_profiles.event_id UNIQUE 인덱스가 존재해야 한다'
);

SELECT ok(
  (SELECT i.indisunique
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   JOIN pg_index i ON i.indrelid = c.oid
   JOIN pg_class idx ON idx.oid = i.indexrelid
   WHERE n.nspname = 'public'
     AND c.relname = 'event_profiles'
     AND idx.relname = 'event_profiles_event_id_key'),
  'event_profiles_event_id_key는 UNIQUE 인덱스여야 한다'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'event_profiles_event_id_fkey'
      AND conrelid = 'public.event_profiles'::regclass
      AND confrelid = 'public.events'::regclass
  ),
  'event_profiles.event_id -> events.id FK가 존재해야 한다'
);

SELECT is(
  (SELECT confdeltype::text
   FROM pg_constraint
   WHERE conname = 'event_profiles_event_id_fkey'
     AND conrelid = 'public.event_profiles'::regclass),
  'c',
  'event_profiles의 Event FK는 ON DELETE CASCADE여야 한다'
);

SELECT ok(
  (SELECT relrowsecurity
   FROM pg_class
   WHERE oid = 'public.event_profiles'::regclass),
  'event_profiles 테이블에 RLS가 활성화되어 있어야 한다'
);

SELECT ok(
  NOT has_table_privilege('anon', 'public.event_profiles', 'SELECT'),
  'anon은 event_profiles를 직접 SELECT할 수 없어야 한다'
);

SELECT ok(
  NOT has_table_privilege('authenticated', 'public.event_profiles', 'SELECT'),
  'authenticated는 event_profiles를 직접 SELECT할 수 없어야 한다'
);

SELECT has_trigger(
  'public', 'event_profiles', 'set_updated_at',
  'event_profiles에 updated_at 자동 갱신 트리거가 존재해야 한다'
);


-- ============================================================
-- 3. subtopics
-- ============================================================

SELECT has_table('public', 'subtopics', 'subtopics 테이블이 존재해야 한다');

SELECT has_column('public', 'subtopics', 'id',                   'subtopics.id 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'topic_id',             'subtopics.topic_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'name',                 'subtopics.name 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'common_basis',         'subtopics.common_basis 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'membership_criterion', 'subtopics.membership_criterion 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'summary',              'subtopics.summary 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'type',                 'subtopics.type 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'created_at',           'subtopics.created_at 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopics', 'updated_at',           'subtopics.updated_at 컬럼이 존재해야 한다');

SELECT col_type_is('public', 'subtopics', 'topic_id',             'bigint', 'subtopics.topic_id는 bigint 타입이어야 한다');
SELECT col_type_is('public', 'subtopics', 'common_basis',         'text',   'subtopics.common_basis는 text 타입이어야 한다');
SELECT col_type_is('public', 'subtopics', 'membership_criterion', 'text',   'subtopics.membership_criterion은 text 타입이어야 한다');
SELECT col_type_is('public', 'subtopics', 'type',                 'text',   'subtopics.type은 text 타입이어야 한다');

SELECT col_is_pk('public', 'subtopics', 'id', 'subtopics.id는 Primary Key여야 한다');
SELECT col_not_null('public', 'subtopics', 'topic_id', 'subtopics.topic_id는 NOT NULL이어야 한다');
SELECT col_not_null('public', 'subtopics', 'name',     'subtopics.name은 NOT NULL이어야 한다');
SELECT col_not_null('public', 'subtopics', 'type',     'subtopics.type은 NOT NULL이어야 한다');

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'subtopics_type_check'
      AND conrelid = 'public.subtopics'::regclass
      AND contype = 'c'
      AND pg_get_constraintdef(oid) LIKE '%FOCAL_POINT%'
      AND pg_get_constraintdef(oid) LIKE '%PROCESS%'
      AND pg_get_constraintdef(oid) LIKE '%RECURRING_ISSUE%'
  ),
  'subtopics.type은 허용된 3개 유형만 저장할 수 있어야 한다'
);

SELECT has_index(
  'public', 'subtopics', 'subtopics_topic_id_idx',
  'subtopics.topic_id 조회용 인덱스가 존재해야 한다'
);

SELECT is(
  (SELECT confdeltype::text
   FROM pg_constraint
   WHERE conname = 'subtopics_topic_id_fkey'
     AND conrelid = 'public.subtopics'::regclass),
  'c',
  'subtopics의 Topic FK는 ON DELETE CASCADE여야 한다'
);

SELECT ok(
  (SELECT relrowsecurity
   FROM pg_class
   WHERE oid = 'public.subtopics'::regclass),
  'subtopics 테이블에 RLS가 활성화되어 있어야 한다'
);

SELECT ok(
  has_table_privilege('anon', 'public.subtopics', 'SELECT'),
  'anon은 subtopics를 SELECT할 수 있어야 한다'
);

SELECT ok(
  has_table_privilege('authenticated', 'public.subtopics', 'SELECT'),
  'authenticated는 subtopics를 SELECT할 수 있어야 한다'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'subtopics'
      AND policyname = 'Enable read access for all users'
      AND cmd = 'SELECT'
  ),
  'subtopics에 anon/authenticated SELECT 정책이 존재해야 한다'
);

SELECT has_trigger(
  'public', 'subtopics', 'set_updated_at',
  'subtopics에 updated_at 자동 갱신 트리거가 존재해야 한다'
);


-- ============================================================
-- 4. subtopic_events
-- ============================================================

SELECT has_table('public', 'subtopic_events', 'subtopic_events 테이블이 존재해야 한다');

SELECT has_column('public', 'subtopic_events', 'id',          'subtopic_events.id 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopic_events', 'subtopic_id', 'subtopic_events.subtopic_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopic_events', 'event_id',    'subtopic_events.event_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'subtopic_events', 'created_at',  'subtopic_events.created_at 컬럼이 존재해야 한다');

SELECT col_is_pk('public', 'subtopic_events', 'id', 'subtopic_events.id는 Primary Key여야 한다');
SELECT col_not_null('public', 'subtopic_events', 'subtopic_id', 'subtopic_events.subtopic_id는 NOT NULL이어야 한다');
SELECT col_not_null('public', 'subtopic_events', 'event_id',    'subtopic_events.event_id는 NOT NULL이어야 한다');

SELECT has_index(
  'public', 'subtopic_events', 'subtopic_events_subtopic_id_event_id_key',
  'subtopic_events의 (subtopic_id, event_id) UNIQUE 인덱스가 존재해야 한다'
);

SELECT ok(
  (SELECT i.indisunique
   FROM pg_class c
   JOIN pg_namespace n ON n.oid = c.relnamespace
   JOIN pg_index i ON i.indrelid = c.oid
   JOIN pg_class idx ON idx.oid = i.indexrelid
   WHERE n.nspname = 'public'
     AND c.relname = 'subtopic_events'
     AND idx.relname = 'subtopic_events_subtopic_id_event_id_key'),
  'subtopic_events_subtopic_id_event_id_key는 UNIQUE 인덱스여야 한다'
);

SELECT has_index(
  'public', 'subtopic_events', 'subtopic_events_event_id_idx',
  'subtopic_events.event_id 조회용 인덱스가 존재해야 한다'
);

SELECT is(
  (SELECT confdeltype::text
   FROM pg_constraint
   WHERE conname = 'subtopic_events_subtopic_id_fkey'
     AND conrelid = 'public.subtopic_events'::regclass),
  'c',
  'subtopic_events의 Subtopic FK는 ON DELETE CASCADE여야 한다'
);

SELECT is(
  (SELECT confdeltype::text
   FROM pg_constraint
   WHERE conname = 'subtopic_events_event_id_fkey'
     AND conrelid = 'public.subtopic_events'::regclass),
  'c',
  'subtopic_events의 Event FK는 ON DELETE CASCADE여야 한다'
);

SELECT ok(
  (SELECT relrowsecurity
   FROM pg_class
   WHERE oid = 'public.subtopic_events'::regclass),
  'subtopic_events 테이블에 RLS가 활성화되어 있어야 한다'
);

SELECT ok(
  has_table_privilege('anon', 'public.subtopic_events', 'SELECT'),
  'anon은 subtopic_events를 SELECT할 수 있어야 한다'
);

SELECT ok(
  has_table_privilege('authenticated', 'public.subtopic_events', 'SELECT'),
  'authenticated는 subtopic_events를 SELECT할 수 있어야 한다'
);

SELECT ok(
  EXISTS (
    SELECT 1
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'subtopic_events'
      AND policyname = 'Enable read access for all users'
      AND cmd = 'SELECT'
  ),
  'subtopic_events에 anon/authenticated SELECT 정책이 존재해야 한다'
);

SELECT has_trigger(
  'public', 'subtopic_events', 'enforce_subtopic_event_same_topic',
  'subtopic_events에 동일 Topic 연결 검증 트리거가 존재해야 한다'
);

-- 동일 Topic / 다른 Topic 연결 동작 검증용 fixture
INSERT INTO public.topics (category, title, summary)
VALUES
  ((enum_range(NULL::public.category))[1], '__pgtap_subtopic_topic_a__', 'test'),
  ((enum_range(NULL::public.category))[1], '__pgtap_subtopic_topic_b__', 'test');

-- 허용되지 않은 Subtopic type은 저장할 수 없어야 한다.
SELECT throws_ok(
  format(
    'INSERT INTO public.subtopics (topic_id, name, type)
     VALUES (%s, %L, %L)',
    (SELECT id FROM public.topics WHERE title = '__pgtap_subtopic_topic_a__'),
    '__pgtap_invalid_type__',
    'FOCAL-POINT'
  ),
  '23514',
  NULL,
  '허용되지 않은 Subtopic type은 저장할 수 없어야 한다'
);

INSERT INTO public.events (topic_id, category, title, summary)
SELECT id, category, '__pgtap_subtopic_event_a__', 'test'
FROM public.topics
WHERE title = '__pgtap_subtopic_topic_a__';

INSERT INTO public.events (topic_id, category, title, summary)
SELECT id, category, '__pgtap_subtopic_event_b__', 'test'
FROM public.topics
WHERE title = '__pgtap_subtopic_topic_b__';

INSERT INTO public.subtopics (topic_id, name, type)
SELECT id, '__pgtap_subtopic_a__', 'FOCAL_POINT'
FROM public.topics
WHERE title = '__pgtap_subtopic_topic_a__';

SELECT lives_ok(
  format(
    'INSERT INTO public.subtopic_events (subtopic_id, event_id) VALUES (%s, %s)',
    (SELECT id FROM public.subtopics WHERE name = '__pgtap_subtopic_a__'),
    (SELECT id FROM public.events WHERE title = '__pgtap_subtopic_event_a__')
  ),
  '같은 Topic의 Subtopic과 Event는 연결할 수 있어야 한다'
);

SELECT throws_ok(
  format(
    'INSERT INTO public.subtopic_events (subtopic_id, event_id) VALUES (%s, %s)',
    (SELECT id FROM public.subtopics WHERE name = '__pgtap_subtopic_a__'),
    (SELECT id FROM public.events WHERE title = '__pgtap_subtopic_event_b__')
  ),
  '23514',
  'subtopic_events topic mismatch: subtopic and event must belong to the same topic',
  '다른 Topic의 Event를 Subtopic에 연결할 수 없어야 한다'
);

SELECT throws_ok(
  format(
    'UPDATE public.subtopic_events SET event_id = %s WHERE subtopic_id = %s AND event_id = %s',
    (SELECT id FROM public.events WHERE title = '__pgtap_subtopic_event_b__'),
    (SELECT id FROM public.subtopics WHERE name = '__pgtap_subtopic_a__'),
    (SELECT id FROM public.events WHERE title = '__pgtap_subtopic_event_a__')
  ),
  '23514',
  'subtopic_events topic mismatch: subtopic and event must belong to the same topic',
  '기존 연결을 다른 Topic의 Event로 변경할 수 없어야 한다'
);

SELECT ok(
  NOT EXISTS (
    SELECT 1
    FROM public.subtopic_events se
    JOIN public.subtopics s ON s.id = se.subtopic_id
    JOIN public.events e ON e.id = se.event_id
    WHERE s.topic_id IS DISTINCT FROM e.topic_id
  ),
  'subtopic_events에는 서로 다른 Topic 간 연결이 존재하지 않아야 한다'
);


SELECT * FROM finish();

ROLLBACK;
