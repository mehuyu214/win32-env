#include <stdio.h>
#include <cpuid.h>
int main() {
    unsigned int a, b, c, d;
    __get_cpuid(1, &a, &b, &c, &d);
    printf("SSE=%d SSE2=%d SSSE3=%d SSE41=%d AVX=%d\n",
        !!(d & bit_SSE), !!(d & bit_SSE2), !!(c & bit_SSSE3), !!(c & bit_SSE4_1), !!(c & bit_AVX));
    __get_cpuid(0, &a, &b, &c, &d);
    printf("maxleaf=%u vendor=%.12s\n", a, (char*)&b);
    return 0;
}
