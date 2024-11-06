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

    if (mpz_set_str(e_int, e_hex, 16) == -1 || mpz_set_str(n_int, n_hex, 16) == -1)
    {
        fprintf(stderr, "Error: Failed to set exponent or modulus.\n");
        return;
    }

    mpz_powm(encrypted_int, s_int, e_int, n_int);
    gmp_sprintf(encrypted_hex, "%Zx", encrypted_int);

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
