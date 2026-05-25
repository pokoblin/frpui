# frpui

A lightweight macOS menu bar client for [frp](https://github.com/fatedier/frp)'s `frpc`.

frpui is a thin SwiftUI shell that lives in the menu bar and manages the bundled
`frpc` process for you — start/stop the tunnel, edit the configuration, view logs,
and have it launch at login. The actual tunneling is done entirely by `frpc` from
the upstream [fatedier/frp](https://github.com/fatedier/frp) project.

## Features

- **Menu bar only** — no Dock icon (`LSUIElement`). A single status item with a small menu.
- **Start / Stop service** — one click toggles `frpc`. A small status dot shows state:
  yellow while starting/connecting, green once a proxy is successfully established.
- **Settings**
  - **Appearance** — System (default) / Light / Dark.
  - **Start service on launch** — auto-start the tunnel when the app opens.
  - **Launch at login** — register the app as a login item via `SMAppService`.
  - **Configuration editor** — edit `frpc.toml` directly from the app.
  - **Log tab** — read-only live output from `frpc`.
- **Quit** — also stops the `frpc` process.

The editable configuration lives at
`~/Library/Application Support/frpui/frpc.toml`. On first run it is seeded from the
bundled `cli/frpc.toml`, and `frpc` is launched with `-c` pointing at this copy.

## Requirements

- macOS 14.0 or later
- [Xcode](https://developer.apple.com/xcode/) 15 or later
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — the Xcode project is generated, not committed

## The `frpc` binary (not included)

The `frpc` executable is **not** committed to this repository. Before building, download
the `frpc` binary that matches your Mac's architecture from the official frp releases and
place it at `cli/frpc`:

1. Go to the frp releases page: <https://github.com/fatedier/frp/releases>
2. Download the macOS archive for your CPU:
   - Apple Silicon (M1/M2/M3…): `frp_<version>_darwin_arm64.tar.gz`
   - Intel: `frp_<version>_darwin_amd64.tar.gz`
3. Extract it and copy the `frpc` executable into this project's `cli/` directory:

   ```sh
   tar -xzf frp_<version>_darwin_arm64.tar.gz
   cp frp_<version>_darwin_arm64/frpc cli/frpc
   chmod +x cli/frpc
   ```

A sample `cli/frpc.toml` is included as a starting point — edit it (or edit the config
from the app's Settings) to point at your own frp server.

> The `cli/frpc` and `cli/frpc.toml` files are copied into the app bundle at build time,
> so they are picked up fresh on every build.

## Build & run

### Development build (ad-hoc signed)

No signing configuration needed — good for running locally.

```sh
xcodegen generate
xcodebuild -project frpui.xcodeproj -scheme frpui -configuration Debug build
```

Or simply open `frpui.xcodeproj` in Xcode (after `xcodegen generate`) and press Run.

### Signed release build

`build.sh` builds and code-signs the app with a certificate from your local keychain,
then copies the result to `dist/frpui.app`.

1. Create your local signing configuration from the template:

   ```sh
   cp build_config.toml.example build_config.toml
   ```

2. List your available signing identities and put the one you want into
   `build_config.toml`:

   ```sh
   security find-identity -v -p codesigning
   ```

   ```toml
   signing_identity = "Developer ID Application: Your Name (TEAMID1234)"
   team_id = "TEAMID1234"
   configuration = "Release"
   ```

3. Build:

   ```sh
   ./build.sh
   ```

   The signed app is written to `dist/frpui.app`. The first signing may trigger a
   keychain "Allow" prompt.

`build_config.toml` contains your personal signing details and is git-ignored — only the
`build_config.toml.example` template is committed.

## Credits

frpui is only a UI wrapper. All the heavy lifting is done by **frp**:
<https://github.com/fatedier/frp>. Please refer to the frp project for tunneling
documentation, configuration reference, and licensing of the `frpc` binary.
