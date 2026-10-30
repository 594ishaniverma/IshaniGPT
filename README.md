# IshaniGPT

IshaniGPT is a Flutter chat client backed by a FastAPI service and the existing
Gemini-powered assistant.

## Run the API

From the repository root, install the Python dependencies and start the server:

```powershell
python -m venv venv
.\venv\Scripts\Activate.ps1
pip install -r requirements.txt
uvicorn app:app --reload
```

Configure `GOOGLE_API_KEY` and `TAVILY_API_KEY` in the root `.env` file to use
the assistant and its tools. The API creates or upgrades its SQLite database at
`data/chatbot_memory.db` when it starts.

## Run the Flutter app

In another terminal:

```powershell
Set-Location frontend
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

## Production deployment

GitHub Actions runs the checks and builds in [cicd.yml](.github/workflows/cicd.yml)
on GitHub-hosted runners (`ubuntu-latest`). On every push to `main`, the workflow
publishes the API container image to GitHub Container Registry at
`ghcr.io/<owner>/<repository>/api`. It does not require a self-hosted runner.
Hosting platforms can deploy that image directly; for container hosting that
needs authentication, grant the platform read access to the package.

Production containers require explicit configuration and must not use an `.env`
file containing real credentials:

```env
ENVIRONMENT=production
GOOGLE_API_KEY=<your-key>
POSTGRES_USER=ishani
POSTGRES_PASSWORD=<generate-a-secret>
POSTGRES_DB=ishani_gpt
FRONTEND_ORIGINS=https://chat.example.com
TAVILY_API_KEY=<optional-key>
```

Start PostgreSQL and the API with Docker Compose:

```powershell
$env:GOOGLE_API_KEY = Read-Host "Google API key"
$env:POSTGRES_USER = "ishani"
$env:POSTGRES_PASSWORD = Read-Host "Postgres password"
$env:FRONTEND_ORIGINS = "https://chat.example.com"
docker compose up --build -d
curl.exe http://127.0.0.1:8000/ready
```

The Compose deployment stores PostgreSQL data, uploaded files, Chroma indexes,
and LangGraph checkpoints in named volumes. For a custom deployment, configure
`DATABASE_URL`, `SQLITE_DATABASE_PATH`, `CHECKPOINT_SQLITE_PATH`,
`CHROMA_PERSIST_DIRECTORY`, and `UPLOAD_DIR`; paths for SQLite may be absolute.
A PostgreSQL `DATABASE_URL` may use either `postgres://` or `postgresql://` and
the application normalizes it for the included psycopg driver. Run database
migrations before rolling out a new API image if Alembic migrations change.
Deploy behind HTTPS and keep credentials out of source control and container
images.

`API_BASE_URL` defaults to `http://127.0.0.1:8000`. For an Android emulator,
use `http://10.0.2.2:8000`; for a physical device, use the computer's LAN
address and make the API reachable from that device.

The app includes email/password sign-up and sign-in, secure session storage,
conversation history, and chat. Passwords are hashed by the API, and
conversations are scoped to their signed-in owner.

For a deployed web client, set `FRONTEND_ORIGINS` in the API environment to a
comma-separated list of trusted origins (for example,
`https://chat.example.com`) and serve the API over HTTPS.
