#include <setjmp.h>
#include <stdio.h>

jmp_buf env;
int breakpoint_called = 0;

void call_with_breakpoint(void (*func_ptr)(void)) {
    breakpoint_called = 0;
    if (setjmp(env) == 0) {
        //printf("[call with] breakpoint set, continuing normally\n");
        func_ptr();
    } else {
        printf("[call with] continuing after from breakpoint. Breakpoint hit: %d\n", breakpoint_called);
    }
}

// Bug in release mode: without these, linking time optimization removes 
// the symbol from the full zepl binary. 
// $ nm -gU ./zig-out/lib/libbreakpoint.a
//   .zig-cache/o/9c50e5448c98f4446101a9f01be863f5/breakpoint.o:
// 0000000000000058 T _breakpoint
// 00000000000008c8 S _breakpoint_called
// 0000000000000078 T _call_me_with_breakpoint
// 0000000000000000 T _call_with_breakpoint
__attribute__((noinline))
__attribute__((used))
void breakpoint() {
    breakpoint_called = 1;
    longjmp(env, 1);
}

void call_me_with_breakpoint() {
    printf("[call me] calling with breakpoint\n");
    breakpoint();
    printf("[call me] this should not run!\n");
}


