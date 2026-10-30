# Architecture

TV Remote is a plain UIKit app with no storyboards and no image assets besides the icon and launch images. The code falls into three layers.

## Networking (no UIKit)

    TVTLS.c  ->  TVLink  ->  TVPairing   (port 6467, once per TV)
                         ->  TVRemote    (port 6466, the live session)
    TVProto  (protobuf + key codes)      TVStore (identity, TV list)      TVDiscovery (finding TVs)

- **`TVTLS.c`** wraps Mbed TLS: a TLS 1.2 client that presents our client certificate, does not verify the TV's (self-signed) certificate, and has socket timeouts
  (a read that times out returns -2 so callers can tell it from an error). It also generates the RSA-2048 key and the self-signed client certificate, and extracts
  the RSA modulus/exponent of both certificates, which the pairing secret needs. `mbedtls_ms_time()` is provided here because iOS 6 has no `clock_gettime()`.
- **`TVLink`** is one TLS connection. A reader thread (a global queue) takes complete length-prefixed frames off the stream and delivers them on the main queue
  (`onMessage`, `onClose`). `send:` may be called from the main queue; writes are queued. `close` only shuts the socket down; the reader's exit handler frees the
  connection after any queued writes, which avoids a use-after-free between close and a write in flight.
- **`TVPairing`** is the pairing state machine (request, options, configuration, secret) with callbacks `onNeedCode`, `onBadCode`, `onDone`, `onFailed`.
  A code whose check byte is wrong is rejected locally (`onBadCode`) and the pairing stays open.
- **`TVRemote`** is a singleton for the live session: states Idle / Connecting / Ready / Failed, the TV's name from its `configure` message, the app in front, volume,
  power state, and an "unpaired" flag when the TV rejects the identity. It answers pings, sends keys (`sendKey:`, `holdKey:down:`) and app links, reconnects after four
  seconds, and posts `TVRemoteChanged`.
- **`TVProto`** is just enough protobuf (varint, bytes, string, nested messages; a parser that maps field numbers to values) plus the Android key code constants.
- **`TVStore`** keeps the client identity PEMs, the TV list (name, host `ip[:remotePort]`, paired flag), the current host and the page number in `NSUserDefaults`,
  and generates the identity on a background thread when it is missing.
- **`TVDiscovery`** combines Bonjour (`_androidtvremote2._tcp.`) with a sweep of the Wi-Fi /24 for an open port 6466 (24 concurrent probes, run on a background queue).

`docs/PROTOCOL.md` describes the messages.

## UI

- **`TVStyle`** draws everything procedurally with Core Graphics: a walnut wood image (grain lines on a gradient), the black glossy-plastic faceplate with a bevel, brass screws
  and a soft radial sheen, and the primitives the controls use (keys, circle keys, wells, engraved text, glyphs). The wood and the faceplate are rendered once and cached as images.
  `TVHaptic()` plays a short vibration through `AudioServicesPlaySystemSoundWithVibration` (looked up with `dlsym`; the iPhone 5 has no Taptic Engine), falling back
  to the plain vibrate sound.
- **`TVControls`** holds the widgets. `TVPad` is the base class: it fires on touch-down rather than on release (a remote has to feel immediate) and can repeat while held.
  `TVKeyButton`, `TVDPad`, `TVRocker`, `TVStatusPlate`, `TVTouchpad` (30-point swipe steps become arrow keys; a tap is OK; a two-finger tap is Back) and `TVPageSwitch`
  (the full-width tab bar) build on it. Each key goes through `TVPress(code)`, which posts `TVNotConnected` when the key could not be sent so the status plate can say so.
- **`TVMainController`** lays out the wooden body (a 288 x 500 faceplate), the shared header (status plate and power key) and the five pages. The page is remembered in the preferences.
- **`TVDevicesSheet`** is the "Your TVs" panel that replaces the faceplate while it is open, and owns the pairing UI. **`TVPrompt`** is an in-app prompt view used instead of
  `UIAlertView`, because some jailbreak tweaks on the target device hide alert views.

## Threading

UI and `TVRemote`/`TVPairing` state live on the main queue. The only other threads are: the `TVLink` reader, the key generation in `TVStore`, and the discovery sweep.
Everything they report is dispatched back to the main queue before it touches state or views.

## Simulator build

`build.sh sim` compiles with `-DTV_PREVIEW`. That enables the environment hooks listed in the README (connect to a mock, pick a page, start pairing, enter the code automatically)
so screens can be reached and photographed without tapping. Nothing under `TV_PREVIEW` is compiled into the device build.
