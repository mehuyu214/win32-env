# envtest — execve driver for the environment-fidelity test (FIXLOG §34).
# Calls execve("tests/argtest", argv, envp) with a crafted argv (13
# arguments: spaces, tab, $, backslash, double quote, backtick, ;, *,
# an embedded newline, an empty string, a 200-char and a 4000-char
# argument) and a crafted envp (6 variables in a fixed order plus a
# duplicated key, Q32_DUP=first then Q32_DUP=second). No libc: raw
# int 0x80 syscalls only. Run from the repo root, under qemu-i386
# via q32sup: the supervisor must rewrite this execve to the wrapper,
# and argtest's output must then show argv/envp exactly as built here.
.section .text
.globl _start
_start:
    # marker "A\n" (parity with tests/exectest.s)
    mov $4, %eax
    mov $1, %ebx
    mov $msgA, %ecx
    mov $2, %edx
    int $0x80
    # execve(path, argv, envp)
    mov $11, %eax
    mov $path, %ebx
    mov $argv, %ecx
    mov $envp, %edx
    int $0x80
    # only reached if execve failed: print "F\n", exit 1
    mov $4, %eax
    mov $1, %ebx
    mov $msgF, %ecx
    mov $2, %edx
    int $0x80
    mov $1, %eax
    mov $1, %ebx
    int $0x80

.section .data
msgA: .ascii "A\n"
msgF: .ascii "F\n"
path: .asciz "tests/argtest"
argv: .long path, a1, a2, a3, a4, a5, a6, a7, a8, a9, a10, a11, a12, a13, 0
envp: .long e1, e2, e3, e4, e5, e6, e7, e8, 0
a1: .asciz "plain"
a2: .asciz "with space"
a3: .asciz "with\ttab"
a4: .asciz "dol$lar"
a5: .asciz "back\\slash"
a6: .asciz "dq\"quote"
a7: .asciz "bt`tick"
a8: .asciz "semi;colon"
a9: .asciz "star*glob"
a10: .asciz "new\nline"
a11: .asciz ""
a12: .fill 200, 1, 0x78
      .byte 0
a13: .fill 4000, 1, 0x79
      .byte 0
e1: .asciz "Q32_TEST=hello"
e2: .asciz "Q32_DOLLAR=$HOME-x"
e3: .asciz "Q32_SEMI=a;b;c"
e4: .ascii "Q32_LONG="
      .fill 200, 1, 0x78
      .byte 0
e5: .asciz "Q32_EMPTY="
e6: .asciz "Q32_NL=line1\nline2"
e7: .asciz "Q32_DUP=first"
e8: .asciz "Q32_DUP=second"
