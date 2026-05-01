# hannoon-supabase

## 디렉토리 구조
 
```
hannoon-supabase/
├── .github/
│   └── workflows/
│       ├── deploy-production.yml
│       ├── deploy-staging.yml
│       └── pr-check.yml
├── supabase/
│   ├── migrations/          # 스키마 변경 이력
│   │   └── 20240101000000_init.sql
│   ├── functions/           # Edge Functions (필요시)
│   ├── seed.sql             # 개발용 시드 데이터
│   └── config.toml          # Supabase 설정
├── docs/
│   ├── schema.md            # 테이블 설계 문서
│   └── rls-policy.md        # RLS 정책 문서
├── .env.example
├── .gitignore
└── README.md
```