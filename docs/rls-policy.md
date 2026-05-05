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

# RLS Policies

| Table | Policy | Roles | Operation |
|---|---|---|---|
| articles | Enable read access for all users | anon, authenticated | SELECT |
| topics | Enable read access for all users | anon, authenticated | SELECT |
| events | Enable read access for all users | anon, authenticated | SELECT |
| event_articles | Enable read access for all users | anon, authenticated | SELECT |
| abusing_articles | Enable read access for all users | anon, authenticated | SELECT |

---

## public.subscriptions

### 정책 목록

| 정책명 | 타입 | 명령 | 대상 역할 | 조건 |
|--------|------|------|-----------|------|
| 본인 id로만 구독 생성 | PERMISSIVE | INSERT | `authenticated` | `auth.uid() = user_id` |
| 본인 구독 정보만 조회 | PERMISSIVE | SELECT | `authenticated` | `auth.uid() = user_id` |
| 본인 구독만 삭제 | PERMISSIVE | DELETE | `authenticated` | `auth.uid() = user_id` |

### 역할별 접근

| 역할 | SELECT | INSERT | DELETE |
|------|--------|--------|--------|
| `anon` | ✕ (권한 없음) | ✕ | ✕ |
| `authenticated` | 본인 행만 | 본인 user_id로만 | 본인 행만 |
| `service_role` | RLS 우회 | RLS 우회 | RLS 우회 |

### 설계 의도

- 구독/구독 해제는 `subscribe_topic`, `unsubscribe_topic` RPC 함수를 통해서만 수행한다.
- `anon`은 테이블 권한 자체가 없으므로 RLS 평가 전에 차단된다.
- `get_topics`, `get_events`는 `anon`도 호출할 수 있지만 비로그인 시 `subscription_id = null`, `is_subscribed = false`를 반환한다.
- `get_subscribed_topics`는 `authenticated` 전용이며 `auth.uid()` 기준 본인 구독만 반환한다.

# RLS Policies

| Table | Policy | Roles | Operation |
|---|---|---|---|
| feeds | Enable read access for all users | anon, authenticated | SELECT |

# RLS Policy

## 기본 방침

`revoke_default_privileges` 마이그레이션으로 `anon` / `authenticated`의 `public` 스키마 기본 권한을 전부 취소하고, 테이블마다 명시적으로 필요한 권한만 부여한다.

---

## public.article_ai_results

### 정책 목록

| 정책명 | 타입 | 명령 | 대상 역할 | 조건 |
|--------|------|------|-----------|------|
| No access for users | PERMISSIVE | SELECT | `authenticated` | `false` |

---

### 역할별 접근

| 역할 | SELECT | INSERT | UPDATE | DELETE |
|------|--------|--------|--------|--------|
| `anon` | ✕ | ✕ | ✕ | ✕ |
| `authenticated` | ✕ (항상 false) | ✕ | ✕ | ✕ |
| `service_role` | RLS 우회 | RLS 우회 | RLS 우회 | RLS 우회 |

---

### 설계 의도

- `article_ai_results`는 AI 분석 결과를 저장하는 내부 테이블
- 일반 사용자 접근은 완전히 차단
- 모든 데이터 생성 및 갱신은 서버(`service_role`)에서 수행
- `summary`, `keywords` 등은 AI 처리 결과 저장
- `status`, `last_error`로 실패 및 재처리 흐름 관리