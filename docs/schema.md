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
