-- =============================================================
-- 기본 권한 취소 (Revoke Default Privileges)
-- anon, authenticated 역할에서 public 스키마 기본 권한을 제거합니다.
-- 모든 테이블 접근은 RLS 정책을 통해 명시적으로 허용합니다.
-- =============================================================

-- -------------------------------------------------------------
-- 1. 기존 객체에 대한 명시적 권한 취소 (Existing Objects)
--    ALTER DEFAULT PRIVILEGES 는 이후 생성 객체에만 적용되므로,
--    이미 존재하는 객체는 아래 구문으로 명시적으로 취소합니다.
--    객체가 없는 경우에도 오류 없이 실행됩니다.
-- -------------------------------------------------------------

REVOKE ALL ON ALL TABLES    IN SCHEMA "public" FROM "anon";
REVOKE ALL ON ALL TABLES    IN SCHEMA "public" FROM "authenticated";

-- PostgreSQL은 함수에 EXECUTE를 PUBLIC에 기본 부여합니다.
-- anon/authenticated는 PUBLIC 멤버이므로 PUBLIC도 함께 취소합니다.
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "public" FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "public" FROM "anon";
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA "public" FROM "authenticated";

REVOKE ALL ON ALL SEQUENCES IN SCHEMA "public" FROM "anon";
REVOKE ALL ON ALL SEQUENCES IN SCHEMA "public" FROM "authenticated";


-- -------------------------------------------------------------
-- 2. 이후 생성 객체에 대한 기본 권한 취소 (Future Objects)
-- -------------------------------------------------------------

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES    FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON TABLES    FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM PUBLIC;
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON FUNCTIONS FROM "authenticated";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" REVOKE ALL ON SEQUENCES FROM "authenticated";
