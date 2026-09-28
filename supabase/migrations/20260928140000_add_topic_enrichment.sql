-- Apply once with the migration/admin role. No article/event rows are changed.
begin;
alter table public.topics add column if not exists keywords text[] not null default '{}';
alter table public.topics add column if not exists ai_generated_at timestamptz;
create table if not exists public.topic_enrichment_state (
 scope_key text primary key, source_hash text not null, version bigint not null,
 model_version text not null, generated_at timestamptz not null default now()
);
create table if not exists public.topic_relations (
 topic_id bigint not null references public.topics(id) on delete cascade,
 related_topic_id bigint not null references public.topics(id) on delete cascade,
 reason text not null check(length(reason) between 1 and 500),
 evidence jsonb not null, generated_at timestamptz not null default now(),
 primary key(topic_id,related_topic_id), check(topic_id < related_topic_id)
);
create index if not exists topic_relations_related_topic_id_idx
 on public.topic_relations(related_topic_id);
alter table public.topic_relations enable row level security;
alter table public.topic_enrichment_state enable row level security;
revoke all on public.topic_relations, public.topic_enrichment_state from anon, authenticated;
grant select on public.topic_relations to anon, authenticated;
grant select,insert,update,delete on public.topic_relations, public.topic_enrichment_state to service_role;
create policy topic_relations_read on public.topic_relations for select to anon,authenticated using (true);

create or replace function public.topic_enrichment_snapshot(p_topic_ids bigint[])
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_topics jsonb; v_key text; v_state public.topic_enrichment_state%rowtype;
begin
 if p_topic_ids is null or cardinality(p_topic_ids) not between 1 and 10 or
    (select count(distinct x) from unnest(p_topic_ids) x) <> cardinality(p_topic_ids) then
   raise exception 'Provide 1 to 10 unique topic IDs';
 end if;
 select string_agg(x::text,',' order by x) into v_key from unnest(p_topic_ids) x;
 select jsonb_agg(jsonb_build_object('id',t.id::text,'title',t.title,'category',t.category::text,
   'events',coalesce((select jsonb_agg(jsonb_build_object('id',e.id::text,'title',e.title,
     'summary',e.summary,'core_content',coalesce(e.core_content,'')) order by e.id)
     from public.events e where e.topic_id=t.id),'[]'::jsonb)) order by t.id)
 into v_topics from public.topics t where t.id=any(p_topic_ids);
 if coalesce(jsonb_array_length(v_topics),0) <> cardinality(p_topic_ids) then raise exception 'Unknown topic ID'; end if;
 select * into v_state from public.topic_enrichment_state where scope_key=v_key;
 return jsonb_build_object('scope_key',v_key,'topics',v_topics,'source_hash',md5(v_topics::text),
   'saved_hash',v_state.source_hash,'publication_version',coalesce(v_state.version,0),
   'saved_model_version',v_state.model_version);
end $$;

create or replace function public.publish_topic_enrichment(
 p_topic_ids bigint[], p_source_hash text, p_publication_version bigint,
 p_model_version text, p_topics jsonb, p_relations jsonb)
returns jsonb language plpgsql security invoker set search_path = '' as $$
declare s jsonb; r jsonb; a bigint; b bigint; n int; ids bigint[]; ev text; current_topic jsonb;
begin
 -- Short publish-only locks: inference runs outside the transaction.
 lock table public.topics in share row exclusive mode;
 lock table public.events in share mode;
 lock table public.topic_enrichment_state in share row exclusive mode;
 s:=public.topic_enrichment_snapshot(p_topic_ids);
 if s->>'source_hash' is distinct from p_source_hash or
    (s->>'publication_version')::bigint is distinct from p_publication_version then
   raise exception 'STALE_SNAPSHOT: inputs or publication changed; regenerate';
 end if;
 if p_model_version is null or length(p_model_version) not between 1 and 500 or
    jsonb_typeof(p_topics) is distinct from 'array' or jsonb_array_length(p_topics)<>cardinality(p_topic_ids) or
    jsonb_typeof(p_relations) is distinct from 'array' then raise exception 'Invalid output shape'; end if;
 select array_agg((x->>'id')::bigint) into ids from jsonb_array_elements(p_topics) x;
 if (select count(distinct x) from unnest(ids) x)<>cardinality(p_topic_ids) or not ids <@ p_topic_ids then raise exception 'Topic IDs mismatch'; end if;
 for r in select * from jsonb_array_elements(p_topics) loop
   a:=(r->>'id')::bigint;
   if jsonb_typeof(r->'summary') is distinct from 'string' or length(r->>'summary')>1200 or
      jsonb_typeof(r->'keywords') is distinct from 'array' or jsonb_array_length(r->'keywords')>5 or
      exists(select 1 from jsonb_array_elements(r->'keywords') x where jsonb_typeof(x)<>'string' or length(x#>>'{}') not between 1 and 30) then raise exception 'Invalid summary/keywords'; end if;
   select x into current_topic from jsonb_array_elements(s->'topics') x where x->>'id'=a::text;
   if jsonb_array_length(current_topic->'events')=0 then
     if r->>'summary'<>'' or r->'keywords'<>'[]'::jsonb then raise exception 'Empty topic must be cleared'; end if;
   elsif length(trim(r->>'summary'))=0 or jsonb_array_length(r->'keywords')=0 then raise exception 'Missing generated content'; end if;
 end loop;
 for r in select * from jsonb_array_elements(p_relations) loop
   a:=(r->>'topic_id')::bigint; b:=(r->>'related_topic_id')::bigint;
   if a is null or b is null or a>=b or not a=any(p_topic_ids) or not b=any(p_topic_ids) or
      length(trim(coalesce(r->>'reason',''))) not between 1 and 500 or
      jsonb_typeof(r->'source_event_ids') is distinct from 'array' or jsonb_typeof(r->'target_event_ids') is distinct from 'array' or
      jsonb_array_length(r->'source_event_ids')=0 or jsonb_array_length(r->'target_event_ids')=0 then raise exception 'Invalid relation'; end if;
   for ev in select jsonb_array_elements_text(r->'source_event_ids') loop
     if not exists(select 1 from public.events where id=ev::bigint and topic_id=a) then raise exception 'Invalid source evidence'; end if;
   end loop;
   for ev in select jsonb_array_elements_text(r->'target_event_ids') loop
     if not exists(select 1 from public.events where id=ev::bigint and topic_id=b) then raise exception 'Invalid target evidence'; end if;
   end loop;
 end loop;
 for r in select * from jsonb_array_elements(p_topics) loop
   update public.topics set summary=r->>'summary', keywords=array(select jsonb_array_elements_text(r->'keywords')),
     ai_generated_at=now() where id=(r->>'id')::bigint;
 end loop;
 -- Only this configured topic scope is replaced. Both directions share one row.
 delete from public.topic_relations where topic_id=any(p_topic_ids) and related_topic_id=any(p_topic_ids);
 for r in select * from jsonb_array_elements(p_relations) loop
   insert into public.topic_relations(topic_id,related_topic_id,reason,evidence)
   values((r->>'topic_id')::bigint,(r->>'related_topic_id')::bigint,r->>'reason',
     jsonb_build_object('source_event_ids',r->'source_event_ids','target_event_ids',r->'target_event_ids'));
 end loop;
 insert into public.topic_enrichment_state(scope_key,source_hash,version,model_version)
 values(s->>'scope_key',p_source_hash,p_publication_version+1,p_model_version)
 on conflict(scope_key) do update set source_hash=excluded.source_hash,version=excluded.version,
   model_version=excluded.model_version,generated_at=now();
 return jsonb_build_object('saved',true,'version',p_publication_version+1,'topic_count',cardinality(p_topic_ids),'relation_count',jsonb_array_length(p_relations));
end $$;
revoke all on function public.topic_enrichment_snapshot(bigint[]) from public,anon,authenticated;
revoke all on function public.publish_topic_enrichment(bigint[],text,bigint,text,jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.topic_enrichment_snapshot(bigint[]) to service_role;
grant execute on function public.publish_topic_enrichment(bigint[],text,bigint,text,jsonb,jsonb) to service_role;

create or replace function public.get_topic_enrichment(p_topic_id bigint)
returns jsonb language sql stable security invoker set search_path = '' as $$
 select jsonb_build_object('topic_id',t.id::text,'keywords',t.keywords,'summary',t.summary,'generated_at',t.ai_generated_at,
   'related_topics',coalesce((select jsonb_agg(jsonb_build_object('id',other.id::text,'title',other.title,
     'summary',other.summary,'category',other.category,'reason',r.reason) order by other.id)
     from public.topic_relations r join public.topics other on other.id=case when r.topic_id=t.id then r.related_topic_id else r.topic_id end
     where r.topic_id=t.id or r.related_topic_id=t.id),'[]'::jsonb))
 from public.topics t where t.id=p_topic_id;
$$;
revoke all on function public.get_topic_enrichment(bigint) from public;
grant execute on function public.get_topic_enrichment(bigint) to anon,authenticated,service_role;
commit;
