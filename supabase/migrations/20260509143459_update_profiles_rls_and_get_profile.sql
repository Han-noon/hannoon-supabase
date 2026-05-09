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
    'profile_image_url', profile_image_url
  )
  FROM public.profiles WHERE id = auth.uid();
$function$;