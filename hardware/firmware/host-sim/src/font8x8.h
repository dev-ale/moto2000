/*
 * font8x8.h — embedded 8×8 bitmap font.
 *
 * A hand-authored, deterministic 8×8 ASCII font covering digits, letters
 * (uppercase + lowercase), space, colon, and a few punctuation glyphs —
 * the only characters the host simulator ever needs to render for Slice
 * 1.5b. Each glyph is 8 rows × 8 columns packed as one byte per row, bit
 * 7 = leftmost pixel.
 *
 * Using an embedded font instead of a real TTF keeps the simulator
 * offline, deterministic across CI runners (no freetype, no fontconfig),
 * and cheap to build.
 *
 * The glyph designs below are original and intentionally chunky so they
 * remain readable when scaled 10× for the clock screen.
 */
#ifndef HOST_SIM_FONT8X8_H
#define HOST_SIM_FONT8X8_H

#include <stdint.h>

static const uint8_t FONT8X8_SPACE[8]     = {0,    0,    0,    0,    0,    0,    0,    0};
static const uint8_t FONT8X8_COLON[8]     = {0,    0x18, 0x18, 0,    0,    0x18, 0x18, 0};
static const uint8_t FONT8X8_COMMA[8]     = {0,    0,    0,    0,    0,    0x18, 0x18, 0x30};
static const uint8_t FONT8X8_PERIOD[8]    = {0,    0,    0,    0,    0,    0,    0x18, 0x18};
static const uint8_t FONT8X8_SLASH[8]     = {0x03, 0x06, 0x0C, 0x18, 0x30, 0x60, 0xC0, 0};
static const uint8_t FONT8X8_PLUS[8]      = {0,    0x18, 0x18, 0x7E, 0x18, 0x18, 0,    0};
static const uint8_t FONT8X8_MINUS[8]     = {0,    0,    0,    0x7E, 0,    0,    0,    0};

static const uint8_t FONT8X8_0[8] = {0x3C, 0x66, 0x6E, 0x76, 0x66, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_1[8] = {0x18, 0x38, 0x18, 0x18, 0x18, 0x18, 0x7E, 0};
static const uint8_t FONT8X8_2[8] = {0x3C, 0x66, 0x06, 0x0C, 0x30, 0x60, 0x7E, 0};
static const uint8_t FONT8X8_3[8] = {0x3C, 0x66, 0x06, 0x1C, 0x06, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_4[8] = {0x0C, 0x1C, 0x3C, 0x6C, 0x7E, 0x0C, 0x0C, 0};
static const uint8_t FONT8X8_5[8] = {0x7E, 0x60, 0x7C, 0x06, 0x06, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_6[8] = {0x3C, 0x66, 0x60, 0x7C, 0x66, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_7[8] = {0x7E, 0x06, 0x0C, 0x18, 0x30, 0x30, 0x30, 0};
static const uint8_t FONT8X8_8[8] = {0x3C, 0x66, 0x66, 0x3C, 0x66, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_9[8] = {0x3C, 0x66, 0x66, 0x3E, 0x06, 0x66, 0x3C, 0};

static const uint8_t FONT8X8_A[8] = {0x3C, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0};
static const uint8_t FONT8X8_B[8] = {0x7C, 0x66, 0x66, 0x7C, 0x66, 0x66, 0x7C, 0};
static const uint8_t FONT8X8_C[8] = {0x3C, 0x66, 0x60, 0x60, 0x60, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_D[8] = {0x78, 0x6C, 0x66, 0x66, 0x66, 0x6C, 0x78, 0};
static const uint8_t FONT8X8_E[8] = {0x7E, 0x60, 0x60, 0x78, 0x60, 0x60, 0x7E, 0};
static const uint8_t FONT8X8_F[8] = {0x7E, 0x60, 0x60, 0x78, 0x60, 0x60, 0x60, 0};
static const uint8_t FONT8X8_G[8] = {0x3C, 0x66, 0x60, 0x6E, 0x66, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_H[8] = {0x66, 0x66, 0x66, 0x7E, 0x66, 0x66, 0x66, 0};
static const uint8_t FONT8X8_I[8] = {0x3C, 0x18, 0x18, 0x18, 0x18, 0x18, 0x3C, 0};
static const uint8_t FONT8X8_J[8] = {0x1E, 0x0C, 0x0C, 0x0C, 0x0C, 0x6C, 0x38, 0};
static const uint8_t FONT8X8_K[8] = {0x66, 0x6C, 0x78, 0x70, 0x78, 0x6C, 0x66, 0};
static const uint8_t FONT8X8_L[8] = {0x60, 0x60, 0x60, 0x60, 0x60, 0x60, 0x7E, 0};
static const uint8_t FONT8X8_M[8] = {0x63, 0x77, 0x7F, 0x6B, 0x63, 0x63, 0x63, 0};
static const uint8_t FONT8X8_N[8] = {0x66, 0x76, 0x7E, 0x7E, 0x6E, 0x66, 0x66, 0};
static const uint8_t FONT8X8_O[8] = {0x3C, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_P[8] = {0x7C, 0x66, 0x66, 0x7C, 0x60, 0x60, 0x60, 0};
static const uint8_t FONT8X8_Q[8] = {0x3C, 0x66, 0x66, 0x66, 0x6A, 0x6C, 0x36, 0};
static const uint8_t FONT8X8_R[8] = {0x7C, 0x66, 0x66, 0x7C, 0x78, 0x6C, 0x66, 0};
static const uint8_t FONT8X8_S[8] = {0x3C, 0x66, 0x60, 0x3C, 0x06, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_T[8] = {0x7E, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0};
static const uint8_t FONT8X8_U[8] = {0x66, 0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0};
static const uint8_t FONT8X8_V[8] = {0x66, 0x66, 0x66, 0x66, 0x66, 0x3C, 0x18, 0};
static const uint8_t FONT8X8_W[8] = {0x63, 0x63, 0x63, 0x6B, 0x7F, 0x77, 0x63, 0};
static const uint8_t FONT8X8_X[8] = {0x66, 0x66, 0x3C, 0x18, 0x3C, 0x66, 0x66, 0};
static const uint8_t FONT8X8_Y[8] = {0x66, 0x66, 0x66, 0x3C, 0x18, 0x18, 0x18, 0};
static const uint8_t FONT8X8_Z[8] = {0x7E, 0x06, 0x0C, 0x18, 0x30, 0x60, 0x7E, 0};

static const uint8_t *font8x8_glyph(char c)
{
    switch (c) {
        case ' ': return FONT8X8_SPACE;
        case ':': return FONT8X8_COLON;
        case ',': return FONT8X8_COMMA;
        case '.': return FONT8X8_PERIOD;
        case '/': return FONT8X8_SLASH;
        case '+': return FONT8X8_PLUS;
        case '-': return FONT8X8_MINUS;
        case '0': return FONT8X8_0;
        case '1': return FONT8X8_1;
        case '2': return FONT8X8_2;
        case '3': return FONT8X8_3;
        case '4': return FONT8X8_4;
        case '5': return FONT8X8_5;
        case '6': return FONT8X8_6;
        case '7': return FONT8X8_7;
        case '8': return FONT8X8_8;
        case '9': return FONT8X8_9;
        case 'A': case 'a': return FONT8X8_A;
        case 'B': case 'b': return FONT8X8_B;
        case 'C': case 'c': return FONT8X8_C;
        case 'D': case 'd': return FONT8X8_D;
        case 'E': case 'e': return FONT8X8_E;
        case 'F': case 'f': return FONT8X8_F;
        case 'G': case 'g': return FONT8X8_G;
        case 'H': case 'h': return FONT8X8_H;
        case 'I': case 'i': return FONT8X8_I;
        case 'J': case 'j': return FONT8X8_J;
        case 'K': case 'k': return FONT8X8_K;
        case 'L': case 'l': return FONT8X8_L;
        case 'M': case 'm': return FONT8X8_M;
        case 'N': case 'n': return FONT8X8_N;
        case 'O': case 'o': return FONT8X8_O;
        case 'P': case 'p': return FONT8X8_P;
        case 'Q': case 'q': return FONT8X8_Q;
        case 'R': case 'r': return FONT8X8_R;
        case 'S': case 's': return FONT8X8_S;
        case 'T': case 't': return FONT8X8_T;
        case 'U': case 'u': return FONT8X8_U;
        case 'V': case 'v': return FONT8X8_V;
        case 'W': case 'w': return FONT8X8_W;
        case 'X': case 'x': return FONT8X8_X;
        case 'Y': case 'y': return FONT8X8_Y;
        case 'Z': case 'z': return FONT8X8_Z;
        default:  return FONT8X8_SPACE;
    }
}

#endif /* HOST_SIM_FONT8X8_H */
