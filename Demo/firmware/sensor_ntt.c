/* Demo path: one ARM program captures sensor data then submits it to PL.
 * Host is only the independent comparison step; it does not replay CSV input.
 */
#define main capture_sensor
#include "sensor.c"
#undef main
volatile uint32_t ntt_actual[1024], packed_input[1024];
volatile uint32_t intt_actual[1024];
#ifdef QUALITY_GATE
volatile uint32_t quality_approved;
__attribute__((noinline)) void quality_ready(void) {__asm__ volatile("nop":::"memory");}
#endif
int main(void) {
    capture_sensor();
    if (result[0]!=0x600D || result[5]!=SAMPLE_LIMIT) return 1;
#ifdef QUALITY_GATE
    quality_ready(); /* Host breakpoint: no NTT register accessed yet. */
    if(quality_approved!=1){result[0]=0x7000;return 0;}
#endif
    result[0]=0x200;
    volatile uint32_t *const ntt=(void*)0xA0000000UL;
    for(unsigned b=0;b<4;b++) {
        for(unsigned i=0;i<256;i++) {
            unsigned sample=RAW_CAPACITY-256+b*64+i/4, channel=(i%4)/2;
            unsigned shift=(i%2)*9;
            uint32_t coeff=(raw[sample][channel]>>shift)&511;
            packed_input[b*256+i]=coeff;
            ntt[256+i]=coeff;
            __asm__ volatile("dsb sy":::"memory");
        }
        for(unsigned i=0;i<256;i++) {
            if(ntt[256+i]!=packed_input[b*256+i]) {
                result[0]=0xBADA;result[3]=b*256+i;return 1;
            }
        }
        ntt[2]=1;ntt[0]=1;
        __asm__ volatile("dsb sy":::"memory");
        unsigned timeout=10000000;
        while(!(ntt[1]&2) && --timeout) {}
        if(!timeout){result[0]=0xBADB;result[3]=b;return 1;}
        for(unsigned i=0;i<256;i++) ntt_actual[b*256+i]=ntt[256+i];
        ntt[2]=1;
        __asm__ volatile("dsb sy":::"memory");
        ntt[0]=3; /* start, inverse mode; operate on the actual PL NTT output */
        __asm__ volatile("dsb sy":::"memory");
        timeout=10000000;
        while(!(ntt[1]&2) && --timeout) {}
        if(!timeout){result[0]=0xBADC;result[3]=b;return 1;}
        for(unsigned i=0;i<256;i++) intt_actual[b*256+i]=ntt[256+i];
        result[6]=b+1;
    }
    __asm__ volatile("dsb sy":::"memory");
    result[0]=0x600D;
    return 0;
}
