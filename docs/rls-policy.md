# RLS Policy

## 기본 방침

`revoke_default_privileges` 마이그레이션으로 `anon` / `authenticated`의 `public` 스키마 기본 권한을 전부 취소하고, 테이블마다 명시적으로 필요한 권한만 부여한다.

---

## public.profiles

### 정책 목록

| 정책명 | 타입 | 명령 | 대상 역할 | 조건 |
|--------|------|------|-----------|------|
| 본인 회원정보만 조회 | PERMISSIVE | SELECT | `authenticated` | `auth.uid() = id` |

### 역할별 접근

| 역할 | SELECT | INSERT | UPDATE | DELETE |
|------|--------|--------|--------|--------|
| `anon` | ✕ (권한 없음) | ✕ | ✕ | ✕ |
| `authenticated` | 본인 행만 | ✕ | ✕ | ✕ |
| `service_role` | RLS 우회 | RLS 우회 | RLS 우회 | RLS 우회 |

### 설계 의도

- 회원정보 쓰기(INSERT/UPDATE/DELETE)는 클라이언트가 직접 호출하지 않는다. 가입은 `handle_new_user` 트리거가, 수정·탈퇴는 별도 서버 함수(service_role 사용)가 담당한다.
- `anon`은 테이블 SELECT 권한 자체가 없으므로 RLS 평가 전에 차단된다.
