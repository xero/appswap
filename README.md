# appswap

> [!NOTE]
> appswap is a macOS menu bar app that switches apps on Option+Tab. It lists running apps the way Command+Tab does, gives every open Finder window its own entry, and leaves Finder out when it has nothing open.

---

## Status

appswap is under construction and doesn't switch anything yet. The repository holds the package skeleton, the build and signing scripts, and CI. There are no releases to download.

It targets macOS 15 and later on Apple silicon.

---

## Building

You need Xcode 27. There's no Xcode project; the app is a Swift package plus one bundling script.

```sh
swift test
scripts/bundle.sh
scripts/run.sh
```

`scripts/bundle.sh` builds `dist/appswap.app`, signs it, and checks the result. With no settings it makes a throwaway build with an ad hoc signature. macOS ties the Accessibility permission to the signature, so an ad hoc build loses its grant every time you rebuild.

Run `scripts/cert.sh` once to fix that. It makes a self-signed certificate in a keychain file of its own and writes a `.env` that points the bundle script at it. Your login keychain stays untouched.

Always run the bundle, never `swift run`. Only the bundle has the Info.plist and the signature that macOS judges the app by.

---

## License

[MIT](./LICENSE)
