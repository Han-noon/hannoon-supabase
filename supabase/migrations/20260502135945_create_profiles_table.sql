create table "public"."profiles" (
  "id" uuid not null default auth.uid(),
  "email" character varying,
  "name" text,
  "profile_image_url" text,
  "created_at" timestamp not null default now()
);


alter table "public"."profiles" enable row level security;

CREATE UNIQUE INDEX profiles_email_key ON public.profiles USING btree (email);

CREATE UNIQUE INDEX profiles_pkey ON public.profiles USING btree (id);

alter table "public"."profiles" add constraint "profiles_pkey" PRIMARY KEY using index "profiles_pkey";

alter table "public"."profiles" add constraint "profiles_email_key" UNIQUE using index "profiles_email_key";

alter table "public"."profiles" add constraint "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."profiles" validate constraint "profiles_id_fkey";

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.handle_new_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.raw_app_meta_data->>'provider' = 'google' then
    insert into public.profiles (id, email, name, profile_image_url)
    values (
      new.id,
      new.email,
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'avatar_url'
    );
  else
    insert into public.profiles (id, email)
    values (new.id, new.email);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.get_profile()
 RETURNS json
 LANGUAGE sql
 STABLE
 SECURITY INVOKER
 SET search_path = ''
AS $function$
  SELECT json_build_object(
    'email', email,
    'name', name,
    'profile_image_url', profile_image_url
  )
  FROM public.profiles WHERE id = auth.uid();
$function$;

REVOKE EXECUTE ON FUNCTION public.handle_new_user() FROM PUBLIC;

grant select on table "public"."profiles" to "authenticated";

grant execute on function "public"."get_profile"() to "authenticated";

grant references on table "public"."profiles" to "service_role";

grant trigger on table "public"."profiles" to "service_role";

grant truncate on table "public"."profiles" to "service_role";


create policy "본인 회원정보만 조회"
on "public"."profiles"
as permissive
for select
to authenticated
using (auth.uid() = id);


CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


