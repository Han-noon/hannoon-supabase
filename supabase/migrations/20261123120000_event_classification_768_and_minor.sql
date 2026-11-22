-- 이벤트 분류 재설계(hannoon-ai feat/event-classification-jev)에 맞춘 스키마.
--
-- 1) 임베딩을 로컬 ko-sRoBERTa(jhgan/ko-sroberta-multitask, 768차원)로 전환한다.
--    4096차원(Upstage) 벡터는 768차원 모델과 호환되지 않으므로 타입 변경 중 저장된 값을 비우고,
--    마이그레이션 후 재생성한다. 임베딩 모듈을 공유하므로 topic_causes도 함께 바꾼다.
ALTER TABLE "public"."articles"
  ALTER COLUMN embedding TYPE "extensions".vector(768)
  USING NULL::"extensions".vector(768);

ALTER TABLE "public"."events"
  ALTER COLUMN embedding TYPE "extensions".vector(768)
  USING NULL::"extensions".vector(768);

ALTER TABLE "public"."topic_causes"
  ALTER COLUMN cause_embedding TYPE "extensions".vector(768)
  USING NULL::"extensions".vector(768);

-- 2) 벡터 후보 검색(top-K ANN)은 시간창 없이 전체 기사를 대상으로 하므로 hnsw 인덱스가 필요하다.
--    (pgvector hnsw는 2000차원 이하만 지원 — 4096에서는 만들 수 없어 #41에서 뺐던 인덱스)
CREATE INDEX IF NOT EXISTS articles_embedding_hnsw
  ON "public"."articles"
  USING hnsw (embedding "extensions"."vector_cosine_ops");

-- 3) 이벤트 분류가 기사별로 추출한 부수 사건(minor) 목록을 저장한다.
ALTER TABLE "public"."articles"
  ADD COLUMN IF NOT EXISTS minor jsonb;
