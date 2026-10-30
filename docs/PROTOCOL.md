# Android TV Remote protocol v2, as implemented here

This describes what TV Remote sends and expects. It is not an official specification: Google does not publish one. The message layouts come from
[androidtvremote2](https://github.com/tronikos/androidtvremote2) (`polo.proto`, `remotemessage.proto`), which is the reference used here and whose
generated Python definitions `tools/mock_tv.py` imports. Field names below are that library's. The code that implements it is `src/TVPairing.m`,
`src/TVRemote.m`, `src/TVProto.m`, `src/TVLink.m` and `src/TVTLS.c`.

**Status:** all of this has been exercised against `tools/mock_tv.py` (built on the same definitions), not against a real TV.

## Transport

Two TCP services on the TV, both TLS:

| Port | Purpose |
| --- | --- |
| 6466 | remote control ("remote" protocol) |
| 6467 | pairing ("polo" protocol); always remote port + 1 |

The TV is also announced over Bonjour as `_androidtvremote2._tcp.`.

TLS 1.2 (the client caps the connection there) with a **client certificate**: the TV requests one and accepts any self-signed certificate. The app
generates an RSA-2048 key and a self-signed certificate (CN `tvremote-iphone`, serial 1000, SHA-256, valid 2020-01-01 to 2049-12-31, CA basic
constraint) once and reuses it; the TV remembers it after pairing. The TV's own certificate is self-signed as well, so the client does not verify it
(`MBEDTLS_SSL_VERIFY_NONE`). The pairing code is what protects against a man-in-the-middle, because it is derived from both certificates (see below).

Every message on both ports is a protobuf message prefixed with its length as a varint (`TVPBFrame`, `TVPBTakeFrames`). The reader treats an absurd
length as a protocol error and closes the connection.

## Pairing (port 6467)

All messages are `OuterMessage`:

| Field | Number | Notes |
| --- | --- | --- |
| `protocol_version` | 1 | always 2 |
| `status` | 2 | 200 OK, 400 error, 401 bad configuration, 402 bad secret |
| `pairing_request` | 10 | `{1 service_name = "atvremote", 2 client_name}` |
| `pairing_request_ack` | 11 | |
| `options` | 20 | `{1 input_encodings {1 type, 2 symbol_length}, 2 output_encodings, 3 preferred_role}` |
| `configuration` | 30 | `{1 encoding {1 type, 2 symbol_length}, 2 client_role}` |
| `configuration_ack` | 31 | |
| `secret` | 40 | `{1 secret bytes}` |
| `secret_ack` | 41 | |

Sequence (the app is the client, role INPUT = 1):

1. Client sends `pairing_request` (service `atvremote`, client name `iPhone 5`). TV answers `pairing_request_ack`.
2. Client sends `options` with one input encoding, type HEXADECIMAL (3), symbol length 6, and `preferred_role` = 1. TV answers with its own `options`.
3. Client sends `configuration` with the same encoding and `client_role` = 1. TV answers `configuration_ack` and **shows a 6-character hex code on screen**.
4. The user types the code. The client computes the secret (below) and sends `secret`.
5. TV answers `secret_ack` and remembers the client certificate. A wrong secret gets `status` 402.

### The secret

    secret = SHA-256( client modulus || client exponent || server modulus || server exponent || code bytes[1:] )

- Modulus and exponent are the RSA public numbers of the client's and the TV's certificates as big-endian byte strings without leading zeros
  (so 65537 is `01 00 01`).
- `code bytes` is the code decoded from hex (3 bytes). The **first** byte is a check byte and is not hashed; the remaining two bytes are.
- The first byte of the digest must equal the first byte of the code. The client checks this locally before sending
  (`+[TVPairing secretForCode:...]` returns nil otherwise), so a mistyped code is caught without a round trip and the pairing stays open for another try.

`tests/secret_ref.py` computes known-answer values with `hashlib`; `tests/flowtest.m` compares the Objective-C implementation against them.

## Remote (port 6466)

All messages are `RemoteMessage`, a message with exactly one of these fields set:

| Field | Number | Direction | Content |
| --- | --- | --- | --- |
| `remote_configure` | 1 | both | `{1 code1 (feature flags), 2 device_info {1 model, 2 vendor, 3 unknown1, 4 unknown2, 5 package_name, 6 app_version}}` |
| `remote_set_active` | 2 | both | `{1 active}` (feature flags) |
| `remote_error` | 3 | TV | shown to the user as a generic error |
| `remote_ping_request` | 8 | TV | `{1 val1}`; the TV pings about every 5 s |
| `remote_ping_response` | 9 | client | `{1 val1}` echoed |
| `remote_key_inject` | 10 | client | `{1 key_code, 2 direction}` |
| `remote_ime_key_inject` | 20 | TV | `{1 app_info {12 app_package}}`; tells which app is in the foreground |
| `remote_start` | 40 | TV | `{1 started}`; the TV is on and ready |
| `remote_set_volume_level` | 50 | TV | `{6 volume_max, 7 volume_level, 8 volume_muted}` |
| `remote_app_link_launch_request` | 90 | client | `{1 app_link}` |

Handshake after the TLS connection is up:

1. TV sends `remote_configure` with its `device_info` and the feature bits it supports in `code1`. The app shows `vendor + " " + model` as the TV's name.
2. Client answers `remote_configure` with `code1` = (TV's bits AND the features below) and its own `device_info` (`unknown1` 1, `unknown2` "1",
   package `atvremote`, version `1.0.0`).
3. TV sends `remote_set_active`; client answers `remote_set_active` with the features it wants.
4. TV sends `remote_start`; the session is ready. Volume and current-app messages follow.
5. Keep answering `remote_ping_request` with the same value. The app treats 20 seconds without any data as a dead connection and reconnects after 4 s.

Feature flags (`FEATURES = 1 | 2 | 4 | 32 | 64 | 512`), as in androidtvremote2's `Feature`:

| Bit | Value | Name |
| --- | --- | --- |
| 0 | 1 | PING |
| 1 | 2 | KEY |
| 2 | 4 | IME (needed to learn the current app) |
| 5 | 32 | POWER |
| 6 | 64 | VOLUME |
| 9 | 512 | APP_LINK |

### Keys

`key_code` is an Android `KeyEvent` code. `direction` is `START_LONG` = 1, `END_LONG` = 2 or `SHORT` = 3. A tap sends one `SHORT`; keys that repeat
while held send `START_LONG` on touch down and `END_LONG` on release.

| Code | Name | Code | Name |
| --- | --- | --- | --- |
| 3 | HOME | 85 | MEDIA_PLAY_PAUSE |
| 4 | BACK | 86 | MEDIA_STOP |
| 19 / 20 / 21 / 22 | DPAD_UP / DOWN / LEFT / RIGHT | 87 / 88 | MEDIA_NEXT / PREVIOUS |
| 23 | DPAD_CENTER | 89 / 90 | MEDIA_REWIND / FAST_FORWARD |
| 24 / 25 | VOLUME_UP / DOWN | 164 | MUTE |
| 26 | POWER | 165 | INFO |
| 66 | ENTER | 166 / 167 | CHANNEL_UP / DOWN |
| 67 | DEL | 172 | GUIDE |
| 82 | MENU | 176 | SETTINGS |
| 84 | SEARCH | 178 | TV_INPUT |

The colour keys (183-186, PROG_RED / GREEN / YELLOW / BLUE) are defined in `TVProto.h` but have no button.

Typing on the Keys page sends letters as key presses: `a`-`z` are codes 29-54, `0`-`9` are 7-16, plus space 62, `.` 56, `,` 55, `-` 69, `/` 76, `@` 77,
`+` 81, `=` 70, `'` 75, `;` 74, `\` 73. Text is lower-cased and stripped of diacritics first (a Turkish dotless i becomes `i`); anything else is dropped.
The protocol's text-field messages (`remote_ime_batch_edit` and friends) are not used.

### App links

`remote_app_link_launch_request` carries a URL that the TV hands to Android: web links (`https://www.youtube.com`) open in whichever app has claimed the
domain, and `market://launch?id=<package>` opens the Play Store listing or the app itself. Which links work on which TV is one of the things still
unverified; see the README.

### Not implemented

Pointer or mouse events (v2 has none), voice (`remote_voice_*`), IME batch edits, `remote_adjust_volume_level`, audio-device selection.
