# argtest — prints argv and envp exactly as the guest sees them.
# Usage: argtest <args...>
# Output: one line per argument ("A:<arg>") then one per env entry
# ("E:<var>"), in the order the kernel handed them to this process.
# No libc: raw int 0x80 syscalls only, so it runs under qemu-i386
# with no loader or sysroot dependency. Used to test q32sup's
# environment fidelity (FIXLOG §34): the wrapper must pass envp
# through byte-for-byte (order, duplicates, no added PWD).
.section .text
.globl _start

# print(eax = NUL-terminated string): write it to stdout.
# Clobbers eax, ecx, edx only.
print:
    push %ebx
    push %esi
    push %edi
    mov %eax, %esi
    mov %esi, %ecx
    xor %edx, %edx
1:
    cmpb $0, (%esi,%edx)
    je 2f
    inc %edx
    jmp 1b
2:
    mov $4, %eax
    mov $1, %ebx
    int $0x80
    pop %edi
    pop %esi
    pop %ebx
    ret

_start:
    mov (%esp), %esi            # esi = argc (preserved by syscalls)
    lea 4(%esp), %ebx           # ebx = &argv[0]
    xor %edi, %edi              # edi = i
argv_loop:
    cmp %esi, %edi
    jge argv_done
    mov $pfxA, %eax
    call print
    mov (%ebx,%edi,4), %eax
    call print
    mov $pfxNL, %eax
    call print
    inc %edi
    jmp argv_loop
argv_done:
    # envp array starts right after argv's NULL slot:
    # &envp[0] = &argv[0] + 4 * (argc + 1)
    lea 4(%ebx,%esi,4), %edi    # edi = &envp[0]
env_loop:
    mov (%edi), %eax
    test %eax, %eax
    jz env_done
    push %eax
    mov $pfxE, %eax
    call print
    pop %eax
    call print
    mov $pfxNL, %eax
    call print
    add $4, %edi
    jmp env_loop
env_done:
    mov $1, %eax                # exit(0)
    xor %ebx, %ebx
    int $0x80

.section .data
pfxA: .asciz "A:"
pfxE: .asciz "E:"
pfxNL: .asciz "\n"
