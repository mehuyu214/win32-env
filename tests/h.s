.global _start
_start:
  mov $4, %eax
  mov $1, %ebx
  mov $msg, %ecx
  mov $13, %edx
  int $0x80
  mov $1, %eax
  xor %ebx, %ebx
  int $0x80
msg: .ascii "hello32-native\n"
