# Syncra Cloud Functions — API-key proxy

Two HTTPS functions hold the third-party keys server-side so the Flutter client
never ships them:

| Function | Proxies | Secret |
| --- | --- | --- |
| `anthropicProxy` | `POST api.anthropic.com/v1/messages` | `ANTHROPIC_API_KEY` |
| `jsearchProxy` | `GET jsearch.p.rapidapi.com/search` | `RAPIDAPI_KEY` |

Each verifies the caller's Firebase ID token before injecting the key, so only
signed-in app users can use them.

## One-time deploy

```bash
# 0. Upgrade the Firebase project to the Blaze (pay-as-you-go) plan in the
#    console — Cloud Functions will not deploy on Spark.

# 1. Install deps
cd functions && npm install && cd ..

# 2. Store the secrets (you paste each key ONCE; it goes to Secret Manager,
#    never into code or git). Use freshly rotated keys.
firebase functions:secrets:set ANTHROPIC_API_KEY
firebase functions:secrets:set RAPIDAPI_KEY

# 3. Deploy
firebase deploy --only functions
```

After deploy the functions live at:

- `https://us-central1-syncra-signlogin.cloudfunctions.net/anthropicProxy`
- `https://us-central1-syncra-signlogin.cloudfunctions.net/jsearchProxy`

which is the default `SyncraProxy.base` the app already points at.

## Running the app

```bash
flutter run          # no --dart-define keys needed
```

To rotate a key later: `firebase functions:secrets:set <NAME>` then
`firebase deploy --only functions` (a redeploy picks up the new secret version).

To run the app fully offline against mock data: `flutter run --dart-define=SYNCRA_USE_MOCKS=true`.
