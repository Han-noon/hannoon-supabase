create table "public"."feeds" (
  "url" text not null,
  "category" public.category not null,
  "publisher" text not null,
  "bias_type" public.bias_type not null,
  "title" text not null,
  "etag" text,
  "modified_at" timestamp,
  "last_checked" timestamp
);

alter table "public"."feeds" enable row level security;

CREATE UNIQUE INDEX feeds_pkey ON public.feeds USING btree (url);

alter table "public"."feeds"
  add constraint "feeds_pkey" PRIMARY KEY using index "feeds_pkey";


grant select on table "public"."feeds" to "anon";
grant select on table "public"."feeds" to "authenticated";

grant select, insert, update, delete on table "public"."feeds" to "service_role";
grant references on table "public"."feeds" to "service_role";
grant trigger on table "public"."feeds" to "service_role";
grant truncate on table "public"."feeds" to "service_role";


create policy "Enable read access for all users"
on "public"."feeds"
as permissive
for select
to anon, authenticated
using (true);