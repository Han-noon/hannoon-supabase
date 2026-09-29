-- 이벤트 분류 후보 검색: 기사 임베딩 top-K ANN과 엔티티 역색인, 두 경로로 후보 기사를 회수한다.

-- 기사별 고유명사(LLM 추출). 새 기사와 엔티티가 겹치는 기사를 찾는 회수 경로로 쓴다.
CREATE TABLE "public"."article_entities" (
  article_id bigint NOT NULL REFERENCES "public"."articles"(id),
  entity text NOT NULL
);

-- "엔티티로 기사 찾기"(회수 경로)와 "기사의 엔티티 목록 조회"(event_articles 조인) 양쪽을 지원.
CREATE INDEX IF NOT EXISTS article_entities_entity_idx
  ON "public"."article_entities" (entity);

CREATE INDEX IF NOT EXISTS article_entities_article_id_idx
  ON "public"."article_entities" (article_id);

ALTER TABLE "public"."article_entities" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "public"."article_entities" FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."article_entities" TO service_role;

-- 벡터 후보 검색(top-K ANN)은 시간창 없이 전체 기사를 대상으로 하므로 hnsw 인덱스가 필요하다.
CREATE INDEX IF NOT EXISTS articles_embedding_hnsw
  ON "public"."articles"
  USING hnsw (embedding "extensions"."vector_cosine_ops");
