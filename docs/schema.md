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
| short_summary | text | NULL | — |

- `short_summary`: 이벤트의 짧은 명사형 요약(예: "의대 정원 2,000명 확대 공식화"). 토픽 분류 진입 시 요약 롤업과 같은 호출에서 채우며, 롤업 전 이벤트는 NULL.

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

### article_entities

기사별 고유명사(LLM 추출). 새 기사와 엔티티가 겹치는 기사를 이벤트 후보로 회수하는 역색인.

| Column | Type | Nullable | Default |
|---|---|---|---|
| article_id | bigint (FK → articles.id) | NOT NULL | — |
| entity | text | NOT NULL | — |

제약·인덱스:

- `article_entities_pkey` — PRIMARY KEY (article_id, entity). 재추출 시 중복 행 방지, `article_id` 조회 인덱스 겸용
- `article_entities_entity_idx` — (entity), 엔티티로 기사 찾기

권한: RLS 활성화, `anon`·`authenticated` 권한 없음, `service_role`만 `SELECT`, `INSERT`, `UPDATE`, `DELETE`.

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
| `get_topics(p_search, p_category, p_page, p_size, p_order)` | json | topics 목록 조회. `{ topics, page, size, total_count, total_pages }` 반환, 각 topic에 `subscription_id`, `is_subscribed`와 카드 집계(`article_count`, `left_count`, `mid_count`, `right_count`, `left_percent`, `mid_percent`, `right_percent`, `first_published_at`), 대표 이미지 `topic_image_url`, `keywords`(text[], 생성 전엔 빈 배열) 포함. `*_percent`는 정수 %로 세 값의 합이 항상 100(기사가 없으면 모두 0) — 내림 후 남는 %를 나머지가 큰 쪽부터 1씩 줌. 진보·보수를 이름 순서로 우대하지 않도록, 진보 = 보수 건수면 두 비율을 같게 하고 나머지는 중도에, 그 밖에 나머지가 같으면 중도 → 건수가 많은 쪽 순. 그래서 중도와 한쪽 건수가 같으면 중도가 1%p 높을 수 있음(예: 1·1·4 → 16/17/67) (`bias_percentages`, `20261003120000`). `topic_image_url`은 topics에 이미지가 없어서, 이미지가 있는(NULL·빈 문자열 제외) 이벤트 중 가장 최근 이벤트의 `event_image_url`이며 없으면 null. 날짜는 `get_live_topic_timeline`과 같은 기사 MIN(published_at), 동률이면 id DESC. `p_order`: `latest`(기본, created_at DESC → id DESC) / `articles`(article_count DESC → created_at DESC → id DESC), 그 외 값은 예외. 집계는 `get_hot_topics`와 같은 기준 — `event_articles`(정상 기사)만 세고 미래 시각 기사 제외, 그래서 진보+중도+보수 = `article_count`. 이벤트 상세(`get_event`)의 기사 수는 어뷰징을 더한 캐시 컬럼이라 기준이 다름. `first_published_at`은 KST `timestamp`(시간대 없음). 페이지를 먼저 자르고 그 토픽만 집계하며, 전체 집계는 `articles` 정렬일 때만 (`20260930120000`) |
| `get_subscribed_topics(p_page, p_size)` | json | 현재 사용자가 구독한 topics 목록 조회. `{ topics, page, size, total_count, total_pages }` 반환. 각 topic에 `get_topics`와 같은 카드 집계·비율 필드와 `topic_image_url`, `keywords` 포함, 정렬은 id DESC |
| `bias_percentages(p_left int, p_mid int, p_right int)` | table(`left_percent`, `mid_percent`, `right_percent`) | 세 성향 카운트를 합이 100인 정수 %로 변환(최대 나머지 방식, 진보 = 보수면 같은 비율). 음수 입력은 예외. `get_topics`/`get_subscribed_topics`가 사용. IMMUTABLE |
| `get_events(p_search, p_category, p_page, p_size)` | json | events 목록 조회. `{ events, page, size, total_count, total_pages }` 반환, 각 event에 `subscription_id`, `is_subscribed` 포함 |
| `subscribe_topic(p_topic_id bigint)` | json | 토픽 구독 후 `{ subscription_id, is_subscribed }` 반환. 이미 구독 중이어도 기존 구독 정보 반환 |
| `unsubscribe_topic(p_topic_id bigint)` | void | 토픽 구독 해제. 미구독이어도 성공 처리 |

---

## 권한 (Grants) — list query functions

| 대상 | 권한 |
|------|------|
| `anon` | `EXECUTE` on `get_topics(text, category, int, int, text)` |
| `anon` | `EXECUTE` on `bias_percentages(int, int, int)` |
| `anon` | `EXECUTE` on `get_events(text, category, int, int)` |
| `authenticated` | `EXECUTE` on `get_topics(text, category, int, int, text)` |
| `authenticated` | `EXECUTE` on `bias_percentages(int, int, int)` |
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

---

## Functions - home widgets

홈 화면 위젯(실시간 이슈 타임라인, 오늘의 핫 토픽 랭킹)용 조회 RPC. `20260913120000_create_home_widget_functions.sql`.

- 기준 시각 `as_of` = `LEAST(now(), MAX(articles.published_at))`. 수집이 멈췄거나 과거 기사로 시연해도 시간창이 비지 않도록 데이터의 최신 시각에 맞추고, 미래 시각 기사가 있어도 `now()`를 넘지 않는다.
- 이벤트 날짜는 `events.created_at`(파이프라인 적재 시각)이 아니라 소속 기사의 `MIN(published_at)`.
- 반환 시각(`as_of`, `occurred_at`)은 `timestamp without time zone`을 JSON으로 바꾼 값이라 오프셋이 없다(DB 타임존 Asia/Seoul 기준, 기존 RPC와 동일).
- 기사 수는 `COUNT(DISTINCT article_id)` — `event_articles`에 (event_id, article_id) UNIQUE가 없어 중복 매핑이 있어도 부풀지 않는다.

| Function | Returns | Description |
|---|---|---|
| `get_hot_topics(p_window_hours int, p_size int)` | json | 토픽 순위. `{ as_of, window_hours, topics }` 반환, 항목 필드: `rank, topic_id, title, category, article_count, window_article_count`. **순위는 `(as_of - p_window_hours, as_of]` 구간 기사 수(`window_article_count`)로 매기고, `article_count`는 창과 무관한 토픽 누적 기사 수(`published_at <= as_of`)다** — 홈 카드가 누적을 보여주면서 순위는 최근 보도량을 따르기 때문(`20260928120000`). 정렬: `window_article_count` DESC → 창 안 최근 기사 시각 DESC → topic_id. 창 안에 기사가 없는 토픽과 토픽 미배정 이벤트의 기사는 제외. `p_window_hours` default 1 (1 미만 예외, 720 초과 시 클램핑), `p_size` default 5 (1 미만 예외, 100 초과 시 클램핑) |
| `get_live_topic_timeline(p_topic_id bigint, p_size int, p_active_hours int)` | json | 지정 토픽의 최근 이벤트 `p_size`개를 오래된 순으로 반환. `{ as_of, topic, events }`, `topic`: `{ id, title, category }`, 항목 필드: `id, title, occurred_at, article_count, is_latest, is_active`. `is_latest`는 가장 최근 이벤트, `is_active`는 가장 최근 이벤트에 `as_of - p_active_hours` 이후 기사가 있을 때 true. 기사가 없는 이벤트와 기준 시각 이후(미래 시각) 기사는 제외. 토픽이 없으면 예외 대신 `topic = null, events = []`. `p_size` default 3 (1 미만 예외, 100 초과 시 클램핑), `p_active_hours` default 24 (1 미만 예외, 720 초과 시 클램핑) |

인덱스:

- `articles_published_at_idx` -> 시간창 필터와 `MAX(published_at)` 조회
- `event_articles_article_id_idx` -> 기사 → 이벤트 조인

---

## Grants - home widgets

| Role | Privileges |
|---|---|
| `anon`, `authenticated`, `service_role` | `EXECUTE` on `get_hot_topics(int, int)`, `get_live_topic_timeline(bigint, int, int)` |

---

## topic_views

홈의 "실시간 인기 타임라인"(최근 1시간 조회수 1위 토픽)을 위한 조회 로그. 이벤트 상세(`/event-detail/:id`)·토픽 페이지(`/timeline/:topic_id`)를 열 때마다 웹이 `record_topic_view`를 호출해 한 줄씩 쌓는다. 비로그인 사용자는 브라우저 난수 `viewer_key`가 있을 때만 기록한다. `20260913130000_create_topic_views.sql`.

`viewed_events`(최근 본 이벤트)는 로그인 사용자만, 사람당 이벤트 1행이라 조회수를 셀 수 없어 따로 둔다.

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | - |
| topic_id | bigint (FK -> topics.id, ON DELETE CASCADE) | NOT NULL | - |
| event_id | bigint (FK -> events.id, ON DELETE CASCADE) | NULL (토픽 페이지 조회) | - |
| user_id | uuid (FK -> profiles.id, ON DELETE SET NULL) | NULL (비로그인) | - |
| viewer_key | text | NULL | - |
| viewed_at | timestamp | NOT NULL | now() |

- `viewer_key`: 비로그인 사용자 브라우저가 만든 난수. 중복 조회 제한에만 쓰며, 로그인 사용자 행에는 저장하지 않는다.
- RLS 활성화 + 정책 없음, `anon`/`authenticated` 테이블 권한은 명시적으로 회수. 아래 `SECURITY DEFINER` 함수로만 기록·집계·정리한다(원시 로그 노출 방지).
- 보관: pg_cron 작업 `purge-topic-views`(매시 17분)가 `purge_topic_views()`로 7일 지난 로그를 삭제하고, 1일 지난 행의 `user_id`·`viewer_key`를 비운다. 식별자는 10분 중복 제한에만 쓴다.
- 인덱스:
  - `topic_views_viewed_at_topic_id_idx` (viewed_at, topic_id) -> 인기 집계
  - `topic_views_topic_id_viewed_at_idx` (topic_id, viewed_at) -> 최근 10분 중복 확인
  - `topic_views_event_id_idx`, `topic_views_user_id_idx` (부분 인덱스) -> 외래키 CASCADE / SET NULL
  - `topic_views_identified_viewed_at_idx` (viewed_at, 식별자가 남은 행만) -> 식별자 비우기
- 알려진 한계: anon 키로 누구나 호출할 수 있고 요청자(IP) 기준 제한이 없어, `viewer_key`를 바꿔 가며 호출하면 조회수를 부풀릴 수 있다. 이벤트의 토픽이 나중에 바뀌어도 과거 조회는 조회 시점 토픽에 남는다.

## Functions - topic_views

| Function | Returns | Description |
|---|---|---|
| `record_topic_view(p_topic_id bigint, p_event_id bigint, p_viewer_key text)` | void | 조회 1건 기록. `p_topic_id`(토픽 페이지)와 `p_event_id`(이벤트 상세) 중 정확히 하나를 지정(아니면 예외). 이벤트 조회는 소속 토픽의 조회로 센다. 비로그인인데 `p_viewer_key`가 없거나 빈 문자열이면 기록하지 않음. 토픽 미배정 이벤트·없는 id는 예외 없이 기록하지 않음. 같은 사람(로그인: `user_id`, 비로그인: `viewer_key`)이 같은 화면을 10분 안에 다시 열면 한 번만 기록하며, 동시 호출은 advisory lock으로 직렬화. `p_viewer_key` 64자 초과 시 예외. `SECURITY DEFINER`, `timezone = 'Asia/Seoul'` 고정 |
| `get_popular_topic_timeline(p_window_hours int, p_size int, p_active_hours int)` | json | `(views_as_of - p_window_hours, views_as_of]` 조회수 1위 토픽의 타임라인. `views_as_of = now()` — 조회는 사용자 행동이라 기사 데이터 최신 시각인 `as_of`와 기준이 다르다. 정렬: 조회수 DESC → 마지막 조회 시각 DESC → topic_id. 반환: `get_live_topic_timeline` 결과(`as_of, topic, events`) + `window_hours, view_count, views_as_of`. 조회가 없으면 기사 수로 대체하지 않고 `topic = null, events = [], view_count = 0`. `p_window_hours` default 1 (1 미만 예외, 24 초과 시 클램핑), `p_size`·`p_active_hours`는 `get_live_topic_timeline`에 그대로 전달. `SECURITY DEFINER` — 안에서 호출하는 `get_live_topic_timeline`도 소유자 권한으로 실행되어 RLS를 적용받지 않으므로, topics/events/articles/event_articles에 제한 정책을 추가하면 함께 검토할 것. `timezone = 'Asia/Seoul'` 고정 |
| `purge_topic_views()` | json | 7일 지난 로그 삭제 + 1일 지난 행의 `user_id`·`viewer_key` 비우기. `{ deleted, anonymized }` 반환. pg_cron 작업 `purge-topic-views`가 매시 17분 실행. `service_role` 전용 — 함수의 PUBLIC 실행 권한은 Postgres 전역 기본값이라 스키마 단위 기본 권한 회수로 막히지 않아 `PUBLIC`/`anon`/`authenticated`에서 명시적으로 회수, `SECURITY DEFINER`, `timezone = 'Asia/Seoul'` 고정 |

## Grants - topic_views

| Role | Privileges |
|---|---|
| `anon`, `authenticated` | 테이블 권한 없음, `EXECUTE` on `record_topic_view(bigint, bigint, text)`, `get_popular_topic_timeline(int, int, int)` |
| `service_role` | `SELECT`, `INSERT`, `UPDATE`, `DELETE` on `topic_views`, `EXECUTE` on 세 함수 |

## 토픽 AI 생성 결과

- `topics.ai_summary text`: 카드용 AI 요약(생성 전 NULL). 분류 파이프라인의 `topics.summary`와 분리하여 서로 덮어쓰지 않음.
- `topics.keywords text[]`: 내용 기반 키워드, 기본값 `{}`.
- `topics.ai_generated_at timestamptz`: 마지막 생성 시각.
- `topic_relations`: `topic_id < related_topic_id`인 양방향 연결 1행, 설명·이벤트 근거 저장. 토픽 삭제 시 CASCADE.
- `topic_enrichment_state`: 토픽 ID 묶음별 입력 해시·버전·모델 버전. 생성 결과의 중복/동시 저장 방지.
- `topic_enrichment_snapshot(bigint[])`: 최대 10개 토픽의 이벤트 입력과 현재 저장 버전 반환.
- `publish_topic_enrichment(bigint[], text, bigint, text, jsonb, jsonb)`: 입력 해시·버전·근거를 검증한 뒤 요약/키워드/연관 관계를 원자적으로 갱신. 추론은 외부에서 수행하며 저장 중 topics/events/state에 테이블 잠금 사용.
- `get_topic_enrichment(bigint)`: 키워드·요약·생성 시각·연관 토픽 조회. 공개 응답의 `topic_id`와 연관 토픽 `id`는 JSON 숫자, `summary`는 `ai_summary`에서 조회. 내부 snapshot ID는 서버 정밀도 보존을 위해 문자열 유지. 기존 목록 RPC 응답은 변경하지 않음.

이번 마이그레이션은 스키마만 추가한다. 실제 결과 입력은 별도 생성 작업으로 진행하며, 동일 DB에서는 고정된 토픽 ID 목록으로 운영한다.
