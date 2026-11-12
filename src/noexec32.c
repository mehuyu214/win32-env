#define _GNU_SOURCE
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <dlfcn.h>
#include <stdarg.h>
#include <sys/syscall.h>
#include <stdio.h>
static int (*real_execve)(const char *, char *const *, char *const *);
static long (*real_syscall)(long, ...);
static int is32elf(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    unsigned char h[20];
    int n = read(fd, h, 20);
    close(fd);
    return (n == 20 && h[0] == 0x7f && h[1] == 'E' && h[2] == 'L' && h[3] == 'F'
            && h[4] == 1 && h[18] == 3 && h[19] == 0);
}
int execve(const char *path, char *const argv[], char *const envp[]) {
    if (!real_execve) real_execve = dlsym(RTLD_NEXT, "execve");
    if (is32elf(path)) { fprintf(stderr, "[noexec32] blocked execve %s\n", path); errno = ENOEXEC; return -1; }
    return real_execve(path, argv, envp);
}
int execveat(int dirfd, const char *path, char *const argv[], char *const envp[], int flags) {
    static int (*real_execveat)(int, const char *, char *const *, char *const *, int);
    if (!real_execveat) real_execveat = dlsym(RTLD_NEXT, "execveat");
    if (path && path[0] == '/' && is32elf(path)) { fprintf(stderr, "[noexec32] blocked execveat %s\n", path); errno = ENOEXEC; return -1; }
    return real_execveat(dirfd, path, argv, envp, flags);
}
long syscall(long number, ...) {
    va_list ap;
    va_start(ap, number);
    long a1 = va_arg(ap, long), a2 = va_arg(ap, long), a3 = va_arg(ap, long);
    long a4 = va_arg(ap, long), a5 = va_arg(ap, long), a6 = va_arg(ap, long);
    va_end(ap);
    if (!real_syscall) real_syscall = dlsym(RTLD_NEXT, "syscall");
    if (number == __NR_execve && is32elf((const char *)a1)) {
        fprintf(stderr, "[noexec32] blocked syscall execve %s\n", (const char *)a1);
        errno = ENOEXEC; return -1;
    }
    if (number == __NR_execveat && a2 && ((const char *)a2)[0] == '/' && is32elf((const char *)a2)) {
        fprintf(stderr, "[noexec32] blocked syscall execveat %s\n", (const char *)a2);
        errno = ENOEXEC; return -1;
    }
    return real_syscall(number, a1, a2, a3, a4, a5, a6);
}
