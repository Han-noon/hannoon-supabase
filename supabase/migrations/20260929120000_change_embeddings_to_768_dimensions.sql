-- 임베딩 모델을 로컬 ko-sRoBERTa(jhgan/ko-sroberta-multitask, 768차원)로 전환한다.
-- 4096차원(Upstage solar-embedding) 벡터는 768차원 모델과 호환되지 않는다.
-- 타입 변경 중 저장된 임베딩을 비우고, 마이그레이션 후 재생성한다.
ALTER TABLE "public"."articles"
  ALTER COLUMN embedding TYPE "extensions".vector(768)
  USING NULL::"extensions".vector(768);

ALTER TABLE "public"."events"
  ALTER COLUMN embedding TYPE "extensions".vector(768)
  USING NULL::"extensions".vector(768);

ALTER TABLE "public"."topic_causes"
  ALTER COLUMN cause_embedding TYPE "extensions".vector(768)
  USING NULL::"extensions".vector(768);
