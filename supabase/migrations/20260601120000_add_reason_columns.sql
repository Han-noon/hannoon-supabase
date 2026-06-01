-- 토픽/이벤트 분류 시 LLM의 판단 근거 저장
ALTER TABLE "public"."events"
  ADD COLUMN reason text;

ALTER TABLE "public"."event_articles"
  ADD COLUMN reason text;

ALTER TABLE "public"."abusing_articles"
  ADD COLUMN reason text;
