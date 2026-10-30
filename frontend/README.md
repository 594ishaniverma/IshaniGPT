# IshaniGPT frontend

A Flutter client for the IshaniGPT API.

## Configure

The API base URL defaults to `http://127.0.0.1:8000`. Override it at build or run time:

```sh
flutter run -d chrome --dart-define=API_BASE_URL=https://api.example.com
```

Tokens are stored in secure platform storage. Authenticated API requests use `Authorization: Bearer $_accessToken` and expired sessions are cleared on `401 Unauthorized` responses.

## API behavior and deployment

HTTP requests have a 30-second default timeout (configurable through `ChatApi`) and support cancellation via `CancellationToken`. The chat screen uses the backend's Server-Sent Events endpoint at `/conversations/{threadId}/messages/stream`, so assistant text is displayed as it arrives.

For a deployed frontend, build with the public HTTPS API origin, not `localhost`:

```sh
flutter build web --release --dart-define=API_BASE_URL=https://api.example.com
```

Deploy the generated `build/web` directory to a static host. Configure `FRONTEND_ORIGINS` on the API to include the exact frontend origin, and allow the streaming endpoint through any reverse proxy without buffering. Serve both frontend and API over HTTPS.

The current backend does not expose paginated conversation or message endpoints; clients therefore use the existing full-list methods until pagination is added server-side.

## Develop

```sh
flutter pub get
flutter analyze
flutter test
flutter build web --release
flutter run
```

Android, desktop, and API-host configuration may require a reachable LAN address rather than `127.0.0.1` (Android emulator loopback is the emulator, not the host machine).
