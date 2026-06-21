# Schema

## public.profiles

| 컬럼 | 타입 | 제약 | 기본값 |
|------|------|------|--------|
| `id` | `uuid` | PK, NOT NULL, FK → `auth.users(id)` | `auth.uid()` |
| `email` | `character varying` | UNIQUE | - |
| `created_at` | `timestamp with time zone` | NOT NULL | `now()` |
| `name` | `text` | - | - |
| `profile_image_path` | `text` | - | - |

### 제약조건

- `profiles_pkey` — `id` Primary Key
- `profiles_email_key` — `email` Unique
- `profiles_id_fkey` — `id` → `auth.users(id)` ON UPDATE CASCADE ON DELETE CASCADE

### Row Level Security

활성화됨. 정책은 [rls-policy.md](./rls-policy.md) 참고.

---

## 함수

### `public.handle_new_user()`

`auth.users`에 유저가 생성될 때 `profiles`에 자동으로 행을 삽입하는 트리거 함수.

- Language: `plpgsql`
- Security: `SECURITY DEFINER` (`SET search_path TO ''`)
- 트리거: `on_auth_user_created` — `AFTER INSERT ON auth.users FOR EACH ROW`
- 현재 로그인 방식은 Google OAuth만 사용한다.
- Google OAuth 로그인 시: OAuth 메타데이터의 `full_name`을 `name`에 저장하고, `profile_image_path`를 `{uid}/profile` 고정 경로로 저장한다.

### `public.get_profile()`

현재 로그인한 유저의 프로필 정보를 반환하는 RPC 함수.

- Language: `sql`
- Security: `SECURITY INVOKER` (`SET search_path = ''`, RLS 적용)
- Returns: `json` — `{ id, email, name, profile_image_path }`
- 권한: `authenticated`

### `public.delete_user()`

현재 로그인한 유저가 본인 계정을 탈퇴하는 RPC 함수.

- Language: `plpgsql`
- Security: `SECURITY DEFINER` (`SET search_path = ''`)
- Returns: `void`
- 권한: `authenticated`
- 동작: `auth.uid()`가 NULL이면 `'로그인이 필요합니다.'` 예외. 아니면 `auth.users`의 본인 행을 삭제하며, `profiles`(ON DELETE CASCADE) → `subscriptions`/`notifications`(ON DELETE CASCADE)까지 연쇄 삭제된다.
- 프로필 이미지(`user_profile_images/{uid}/profile`) 삭제는 클라이언트가 탈퇴 전 Storage SDK로 직접 수행한다.

---

## 권한 (Grants)

| 대상 | 권한 |
|------|------|
| `authenticated` | `SELECT` on `profiles` |
| `authenticated` | `UPDATE` on `profiles` |
| `authenticated` | `EXECUTE` on `get_profile()` |
| `authenticated` | `EXECUTE` on `delete_user()` |
| `service_role` | `ALL` on `profiles` |

# Schema

## Enum Types

| Type | Values |
|---|---|
| `category` | `정치`, `경제`, `사회`, `국제` |
| `article_status` | `needs_crawl`, `ready`, `crawl_failed` |
| `bias_type` | `진보`, `중도`, `보수` |
| `content_source` | `rss`, `crawl` |
| `abusing_type` | `title_content_mismatch`, `content_context_mismatch` |

---

## Extensions

| Extension | Schema | Usage |
|---|---|---|
| `pg_trgm` | `extensions` | topics/events 검색용 `extensions.word_similarity`, `extensions.gin_trgm_ops` |
| `vector` | `extensions` | articles/events 임베딩 저장 및 유사도 검색 (4096차원) |
| `pg_net` | `extensions` | DB 트리거에서 비동기 HTTP 요청 (`net.http_post`) |

---

## Tables

### articles

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| feed_url | text | NOT NULL | — |
| guid | bigint | NOT NULL | — |
| link | text | NOT NULL | — |
| category | category | NOT NULL | — |
| title | text | NOT NULL | — |
| summary | text | NOT NULL | — |
| content | text | NULL | — |
| content_source | content_source | NOT NULL | — |
| publisher | text | NOT NULL | — |
| published_at | timestamp | NOT NULL | — |
| bias_type | bias_type | NOT NULL | — |
| status | article_status | NOT NULL | — |
| article_image_url | text | NULL | — |
| created_at | timestamp | NOT NULL | now() |
| updated_at | timestamp | NOT NULL | now() |
| embedding | vector(4096) | NULL | — |

### topics

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| category | category | NOT NULL | — |
| title | text | NOT NULL | — |
| summary | text | NOT NULL | — |
| created_at | timestamp | NOT NULL | now() |
| updated_at | timestamp | NOT NULL | now() |

### events

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| topic_id | bigint (FK → topics.id) | NULL | — |
| category | category | NOT NULL | — |
| title | text | NOT NULL | — |
| summary | text | NOT NULL | — |
| article_count | integer | NOT NULL | 0 |
| left_count | integer | NOT NULL | 0 |
| mid_count | integer | NOT NULL | 0 |
| right_count | integer | NOT NULL | 0 |
| abusing_count | integer | NOT NULL | 0 |
| event_image_url | text | NULL | — |
| created_at | timestamp | NOT NULL | now() |
| updated_at | timestamp | NOT NULL | now() |
| prev_event_id | bigint (FK → events.id) | NULL | — |
| next_event_id | bigint (FK → events.id) | NULL | — |
| embedding | vector(4096) | NULL | — |
| reason | text | NULL | — |

### subscriptions

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| user_id | uuid (FK → profiles.id) | NOT NULL | — |
| topic_id | bigint (FK → topics.id) | NOT NULL | — |
| created_at | timestamp | NOT NULL | now() |

제약:

- `subscriptions_user_id_topic_id_key` — UNIQUE (user_id, topic_id)
- `subscriptions_user_id_fkey` — `user_id` → `profiles(id)` ON DELETE CASCADE (회원 탈퇴 시 연쇄 삭제)

### event_articles

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| event_id | bigint (FK → events.id) | NOT NULL | — |
| article_id | bigint (FK → articles.id) | NOT NULL | — |
| reason | text | NULL | — |

### abusing_articles

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| event_id | bigint (FK → events.id) | NOT NULL | — |
| article_id | bigint (FK → articles.id) | NOT NULL | — |
| type | abusing_type | NOT NULL | — |
| reason | text | NULL | — |

### topic_causes

각 토픽에서 서버가 추출한 원인 문장 및 임베딩 저장.

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| topic_id | bigint (FK → topics.id) | NOT NULL | — |
| cause_text | text | NOT NULL | — |
| cause_embedding | vector(4096) | NULL | — |

---

## Triggers

| Trigger | Table | Event | Function | Description |
|---|---|---|---|---|
| `set_updated_at` | articles, topics, events | BEFORE UPDATE | `update_updated_at()` | updated_at 자동 갱신 |
| `update_event_counts_on_article_insert` | event_articles | AFTER INSERT | `update_event_counts_on_article_insert()` | article_count, left/mid/right_count 증가 |
| `increment_abusing_count` | abusing_articles | AFTER INSERT | `increment_abusing_count()` | events.abusing_count 증가 |
| `decrement_bias_count` | abusing_articles | AFTER INSERT | `decrement_bias_count()` | article.bias_type에 따라 events.left/mid/right_count 감소 (하한 0) |

---

## Functions

| Function | Returns | Description |
|---|---|---|
| `get_topic(p_topic_id bigint)` | json | 단일 topic 조회. 없으면 예외 발생 |
| `get_event(p_event_id bigint)` | json | 단일 event 조회. 없으면 예외 발생. `event_id`, `prev_event_id`, `next_event_id`, `prev_event_title`, `next_event_title` 포함. 로그인 사용자가 호출하면 `viewed_events`에 조회 기록을 upsert(최근 본 이벤트) → `VOLATILE` 함수 |
| `get_events_by_topic(p_topic_id, p_cursor_id, p_size, p_order)` | json | cursor 기반 페이지네이션. `{ events, has_more, next_cursor }` 반환 |
| `get_articles_by_event(p_event_id, p_bias_type, p_page, p_size, p_order)` | json | 이벤트별 기사 page 기반 페이지네이션. `{ articles, page, size, total_count, total_pages }` 반환. `articles` 항목 필드: `link, title, summary, article_image_url, publisher, published_at, bias_type`. `p_bias_type`: NULL(전체)/진보/중도/보수, `p_page` default 1 (1 미만 예외), `p_size` default 3 (1 미만 예외, 100 초과 시 클램핑), `p_order`: asc(기본)/desc |
| `get_abusing_articles_by_event(p_event_id, p_abusing_type, p_page, p_size)` | json | 이벤트별 어뷰징 기사 page 기반 페이지네이션. `{ articles, page, size, total_count, total_pages }` 반환. `articles` 항목 필드: `link, title, summary, article_image_url, publisher, published_at`. `p_abusing_type`: NULL(전체)/title_content_mismatch/content_context_mismatch, `p_page` default 1 (1 미만 예외), `p_size` default 4 (1 미만 예외, 100 초과 시 클램핑). 정렬: id DESC(최근순) |
| `get_articles_by_event(p_event_id, p_bias_type, p_page, p_size, p_order)` | json | 이벤트별 기사 page 기반 페이지네이션. `{ articles, page, size, total_count, total_pages }` 반환. `p_bias_type`: NULL(전체)/left/mid/right, `p_page` default 1 (1 미만 예외), `p_size` default 3 (1 미만 예외, 100 초과 시 클램핑), `p_order`: asc(기본)/desc |
| `get_topics(p_search, p_category, p_page, p_size)` | json | topics 목록 조회. `{ topics, page, size, total_count, total_pages }` 반환, 각 topic에 `subscription_id`, `is_subscribed` 포함 |
| `get_subscribed_topics(p_page, p_size)` | json | 현재 사용자가 구독한 topics 목록 조회. `{ topics, page, size, total_count, total_pages }` 반환 |
| `get_events(p_search, p_category, p_page, p_size)` | json | events 목록 조회. `{ events, page, size, total_count, total_pages }` 반환, 각 event에 `subscription_id`, `is_subscribed` 포함 |
| `subscribe_topic(p_topic_id bigint)` | json | 토픽 구독 후 `{ subscription_id, is_subscribed }` 반환. 이미 구독 중이어도 기존 구독 정보 반환 |
| `unsubscribe_topic(p_topic_id bigint)` | void | 토픽 구독 해제. 미구독이어도 성공 처리 |

---

## 권한 (Grants) — list query functions

| 대상 | 권한 |
|------|------|
| `anon` | `EXECUTE` on `get_topics(text, category, int, int)` |
| `anon` | `EXECUTE` on `get_events(text, category, int, int)` |
| `authenticated` | `EXECUTE` on `get_topics(text, category, int, int)` |
| `authenticated` | `EXECUTE` on `get_subscribed_topics(int, int)` |
| `authenticated` | `EXECUTE` on `get_events(text, category, int, int)` |
| `service_role` | `EXECUTE` on list query functions |

---

## 권한 (Grants) — subscriptions

| 대상 | 권한 |
|------|------|
| `authenticated` | `SELECT`, `INSERT`, `DELETE` on `subscriptions` |
| `authenticated` | `EXECUTE` on `subscribe_topic(bigint)` |
| `authenticated` | `EXECUTE` on `unsubscribe_topic(bigint)` |
| `service_role` | `ALL` on `subscriptions` |

# Schema

## Tables

### feeds

| Column | Type | Nullable | Default |
|---|---|---|---|
| url | text | NOT NULL | — |
| category | category | NOT NULL | — |
| publisher | text | NOT NULL | — |
| bias_type | bias_type | NOT NULL | — |
| title | text | NOT NULL | — |
| etag | text | NULL | — |
| modified_at | timestamp | NULL | — |
| last_checked | timestamp | NULL | — |

# Schema

## public.article_ai_results

| 컬럼 | 타입 | 제약 | 기본값 |
|------|------|------|--------|
| `id` | `bigint` | PK, NOT NULL | identity |
| `article_id` | `bigint` | NOT NULL, FK → `articles.id` | - |
| `summary` | `text` | NULL | - |
| `abuse_score` | `numeric` | NULL | - |
| `abuse_label` | `text` | NULL | - |
| `keywords` | `text[]` | NULL | - |
| `status` | `article_ai_status` | NOT NULL | `pending` |
| `last_error` | `text` | NULL | - |
| `created_at` | `timestamp` | NOT NULL | `now()` |
| `updated_at` | `timestamp` | NOT NULL | `now()` |

---

## Enum Types

| Type | Values |
|---|---|
| `article_ai_status` | `pending`, `done`, `failed` |

---

## 제약조건

- `article_ai_results_pkey` — `id` Primary Key  
- `article_ai_results_article_id_fkey` — `article_id` → `articles.id` ON DELETE CASCADE  

---

## Row Level Security

활성화됨. 정책은 [rls-policy.md](./rls-policy.md) 참고.

---

## 권한 (Grants)

| 대상 | 권한 |
|------|------|
| `authenticated` | `SELECT` on `article_ai_results` *(raw GRANT only; RLS로 인해 실제 조회 결과는 0건)* |
 | `authenticated` | `SELECT` on `article_ai_results` *(raw GRANT only; RLS로 인해 실제 조회 결과는 0건)* |
 | `service_role` | `ALL` on `article_ai_results` |
 # Schema

## public.article_jobs

| 컬럼 | 타입 | 제약 | 기본값 |
|------|------|------|--------|
| `id` | `bigint` | PK, NOT NULL | identity |
| `article_id` | `bigint` | NOT NULL, FK → `articles.id` | - |
| `status` | `article_job_status` | NOT NULL | `pending` |
| `attempts` | `integer` | NOT NULL | `0` |
| `last_error` | `text` | NULL | - |
| `last_attempt_at` | `timestamp` | NULL | - |
| `created_at` | `timestamp` | NOT NULL | `now()` |
| `updated_at` | `timestamp` | NOT NULL | `now()` |

---

## Enum Types

| Type | Values |
|---|---|
| `article_job_status` | `pending`, `sent`, `failed` |

---

## 제약조건

- `article_jobs_pkey` — `id` Primary Key  
- `article_jobs_article_id_fkey` — `article_id` → `articles.id` ON DELETE CASCADE  

---

## Row Level Security

활성화됨. 정책은 [rls-policy.md](./rls-policy.md) 참고.

---

## 권한 (Grants)

| 대상 | 권한 |
|------|------|
| `service_role` | `ALL` on `article_jobs` |
---

## Storage Buckets

| Bucket | 공개 여부 | 파일 크기 제한 | 허용 MIME |
|--------|-----------|----------------|-----------|
| `user_profile_images` | public (누구나 읽기 가능, 쓰기는 RLS로 제한) | 5 MB | jpeg, png, webp |
| `event_images` | public | 10 MB | jpeg, png, webp |
---

## notifications

구독한 토픽에 새 이벤트가 생성되면 사용자별 알림 내역을 저장한다.

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | - |
| created_at | timestamp | NOT NULL | now() |
| user_id | uuid (FK -> profiles.id) | NOT NULL | - |
| topic_id | bigint (FK -> topics.id) | NOT NULL | - |
| event_id | bigint (FK -> events.id) | NOT NULL | - |
| read_at | timestamp | NULL | - |

제약:

- `notifications_pkey` -> `id` Primary Key
- `notifications_user_id_event_id_key` -> UNIQUE (`user_id`, `event_id`)
- `notifications_event_id_fkey` -> `event_id` references `events(id)`
- `notifications_topic_id_fkey` -> `topic_id` references `topics(id)`
- `notifications_user_id_fkey` -> `user_id` references `profiles(id)` ON DELETE CASCADE (회원 탈퇴 시 연쇄 삭제)

인덱스:

- `notifications_user_id_created_at_idx` -> 사용자별 최신 알림 목록 조회
- `notifications_user_id_unread_idx` -> 사용자별 미읽음 알림 카운트 조회

---

## Functions - notifications

| Function | Returns | Description |
|---|---|---|
| `create_notifications_for_new_event()` | trigger | 새 이벤트 생성 시 해당 토픽 구독자에게 알림 생성 |
| `get_notifications(p_page int, p_size int)` | json | 본인 알림 목록 조회. 조회만 하며 `read_at`은 갱신하지 않음. 응답에서 `is_read`는 `read_at IS NOT NULL`로 계산 |
| `get_unread_notification_count()` | json | `{ unread_count }` 반환 |
| `mark_notification_as_read(p_notification_id bigint)` | json | 알림 클릭/상세 진입 시 단일 알림 읽음 처리 |
| `mark_all_notifications_as_read()` | json | 본인의 모든 미읽음 알림 읽음 처리 |
| `delete_notification(p_notification_id bigint)` | void | 본인 알림 단일 삭제 |
| `delete_all_notifications()` | json | 본인 알림 전체 삭제 |
| `notify_onesignal_on_notification_insert()` | trigger | notifications INSERT 시 `net.http_post()`로 `notify-onesignal` edge function을 비동기 호출. `private.app_config`에서 `edge_function_url`(URL), `webhook_secret`(인증)을 읽음 |

---

## Grants - notifications

| Role | Privileges |
|---|---|
| `authenticated` | `SELECT`, `UPDATE`, `DELETE` on `notifications` |
| `authenticated` | `EXECUTE` on notification RPC functions |
| `service_role` | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `REFERENCES`, `TRIGGER`, `TRUNCATE` on `notifications` |

---

## Edge Functions

### `notify-onesignal`

DB 트리거(`notify_onesignal_after_notification_insert`)가 호출하는 Deno edge function.

| 항목 | 내용 |
|---|---|
| 인증 | `WEBHOOK_SECRET`으로 트리거 외 호출 차단. 미설정 시 검증 생략 (로컬 개발 편의) |
| topic 조회 | Supabase service role로 `topics.title` 조회 |
| 푸시 발송 | OneSignal v2 API — `include_aliases.external_id` 타겟팅, `target_channel: "push"` |
| 메시지 | `"{topic_title}에 새로운 사건이 등록되었습니다."` (ko/en 동일) |
| payload | `notification_id`, `event_id`, `topic_id` |

**환경변수**

| 변수 | 주입 방식 |
|---|---|
| `SUPABASE_URL` | Supabase 자동 주입 |
| `SUPABASE_SERVICE_ROLE_KEY` | Supabase 자동 주입 |
| `WEBHOOK_SECRET` | GitHub Secrets → `supabase secrets set` |
| `ONESIGNAL_APP_ID` | GitHub Secrets → `supabase secrets set` |
| `ONESIGNAL_REST_API_KEY` | GitHub Secrets → `supabase secrets set` |

---

## viewed_events

사용자가 열람한 이벤트와 마지막 조회 시각을 저장한다(최근 본 이벤트). 기록은 `get_event` 호출 시 upsert 된다.

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | - |
| user_id | uuid (FK -> profiles.id) | NOT NULL | - |
| event_id | bigint (FK -> events.id) | NOT NULL | - |
| viewed_at | timestamp | NOT NULL | now() |

제약:

- `viewed_events_pkey` -> `id` Primary Key
- `viewed_events_user_id_event_id_key` -> UNIQUE (`user_id`, `event_id`) — 사용자별 이벤트당 1행, upsert ON CONFLICT 대상
- `viewed_events_user_id_fkey` -> `user_id` references `profiles(id)`
- `viewed_events_event_id_fkey` -> `event_id` references `events(id)`

인덱스:

- `viewed_events_user_id_event_id_key` (UNIQUE) -> upsert 대상이자 user_id 단독 조회도 커버
- `viewed_events_user_id_viewed_at_idx` -> 사용자별 최신순 페이지네이션(user_id 필터 + viewed_at 정렬) 커버

---

## Functions - viewed_events

| Function | Returns | Description |
|---|---|---|
| `get_event(p_event_id bigint)` | json | (갱신) 단건 이벤트 조회 시 로그인 사용자의 조회 기록을 `viewed_events`에 upsert. 같은 이벤트 재조회 시 `viewed_at`만 갱신, `anon` 호출은 기록하지 않음 |
| `get_viewed_events(p_page int, p_size int)` | json | 최근 일주일 내 본인이 조회한 이벤트 목록. `{ events, page, size, total_count, total_pages }` 반환, 정렬 `viewed_at DESC`. `p_page` default 1, `p_size` default 9(1 미만 예외, 100 초과 시 클램핑). 항목 필드: `event_id, topic_id, topic_title, event_title, category, summary, created_at, updated_at, viewed_at, subscription_id, is_subscribed`. 비로그인 시 예외 |

---

## Grants - viewed_events

| Role | Privileges |
|---|---|
| `authenticated` | `SELECT`, `INSERT`, `UPDATE` on `viewed_events` |
| `authenticated` | `EXECUTE` on `get_viewed_events(int, int)` |
| `service_role` | `SELECT`, `INSERT`, `UPDATE`, `DELETE`, `REFERENCES`, `TRIGGER`, `TRUNCATE` on `viewed_events` |
