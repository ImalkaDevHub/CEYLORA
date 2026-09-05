# CEYLORA

Premium AI-powered travel & lifestyle experiences platform for Sri Lanka.

## Tech Stack
- Backend: ASP.NET Core Web API (C#), Clean Architecture (Api/Application/Domain/Infrastructure)
- Database: PostgreSQL, hosted on Supabase (Session Pooler connection)
- Web: React (Vite) + Redux Toolkit
- Mobile: Flutter + Provider
- Agentic AI: LangGraph (planned)

## Prerequisites
- .NET 8 SDK
- Node.js LTS
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

## Notes on Supabase
This project uses Supabase's **Session Pooler** connection (not the direct connection), since Supabase's direct host is IPv6-only and unreachable on many networks. The pooler is IPv4-proxied and free.
