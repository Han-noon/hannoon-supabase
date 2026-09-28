BEGIN;
SELECT plan(20);

-- 테스트가 만든 행만 사용하고 마지막에 롤백한다.
CREATE TEMP TABLE enrichment_fixture (topic_ids bigint[], initial_snapshot jsonb, outputs jsonb, relations jsonb);
WITH inserted AS (
  INSERT INTO public.topics(category,title,summary)
  VALUES ('경제','_enrichment_a','기존 요약'),('사회','_enrichment_b','기존 요약') RETURNING id
)
INSERT INTO enrichment_fixture(topic_ids) SELECT array_agg(id ORDER BY id) FROM inserted;
INSERT INTO public.events(topic_id,category,title,summary)
SELECT topic_ids[1],'경제'::public.category,'_enrichment_event_a','첫 번째 근거' FROM enrichment_fixture
UNION ALL SELECT topic_ids[2],'사회'::public.category,'_enrichment_event_b','두 번째 근거' FROM enrichment_fixture;
UPDATE enrichment_fixture f SET
 initial_snapshot=public.topic_enrichment_snapshot(topic_ids),
 outputs=(SELECT jsonb_agg(jsonb_build_object('id',id::text,'summary','생성된 요약','keywords',jsonb_build_array('쟁점'))) FROM unnest(topic_ids) id),
 relations=jsonb_build_array(jsonb_build_object('topic_id',topic_ids[1]::text,'related_topic_id',topic_ids[2]::text,
   'reason','공통 쟁점에 대한 비교','source_event_ids',(SELECT jsonb_agg(id::text) FROM public.events WHERE topic_id=f.topic_ids[1]),
   'target_event_ids',(SELECT jsonb_agg(id::text) FROM public.events WHERE topic_id=f.topic_ids[2])));
GRANT SELECT,UPDATE ON enrichment_fixture TO service_role;

SELECT ok(NOT has_function_privilege('anon','public.topic_enrichment_snapshot(bigint[])','EXECUTE'),'anon cannot read internal snapshot');
SELECT ok(NOT has_function_privilege('authenticated','public.publish_topic_enrichment(bigint[],text,bigint,text,jsonb,jsonb)','EXECUTE'),'authenticated cannot publish');
SELECT ok(has_function_privilege('service_role','public.publish_topic_enrichment(bigint[],text,bigint,text,jsonb,jsonb)','EXECUTE'),'service role can publish');
SELECT ok(NOT has_table_privilege('anon','public.topic_enrichment_state','SELECT'),'internal state is private');
SELECT ok(NOT has_table_privilege('authenticated','public.topic_relations','INSERT'),'client cannot write relations');
SELECT is((initial_snapshot->>'publication_version')::bigint,0::bigint,'new scope version is zero') FROM enrichment_fixture;
SELECT throws_ok($$SELECT public.topic_enrichment_snapshot(ARRAY[1,1]::bigint[])$$,'P0001','Provide 1 to 10 unique topic IDs','duplicate scope rejected');

SET LOCAL ROLE service_role;
SELECT is((public.publish_topic_enrichment(topic_ids,initial_snapshot->>'source_hash',0,'test-model',outputs,relations)->>'saved')::boolean,true,'service role publishes atomically') FROM enrichment_fixture;
RESET ROLE;
SELECT is((public.get_topic_enrichment(topic_ids[1])->>'summary'),'생성된 요약','summary saved') FROM enrichment_fixture;
SELECT is(public.get_topic_enrichment(topic_ids[1])->'keywords','["쟁점"]'::jsonb,'keywords saved') FROM enrichment_fixture;
SELECT is(public.get_topic_enrichment(topic_ids[2])->'related_topics'->0->>'id',topic_ids[1]::text,'relation readable in reverse direction') FROM enrichment_fixture;
SELECT is(public.topic_enrichment_snapshot(topic_ids)->>'source_hash',initial_snapshot->>'source_hash','generated output does not change input hash') FROM enrichment_fixture;
SELECT throws_ok(format('SELECT public.publish_topic_enrichment(%L::bigint[],%L,0,%L,%L::jsonb,%L::jsonb)',topic_ids,initial_snapshot->>'source_hash','test-model',outputs,relations),
 'P0001','STALE_SNAPSHOT: inputs or publication changed; regenerate','stale publication rejected') FROM enrichment_fixture;
SELECT throws_ok(format('SELECT public.publish_topic_enrichment(%L::bigint[],%L,1,%L,%L::jsonb,%L::jsonb)',topic_ids,initial_snapshot->>'source_hash','test-model',outputs,jsonb_set(relations,'{0,source_event_ids}',relations->0->'target_event_ids')),
 'P0001','Invalid source evidence','wrong-topic evidence rejected') FROM enrichment_fixture;
SELECT is((public.topic_enrichment_snapshot(topic_ids)->>'publication_version')::bigint,1::bigint,'failed write does not advance version') FROM enrichment_fixture;
UPDATE public.events SET summary='수정된 근거' WHERE topic_id=(SELECT topic_ids[1] FROM enrichment_fixture);
SELECT isnt(public.topic_enrichment_snapshot(topic_ids)->>'source_hash',initial_snapshot->>'source_hash','event edit invalidates snapshot') FROM enrichment_fixture;
DELETE FROM public.events WHERE topic_id=(SELECT topic_ids[2] FROM enrichment_fixture);
UPDATE enrichment_fixture SET initial_snapshot=public.topic_enrichment_snapshot(topic_ids), outputs=jsonb_set(jsonb_set(outputs,'{1,summary}','""'::jsonb),'{1,keywords}','[]'::jsonb);
SELECT is((public.publish_topic_enrichment(topic_ids,initial_snapshot->>'source_hash',1,'test-model',outputs,'[]'::jsonb)->>'saved')::boolean,true,'empty topic can be cleared') FROM enrichment_fixture;
SELECT is(public.get_topic_enrichment(topic_ids[2])->>'summary','','empty summary cleared') FROM enrichment_fixture;
SELECT is(public.get_topic_enrichment(topic_ids[2])->'related_topics','[]'::jsonb,'old relations removed') FROM enrichment_fixture;
SET LOCAL ROLE anon;
SELECT lives_ok($$SELECT public.get_topic_enrichment(id) FROM public.topics WHERE title='_enrichment_a'$$,'anon can read public card');
RESET ROLE;
SELECT * FROM finish();
ROLLBACK;
