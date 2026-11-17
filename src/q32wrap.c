#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

extern char **environ;

/* q32wrap — tiny exec helper for q32sup wrappers (FIXLOG §34).
 *
 * A q32sup wrapper file is NOT a shell script: its first line is a
 * shebang naming this helper, and the rest is a parameter block of
 * four NUL-terminated strings: the qemu-i386 path, the -cpu model,
 * the sysroot path, and the 32-bit target path. This program reads
 * that block and execve()s qemu with argv [qemu, -cpu, cpu, -L,
 * sysroot, target, <the caller's original arguments>] and the
 * environment EXACTLY as received (environ is passed through
 * untouched).
 *
 * Why a helper instead of #!/bin/sh: dash rebuilds the environment
 * when it starts — it adds PWD, reorders variables, and collapses
 * duplicate keys last-wins — so every guest exec through a shell
 * wrapper saw a different environment from the one its caller set
 * (verified: order scrambled, Q32_DUP=first lost, PWD added). This
 * binary is the only thing between the kernel and qemu, and it
 * touches neither argv (beyond the fixed qemu prefix) nor environ.
 * No quoting is involved anywhere: the parameters are NUL-delimited,
 * so any byte except NUL survives them intact.
 *
 * Usage (invoked by the kernel via the wrapper's shebang):
 *   q32wrap <wrapper-file> [original args...]
 * Diagnostics go to stderr; any failure exits 127.
 */
static int fail(const char *what, const char *detail) {
    if (detail)
        fprintf(stderr, "[q32wrap] %s: %s\n", what, detail);
    else
        fprintf(stderr, "[q32wrap] %s\n", what);
    return 127;
}

int main(int argc, char **argv) {
    if (argc < 2) return fail("usage: q32wrap <wrapper-file> [args...]", NULL);
    int fd = open(argv[1], O_RDONLY);
    if (fd < 0) return fail("cannot open wrapper file", strerror(errno));
    static char buf[16384];
    ssize_t total = 0;
    for (;;) {
        ssize_t n = read(fd, buf + total, sizeof(buf) - (size_t)total);
        if (n < 0) {
            if (errno == EINTR) continue;
            close(fd);
            return fail("cannot read wrapper file", strerror(errno));
        }
        if (n == 0) break;
        total += n;
        if (total >= (ssize_t)sizeof(buf)) break;
    }
    close(fd);
    if (total <= 0) return fail("cannot read wrapper file", "empty file");
    /* skip the shebang line */
    char *p = memchr(buf, '\n', (size_t)total);
    if (!p) return fail("malformed wrapper: no shebang line", NULL);
    p++;
    const char *field[4];
    for (int i = 0; i < 4; i++) {
        if (p >= buf + total)
            return fail("malformed wrapper: truncated parameter block", NULL);
        field[i] = p;
        char *z = memchr(p, '\0', (size_t)(buf + total - p));
        if (!z)
            return fail("malformed wrapper: unterminated parameter", NULL);
        p = z + 1;
    }
    /* new argv: qemu -cpu <cpu> -L <sysroot> <target> <orig args...> */
    char **nargv = malloc(sizeof(char *) * (size_t)(argc + 5));
    if (!nargv) return fail("out of memory", NULL);
    int o = 0;
    nargv[o++] = (char *)field[0];
    nargv[o++] = "-cpu";
    nargv[o++] = (char *)field[1];
    nargv[o++] = "-L";
    nargv[o++] = (char *)field[2];
    nargv[o++] = (char *)field[3];
    for (int i = 2; i < argc; i++) nargv[o++] = argv[i];
    nargv[o] = NULL;
    execve(field[0], nargv, environ);
    return fail("execve qemu failed", strerror(errno));
}
