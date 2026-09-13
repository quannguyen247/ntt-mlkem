/* MAX30102 acquisition used by the KV260 validation flow. */
#include <stdint.h>
#ifndef SAMPLE_LIMIT
#define SAMPLE_LIMIT 256
#endif
#ifndef RAW_CAPACITY
#define RAW_CAPACITY 256
#endif
volatile uint32_t result[8], raw[RAW_CAPACITY][2];
static volatile uint32_t *const gpio=(void*)0xA0010000UL;
static unsigned tri=3;
static int fault;
static uint64_t ticks(void){uint64_t v; __asm__ volatile("mrs %0,cntpct_el0":"=r"(v)); return v;}
static void us(unsigned n){uint64_t f;__asm__ volatile("mrs %0,cntfrq_el0":"=r"(f));uint64_t t=ticks();while(ticks()-t < f*n/1000000){} }
/* DATA remains zero: output enable pulls low; input mode releases to pull-up. */
static void line(unsigned mask,int high){tri=high?tri|mask:tri&~mask;gpio[1]=tri;__asm__ volatile("dsb sy":::"memory");us(5);}
static void scl(int high){line(1,high);if(high){unsigned n=1000;while(!(gpio[0]&1)&&--n)us(1);if(!n)fault=1;}}
static void sda(int high){line(2,high);}
static void start(void){sda(1);scl(1);sda(0);scl(0);}
static void stop(void){sda(0);scl(1);sda(1);}
static int put(unsigned v){for(int i=7;i>=0;i--){sda((v>>i)&1);scl(1);scl(0);}sda(1);scl(1);int ack=!(gpio[0]&2);scl(0);return ack&&!fault;}
static unsigned get(int ack){unsigned v=0;sda(1);for(int i=0;i<8;i++){scl(1);v=(v<<1)|!!(gpio[0]&2);scl(0);}sda(!ack);scl(1);scl(0);sda(1);return v;}
static int rd(unsigned reg,unsigned char *b,unsigned n){start();if(!put(0xae)||!put(reg)){stop();return 0;}start();if(!put(0xaf)){stop();return 0;}for(unsigned i=0;i<n;i++)b[i]=get(i+1<n);stop();return !fault;}
static int wr(unsigned reg,unsigned v){start();int ok=put(0xae)&&put(reg)&&put(v);stop();return ok;}
int main(void){
 gpio[1]=3;gpio[0]=0;us(1000);result[0]=0x100;result[1]=gpio[0]&3;
 if(result[1]!=3){result[0]=0xBAD0;return 1;}
 unsigned char b[6];
 if(!rd(0xff,b,1)){result[0]=0xBAD1;return 1;}result[2]=b[0];
 if(b[0]!=0x15){result[0]=0xBAD2;return 1;}
 if(!wr(9,0x40)){result[0]=0xBAD3;return 1;}
 unsigned n=1000;do{us(1000);if(!rd(9,b,1)){result[0]=0xBAD4;return 1;}}while((b[0]&0x40)&&--n);
 if(!n||fault){result[0]=0xBAD4;return 1;}
 /* No averaging, 100 samples/s, 18-bit (411 us), low LED current 0x08. */
 if(!wr(8,0)||!wr(4,0)||!wr(5,0)||!wr(6,0)||!wr(10,0x27)||!wr(12,8)||!wr(13,8)||!wr(9,3)){result[0]=0xBAD5;return 1;}
 for(unsigned i=0;i<SAMPLE_LIMIT && !result[7];){
   unsigned wait=2000;
   do {if(!rd(4,b,3)){result[0]=0xBAD6;goto end;} if(b[1]){result[0]=0xBAD7;goto end;}if(b[0]!=b[2])break;us(1000);}while(--wait);
   if(!wait){result[0]=0xBAD8;goto end;}
   if(!rd(7,b,6)){result[0]=0xBAD9;goto end;}
   raw[i%RAW_CAPACITY][0]=((b[0]<<16)|(b[1]<<8)|b[2])&0x3ffff;
   raw[i%RAW_CAPACITY][1]=((b[3]<<16)|(b[4]<<8)|b[5])&0x3ffff;
   __asm__ volatile("dsb sy":::"memory");
   result[5]=++i;
 }
 result[0]=0x600D;
end: wr(9,0x80);gpio[1]=3;return 0;
}
