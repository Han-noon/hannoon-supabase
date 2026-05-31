ALTER TABLE public.articles
  ALTER COLUMN guid TYPE text USING guid::text,
  ALTER COLUMN guid DROP NOT NULL;
