# Schema

## public.profiles

| 컬럼 | 타입 | 제약 | 기본값 |
|------|------|------|--------|
| `id` | `uuid` | PK, NOT NULL, FK → `auth.users(id)` | `auth.uid()` |
| `email` | `character varying` | UNIQUE | - |
| `created_at` | `timestamp with time zone` | NOT NULL | `now()` |
| `name` | `text` | - | - |
| `profile_image_url` | `text` | - | - |

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
- Google OAuth 로그인 시: OAuth 메타데이터에서 `name`, `profile_image_url` 자동 삽입
- 일반 가입 시: `id`, `email`만 삽입

### `public.get_profile()`

현재 로그인한 유저의 프로필 정보를 반환하는 RPC 함수.

- Language: `sql`
- Security: `SECURITY INVOKER` (`SET search_path = ''`, RLS 적용)
- Returns: `json` — `{ email, name, profile_image_url }`
- 권한: `authenticated`

### `public.update_profile_image_url(new_url text)`

현재 로그인한 유저의 `profile_image_url`을 갱신하는 RPC 함수.

- Language: `sql`
- Security: `SECURITY INVOKER` (`SET search_path = ''`)
- Parameter: `new_url text`
- Returns: `void`
- 권한: `authenticated`

---

## 권한 (Grants)

| 대상 | 권한 |
|------|------|
| `authenticated` | `SELECT` on `profiles` |
| `authenticated` | `EXECUTE` on `get_profile()` |
| `authenticated` | `EXECUTE` on `update_profile_image_url(text)` |
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
| topic_id | bigint (FK → topics.id) | NOT NULL | — |
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
| prev_event | bigint (FK → events.id) | NULL | — |
| next_event | bigint (FK → events.id) | NULL | — |

### subscriptions

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| user_id | uuid (FK → profiles.id) | NOT NULL | — |
| topic_id | bigint (FK → topics.id) | NOT NULL | — |
| created_at | timestamp | NOT NULL | now() |

제약: `subscriptions_user_id_topic_id_key` — UNIQUE (user_id, topic_id)

### event_articles

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| event_id | bigint (FK → events.id) | NOT NULL | — |
| article_id | bigint (FK → articles.id) | NOT NULL | — |

### abusing_articles

| Column | Type | Nullable | Default |
|---|---|---|---|
| id | bigint (identity) | NOT NULL | — |
| event_id | bigint (FK → events.id) | NOT NULL | — |
| article_id | bigint (FK → articles.id) | NOT NULL | — |
| type | abusing_type | NOT NULL | — |

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
| `get_event(p_event_id bigint)` | json | 단일 event 조회. 없으면 예외 발생 |
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
