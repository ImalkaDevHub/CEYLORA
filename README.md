# CEYLORA

[![CI](https://github.com/ImalkaDevHub/CEYLORA/actions/workflows/ci.yml/badge.svg)](https://github.com/ImalkaDevHub/CEYLORA/actions/workflows/ci.yml)

Premium AI-powered travel & lifestyle experiences platform for Sri Lanka.

## Tech Stack
- Backend: ASP.NET Core Web API (C#), Clean Architecture (Api/Application/Domain/Infrastructure)
- Database: PostgreSQL, hosted on Supabase (Session Pooler connection)
- Web: React (Vite) + Redux Toolkit
- Mobile: Flutter + Provider
- Agentic AI: LangGraph (planned)

## Prerequisites
- .NET 10 SDK
- Node.js 24 (LTS)
- Flutter SDK
- A Supabase project (or any PostgreSQL instance)

## Environment Variables / Secrets Required
Set these via `dotnet user-secrets` in `src/CEYLORA.Api` — do not commit actual values:
- `ConnectionStrings:DefaultConnection` — PostgreSQL connection string (Supabase Session Pooler recommended for IPv4 networks; Direct connection is IPv6-only)
- `Jwt:Key` — JWT signing secret
- `Jwt:Issuer` — JWT issuer name
- `Jwt:Audience` — JWT audience name

For the React app, copy `web/.env.example` to `web/.env` and set:
- `VITE_API_BASE_URL` — your running API's base URL

## Setup
1. Clone the repo
2. Backend: `cd src/CEYLORA.Api && dotnet user-secrets init` then set the secrets above
3. Apply migrations: `dotnet ef database update --project src/CEYLORA.Infrastructure --startup-project src/CEYLORA.Api`
4. Run API: `dotnet run --project src/CEYLORA.Api`
5. Frontend: `cd web && npm install && npm run dev`

### Optional demo data
An empty database has nothing to browse or book. To fill it with sample destinations, stays and
120 nights of room inventory, enable the seeder once (it only ever fills an empty accommodation table
and never changes existing rows):
```bash
dotnet user-secrets set "Seed:DemoData" "true" --project src/CEYLORA.Api
```

## Testing and CI
Every part has its own tests, and none of them needs a database or the AI service:

| Part | Command (run from the repo root) | Tests |
|---|---|---|
| Backend (.NET) | `dotnet test CEYLORA.slnx` | xUnit on an in-memory provider and in-memory SQLite (real transactions and constraints) |
| Web (React) | `cd web && npm ci && npm run lint && npm test && npm run build` | Vitest + Testing Library |
| Mobile (Flutter) | `cd mobile && flutter pub get && flutter analyze && flutter test` | unit and widget tests with a fake API |

GitHub Actions (`.github/workflows/ci.yml`) runs the same commands on every push and pull request to
`main` and `dev` as three independent jobs (`backend`, `web`, `mobile`), plus a final **CI passed** job
that succeeds only when all three do: make that the required check for merging.

## Notes on Supabase
This project uses Supabase's **Session Pooler** connection (not the direct connection), since Supabase's direct host is IPv6-only and unreachable on many networks. The pooler is IPv4-proxied and free.
