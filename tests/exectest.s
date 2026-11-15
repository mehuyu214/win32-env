.section .text
.globl _start
_start:
    # write "A\n"
    mov $4, %eax
    mov $1, %ebx
    mov $msgA, %ecx
    mov $2, %edx
    int $0x80
    # target path: argv[1] if given, else "tests/hello32" (repo-relative)
    mov (%esp), %eax
    cmp $2, %eax
    jl use_default
    mov 8(%esp), %ebx
    jmp do_exec
use_default:
    mov $defpath, %ebx
do_exec:
    mov %ebx, av0
    # execve(path, argv, envp)
    mov $11, %eax
    mov av0, %ebx
    mov $argv, %ecx
    mov $envp, %edx
    int $0x80
    # only reached if execve failed: eax = -errno; print "F\n"
    mov %eax, %esi
    mov $4, %eax
    mov $1, %ebx
    mov $msgF, %ecx
    mov $2, %edx
    int $0x80
    mov %esi, %ebx
    negl %ebx
    mov $1, %eax
    int $0x80
.section .data
msgA: .ascii "A\n"
msgF: .ascii "F\n"
defpath: .asciz "tests/hello32"
av0: .long 0
argv: .long av0, 0
envp: .long 0
