#include "TVTLS.h"
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <netdb.h>
#include <sys/time.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include "mbedtls/ssl.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/pk.h"
#include "mbedtls/rsa.h"
#include "mbedtls/bignum.h"
#include "mbedtls/error.h"
#include "mbedtls/platform_time.h"

/* iOS 6 has no clock_gettime(), so mbedTLS is built with MBEDTLS_PLATFORM_MS_TIME_ALT */
mbedtls_ms_time_t mbedtls_ms_time(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (mbedtls_ms_time_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
}

struct TVConn {
    int fd;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context drbg;
    mbedtls_x509_crt cert;
    mbedtls_pk_context key;
};

static void strerr(int r, const char *what, char *err, size_t errLen) {
    char msg[160];
    mbedtls_strerror(r, msg, sizeof msg);
    snprintf(err, errLen, "%s: %s (-0x%04x)", what, msg, (unsigned)-r);
}

/* ---------- identity ---------- */

int tv_identity_generate(const char *commonName, char *certPem, size_t certLen, char *keyPem, size_t keyLen, char *err, size_t errLen) {
    mbedtls_entropy_context entropy; mbedtls_ctr_drbg_context drbg;
    mbedtls_pk_context key; mbedtls_x509write_cert crt; mbedtls_mpi serial;
    mbedtls_entropy_init(&entropy); mbedtls_ctr_drbg_init(&drbg); mbedtls_pk_init(&key); mbedtls_x509write_crt_init(&crt); mbedtls_mpi_init(&serial);
    int r;
    char subject[200];
    snprintf(subject, sizeof subject, "CN=%s", commonName);
    if ((r = mbedtls_ctr_drbg_seed(&drbg, mbedtls_entropy_func, &entropy, (const unsigned char *)"tvremote", 8)) != 0) { strerr(r, "random", err, errLen); goto done; }
    if ((r = mbedtls_pk_setup(&key, mbedtls_pk_info_from_type(MBEDTLS_PK_RSA))) != 0) { strerr(r, "key setup", err, errLen); goto done; }
    if ((r = mbedtls_rsa_gen_key(mbedtls_pk_rsa(key), mbedtls_ctr_drbg_random, &drbg, 2048, 65537)) != 0) { strerr(r, "key generation", err, errLen); goto done; }
    mbedtls_x509write_crt_set_version(&crt, MBEDTLS_X509_CRT_VERSION_3);
    mbedtls_x509write_crt_set_md_alg(&crt, MBEDTLS_MD_SHA256);
    mbedtls_x509write_crt_set_subject_key(&crt, &key);
    mbedtls_x509write_crt_set_issuer_key(&crt, &key);
    if ((r = mbedtls_x509write_crt_set_subject_name(&crt, subject)) != 0 || (r = mbedtls_x509write_crt_set_issuer_name(&crt, subject)) != 0) { strerr(r, "subject", err, errLen); goto done; }
    mbedtls_mpi_lset(&serial, 1000);
    unsigned char sbuf[8]; mbedtls_mpi_write_binary(&serial, sbuf, 2);
    if ((r = mbedtls_x509write_crt_set_serial_raw(&crt, sbuf, 2)) != 0) { strerr(r, "serial", err, errLen); goto done; }
    /* fixed dates: the phone's clock may be off, and the TV does not look at them */
    if ((r = mbedtls_x509write_crt_set_validity(&crt, "20200101000000", "20491231235959")) != 0) { strerr(r, "validity", err, errLen); goto done; }
    if ((r = mbedtls_x509write_crt_set_basic_constraints(&crt, 1, 0)) != 0) { strerr(r, "constraints", err, errLen); goto done; }
    if ((r = mbedtls_x509write_crt_pem(&crt, (unsigned char *)certPem, certLen, mbedtls_ctr_drbg_random, &drbg)) != 0) { strerr(r, "certificate", err, errLen); goto done; }
    if ((r = mbedtls_pk_write_key_pem(&key, (unsigned char *)keyPem, keyLen)) != 0) { strerr(r, "key export", err, errLen); goto done; }
    r = 0;
done:
    mbedtls_mpi_free(&serial); mbedtls_x509write_crt_free(&crt); mbedtls_pk_free(&key);
    mbedtls_ctr_drbg_free(&drbg); mbedtls_entropy_free(&entropy);
    return r;
}

static int rsa_parts(const mbedtls_pk_context *pk, unsigned char *mod, size_t *modLen, unsigned char *exp, size_t *expLen) {
    if (mbedtls_pk_get_type(pk) != MBEDTLS_PK_RSA) return -1;
    mbedtls_mpi N, E; mbedtls_mpi_init(&N); mbedtls_mpi_init(&E);
    int r = mbedtls_rsa_export(mbedtls_pk_rsa(*pk), &N, NULL, NULL, NULL, &E);
    if (r == 0) {
        size_t n = mbedtls_mpi_size(&N), e = mbedtls_mpi_size(&E);
        if (n > *modLen || e > *expLen) r = -1;
        else { mbedtls_mpi_write_binary(&N, mod, n); mbedtls_mpi_write_binary(&E, exp, e); *modLen = n; *expLen = e; }
    }
    mbedtls_mpi_free(&N); mbedtls_mpi_free(&E);
    return r;
}

int tv_cert_rsa(const char *certPem, unsigned char *mod, size_t *modLen, unsigned char *exp, size_t *expLen) {
    mbedtls_x509_crt crt; mbedtls_x509_crt_init(&crt);
    int r = mbedtls_x509_crt_parse(&crt, (const unsigned char *)certPem, strlen(certPem) + 1);
    if (r == 0) r = rsa_parts(&crt.pk, mod, modLen, exp, expLen);
    mbedtls_x509_crt_free(&crt);
    return r;
}

int tv_tls_peer_rsa(TVConn *c, unsigned char *mod, size_t *modLen, unsigned char *exp, size_t *expLen) {
    const mbedtls_x509_crt *crt = mbedtls_ssl_get_peer_cert(&c->ssl);
    if (!crt) return -1;
    return rsa_parts(&crt->pk, mod, modLen, exp, expLen);
}

/* ---------- connection ---------- */

static int net_send(void *ctx, const unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
    ssize_t n = send(fd, buf, len, 0);
    if (n >= 0) return (int)n;
    if (errno == EINTR) return MBEDTLS_ERR_SSL_WANT_WRITE;
    if (errno == EAGAIN || errno == EWOULDBLOCK) return MBEDTLS_ERR_SSL_TIMEOUT;
    return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
}

static int net_recv(void *ctx, unsigned char *buf, size_t len) {
    int fd = *(int *)ctx;
    ssize_t n = recv(fd, buf, len, 0);
    if (n >= 0) return (int)n;
    if (errno == EINTR) return MBEDTLS_ERR_SSL_WANT_READ;
    if (errno == EAGAIN || errno == EWOULDBLOCK) return MBEDTLS_ERR_SSL_TIMEOUT;
    return MBEDTLS_ERR_SSL_INTERNAL_ERROR;
}

static int tcp_connect(const char *host, int port, int timeout, char *err, size_t errLen) {
    char portStr[16];
    snprintf(portStr, sizeof portStr, "%d", port);
    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof hints);
    hints.ai_family = AF_UNSPEC;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, portStr, &hints, &res) != 0 || !res) { snprintf(err, errLen, "cannot resolve %s", host); return -1; }
    int fd = -1, lastErr = 0;
    for (struct addrinfo *a = res; a; a = a->ai_next) {
        fd = socket(a->ai_family, a->ai_socktype, a->ai_protocol);
        if (fd < 0) { lastErr = errno; continue; }
        int one = 1;
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, sizeof one);
        setsockopt(fd, IPPROTO_TCP, 1 /* TCP_NODELAY */, &one, sizeof one);
        fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK);
        int r = connect(fd, a->ai_addr, a->ai_addrlen);
        if (r < 0 && errno == EINPROGRESS) {
            fd_set w; FD_ZERO(&w); FD_SET(fd, &w);
            struct timeval tv = { timeout, 0 };
            if (select(fd + 1, NULL, &w, NULL, &tv) > 0) {
                int soerr = 0; socklen_t sl = sizeof soerr;
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &sl);
                r = soerr ? -1 : 0; if (soerr) lastErr = soerr;
            } else { r = -1; lastErr = ETIMEDOUT; }
        } else if (r < 0) lastErr = errno;
        if (r == 0) {
            fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) & ~O_NONBLOCK);
            struct timeval tv = { timeout, 0 };
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof tv);
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof tv);
            break;
        }
        close(fd); fd = -1;
    }
    freeaddrinfo(res);
    if (fd < 0) snprintf(err, errLen, "cannot connect to %s:%d (errno %d)", host, port, lastErr);
    return fd;
}

TVConn *tv_tls_open(const char *host, int port, int timeout, const char *certPem, const char *keyPem, char *err, size_t errLen) {
    TVConn *c = calloc(1, sizeof *c);
    if (!c) return NULL;
    c->fd = -1;
    mbedtls_ssl_init(&c->ssl); mbedtls_ssl_config_init(&c->conf);
    mbedtls_entropy_init(&c->entropy); mbedtls_ctr_drbg_init(&c->drbg);
    mbedtls_x509_crt_init(&c->cert); mbedtls_pk_init(&c->key);
    int r;
    if ((r = mbedtls_x509_crt_parse(&c->cert, (const unsigned char *)certPem, strlen(certPem) + 1)) != 0) { strerr(r, "certificate", err, errLen); goto fail; }
    if ((r = mbedtls_ctr_drbg_seed(&c->drbg, mbedtls_entropy_func, &c->entropy, (const unsigned char *)"tv", 2)) != 0) { strerr(r, "random", err, errLen); goto fail; }
    if ((r = mbedtls_pk_parse_key(&c->key, (const unsigned char *)keyPem, strlen(keyPem) + 1, NULL, 0, mbedtls_ctr_drbg_random, &c->drbg)) != 0) { strerr(r, "key", err, errLen); goto fail; }
    c->fd = tcp_connect(host, port, timeout, err, errLen);
    if (c->fd < 0) goto fail;
    if ((r = mbedtls_ssl_config_defaults(&c->conf, MBEDTLS_SSL_IS_CLIENT, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT)) != 0) { strerr(r, "TLS config", err, errLen); goto fail; }
    mbedtls_ssl_conf_rng(&c->conf, mbedtls_ctr_drbg_random, &c->drbg);
    mbedtls_ssl_conf_authmode(&c->conf, MBEDTLS_SSL_VERIFY_NONE);
    mbedtls_ssl_conf_max_tls_version(&c->conf, MBEDTLS_SSL_VERSION_TLS1_2);
    if ((r = mbedtls_ssl_conf_own_cert(&c->conf, &c->cert, &c->key)) != 0) { strerr(r, "client identity", err, errLen); goto fail; }
    if ((r = mbedtls_ssl_setup(&c->ssl, &c->conf)) != 0) { strerr(r, "TLS setup", err, errLen); goto fail; }
    mbedtls_ssl_set_bio(&c->ssl, &c->fd, net_send, net_recv, NULL);
    while ((r = mbedtls_ssl_handshake(&c->ssl)) != 0) {
        if (r != MBEDTLS_ERR_SSL_WANT_READ && r != MBEDTLS_ERR_SSL_WANT_WRITE) { strerr(r, "TLS handshake", err, errLen); goto fail; }
    }
    return c;
fail:
    tv_tls_close(c);
    return NULL;
}

int tv_tls_read(TVConn *c, unsigned char *buf, size_t len) {
    for (;;) {
        int r = mbedtls_ssl_read(&c->ssl, buf, len);
        if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (r == MBEDTLS_ERR_SSL_TIMEOUT) return -2;
        if (r == MBEDTLS_ERR_SSL_PEER_CLOSE_NOTIFY || r == MBEDTLS_ERR_SSL_CONN_EOF || r == MBEDTLS_ERR_SSL_INTERNAL_ERROR) return 0;
        return r;
    }
}

int tv_tls_write(TVConn *c, const unsigned char *buf, size_t len) {
    size_t done = 0;
    while (done < len) {
        int r = mbedtls_ssl_write(&c->ssl, buf + done, len - done);
        if (r == MBEDTLS_ERR_SSL_WANT_READ || r == MBEDTLS_ERR_SSL_WANT_WRITE) continue;
        if (r < 0) return r;
        done += (size_t)r;
    }
    return 0;
}

void tv_tls_cancel(TVConn *c) { if (c && c->fd >= 0) shutdown(c->fd, SHUT_RDWR); }

void tv_tls_close(TVConn *c) {
    if (!c) return;
    if (c->fd >= 0) { mbedtls_ssl_close_notify(&c->ssl); close(c->fd); }
    mbedtls_ssl_free(&c->ssl); mbedtls_ssl_config_free(&c->conf);
    mbedtls_ctr_drbg_free(&c->drbg); mbedtls_entropy_free(&c->entropy);
    mbedtls_x509_crt_free(&c->cert); mbedtls_pk_free(&c->key);
    free(c);
}
