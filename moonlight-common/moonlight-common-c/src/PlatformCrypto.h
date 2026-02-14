#pragma once

#include <stdbool.h>

#ifdef USE_MBEDTLS
#include <mbedtls/cipher.h>

typedef struct _PLT_CRYPTO_CONTEXT {
    mbedtls_cipher_context_t ctx;
    bool initialized;
} PLT_CRYPTO_CONTEXT, *PPLT_CRYPTO_CONTEXT;

#elif defined(__APPLE__)
#include <CommonCrypto/CommonCryptor.h>

typedef struct _PLT_CRYPTO_CONTEXT {
    CCCryptorRef cryptor;  // Used for stateful CBC only
    int algorithm;
    bool initialized;
} PLT_CRYPTO_CONTEXT, *PPLT_CRYPTO_CONTEXT;

#else
// Hide the real OpenSSL definition from other code
typedef struct evp_cipher_ctx_st EVP_CIPHER_CTX;

typedef struct _PLT_CRYPTO_CONTEXT {
    EVP_CIPHER_CTX* ctx;
    bool initialized;
} PLT_CRYPTO_CONTEXT, *PPLT_CRYPTO_CONTEXT;
#endif

#define ROUND_TO_PKCS7_PADDED_LEN(x) ((((x) + 15) / 16) * 16)

PPLT_CRYPTO_CONTEXT PltCreateCryptoContext(void);
void PltDestroyCryptoContext(PPLT_CRYPTO_CONTEXT ctx);

#define ALGORITHM_AES_CBC 1
#define ALGORITHM_AES_GCM 2

#define CIPHER_FLAG_RESET_IV          0x01
#define CIPHER_FLAG_FINISH            0x02
#define CIPHER_FLAG_PAD_TO_BLOCK_SIZE 0x04

bool PltEncryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength,
                       unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength,
                       unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength);

bool PltDecryptMessage(PPLT_CRYPTO_CONTEXT ctx, int algorithm, int flags,
                       unsigned char* key, int keyLength,
                       unsigned char* iv, int ivLength,
                       unsigned char* tag, int tagLength,
                       unsigned char* inputData, int inputDataLength,
                       unsigned char* outputData, int* outputDataLength);

void PltGenerateRandomData(unsigned char* data, int length);
