# Security Policy

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

Please do not open a public issue. Report it privately through [GitHub security advisories](https://github.com/luishscosta/mac-mouse-desk/security/advisories/new). Include the macOS version, the app version, and steps to reproduce. You can expect a first reply within a week.

## What the app does and does not do

- It makes no network connections and collects no data.
- It needs **Accessibility** to filter mouse events and, optionally, **Input Monitoring** to see buttons that send keyboard shortcuts. It does not record keystrokes.
- It installs no driver or kernel extension.
- The source is small; build it yourself with `bash scripts/build.sh` (see the [README](README.md#build-from-source)).

## Verifying a download

Each release attaches `SHA256SUMS.txt` with the checksums of `MacMouseDesk.zip` and `MacMouseDesk.dmg`:

```sh
shasum -a 256 -c SHA256SUMS.txt
```

Releases are signed with a self-signed certificate (not notarized). Check it with:

```sh
codesign -dv --verbose=4 "/Applications/Mac Mouse Desk.app" 2>&1 | grep -E "Identifier|Authority"
codesign -dr - "/Applications/Mac Mouse Desk.app"
```

The designated requirement must show the certificate hash `4283a9a9c50b383725bc183f25435ae86af84eb2`.
