ALTER TABLE "public"."profiles"
RENAME COLUMN "profile_image_url" TO "profile_image_path";

UPDATE "public"."profiles"
SET "profile_image_path" = id::text || '/profile';

-- profiles: 본인만 UPDATE 가능
create policy "본인 회원정보만 수정"
on "public"."profiles"
as permissive
for update
to authenticated
using (auth.uid() = id)
with check (auth.uid() = id);

grant update on table "public"."profiles" to "authenticated";


CREATE OR REPLACE FUNCTION public.get_profile()
 RETURNS json
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
 SET search_path = ''
AS $function$
  SELECT json_build_object(
    'id', id,
    'email', email,
    'name', name,
    'profile_image_path', profile_image_path
  )
  FROM public.profiles WHERE id = auth.uid();
$function$;

-- 이미지 변경은 storage SDK 직접 호출로 대체 ({uid}/profile 고정 경로)
DROP FUNCTION IF EXISTS public.update_profile_image_url(text);

-- profile_image_path를 가입 시 {uid}/profile 고정 경로로 설정
CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
begin
  insert into public.profiles (id, email, name, profile_image_path)
  values (
    new.id,
    new.email,
    new.raw_user_meta_data->>'full_name',
    new.id::text || '/profile'
  );
  return new;
end;
$$;
