BEGIN;

SELECT plan(23);

SELECT has_table('public', 'notifications', 'notifications 테이블이 존재해야 한다');
SELECT has_column('public', 'notifications', 'user_id', 'notifications.user_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'notifications', 'topic_id', 'notifications.topic_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'notifications', 'event_id', 'notifications.event_id 컬럼이 존재해야 한다');
SELECT has_column('public', 'notifications', 'read_at', 'notifications.read_at 컬럼이 존재해야 한다');

SELECT is(
  pg_get_function_result('public.get_notifications(int, int)'::regprocedure),
  'json',
  'get_notifications는 json을 반환해야 한다'
);

SELECT is(
  pg_get_function_result('public.mark_all_notifications_as_read()'::regprocedure),
  'json',
  'mark_all_notifications_as_read는 json을 반환해야 한다'
);

WITH first_category AS (
  SELECT e.enumlabel::public.category AS category
  FROM pg_enum e
  JOIN pg_type t ON t.oid = e.enumtypid
  WHERE t.typname = 'category'
  ORDER BY e.enumsortorder
  LIMIT 1
)
INSERT INTO public.topics (category, title, summary)
SELECT category, '_test_notifications_subscribed_topic', '알림 테스트용 구독 토픽'
FROM first_category
UNION ALL
SELECT category, '_test_notifications_other_topic', '알림 테스트용 비구독 토픽'
FROM first_category;

SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email)
VALUES
  ('dddddddd-0000-0000-0000-000000000001', 'notification_test_subscriber@example.com'),
  ('dddddddd-0000-0000-0000-000000000002', 'notification_test_other@example.com');
SET LOCAL session_replication_role = DEFAULT;

INSERT INTO public.subscriptions (user_id, topic_id)
VALUES (
  'dddddddd-0000-0000-0000-000000000001',
  (SELECT id FROM public.topics WHERE title = '_test_notifications_subscribed_topic')
);

INSERT INTO public.events (topic_id, category, title, summary, article_count)
SELECT t.id, t.category, '_test_notifications_event_1', '첫 번째 알림 테스트 이벤트', 1
FROM public.topics t
WHERE t.title = '_test_notifications_subscribed_topic';

SELECT results_eq(
  $$ SELECT count(*)::int
     FROM public.notifications n
     WHERE n.user_id = 'dddddddd-0000-0000-0000-000000000001'
       AND n.event_id = (SELECT id FROM public.events WHERE title = '_test_notifications_event_1') $$,
  ARRAY[1],
  '구독한 토픽에 새 이벤트가 생성되면 구독자 알림이 1개 생성되어야 한다'
);

SELECT results_eq(
  $$ SELECT count(*)::int
     FROM public.notifications n
     WHERE n.user_id = 'dddddddd-0000-0000-0000-000000000002'
       AND n.event_id = (SELECT id FROM public.events WHERE title = '_test_notifications_event_1') $$,
  ARRAY[0],
  '구독하지 않은 사용자는 알림이 생성되지 않아야 한다'
);

SELECT set_config('request.jwt.claim.sub', 'dddddddd-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims',    '{"sub": "dddddddd-0000-0000-0000-000000000001"}', true);
SET LOCAL ROLE authenticated;

SELECT is(
  ((public.get_notifications(NULL, NULL))::jsonb ->> 'total_count')::int,
  1,
  'get_notifications는 본인 알림 총 개수를 반환해야 한다'
);

SELECT is(
  (public.get_notifications(NULL, NULL))::jsonb -> 'notifications' -> 0 ->> 'read_at',
  NULL,
  'get_notifications는 조회만 하고 read_at을 갱신하지 않아야 한다'
);

SELECT is(
  ((public.get_notifications(NULL, NULL))::jsonb -> 'notifications' -> 0 ->> 'is_read')::boolean,
  false,
  'get_notifications는 읽지 않은 알림의 is_read를 false로 반환해야 한다'
);

SELECT is(
  ((public.get_unread_notification_count())::jsonb ->> 'unread_count')::int,
  1,
  'get_unread_notification_count는 읽지 않은 알림 수를 반환해야 한다'
);

SELECT is(
  ((public.mark_notification_as_read((
    SELECT id FROM public.notifications
    WHERE event_id = (SELECT id FROM public.events WHERE title = '_test_notifications_event_1')
  )))::jsonb ->> 'notification_id')::bigint,
  (
    SELECT id FROM public.notifications
    WHERE event_id = (SELECT id FROM public.events WHERE title = '_test_notifications_event_1')
  ),
  'mark_notification_as_read는 읽음 처리한 알림 ID를 반환해야 한다'
);

SELECT ok(
  (
    SELECT read_at IS NOT NULL
    FROM public.notifications
    WHERE event_id = (SELECT id FROM public.events WHERE title = '_test_notifications_event_1')
  ),
  'mark_notification_as_read는 read_at을 설정해야 한다'
);

SELECT is(
  ((public.get_notifications(NULL, NULL))::jsonb -> 'notifications' -> 0 ->> 'is_read')::boolean,
  true,
  'get_notifications는 읽은 알림의 is_read를 true로 반환해야 한다'
);

SELECT is(
  ((public.get_unread_notification_count())::jsonb ->> 'unread_count')::int,
  0,
  '읽음 처리 후 읽지 않은 알림 수는 0이어야 한다'
);

RESET ROLE;

INSERT INTO public.events (topic_id, category, title, summary, article_count)
SELECT t.id, t.category, '_test_notifications_event_2', '두 번째 알림 테스트 이벤트', 1
FROM public.topics t
WHERE t.title = '_test_notifications_subscribed_topic';

SET LOCAL ROLE authenticated;

SELECT is(
  ((public.get_unread_notification_count())::jsonb ->> 'unread_count')::int,
  1,
  '새 알림이 추가되면 읽지 않은 알림 수가 증가해야 한다'
);

SELECT is(
  ((public.mark_all_notifications_as_read())::jsonb ->> 'updated_count')::int,
  1,
  'mark_all_notifications_as_read는 읽지 않은 알림만 읽음 처리해야 한다'
);

SELECT is(
  ((public.get_unread_notification_count())::jsonb ->> 'unread_count')::int,
  0,
  '전체 읽음 처리 후 읽지 않은 알림 수는 0이어야 한다'
);

RESET ROLE;

INSERT INTO public.events (topic_id, category, title, summary, article_count)
SELECT t.id, t.category, '_test_notifications_event_3', '세 번째 알림 테스트 이벤트', 1
FROM public.topics t
WHERE t.title = '_test_notifications_subscribed_topic';

SET LOCAL ROLE authenticated;

SELECT public.delete_notification((
  SELECT id FROM public.notifications
  WHERE event_id = (SELECT id FROM public.events WHERE title = '_test_notifications_event_3')
));

SELECT results_eq(
  $$ SELECT count(*)::int
     FROM public.notifications
     WHERE event_id = (SELECT id FROM public.events WHERE title = '_test_notifications_event_3') $$,
  ARRAY[0],
  'delete_notification은 본인 알림을 삭제해야 한다'
);

SELECT is(
  ((public.delete_all_notifications())::jsonb ->> 'deleted_count')::int,
  2,
  'delete_all_notifications는 남은 본인 알림을 모두 삭제해야 한다'
);

SELECT is(
  ((public.get_notifications(NULL, NULL))::jsonb ->> 'total_count')::int,
  0,
  '전체 삭제 후 본인 알림 수는 0이어야 한다'
);

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims',    '{}', true);

SELECT * FROM finish();

ROLLBACK;
