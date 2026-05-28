BEGIN;

SELECT plan(14);

-- -------------------------------------------------------
-- 구조 / 권한 검증
-- -------------------------------------------------------

SELECT has_function('public', 'delete_user', 'delete_user 함수가 존재해야 한다');

SELECT is(
  (SELECT prosecdef FROM pg_proc
   WHERE proname = 'delete_user' AND pronamespace = 'public'::regnamespace),
  true,
  'delete_user는 SECURITY DEFINER여야 한다'
);

SELECT ok(
  NOT has_function_privilege('anon', 'public.delete_user()', 'EXECUTE'),
  'anon은 delete_user 실행 권한이 없어야 한다'
);

SELECT ok(
  has_function_privilege('authenticated', 'public.delete_user()', 'EXECUTE'),
  'authenticated는 delete_user 실행 권한이 있어야 한다'
);

-- FK가 ON DELETE CASCADE로 설정되어 있어야 한다 (confdeltype = 'c')
SELECT is(
  (SELECT confdeltype::text FROM pg_constraint
   WHERE conname = 'subscriptions_user_id_fkey'
     AND conrelid = 'public.subscriptions'::regclass),
  'c',
  'subscriptions_user_id_fkey는 ON DELETE CASCADE여야 한다'
);

SELECT is(
  (SELECT confdeltype::text FROM pg_constraint
   WHERE conname = 'notifications_user_id_fkey'
     AND conrelid = 'public.notifications'::regclass),
  'c',
  'notifications_user_id_fkey는 ON DELETE CASCADE여야 한다'
);

-- -------------------------------------------------------
-- FK CASCADE 동작 테스트 (profiles 삭제 → subscriptions/notifications 연쇄 삭제)
-- -------------------------------------------------------

WITH first_category AS (
  SELECT e.enumlabel::public.category AS category
  FROM pg_enum e
  JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname = 'category'
  ORDER BY e.enumsortorder
  LIMIT 1
)
INSERT INTO public.topics (category, title, summary)
SELECT category, '_test_delete_user_topic', '탈퇴 CASCADE 테스트용 토픽'
FROM first_category;

-- auth.users FK를 우회해 profiles에 직접 삽입 (ROLLBACK으로 정리됨)
SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES ('ffffffff-0000-0000-0000-000000000001', 'delete_user_cascade@example.com');
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.subscriptions (user_id, topic_id)
VALUES (
  'ffffffff-0000-0000-0000-000000000001',
  (SELECT id FROM public.topics WHERE title = '_test_delete_user_topic')
);

-- 구독 토픽에 이벤트가 생성되면 트리거가 알림을 생성한다
INSERT INTO public.events (topic_id, category, title, summary, article_count)
SELECT t.id, t.category, '_test_delete_user_event', '탈퇴 CASCADE 테스트용 이벤트', 1
FROM public.topics t
WHERE t.title = '_test_delete_user_topic';

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.subscriptions
     WHERE user_id = 'ffffffff-0000-0000-0000-000000000001' $$,
  ARRAY[1],
  '삭제 전 구독이 1개 있어야 한다'
);

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.notifications
     WHERE user_id = 'ffffffff-0000-0000-0000-000000000001' $$,
  ARRAY[1],
  '삭제 전 알림이 1개 있어야 한다'
);

DELETE FROM public.profiles WHERE id = 'ffffffff-0000-0000-0000-000000000001';

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.subscriptions
     WHERE user_id = 'ffffffff-0000-0000-0000-000000000001' $$,
  ARRAY[0],
  'profiles 삭제 시 subscriptions가 CASCADE로 삭제되어야 한다'
);

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.notifications
     WHERE user_id = 'ffffffff-0000-0000-0000-000000000001' $$,
  ARRAY[0],
  'profiles 삭제 시 notifications가 CASCADE로 삭제되어야 한다'
);

-- -------------------------------------------------------
-- delete_user happy path (auth.users 삭제 → profiles CASCADE)
-- -------------------------------------------------------

INSERT INTO auth.users (instance_id, id, aud, role, email)
VALUES (
  '00000000-0000-0000-0000-000000000000',
  'eeeeeeee-0000-0000-0000-000000000001',
  'authenticated',
  'authenticated',
  'delete_user_test@example.com'
);

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.profiles
     WHERE id = 'eeeeeeee-0000-0000-0000-000000000001' $$,
  ARRAY[1],
  'auth.users 삽입 시 트리거로 profiles가 생성되어야 한다'
);

SELECT set_config('request.jwt.claim.sub', 'eeeeeeee-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims',    '{"sub": "eeeeeeee-0000-0000-0000-000000000001"}', true);
SET LOCAL ROLE authenticated;

SELECT public.delete_user();

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims',    '{}', true);

SELECT results_eq(
  $$ SELECT count(*)::int FROM auth.users
     WHERE id = 'eeeeeeee-0000-0000-0000-000000000001' $$,
  ARRAY[0],
  'delete_user 호출 후 auth.users에서 삭제되어야 한다'
);

SELECT results_eq(
  $$ SELECT count(*)::int FROM public.profiles
     WHERE id = 'eeeeeeee-0000-0000-0000-000000000001' $$,
  ARRAY[0],
  'delete_user 호출 후 profiles가 CASCADE로 삭제되어야 한다'
);

-- -------------------------------------------------------
-- 로그인하지 않은 경우 예외
-- -------------------------------------------------------

SET LOCAL ROLE authenticated;
SELECT throws_ok(
  $$ SELECT public.delete_user() $$,
  '로그인이 필요합니다.',
  'delete_user는 로그인하지 않은 경우 예외를 발생시켜야 한다'
);
RESET ROLE;

SELECT * FROM finish();

ROLLBACK;
