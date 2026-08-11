// rsa_encrypt.c - textbook RSA encryption (secret^e mod n, no padding)
// 基于 libtommath (单文件合并版 tommath.c), 替代 gmp 实现.
// 输出: 十六进制, 左补零到模长 (与旧 gmp 版本逐字节一致).
// 编译: gcc -static -O2 encrypt.c tommath.c -o encrypt
#include <ctype.h>
#include <stdio.h>
#include <string.h>
#include "tommath.h"

int encrypt_password(const char *secret, const char *e_hex, const char *n_hex, char *encrypted_hex, size_t encrypted_hex_size)
{
    mp_int s_int, e_int, n_int, c_int;
    int ret = -1;

    if (mp_init_multi(&s_int, &e_int, &n_int, &c_int, NULL) != MP_OKAY)
        return -1;

    // Import secret bytes as a big-endian integer to match Python's
    // int.from_bytes(secret.encode(), 'big').
    if (mp_from_ubin(&s_int, (const unsigned char *)secret, strlen(secret)) != MP_OKAY)
        goto cleanup;
    if (mp_read_radix(&e_int, e_hex, 16) != MP_OKAY ||
        mp_read_radix(&n_int, n_hex, 16) != MP_OKAY)
    {
        fprintf(stderr, "Error: Failed to set exponent or modulus.\n");
        goto cleanup;
    }

    // c = s^e mod n
    if (mp_exptmod(&s_int, &e_int, &n_int, &c_int) != MP_OKAY)
        goto cleanup;

    // modulus byte length from hex length
    size_t n_hex_len = strlen(n_hex);
    size_t mod_bytes = (n_hex_len + 1) / 2;
    size_t hex_width = mod_bytes * 2;
    if (hex_width + 1 > encrypted_hex_size)
    {
        fprintf(stderr, "Error: Output buffer too small.\n");
        goto cleanup;
    }

    // convert c to hex; mp_to_radix outputs UPPERCASE, 转小写与旧 gmp 版一致
    char tmp[1024];
    size_t written = 0;
    if (mp_to_radix(&c_int, tmp, sizeof(tmp), &written, 16) != MP_OKAY)
        goto cleanup;
    for (char *p = tmp; *p; p++)
        *p = (char)tolower((unsigned char)*p);

    // left-pad with zeros to modulus length
    size_t len = strlen(tmp);
    size_t pad = hex_width > len ? hex_width - len : 0;
    if (pad > 0)
    {
        memset(encrypted_hex, '0', pad);
        memcpy(encrypted_hex + pad, tmp, len + 1);  // include '\0'
    }
    else
    {
        memcpy(encrypted_hex, tmp, len + 1);
    }

    ret = 0;

cleanup:
    mp_clear_multi(&s_int, &e_int, &n_int, &c_int, NULL);
    return ret;
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
    if (encrypt_password(secret, rsa_e, rsa_n, encrypted_hex, sizeof(encrypted_hex)) != 0)
    {
        fprintf(stderr, "Error: encryption failed.\n");
        return 1;
    }

    printf("%s\n", encrypted_hex);

    return 0;
}
