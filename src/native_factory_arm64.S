// TPtr factories return indirectly through x8 on this arm64 Live build.
// void pitch_call_factory(void *factory, void **result);
.text
.p2align 2
.globl _pitch_call_factory
_pitch_call_factory:
    mov x16, x0
    mov x8, x1
    br x16
