-- =============================================================
-- 세션 설정 (Session Configuration)
-- Supabase 마이그레이션 실행 환경을 안전하게 설정합니다.
-- =============================================================

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


-- =============================================================
-- 스키마 설정 (Schema Configuration)
-- =============================================================

COMMENT ON SCHEMA "public" IS 'standard public schema';


-- =============================================================
-- 확장 모듈 (Extensions)
-- =============================================================

-- 쿼리 성능 통계 수집
CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

-- 암호화 함수 (해시, 암호화 등)
CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

-- Supabase Vault: 민감한 데이터(시크릿) 안전 저장소
CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

-- UUID 생성 함수
CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";


-- =============================================================
-- Realtime 발행 설정 (Realtime Publication)
-- =============================================================

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";


-- =============================================================
-- 스키마 접근 권한 부여 (Schema Usage Grants)
-- 각 역할(role)에게 public 스키마 사용 권한을 부여합니다.
-- =============================================================

GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";


-- =============================================================
-- 기본 권한 설정 (Default Privileges)
-- postgres 역할이 public 스키마에 생성하는 객체에 대한
-- 기본 접근 권한을 모든 역할에게 부여합니다.
-- =============================================================

-- 시퀀스 기본 권한
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";

-- 함수 기본 권한
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";

-- 테이블 기본 권한
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";


-- =============================================================
-- 불필요한 확장 제거 (Cleanup Extensions)
-- pg_net은 이 프로젝트에서 사용하지 않으므로 제거합니다.
-- =============================================================

DROP EXTENSION IF EXISTS "pg_net";
