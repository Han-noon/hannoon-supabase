BEGIN;

SELECT plan(24);

-- 테이블 존재 확인
SELECT has_table('public', 'profiles', 'profiles 테이블이 존재해야 한다');

-- 컬럼 존재 확인
SELECT has_column('public', 'profiles', 'id',                'id 컬럼이 존재해야 한다');
SELECT has_column('public', 'profiles', 'email',             'email 컬럼이 존재해야 한다');
SELECT has_column('public', 'profiles', 'name',              'name 컬럼이 존재해야 한다');
SELECT has_column('public', 'profiles', 'profile_image_url', 'profile_image_url 컬럼이 존재해야 한다');
SELECT has_column('public', 'profiles', 'created_at',        'created_at 컬럼이 존재해야 한다');

-- 컬럼 타입 확인
SELECT col_type_is('public', 'profiles', 'id',                'uuid',              'id는 uuid 타입이어야 한다');
SELECT col_type_is('public', 'profiles', 'email',             'character varying', 'email은 character varying 타입이어야 한다');
SELECT col_type_is('public', 'profiles', 'name',              'text',              'name은 text 타입이어야 한다');
SELECT col_type_is('public', 'profiles', 'profile_image_url', 'text',              'profile_image_url은 text 타입이어야 한다');
SELECT col_type_is('public', 'profiles', 'created_at',        'timestamp',         'created_at은 timestamp 타입이어야 한다');

-- NOT NULL 확인
SELECT col_not_null('public', 'profiles', 'id',         'id는 NOT NULL이어야 한다');
SELECT col_not_null('public', 'profiles', 'created_at', 'created_at은 NOT NULL이어야 한다');

-- Primary Key 확인
SELECT col_is_pk('public', 'profiles', 'id', 'id는 Primary Key여야 한다');

-- email 유니크 인덱스 확인
SELECT has_index('public', 'profiles', 'profiles_email_key', 'profiles_email_key 인덱스가 존재해야 한다');

-- RLS 활성화 확인
SELECT ok(
  (SELECT relrowsecurity FROM pg_class
   WHERE relname = 'profiles' AND relnamespace = 'public'::regnamespace),
  'profiles 테이블에 RLS가 활성화되어 있어야 한다'
);

-- handle_new_user 함수 존재 확인
SELECT has_function('public', 'handle_new_user', 'handle_new_user 함수가 존재해야 한다');

-- get_profile 함수 존재 확인
SELECT has_function('public', 'get_profile', 'get_profile 함수가 존재해야 한다');

-- on_auth_user_created 트리거 존재 확인
SELECT has_trigger('auth', 'users', 'on_auth_user_created', 'on_auth_user_created 트리거가 존재해야 한다');

-- RLS 정책 존재 확인
SELECT ok(
  EXISTS(
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'profiles'
      AND policyname = '본인 회원정보만 조회'
  ),
  '"본인 회원정보만 조회" RLS 정책이 존재해야 한다'
);

-- RLS 정책 cmd 확인 (SELECT만 허용)
SELECT is(
  (SELECT cmd FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = '본인 회원정보만 조회'),
  'SELECT',
  '"본인 회원정보만 조회" 정책은 SELECT 명령에만 적용되어야 한다'
);

-- RLS 정책 타입 확인 (PERMISSIVE)
SELECT is(
  (SELECT permissive FROM pg_policies
   WHERE schemaname = 'public' AND tablename = 'profiles' AND policyname = '본인 회원정보만 조회'),
  'PERMISSIVE',
  '"본인 회원정보만 조회" 정책은 PERMISSIVE여야 한다'
);

-- -------------------------------------------------------
-- 동작 테스트
-- -------------------------------------------------------

-- auth.users FK를 우회해 profiles에 직접 삽입 (ROLLBACK으로 정리됨)
SET LOCAL session_replication_role = replica;
INSERT INTO public.profiles (id, email) VALUES
  ('aaaaaaaa-0000-0000-0000-000000000001', 'rls_test_a@example.com'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'rls_test_b@example.com');
SET LOCAL session_replication_role = DEFAULT;

-- pgTAP 함수 실행 권한만 임시 부여 (테스트 인프라, ROLLBACK으로 취소됨)
-- public.get_profile() 실행 권한은 마이그레이션에서 검증되어야 하므로 public 전체에는 부여하지 않는다.
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA extensions TO authenticated;

-- anon은 profiles에 SELECT 권한이 없어야 한다
SELECT ok(
  NOT has_table_privilege('anon', 'public.profiles', 'SELECT'),
  'anon은 profiles에 SELECT 권한이 없어야 한다'
);

-- authenticated 유저 A: 본인 프로필만 조회되어야 한다
SELECT set_config('request.jwt.claim.sub', 'aaaaaaaa-0000-0000-0000-000000000001', true);
SELECT set_config('request.jwt.claims',    '{"sub": "aaaaaaaa-0000-0000-0000-000000000001"}', true);
SET LOCAL ROLE authenticated;
SELECT results_eq(
  'SELECT id FROM public.profiles',
  ARRAY['aaaaaaaa-0000-0000-0000-000000000001'::uuid],
  'authenticated 유저는 본인 프로필만 조회되어야 한다'
);

RESET ROLE;
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claims',    '{}', true);

-- -------------------------------------------------------
-- handle_new_user 트리거 동작 테스트
--
-- name / profile_image_url 채움 여부는 실제 Google OAuth 흐름으로 검증한다.
-- config.toml의 [auth.external.google]에 실제 Client ID/Secret을 설정하고,
-- Google Cloud Console의 리디렉션 URI에 http://127.0.0.1:54321/auth/v1/callback을
-- 등록한 뒤 로컬에서 OAuth 로그인하면 실제 메타데이터가 profiles에 삽입된다.
-- -------------------------------------------------------

SELECT * FROM finish();

ROLLBACK;
