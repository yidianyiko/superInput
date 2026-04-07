# Install On Another Mac

## Fastest path for your own Macs

0. On the source Mac, create the local signing identity once:

```bash
cd /Users/lixingting/Desktop/StartUp/Code
./Scripts/create_local_signing_identity.sh
```

1. On the source Mac, build a zip:

```bash
cd /Users/lixingting/Desktop/StartUp/Code
./Scripts/package_release.sh
```

2. Copy the generated zip from `release/` to the other Mac.
3. Unzip it.
4. Move `SlashVibe.app` into `/Applications` or `~/Applications`.
5. Launch it.

## If macOS blocks the app

Because this app is locally self-signed and not notarized with an Apple Developer certificate, Gatekeeper may warn on another Mac.

Try this first:

1. Right-click the app.
2. Click `Open`.
3. Confirm `Open` again in the system dialog.

If needed, go to:

- `System Settings > Privacy & Security`
- scroll to the bottom
- allow the blocked app to open

## First-run permissions

For the current feature set, the other Mac will need to allow:

- `Microphone`
- `Accessibility`
- `Input Monitoring` in some cases for global keyboard capture

## Deepgram key

The API key is stored per Mac in Keychain.

That means:

- moving the `.app` does not move the saved key
- each Mac should enter its own Deepgram key on first use

## Best production path later

For a smoother install on any Mac, the next milestone is:

1. Sign with `Developer ID Application`
2. Notarize with Apple
3. Distribute the notarized `.app` or `.zip`

That removes most Gatekeeper friction.
