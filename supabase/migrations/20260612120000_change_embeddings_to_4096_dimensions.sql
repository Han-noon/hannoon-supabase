-- 768-dimensional embeddings are incompatible with the new 4096-dimensional model.
-- Clear stored embeddings during the type change; regenerate them after this migration.
ALTER TABLE "public"."articles"
  ALTER COLUMN embedding TYPE "extensions".vector(4096)
  USING NULL::"extensions".vector(4096);

ALTER TABLE "public"."events"
  ALTER COLUMN embedding TYPE "extensions".vector(4096)
  USING NULL::"extensions".vector(4096);

ALTER TABLE "public"."topic_causes"
  ALTER COLUMN cause_embedding TYPE "extensions".vector(4096)
  USING NULL::"extensions".vector(4096);
