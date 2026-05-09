EAS Cloud Build (Android) - Quick Instructions

1. Create an Expo/EAS token:
   - Install EAS CLI locally: `npm install -g eas-cli`
   - Login: `eas login`
   - Create a token: `eas token:create -n my-ci-token` and copy the token value.

2. Add the token to GitHub secrets:
   - Go to your repository Settings → Secrets → Actions → New repository secret
   - Name: `EXPO_TOKEN`
   - Value: paste the token

3. Trigger the workflow:
   - Push to `main` or `master`, or go to Actions → EAS Build Android → Run workflow (workflow_dispatch).

4. After the workflow runs:
   - The workflow uploads `frontend/build.json` metadata as an artifact.
   - Open the artifact to find the build ID and links to the Expo build page where you can download the APK.

Notes
- If EAS needs Android signing keys, the build may prompt to generate or request credentials; using `--non-interactive` will let EAS manage keys automatically when possible.
- For private keystore or custom signing, manage credentials in the Expo dashboard or use `eas credentials` CLI.

- Triggered build: 2026-05-09T15:38:28+02:00
