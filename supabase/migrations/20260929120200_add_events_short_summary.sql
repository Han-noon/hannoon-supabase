-- 이벤트 짧은 명사형 요약(예: "의대 정원 2,000명 확대 공식화").
-- 토픽 분류 진입 시 이벤트 요약 롤업과 같은 호출에서 채운다. 롤업 전 이벤트는 NULL.
ALTER TABLE public.events ADD COLUMN IF NOT EXISTS short_summary text;
