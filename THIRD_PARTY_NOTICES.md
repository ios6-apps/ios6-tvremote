# Third-party notices

TV Remote itself is MIT licensed (see `LICENSE`). It includes or uses the following.

## Included in the repository and in the app

**Mbed TLS 3.6.4**, `third_party/mbedtls/` and `third_party/hn_mbedtls_config.h` (a build configuration derived from Mbed TLS's stock
`mbedtls_config.h`).
Copyright The Mbed TLS Contributors. Dual-licensed Apache-2.0 OR GPL-2.0-or-later; this project uses it under the Apache License 2.0.
The full text of both licences is in `third_party/mbedtls/LICENSE`. Source: <https://github.com/Mbed-TLS/mbedtls>.

## Used only for development and tests, not included

**androidtvremote2** (<https://github.com/tronikos/androidtvremote2>), Apache-2.0. `tools/mock_tv.py` imports its generated protobuf definitions
(`polo_pb2`, `remotemessage_pb2`) and `docs/PROTOCOL.md` credits it as the reference for the protocol. It is installed from PyPI by `tests/run.sh`
into `build/venv`; its code is not copied into this repository.

**pyOpenSSL** and **cryptography** (Apache-2.0 / BSD), installed from PyPI by `tests/run.sh` for the mock TV's TLS.

## Not redistributed

**iOS 9.3 SDK stubs.** `./build.sh device` needs them to link for armv7. They are Apple's and are subject to the Xcode and Apple SDKs Agreement,
so `tools/setup-sdk.sh` downloads the public copy from <https://github.com/theos/sdks> (scripts MIT) at build time; they are never committed.

## Trademarks

Android, Android TV, Google TV, Google Play and YouTube are trademarks of Google LLC; TCL, Netflix, Prime Video, Disney+, Kodi, Spotify and
Twitch are trademarks of their respective owners. They appear only to describe what the app can talk to or launch. This project is not
affiliated with or endorsed by any of them.
