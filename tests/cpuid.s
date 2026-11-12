.section .text
.globl _start
_start:
    mov $1, %eax
    cpuid
    # EDX: SSE=bit25, SSE2=bit26 ; ECX: SSSE3=bit9, SSE41=bit19, AVX=bit28
    mov %edx, %esi
    mov %ecx, %edi
    # print "SSE2=" then digit
    mov $str_sse2, %ecx
    call print5
    mov %esi, %eax
    shr $26, %eax
    and $1, %eax
    call printdigit
    mov $str_sse, %ecx
    call print5
    mov %esi, %eax
    shr $25, %eax
    and $1, %eax
    call printdigit
    mov $str_ssse3, %ecx
    call print6
    mov %edi, %eax
    shr $9, %eax
    and $1, %eax
    call printdigit
    mov $10, %eax
    mov %eax, nl
    mov $4, %eax
    mov $1, %ebx
    mov $nl, %ecx
    mov $1, %edx
    int $0x80
    # exit 0
    mov $1, %eax
    xor %ebx, %ebx
    int $0x80
print5:
    mov $4, %eax
    mov $1, %ebx
    mov $5, %edx
    int $0x80
    ret
print6:
    mov $4, %eax
    mov $1, %ebx
    mov $6, %edx
    int $0x80
    ret
printdigit:
    add $48, %eax
    mov %eax, nl
    mov $4, %eax
    mov $1, %ebx
    mov $nl, %ecx
    mov $1, %edx
    int $0x80
    ret
.section .data
str_sse2: .ascii "SSE2="
str_sse: .ascii " SSE="
str_ssse3: .ascii " SSSE3="
nl: .long 0
