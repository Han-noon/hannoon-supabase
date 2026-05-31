ALTER TABLE public.article_jobs
  ADD CONSTRAINT article_jobs_article_id_key UNIQUE (article_id);
