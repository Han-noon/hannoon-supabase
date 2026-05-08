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
