# Contributing to QuotaBar

Issues and pull requests in Chinese or English are welcome. For bugs, include the QuotaBar version, macOS version, supported Codex/ChatGPT version, reproduction steps and the displayed error. Remove credentials, account identifiers and private paths from diagnostics. Report vulnerabilities using the process in [SECURITY.md](SECURITY.md).

## Development

Use Swift 6 and Python 3. The native app, CLI and full integration tests require macOS 13 or newer and Xcode Command Line Tools. Linux supports portable checks.

```sh
./scripts/test.sh
./scripts/build-app.sh dist
open dist/QuotaBar.app
```

Tests are offline by default. `./scripts/test.sh --live` additionally queries your signed-in Codex service on macOS.

Keep shared models and clients in `Sources/QuotaBarCore`, application code in `Sources/QuotaBar`, and CLI commands in `Sources/QuotaBarCLI/Commands`. Preserve stable CLI JSON and existing data paths. Add checks for behavior changes, update relevant documentation, and keep changes focused.

See [the development guide](docs/development.md) for directory conventions, test registration and source exports, and [build and release](docs/build-and-release.md) for installable packages. Contributions remain under the [MIT license](LICENSE); retain existing copyright notices.
