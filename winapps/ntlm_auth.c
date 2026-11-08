/* ntlm_auth (WinApps) — substituto mínimo do ntlm_auth do Samba para o Wine no macOS.
 *
 * O msv1_0 do Wine delega o NTLM ao programa externo "ntlm_auth" (protocolos de helper
 * ntlmssp-client-1 e squid-2.5-ntlmssp). No Mac ele não existe, então qualquer autenticação
 * Windows integrada falha — p.ex. o Power BI conectando no Analysis Services local
 * ("Authentication failed."). Este helper só autentica processos do MESMO usuário do Mac:
 * a resposta do cliente é HMAC-MD5(segredo, desafio || nonce), com o segredo num arquivo
 * 0600 em ~/Library/Application Support/WinApps (ou $WINAPPS_NTLM_KEY). Sem acesso ao
 * segredo (p.ex. cliente remoto) a autenticação é recusada. A chave de sessão é derivada do
 * mesmo segredo, então assinatura/criptografia NTLM2 do Wine funcionam dos dois lados.
 *
 * Compilar: clang -O2 -arch arm64 -arch x86_64 -o ntlm_auth ntlm_auth.c */
#include <CommonCrypto/CommonHMAC.h>
#include <errno.h>
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#define FLAGS 0xa0088235u /* UNICODE|REQUEST_TARGET|SIGN|SEAL|NTLM|ALWAYS_SIGN|NTLM2|128|56 */
#define MAX 8192

static unsigned char secret[32], challenge[8], nonce[8], session_key[16];
static unsigned int flags = FLAGS;
static int have_session, have_secret;

static const char b64[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static void enc64(const unsigned char *in, size_t n, char *out)
{
    size_t i; char *o = out;
    for (i = 0; i + 2 < n; i += 3)
    {
        *o++ = b64[in[i] >> 2]; *o++ = b64[((in[i] & 3) << 4) | (in[i + 1] >> 4)];
        *o++ = b64[((in[i + 1] & 15) << 2) | (in[i + 2] >> 6)]; *o++ = b64[in[i + 2] & 63];
    }
    if (n - i == 1) { *o++ = b64[in[i] >> 2]; *o++ = b64[(in[i] & 3) << 4]; *o++ = '='; *o++ = '='; }
    else if (n - i == 2)
    {
        *o++ = b64[in[i] >> 2]; *o++ = b64[((in[i] & 3) << 4) | (in[i + 1] >> 4)];
        *o++ = b64[(in[i + 1] & 15) << 2]; *o++ = '=';
    }
    *o = 0;
}

static size_t dec64(const char *in, unsigned char *out, size_t max)
{
    unsigned int acc = 0; int bits = 0; size_t n = 0; const char *p;
    for (; *in && *in != '='; in++)
    {
        if (!(p = strchr(b64, *in))) continue;
        acc = (acc << 6) | (unsigned int)(p - b64); bits += 6;
        if (bits >= 8) { bits -= 8; if (n < max) out[n++] = (acc >> bits) & 0xff; }
    }
    return n;
}

static void put16(unsigned char *p, unsigned int v) { p[0] = v; p[1] = v >> 8; }
static void put32(unsigned char *p, unsigned int v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static unsigned int get16(const unsigned char *p) { return p[0] | p[1] << 8; }
static unsigned int get32(const unsigned char *p) { return p[0] | p[1] << 8 | p[2] << 16 | (unsigned int)p[3] << 24; }

static void mac(const char *label, unsigned char out[16])
{
    CCHmacContext c;
    CCHmacInit(&c, kCCHmacAlgMD5, secret, sizeof(secret));
    CCHmacUpdate(&c, label, strlen(label));
    CCHmacUpdate(&c, challenge, 8);
    CCHmacUpdate(&c, nonce, 8);
    CCHmacFinal(&c, out);
}

static int load_secret(void)
{
    char path[1024]; const char *env = getenv("WINAPPS_NTLM_KEY"), *home = getenv("HOME");
    int fd, tries;
    if (env) snprintf(path, sizeof(path), "%s", env);
    else if (home) snprintf(path, sizeof(path), "%s/Library/Application Support/WinApps/ntlm-local.key", home);
    else return -1;
    for (tries = 0; tries < 50; tries++)
    {
        if ((fd = open(path, O_RDONLY)) >= 0)
        {
            struct stat st;
            ssize_t r = read(fd, secret, sizeof(secret));
            int ok = !fstat(fd, &st) && st.st_uid == getuid() && !(st.st_mode & 077) && r == sizeof(secret);
            close(fd);
            if (ok) return 0;
            if (r < (ssize_t)sizeof(secret)) { usleep(20000); continue; } /* outro processo criando */
            return -1; /* dono/permissões errados: recusar */
        }
        if ((fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600)) >= 0)
        {
            arc4random_buf(secret, sizeof(secret));
            if (write(fd, secret, sizeof(secret)) != sizeof(secret)) { close(fd); unlink(path); return -1; }
            close(fd);
            return 0;
        }
        if (errno != EEXIST) return -1;
    }
    return -1;
}

static void reply_b64(const char *tag, const unsigned char *bin, size_t n)
{
    static char out[MAX * 2];
    enc64(bin, n, out);
    printf("%s %s\n", tag, out);
}

static size_t negotiate_msg(unsigned char *m)
{
    memset(m, 0, 40);
    memcpy(m, "NTLMSSP", 8); put32(m + 8, 1); put32(m + 12, FLAGS);
    put32(m + 20, 40); put32(m + 28, 40);
    return 40;
}

static size_t challenge_msg(const unsigned char *neg, size_t neg_len, unsigned char *m)
{
    unsigned int f = FLAGS;
    if (neg_len >= 16 && !memcmp(neg, "NTLMSSP", 8) && get32(neg + 8) == 1) f &= get32(neg + 12) | 0x00008001u;
    flags = f;
    arc4random_buf(challenge, 8);
    memset(m, 0, 56);
    memcpy(m, "NTLMSSP", 8); put32(m + 8, 2);
    put32(m + 16, 56); put32(m + 20, f);
    memcpy(m + 24, challenge, 8);
    put32(m + 44, 56);
    have_session = 0;
    return 56;
}

static size_t authenticate_msg(const unsigned char *chal, size_t len, unsigned char *m)
{
    const char *user = getenv("USER") ? getenv("USER") : "user";
    size_t ulen = strlen(user), i, off = 88;
    unsigned char resp[16];
    if (len < 32 || memcmp(chal, "NTLMSSP", 8) || get32(chal + 8) != 2) return 0;
    flags = get32(chal + 20);
    memcpy(challenge, chal + 24, 8);
    arc4random_buf(nonce, 8);
    mac("WinApps-NTLM-resp", resp);
    mac("WinApps-NTLM-key", session_key);
    have_session = 1;
    memset(m, 0, off);
    memcpy(m, "NTLMSSP", 8); put32(m + 8, 3);
    put16(m + 12, 0); put16(m + 14, 0); put32(m + 16, off);           /* LM: vazio */
    put16(m + 20, 24); put16(m + 22, 24); put32(m + 24, off);         /* NT: mac || nonce */
    memcpy(m + off, resp, 16); memcpy(m + off + 16, nonce, 8); off += 24;
    put16(m + 28, 0); put16(m + 30, 0); put32(m + 32, off);           /* domínio: vazio */
    put16(m + 36, ulen * 2); put16(m + 38, ulen * 2); put32(m + 40, off);
    for (i = 0; i < ulen && off + 2 < MAX; i++) { m[off++] = user[i]; m[off++] = 0; }
    put16(m + 44, 0); put16(m + 46, 0); put32(m + 48, off);           /* estação: vazio */
    put32(m + 52, 0); put32(m + 56, off);                              /* chave de sessão cifrada: vazia */
    put32(m + 60, flags);
    return off;
}

static int verify_authenticate(const unsigned char *m, size_t len)
{
    unsigned int nt_len, nt_off;
    unsigned char expect[16];
    if (len < 64 || memcmp(m, "NTLMSSP", 8) || get32(m + 8) != 3) return 0;
    nt_len = get16(m + 20); nt_off = get32(m + 24);
    if (nt_len != 24 || nt_off + 24 > len) return 0;
    memcpy(nonce, m + nt_off + 16, 8);
    mac("WinApps-NTLM-resp", expect);
    if (memcmp(expect, m + nt_off, 16)) return 0;  /* (sem tempo constante: só uso local) */
    mac("WinApps-NTLM-key", session_key);
    have_session = 1;
    return 1;
}

int main(int argc, char **argv)
{
    static char line[MAX * 2];
    static unsigned char bin[MAX], out[MAX];
    int server = 0, i;
    size_t n;

    for (i = 1; i < argc; i++)
    {
        if (!strcmp(argv[i], "--helper-protocol=squid-2.5-ntlmssp")) server = 1;
        else if (!strcmp(argv[i], "--version")) { puts("Version 4.0.0-WinApps"); return 0; }
    }
    if (load_secret()) fprintf(stderr, "ntlm_auth (WinApps): sem segredo local; recusando\n");
    else have_secret = 1;
    setvbuf(stdout, NULL, _IOLBF, 0);

    while (fgets(line, sizeof(line), stdin))
    {
        line[strcspn(line, "\r\n")] = 0;
        if (!strncmp(line, "SF", 2) || !strncmp(line, "PW", 2)) { puts("OK"); continue; }
        if (!strcmp(line, "GF")) { printf("GF %x\n", flags); continue; }
        if (!strcmp(line, "GK"))
        {
            if (have_session) reply_b64("GK", session_key, 16); else puts("BH no key");
            continue;
        }
        if (!server)
        {
            if (!strncmp(line, "YR", 2)) { n = negotiate_msg(out); flags = FLAGS; have_session = 0; reply_b64("YR", out, n); }
            else if (!strncmp(line, "TT ", 3))
            {
                n = dec64(line + 3, bin, sizeof(bin));
                if (have_secret && (n = authenticate_msg(bin, n, out))) reply_b64("KK", out, n); else puts("BH bad challenge");
            }
            else puts("BH unknown command");
        }
        else
        {
            if (!strncmp(line, "YR", 2))
            {
                n = line[2] == ' ' ? dec64(line + 3, bin, sizeof(bin)) : 0;
                n = challenge_msg(bin, n, out);
                reply_b64("TT", out, n);
            }
            else if (!strncmp(line, "KK ", 3))
            {
                n = dec64(line + 3, bin, sizeof(bin));
                if (have_secret && verify_authenticate(bin, n))
                {
                    const char *user = getenv("USER") ? getenv("USER") : "user";
                    printf("AF %s\n", user);
                }
                else puts("NA NT_STATUS_LOGON_FAILURE");
            }
            else puts("BH unknown command");
        }
    }
    return 0;
}
