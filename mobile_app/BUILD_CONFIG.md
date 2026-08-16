# Pips-Miner build configuration

Build the release APK with the deployed backend URL:

flutter build apk --release --dart-define=PIPSMINER_BACKEND_URL=https://YOUR-DEPLOYED-BACKEND.example

Never put METAAPI_TOKEN or any MetaApi master credential in the APK or GitHub.

The APK asks for MT5 account number, MT5 trading password and broker MT5 server.
The protected backend looks up the existing account under the administrator
MetaApi account, reuses its MetaApi account ID, verifies deployment/connection,
and returns a signed Pips-Miner session.

Subscriptions are intentionally not part of this release.
