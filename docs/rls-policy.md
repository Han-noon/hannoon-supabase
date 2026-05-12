# RLS Policy

## 기본 방침

`revoke_default_privileges` 마이그레이션으로 `anon` / `authenticated`의 `public` 스키마 기본 권한을 전부 취소하고, 테이블마다 명시적으로 필요한 권한만 부여한다.

---

## public.profiles

### 정책 목록

| 정책명 | 타입 | 명령 | 대상 역할 | 조건 |
|--------|------|------|-----------|------|
| 본인 회원정보만 조회 | PERMISSIVE | SELECT | `authenticated` | `auth.uid() = id` |
| 본인 회원정보만 수정 | PERMISSIVE | UPDATE | `authenticated` | `auth.uid() = id` |

### 역할별 접근

| 역할 | SELECT | INSERT | UPDATE | DELETE |
|------|--------|--------|--------|--------|
| `anon` | ✕ (권한 없음) | ✕ | ✕ | ✕ |
| `authenticated` | 본인 행만 | ✕ | 본인 행만 | ✕ |
| `service_role` | RLS 우회 | RLS 우회 | RLS 우회 | RLS 우회 |

### 설계 의도

- INSERT/DELETE는 클라이언트가 직접 호출하지 않는다. 가입은 `handle_new_user` 트리거가, 탈퇴는 별도 서버 함수(service_role 사용)가 담당한다.
- 현재 로그인 방식은 Google OAuth만 사용하며, 가입 시 `handle_new_user` 트리거가 `full_name`과 `{uid}/profile` 경로를 저장한다.
- UPDATE는 `authenticated`가 직접 수행한다.
- `anon`은 `profiles` 테이블에 SELECT 권한 자체가 없으므로 RLS 평가 전에 차단된다. 즉, 비로그인 사용자는 `public.profiles`를 직접 조회할 수 없다.

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
# RLS Policy

## 기본 방침

`revoke_default_privileges` 마이그레이션으로 `anon` / `authenticated`의 `public` 스키마 기본 권한을 전부 취소하고, 테이블마다 명시적으로 필요한 권한만 부여한다.

---

## public.article_jobs

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

- `article_jobs`는 AI 처리 및 크롤링 작업을 위한 내부 큐 테이블
- 일반 사용자 접근은 완전히 차단
- 모든 작업은 서버(`service_role`)에서만 수행
- 실패(`failed`) 상태와 `attempts`, `last_error`를 통해 재시도 로직 구성
---

## storage.objects (user_profile_images)

### 정책 목록

| 정책명 | 타입 | 명령 | 대상 역할 | 조건 |
|--------|------|------|-----------|------|
| user_profile_images_select | PERMISSIVE | SELECT | `authenticated` | 본인 uid 폴더 |
| user_profile_images_insert | PERMISSIVE | INSERT | `authenticated` | 본인 uid 폴더 |
| user_profile_images_update | PERMISSIVE | UPDATE | `authenticated` | 본인 uid 폴더 |
| user_profile_images_delete | PERMISSIVE | DELETE | `authenticated` | 본인 uid 폴더 |

### 역할별 접근

| 역할 | SELECT | INSERT | UPDATE | DELETE |
|------|--------|--------|--------|--------|
| `anon` | ○ (버킷 public, RLS 우회) | ✕ | ✕ | ✕ |
| `authenticated` | ○ (버킷 public, RLS 우회) | 본인 폴더만 | 본인 폴더만 | 본인 폴더만 |
| `service_role` | RLS 우회 | RLS 우회 | RLS 우회 | RLS 우회 |

### 설계 의도

- 버킷이 `public = true`이므로 공개 URL(`/storage/v1/object/public/user_profile_images/...`)로 누구나 읽을 수 있다. SELECT RLS는 실질적으로 적용되지 않는다.
- RLS는 업로드·수정·삭제만 제한한다. 파일 경로는 `{uid}/파일명` 형식이어야 하며, `storage.foldername(name)[1]`로 uid를 추출해 `auth.uid()`와 비교.
- 프로필 이미지는 완성된 public URL이 아니라 `profile_image_path` (`{uid}/profile`)로 `profiles`에 저장한다.
- public URL 조립은 클라이언트가 `profile_image_path`를 사용해 처리한다.
- `event_images` 버킷은 RLS 정책 없음 — service_role(서버)만 업로드하고 public 읽기는 버킷 자체 공개 설정으로 허용.
---

## public.notifications

### 정책 목록

| 정책명 | 타입 | 명령 | 대상 역할 | 조건 |
|---|---|---|---|---|
| 본인 알림만 조회 | PERMISSIVE | SELECT | `authenticated` | `auth.uid() = user_id` |

### 역할별 접근

| 역할 | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `anon` | 불가 | 불가 | 불가 | 불가 |
| `authenticated` | 본인 알림만 | 직접 접근 불가 | 직접 접근 불가 | 직접 접근 불가 |
| `service_role` | RLS 우회 | RLS 우회 | RLS 우회 | RLS 우회 |

### 설계 의도

- 알림 생성은 클라이언트가 직접 수행하지 않고 `create_notifications_for_new_event()` 트리거가 처리한다.
- 알림 목록 조회는 `get_notifications()` RPC를 사용한다.
- 읽음 처리는 알림 클릭/상세 진입 시 `mark_notification_as_read()`로 수행한다.
- 배지 정리는 `mark_all_notifications_as_read()`, 전체 삭제는 `delete_all_notifications()`로 수행한다.
