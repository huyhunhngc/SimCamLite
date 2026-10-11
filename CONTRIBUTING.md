# Contributing to SimCam Lite

Thanks for helping make the iOS Simulator camera better. By taking part you agree to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).

## Reporting bugs

Open an issue with:

- your macOS, Xcode and simulator iOS versions;
- how the app was injected: every app on a simulator, **Launch**, or run from Xcode;
- what you expected and what happened, with steps to reproduce;
- the output of `simcam status` and, if relevant, logs from
  `xcrun simctl spawn booted log stream --predicate 'subsystem == "dev.ifateam.simcamlite"'`.

If the problem only happens in one app, a small sample project that reproduces it helps a lot.

## Suggesting features

Open an issue describing the camera behavior your app needs and how you would use it. Check the
[limitations](README.md#limitations) first; support for missing `AVFoundation` outputs is especially welcome.

## Pull requests

1. Fork the repository and create a branch from `master`.
2. Set up the project as described in [docs/development.md](docs/development.md).
3. Keep changes focused: one fix or feature per pull request.
4. Match the style of the surrounding code, and keep new Swift code free of compiler warnings.
5. Test with at least one real camera app on the Simulator. Describe what you tested in the pull request.
6. If you add or remove files, run `xcodegen generate` and commit the updated project.
7. Update the README or the docs when behavior or commands change.

Never commit `Config/Environment.xcconfig`, `.p8` keys or other credentials.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
