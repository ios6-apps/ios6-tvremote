/* TLS client for the Android TV remote protocol, built on mbedTLS. The TV asks for a client certificate and accepts any self-signed one,
   and its own certificate is self-signed too, so nothing is verified; the pairing code is what proves both sides saw the same keys. */
#ifndef TVTLS_H
#define TVTLS_H
#include <stddef.h>

typedef struct TVConn TVConn;

/* makes a new RSA-2048 key and a self-signed certificate; PEM strings go into the buffers (NUL terminated). Takes several seconds on old phones. */
int tv_identity_generate(const char *commonName, char *certPem, size_t certLen, char *keyPem, size_t keyLen, char *err, size_t errLen);

/* connects and handshakes with the given client identity; NULL on failure with err filled */
TVConn *tv_tls_open(const char *host, int port, int timeoutSeconds, const char *certPem, const char *keyPem, char *err, size_t errLen);
/* > 0: bytes, 0: clean end of stream, < 0: error. Honors the socket read timeout: a timeout returns -2 */
int tv_tls_read(TVConn *c, unsigned char *buf, size_t len);
int tv_tls_write(TVConn *c, const unsigned char *buf, size_t len);
void tv_tls_cancel(TVConn *c);
void tv_tls_close(TVConn *c);

/* RSA modulus and exponent as big-endian byte strings (no leading zeros); returns 0 on success */
int tv_tls_peer_rsa(TVConn *c, unsigned char *mod, size_t *modLen, unsigned char *exp, size_t *expLen);
int tv_cert_rsa(const char *certPem, unsigned char *mod, size_t *modLen, unsigned char *exp, size_t *expLen);

#endif
