-- 이벤트 분류 후보 검색: 엔티티 역색인으로 후보 기사를 회수한다.

-- 기사별 고유명사(LLM 추출). 새 기사와 엔티티가 겹치는 기사를 찾는 회수 경로로 쓴다.
-- PK(article_id, entity)로 재추출 시 같은 행이 쌓이지 않게 하고, article_id 선두 인덱스도 겸한다.
CREATE TABLE "public"."article_entities" (
  article_id bigint NOT NULL REFERENCES "public"."articles"(id),
  entity text NOT NULL,
  PRIMARY KEY (article_id, entity)
);

-- "엔티티로 기사 찾기"(회수 경로). "기사의 엔티티 목록 조회"(event_articles 조인)는 PK 인덱스가 담당.
CREATE INDEX IF NOT EXISTS article_entities_entity_idx
  ON "public"."article_entities" (entity);

ALTER TABLE "public"."article_entities" ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE "public"."article_entities" FROM anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE "public"."article_entities" TO service_role;
