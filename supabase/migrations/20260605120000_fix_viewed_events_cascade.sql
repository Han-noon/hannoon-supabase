alter table "public"."viewed_events" drop constraint "viewed_events_user_id_fkey";
alter table "public"."viewed_events" add constraint "viewed_events_user_id_fkey"
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;
