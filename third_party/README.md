# third_party

## mbedtls/

[Mbed TLS](https://github.com/Mbed-TLS/mbedtls) **3.6.4** (`MBEDTLS_VERSION_STRING` in `include/mbedtls/build_info.h`), the unmodified `include/` and
`library/` directories plus the upstream `LICENSE`. Tests, programs, docs and build-system files are left out; nothing here is edited.
`./build.sh` compiles every `library/*.c` file, and `tests/run.sh` does the same natively on the Mac.

Mbed TLS is dual-licensed Apache-2.0 OR GPL-2.0-or-later; this project uses it under Apache-2.0 (see `../THIRD_PARTY_NOTICES.md`).

### hn_mbedtls_config.h

The build selects this file with `-DMBEDTLS_CONFIG_FILE='"hn_mbedtls_config.h"'`. The name is historical: it was written for an earlier app
(HN Reader) and the same file is shared by the sibling apps, so it keeps its name. It is the stock 3.6.4 `mbedtls_config.h` with these changes:

| Change | Why |
| --- | --- |
| `MBEDTLS_PLATFORM_MS_TIME_ALT` enabled | iOS 6 has no `clock_gettime()`; `src/TVTLS.c` provides `mbedtls_ms_time()` with `gettimeofday()` |
| `MBEDTLS_FS_IO`, `MBEDTLS_NET_C`, `MBEDTLS_TIMING_C` disabled | the app does its own sockets and keeps keys in memory, not in files |
| TLS 1.3, DTLS, session tickets, session cache, cookies, ticket and server-side TLS (`MBEDTLS_SSL_SRV_C`) disabled | smaller binary; the app is a TLS 1.2 client only (it caps the connection at TLS 1.2) |
| `MBEDTLS_PSA_CRYPTO_STORAGE_C`, `MBEDTLS_PSA_ITS_FILE_C` disabled | no persistent PSA key storage |

Everything the app needs stays enabled: RSA-2048 key generation, X.509 certificate writing (the self-signed client certificate), PEM parsing and
TLS 1.2 client. To see the exact difference run
`diff mbedtls/include/mbedtls/mbedtls_config.h hn_mbedtls_config.h`.

### Updating

1. Replace `mbedtls/include` and `mbedtls/library` with the same directories from a new release tarball (keep `LICENSE`).
2. Diff the new stock `mbedtls_config.h` against `hn_mbedtls_config.h`, carry the changes in the table over into a fresh copy of the new stock file.
3. `./build.sh sim`, `./build.sh device` and `tests/run.sh`.
