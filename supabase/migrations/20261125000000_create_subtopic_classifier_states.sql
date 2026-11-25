BEGIN;
-- AI-internal checkpoint only; no existing data is changed.
CREATE TABLE IF NOT EXISTS public.subtopic_classifier_states (
    topic_id bigint PRIMARY KEY REFERENCES public.topics(id) ON DELETE CASCADE,
    state_version integer NOT NULL CHECK (state_version > 0),
    core_state jsonb NOT NULL CHECK (jsonb_typeof(core_state) = 'object'),
    runtime_profiles jsonb NOT NULL CHECK (jsonb_typeof(runtime_profiles) = 'array'),
    updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.subtopic_classifier_states ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.subtopic_classifier_states FROM PUBLIC, anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.subtopic_classifier_states TO service_role;
COMMIT;
