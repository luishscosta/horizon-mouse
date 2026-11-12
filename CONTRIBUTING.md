# Contributing

Thanks for your interest in Horizon Mouse. Issues and pull requests are welcome.

## Reporting a problem

Open an issue with:

- your macOS and Horizon Mouse versions (shown in the app's Settings footer);
- your mouse model and how it is connected (Bluetooth, receiver, cable);
- what you expected, what happened, and steps to reproduce;
- the output of `"/Applications/Horizon Mouse.app/Contents/MacOS/HorizonMouse" --diagnose` and, for button problems, the log from `log stream --predicate 'subsystem == "io.github.luishscosta.horizonmouse"'`.

First check that no other mouse remapper is running: they compete for the same events.

## Submitting a change

1. Fork the repo and branch from `main` (`feat/…`, `fix/…`, `docs/…`).
2. Build and test with the Command Line Tools:

   ```sh
   bash scripts/test.sh
   bash scripts/build.sh
   ```

   Without a certificate the build is signed ad-hoc, and macOS asks for Accessibility again after every build. To avoid that on your Mac, create a self-signed code-signing certificate in Keychain Access and pass its name in `HORIZON_SIGN_IDENTITY`. Published releases are signed with the maintainer's "Mac Mouse Desk Self-Signed" certificate.

   `scripts/test.sh` must pass: it runs the behavior checks, validates the plists, and requires a translation in every language for every new UI string.
3. UI strings are written in English as `L("English text")`. Add the same key to every `Resources/*.lproj/Localizable.strings`.
4. Test your change on hardware (desktop switching, gestures, trackpad untouched) and describe the test in the pull request.
5. Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages (`feat:`, `fix:`, `docs:`…).

Keep changes small and focused. The app must not gain telemetry, accounts, servers or external dependencies.

## Releases

Releases are automatic. A pull request that raises `CFBundleShortVersionString` (and `CFBundleVersion`) in `Resources/Info.plist` and moves the `[Unreleased]` notes of `CHANGELOG.md` to the new version publishes that version when it is merged: the `Release` workflow tests, builds with the maintainer's signing certificate, creates the `vX.Y.Z` tag and GitHub release with the dmg, zip and checksums, and updates the Homebrew tap. It needs the repository secrets `HORIZON_SIGN_CERT_P12` (base64 `.p12` of the certificate), `HORIZON_SIGN_CERT_PASSWORD` and, for the tap, `TAP_GITHUB_TOKEN`.

## License

By contributing, you agree that your contribution is licensed under the project's [MIT license](LICENSE).
