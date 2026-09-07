/* Freestanding A53 test. Cache/MMU disabled by entry.S; results read via JTAG.
 * 0x600D = all comparisons passed, 0xBAD1 = RAM, 0xBAD2 = timeout,
 * 0xBAD3 = NTT mismatch. This tests PS/PL only, not the sensor.
 */
#include <stdint.h>
#include "vectors.h"
volatile uint32_t result[8];
static volatile uint32_t *const ntt = (void *)0xA0000000UL;
static void barrier(void) { __asm__ volatile("dsb sy" ::: "memory"); }
int main(void) {
    result[0] = 0x1234;
    for (unsigned c=0;c<3;c++) {
        result[1]=c;
        ntt[2]=1;
        for (unsigned i=0;i<256;i++) { ntt[256+i]=inputs[c][i]; barrier(); }
        for (unsigned i=0;i<256;i++) {
            uint32_t v=ntt[256+i];
            if(v!=inputs[c][i]) { result[0]=0xBAD1;result[2]=i;result[3]=v;result[4]=inputs[c][i];return 1; }
        }
        ntt[0]=1; barrier();
        unsigned timeout=10000000;
        while (!(ntt[1]&2) && --timeout) {}
        if (!timeout) {result[0]=0xBAD2;return 1;}
        for (unsigned i=0;i<256;i++) {
            uint32_t v=ntt[256+i];
            if(v!=expected[c][i]) {result[0]=0xBAD3;result[2]=i;result[3]=v;result[4]=expected[c][i];return 1;}
            result[5]++;
        }
    }
    result[0]=0x600D;barrier();return 0;
}
