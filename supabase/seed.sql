INSERT INTO public.topics (category, title, summary) VALUES
  ('정치', '22대 총선', '2024년 4월 10일 실시된 제22대 국회의원 선거에 관한 이슈'),
  ('경제', '기준금리 인상', '한국은행 기준금리 인상 결정 및 시장 반응'),
  ('사회', '의대 정원 확대', '정부의 의과대학 입학 정원 확대 정책 및 의료계 반발'),
  ('국제', '미중 정상회담', '미국과 중국 정상 간 회담 및 외교·경제 현안 논의');

INSERT INTO public.events (topic_id, category, title, summary, article_count) VALUES
  ((SELECT id FROM public.topics WHERE title = '22대 총선'), '정치', '여당 과반 확보', '여당이 단독 과반 의석을 확보하며 압승', 5),
  ((SELECT id FROM public.topics WHERE title = '22대 총선'), '정치', '야당 의석 대폭 감소', '제1야당 의석이 전 대비 크게 줄어', 3),
  ((SELECT id FROM public.topics WHERE title = '22대 총선'), '정치', '역대 최고 투표율', '이번 총선 투표율이 역대 최고치 기록', 4),
  ((SELECT id FROM public.topics WHERE title = '22대 총선'), '정치', '주요 당선자 입장', '각 당 주요 당선자 인터뷰 및 향후 계획', 2),
  ((SELECT id FROM public.topics WHERE title = '기준금리 인상'), '경제', '금리 0.25%p 인상 결정', '한국은행 금융통화위원회 기준금리 0.25%p 인상', 6),
  ((SELECT id FROM public.topics WHERE title = '기준금리 인상'), '경제', '주식·부동산 시장 반응', '금리 인상 발표 후 증시 하락 및 부동산 관망세', 4),
  ((SELECT id FROM public.topics WHERE title = '의대 정원 확대'), '사회', '의료계 집단 휴진 예고', '전국 의사협회 집단 휴진 및 파업 예고 성명 발표', 7),
  ((SELECT id FROM public.topics WHERE title = '의대 정원 확대'), '사회', '정부 협상 테이블 제안', '보건복지부 의료계 대표와 협의체 구성 제안', 3),
  ((SELECT id FROM public.topics WHERE title = '의대 정원 확대'), '사회', '의대생 수업 거부', '전국 의과대학 학생들 수업 거부 동참', 5),
  ((SELECT id FROM public.topics WHERE title = '미중 정상회담'), '국제', '공급망 안정 협의', '양국이 핵심 산업 공급망 안정과 수출 통제 완화 방안을 논의', 4),
  ((SELECT id FROM public.topics WHERE title = '미중 정상회담'), '국제', '기후 협력 재개', '기후 변화 대응을 위한 실무 협의체 재가동에 합의', 3),
  ((SELECT id FROM public.topics WHERE title = '미중 정상회담'), '국제', '안보 현안 입장차', '대만과 남중국해 등 안보 현안을 두고 양측 입장차가 지속', 5);

-- articles: 여당 과반 확보 (5건 - 진보 2, 중도 2, 보수 1)
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.example.com/hani', 1001, 'https://www.hani.co.kr/arti/politics/1001', '정치', '여당, 과반 의석 확보…야권 충격', '22대 총선에서 여당이 단독 과반을 넘기며 압승을 거뒀다.', 'rss', '한겨레', '2024-04-11 09:00:00', '진보', 'ready'),
  ('https://feeds.example.com/ohmynews', 1002, 'https://www.ohmynews.com/politics/1002', '정치', '총선 결과, 여당 독주 시대 개막하나', '여당의 과반 확보로 단독 입법이 가능해졌다는 분석이 나온다.', 'rss', '오마이뉴스', '2024-04-11 10:30:00', '진보', 'ready'),
  ('https://feeds.example.com/yonhap', 1003, 'https://www.yna.co.kr/politics/1003', '정치', '22대 총선 여당 과반 확보 확정', '중앙선거관리위원회는 여당이 과반 의석을 확보했다고 공식 발표했다.', 'rss', '연합뉴스', '2024-04-11 08:00:00', '중도', 'ready'),
  ('https://feeds.example.com/khan', 1004, 'https://www.khan.co.kr/politics/1004', '정치', '총선 여당 승리…여야 반응 엇갈려', '여당은 민심의 승리라 자평했고 야권은 결과를 수용하며 쇄신을 다짐했다.', 'rss', '경향신문', '2024-04-11 11:00:00', '중도', 'ready'),
  ('https://feeds.example.com/chosun', 1005, 'https://www.chosun.com/politics/1005', '정치', '여당 압승, 안정적 국정 운영 기반 마련', '여당의 과반 확보로 국정 운영에 탄력이 붙을 것이라는 전망이 나온다.', 'rss', '조선일보', '2024-04-11 12:00:00', '보수', 'ready');

-- articles: 금리 0.25%p 인상 결정 (4건 - 진보 1, 중도 2, 보수 1)
INSERT INTO public.articles (feed_url, guid, link, category, title, summary, content_source, publisher, published_at, bias_type, status) VALUES
  ('https://feeds.example.com/hani', 2001, 'https://www.hani.co.kr/arti/economy/2001', '경제', '한은 금리 인상, 서민 이자 부담 가중 우려', '기준금리 인상으로 가계 대출 이자 부담이 크게 늘어날 전망이다.', 'rss', '한겨레', '2024-01-12 10:00:00', '진보', 'ready'),
  ('https://feeds.example.com/yonhap', 2002, 'https://www.yna.co.kr/economy/2002', '경제', '한국은행, 기준금리 0.25%p 인상 결정', '한국은행 금융통화위원회가 기준금리를 연 3.50%로 인상했다.', 'rss', '연합뉴스', '2024-01-12 09:00:00', '중도', 'ready'),
  ('https://feeds.example.com/khan', 2003, 'https://www.khan.co.kr/economy/2003', '경제', '금통위 금리 인상…물가 안정 목적', '물가 안정을 위한 긴축 기조 유지 차원에서 금리 인상을 결정했다고 한은이 밝혔다.', 'rss', '경향신문', '2024-01-12 11:00:00', '중도', 'ready'),
  ('https://feeds.example.com/chosun', 2004, 'https://www.chosun.com/economy/2004', '경제', '기준금리 인상, 인플레 방어 적절한 조치', '전문가들은 이번 금리 인상이 물가 안정에 기여할 것이라고 평가했다.', 'rss', '조선일보', '2024-01-12 13:00:00', '보수', 'ready');

INSERT INTO public.event_articles (event_id, article_id) VALUES
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1001)),
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1002)),
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1003)),
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1004)),
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1005)),
  ((SELECT id FROM public.events WHERE title = '금리 0.25%p 인상 결정'), (SELECT id FROM public.articles WHERE guid = 2001)),
  ((SELECT id FROM public.events WHERE title = '금리 0.25%p 인상 결정'), (SELECT id FROM public.articles WHERE guid = 2002)),
  ((SELECT id FROM public.events WHERE title = '금리 0.25%p 인상 결정'), (SELECT id FROM public.articles WHERE guid = 2003)),
  ((SELECT id FROM public.events WHERE title = '금리 0.25%p 인상 결정'), (SELECT id FROM public.articles WHERE guid = 2004));

INSERT INTO public.abusing_articles (event_id, article_id, type) VALUES
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1001), 'title_content_mismatch'),
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1002), 'content_context_mismatch'),
  ((SELECT id FROM public.events WHERE title = '여당 과반 확보'), (SELECT id FROM public.articles WHERE guid = 1005), 'title_content_mismatch'),
  ((SELECT id FROM public.events WHERE title = '금리 0.25%p 인상 결정'), (SELECT id FROM public.articles WHERE guid = 2001), 'content_context_mismatch'),
  ((SELECT id FROM public.events WHERE title = '금리 0.25%p 인상 결정'), (SELECT id FROM public.articles WHERE guid = 2004), 'title_content_mismatch');

INSERT INTO auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
)
VALUES
  (
    '00000000-0000-0000-0000-000000000000',
    '11111111-1111-1111-1111-111111111111',
    'authenticated',
    'authenticated',
    'demo1@example.com',
    extensions.crypt('password123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"name":"Demo User 1"}'::jsonb,
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '22222222-2222-2222-2222-222222222222',
    'authenticated',
    'authenticated',
    'demo2@example.com',
    extensions.crypt('password123', extensions.gen_salt('bf')),
    now(),
    '{"provider":"email","providers":["email"]}'::jsonb,
    '{"name":"Demo User 2"}'::jsonb,
    now(),
    now()
  )
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.profiles (id, email, name)
VALUES
  ('11111111-1111-1111-1111-111111111111', 'demo1@example.com', 'Demo User 1'),
  ('22222222-2222-2222-2222-222222222222', 'demo2@example.com', 'Demo User 2')
ON CONFLICT (id) DO UPDATE
SET
  email = EXCLUDED.email,
  name = EXCLUDED.name;

WITH topic_slots AS (
  SELECT
    id,
    row_number() OVER (ORDER BY id) AS slot
  FROM public.topics
  ORDER BY id
  LIMIT 3
),
demo_subscriptions(user_id, topic_slot) AS (
  VALUES
    ('11111111-1111-1111-1111-111111111111'::uuid, 1),
    ('11111111-1111-1111-1111-111111111111'::uuid, 2),
    ('22222222-2222-2222-2222-222222222222'::uuid, 2),
    ('22222222-2222-2222-2222-222222222222'::uuid, 3)
)
INSERT INTO public.subscriptions (user_id, topic_id)
SELECT
  ds.user_id,
  ts.id
FROM demo_subscriptions ds
JOIN topic_slots ts ON ts.slot = ds.topic_slot
ON CONFLICT ON CONSTRAINT subscriptions_user_id_topic_id_key DO NOTHING;
