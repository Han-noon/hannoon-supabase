-- 사건/기사 핵심 내용 및 임베딩 원문 저장
ALTER TABLE "public"."events"
  ADD COLUMN core_content text,
  ADD COLUMN embedding_text text;

ALTER TABLE "public"."articles"
  ADD COLUMN core_content text;
