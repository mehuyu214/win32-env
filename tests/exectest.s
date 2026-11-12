.section .text
.globl _start
_start:
    # write "A\n"
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
path: .asciz "/home/hatch/workspace/vn-trials/wtest/hello32"
argv: .long path, 0
envp: .long 0
