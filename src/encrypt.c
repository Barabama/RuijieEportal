// rsa_encrypt.c
#include <stdio.h>
#include <string.h>
// #include <stdlib.h>
#include <gmp.h>

void encrypt_password(const char *secret, const char *e_hex, const char *n_hex, char *encrypted_hex)
{
    mpz_t s_int, e_int, n_int, encrypted_int;
    mpz_init(s_int);
    mpz_init(e_int);
    mpz_init(n_int);
    mpz_init(encrypted_int);

    mpz_import(s_int, strlen(secret), 1, sizeof(char), 0, 0, secret);
    // Import bytes as a big-endian integer to match Python's
    // int.from_bytes(secret.encode(), 'big'). Use explicit endian=1
    // (most-significant byte first) for portability across platforms.
    size_t secret_len = strlen(secret);
    mpz_import(s_int, secret_len, 1, sizeof(char), 1, 0, secret);
    if (mpz_set_str(e_int, e_hex, 16) == -1 || mpz_set_str(n_int, n_hex, 16) == -1)
    {
        fprintf(stderr, "Error: Failed to set exponent or modulus.\n");
        return;
    }

    mpz_powm(encrypted_int, s_int, e_int, n_int);
    // Ensure hex output is left-padded with zeros to modulus length
    size_t n_hex_len = strlen(n_hex);
    size_t mod_bytes = (n_hex_len + 1) / 2;
    size_t hex_width = mod_bytes * 2;
    char fmt[32];
    // build format like "%0<width>Zx" to pad with zeros
    snprintf(fmt, sizeof(fmt), "%%0%zuZx", hex_width);
    gmp_sprintf(encrypted_hex, fmt, encrypted_int);

    mpz_clear(s_int);
    mpz_clear(e_int);
    mpz_clear(n_int);
    mpz_clear(encrypted_int);
}

int main(int argc, char *argv[])
{
    if (argc != 4)
    {
        fprintf(stderr, "Usage: %s <secret> <rsa_e> <rsa_n>\n", argv[0]);
        return 1;
    }

    const char *secret = argv[1];
    const char *rsa_e = argv[2];
    const char *rsa_n = argv[3];

    char encrypted_hex[512];
    encrypt_password(secret, rsa_e, rsa_n, encrypted_hex);

    printf("%s\n", encrypted_hex);

    return 0;
}
