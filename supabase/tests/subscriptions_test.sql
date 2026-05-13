BEGIN;

SELECT plan(10);

-- 테이블 구조 확인
SELECT has_table('public', 'subscriptions', 'subscriptions 테이블이 존재해야 한다');
SELECT has_column('public', 'subscriptions', 'id', 'id 컬럼이 존재해야 한다');
SELECT has_column('public', 'subscriptions', 'user_id', 'user_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'subscriptions', 'topic_id', 'topic_id 컬럼이 존재해야 한다');

SELECT is(
  pg_get_function_result('public.subscribe_topic(bigint)'::regprocedure),
  'json',
  'subscribe_topic은 구독 정보를 json으로 반환해야 한다'
);

-- 테스트 데이터는 트랜잭션 종료 시 롤백된다.
INSERT INTO public.topics (category, title, summary)
VALUES ('정치', '_test_subscribe_return_id', 'subscribe_topic 반환값 테스트용 토픽');

SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES ('cccccccc-0000-0000-0000-000000000001', 'subscription_test@example.com');
SET LOCAL session_replication_role = DEFAULT;

SELECT set_config('request.jwt.claim.sub', 'cccccccc-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims',    '{"sub": "cccccccc-0000-0000-0000-000000000001"}', true);
SET LOCAL ROLE authenticated;

SELECT results_eq(
  $$ WITH response AS (
       SELECT public.subscribe_topic((SELECT id FROM public.topics WHERE title = '_test_subscribe_return_id'))::jsonb AS body
     )
     SELECT (body ->> 'is_subscribed')::boolean FROM response $$,
  ARRAY[true],
  'subscribe_topic은 is_subscribed=true를 반환해야 한다'
);

SELECT results_eq(
  $$ WITH response AS (
       SELECT public.subscribe_topic((SELECT id FROM public.topics WHERE title = '_test_subscribe_return_id'))::jsonb AS body
     )
     SELECT (body ->> 'subscription_id')::bigint = (
       SELECT id
       FROM public.subscriptions
       WHERE user_id = 'cccccccc-0000-0000-0000-000000000001'
         AND topic_id = (SELECT id FROM public.topics WHERE title = '_test_subscribe_return_id')
     )
     FROM response $$,
  ARRAY[true],
  'subscribe_topic은 subscription_id를 반환해야 한다'
);

SELECT results_eq(
  $$ WITH existing_subscription AS (
       SELECT id
       FROM public.subscriptions
       WHERE user_id = 'cccccccc-0000-0000-0000-000000000001'
         AND topic_id = (SELECT id FROM public.topics WHERE title = '_test_subscribe_return_id')
     ),
     response AS (
       SELECT public.subscribe_topic((SELECT id FROM public.topics WHERE title = '_test_subscribe_return_id'))::jsonb AS body
     )
     SELECT (body ->> 'subscription_id')::bigint = (SELECT id FROM existing_subscription)
       AND (body ->> 'is_subscribed')::boolean
     FROM response $$,
  ARRAY[true],
  'subscribe_topic은 이미 구독 중이어도 기존 구독 정보를 반환해야 한다'
);

SELECT results_eq(
  $$ SELECT count(*)::int
     FROM public.subscriptions
     WHERE user_id = 'cccccccc-0000-0000-0000-000000000001'
       AND topic_id = (SELECT id FROM public.topics WHERE title = '_test_subscribe_return_id') $$,
  ARRAY[1],
  'subscribe_topic 중복 호출은 구독 행을 추가로 만들지 않아야 한다'
);

SELECT throws_ok(
  $$ SELECT public.subscribe_topic(NULL) $$,
  '토픽 ID는 필수입니다',
  'subscribe_topic은 topic id가 null이면 예외를 발생시켜야 한다'
);

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims',    '{}', true);

SELECT * FROM finish();

ROLLBACK;
