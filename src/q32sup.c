#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ptrace.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <sys/user.h>
#include <sys/uio.h>
#include <sys/prctl.h>
#include <sys/syscall.h>
#include <sys/mman.h>
#include <linux/seccomp.h>
#include <linux/filter.h>
#include <linux/audit.h>
#include <stddef.h>
#include <limits.h>

/* q32sup — supervisor that lets 32-bit Windows programs run under
 * qemu-i386 user-mode emulation on hosts where the 32-bit execution
 * transition is disabled by the sandbox.
 *
 * It traces the initial qemu process (and all descendants) with a
 * seccomp filter that reports execve/execveat.  When the target of an
 * exec is a 32-bit x86 ELF, the exec is rewritten to a generated
 * wrapper that re-enters the target through qemu-i386.
 *
 * Fix history (2026-11-16, complaint-board win32-env posts; see
 * FIXLOG-20261116.md).  The original version had these defects:
 *  1. wrapper body embedded the target path in plain double quotes —
 *     a path containing " $ ` or \ broke out (wrong exec / injection).
 *     -> every interpolated string is now shell_quote()d.
 *  2. wrapper file name was a bare djb hash and an existing file was
 *     reused on existence alone — collisions silently reused the
 *     wrong wrapper.  -> FNV-1a 64 over all body inputs, reuse only
 *     after a byte-exact content match, -1/-2/... suffix attempts,
 *     mkstemp unique name as final fallback.
 *  3. wrapper temp file used a fixed "<name>.tmp" — racy.
 *     -> mkstemp() unique temp + atomic rename().
 *  4. ELF check and exec were separated by a path re-resolution
 *     (TOCTOU), and the on-disk wrapper itself could be swapped
 *     between generation and exec.
 *     -> default mode has NO on-disk wrapper: the wrapper body lives
 *     in a memfd and is exec'd via /proc/<supervisor>/fd/<n>; the
 *     target is opened once, ELF-verified from the open fd, and the
 *     wrapper is pointed at /proc/<supervisor>/fd/<fd> (fd pinning),
 *     so path re-resolution cannot substitute a different file.
 *     Q32_WRAPPER=disk forces the (also fixed) on-disk mode; there
 *     the wrapper embeds the checked path itself (so wrapper reuse
 *     is stable across runs) and the residual check->open window of
 *     the Q1 design remains — memfd mode is the default for a reason.
 *     Documented limit: pinning stops path substitution, not in-place
 *     modification of the pinned inode's contents; q32sup is an
 *     execution broker, not a security sandbox.
 *  5. execveat with a non-AT_FDCWD dirfd resolved relative paths
 *     against the tracee's cwd.  -> resolved against
 *     /proc/<pid>/fd/<dirfd>.
 *  6. read_str silently accepted truncated strings; path buffers
 *     were 512 bytes.  -> PATH_MAX buffers; a string with no NUL in
 *     the bytes read is an error (no interception).
 *  7. the wrapper path was written at rsp-1024 and rsp was moved to
 *     point at it.  -> written below the 128-byte red zone at
 *     (rsp - 128 - len - 16) & ~15; rsp is left unchanged.
 *  8. seccomp installation was unchecked and the filter did not
 *     audit the architecture.  -> prctl() results are checked (the
 *     child exits 127 if the filter cannot be installed) and the
 *     filter first checks arch == AUDIT_ARCH_X86_64, allowing
 *     anything else untouched.
 *  9. the QEMU cpu model is overridable via Q32_CPU (default "max"),
 *     matching the q32sup-var builds used by the compat line.
 * 10. Q32_CPU was interpolated into the wrapper with no validation
 *     (shell-quoting stopped injection, but a garbage model only
 *     failed deep inside QEMU with an opaque error).  -> the value
 *     is validated at startup against the charset QEMU cpu model
 *     strings actually use ([A-Za-z0-9+,._=-]); anything else is
 *     rejected with a message on stderr and exit 2.
 * 11. a seccomp install failure in the child exited 127 silently,
 *     and the parent never noticed a child that died before its
 *     first stop (it went on to report success).  -> install_filter()
 *     reports which prctl() failed, with errno, on stderr, and the
 *     parent propagates an already-exited child's status.
 *
 * Path resolution (portability patch, unchanged): paths are resolved
 * relative to the q32sup executable location:
 *   <ROOT>/qemu10/q32sup            (this binary)
 *   <ROOT>/qemu10/usr/bin/qemu-i386 (QEMU)
 *   <ROOT>/sysroot32/root           (SYSROOT)
 *   <ROOT>/qemu10/wrap              (WRAPDIR, disk mode only)
 * Overrides: Q32_QEMU, Q32_SYSROOT, Q32_WRAPDIR, Q32_CPU, Q32_WRAPPER.
 */
static char QEMU_buf[PATH_MAX], SYSROOT_buf[PATH_MAX], WRAPDIR_buf[PATH_MAX], CPU_buf[128];
static const char *QEMU, *SYSROOT, *WRAPDIR, *CPU_MODEL;
static int WRAP_MEMFD = 1;
static void resolve_paths(void) {
    char exe[PATH_MAX];
    ssize_t n = readlink("/proc/self/exe", exe, sizeof(exe) - 1);
    const char *env;
    if ((env = getenv("Q32_QEMU"))) snprintf(QEMU_buf, sizeof(QEMU_buf), "%s", env);
    if ((env = getenv("Q32_SYSROOT"))) snprintf(SYSROOT_buf, sizeof(SYSROOT_buf), "%s", env);
    if ((env = getenv("Q32_WRAPDIR"))) snprintf(WRAPDIR_buf, sizeof(WRAPDIR_buf), "%s", env);
    if ((env = getenv("Q32_CPU"))) {
        /* A value longer than CPU_buf is silently cut by snprintf
         * below, and main() then validates only the truncated copy —
         * an invalid character past the cut would pass unchecked.
         * Reject over-long values loudly instead of truncating. */
        if (strlen(env) >= sizeof(CPU_buf)) {
            fprintf(stderr, "[q32sup] Q32_CPU value too long (%zu chars, max %zu)\n",
                    strlen(env), sizeof(CPU_buf) - 1);
            exit(1);
        }
        snprintf(CPU_buf, sizeof(CPU_buf), "%s", env);
    }
    if ((env = getenv("Q32_WRAPPER")) && strcmp(env, "disk") == 0) WRAP_MEMFD = 0;
    if (n > 0) {
        exe[n] = 0;
        char *slash = strrchr(exe, '/');
        if (slash) *slash = 0;                 /* <ROOT>/qemu10 */
        char *up = strrchr(exe, '/');
        if (up) *up = 0;                       /* <ROOT> */
        if (!QEMU_buf[0]) snprintf(QEMU_buf, sizeof(QEMU_buf), "%s/qemu10/usr/bin/qemu-i386", exe);
        if (!SYSROOT_buf[0]) snprintf(SYSROOT_buf, sizeof(SYSROOT_buf), "%s/sysroot32/root", exe);
        if (!WRAPDIR_buf[0]) snprintf(WRAPDIR_buf, sizeof(WRAPDIR_buf), "%s/qemu10/wrap", exe);
    }
    if (!QEMU_buf[0] || !SYSROOT_buf[0] || !WRAPDIR_buf[0]) {
        fprintf(stderr, "[q32sup] cannot resolve QEMU/sysroot/wrapdir paths: "
                        "run the binary from a win32-env tree, or set Q32_QEMU, "
                        "Q32_SYSROOT and Q32_WRAPDIR explicitly\n");
        exit(1);
    }
    if (!CPU_buf[0]) snprintf(CPU_buf, sizeof(CPU_buf), "%s", "max");
    QEMU = QEMU_buf; SYSROOT = SYSROOT_buf; WRAPDIR = WRAPDIR_buf; CPU_MODEL = CPU_buf;
    if (mkdir(WRAPDIR, 0755) != 0 && errno != EEXIST) {
        if (!WRAP_MEMFD) {
            fprintf(stderr, "[q32sup] cannot create WRAPDIR %s: %s; "
                            "disk wrapper mode needs a writable wrapper directory\n",
                    WRAPDIR, strerror(errno));
            exit(1);
        }
        fprintf(stderr, "[q32sup] warning: cannot create WRAPDIR %s: %s; "
                        "memfd wrappers unaffected, disk fallback unavailable\n",
                WRAPDIR, strerror(errno));
    }
}

/* --- shell quoting: wrap in double quotes, backslash-escape " \ $ ` --- */
static int shell_quote(const char *in, char *out, size_t cap) {
    size_t o = 0;
    if (cap < 3) return -1;
    out[o++] = '"';
    for (const char *p = in; *p; p++) {
        if (*p == '"' || *p == '\\' || *p == '$' || *p == '`') {
            if (o + 2 >= cap - 1) return -1;
            out[o++] = '\\';
        }
        if (o + 1 >= cap - 1) return -1;
        out[o++] = *p;
    }
    out[o++] = '"';
    out[o] = 0;
    return 0;
}

static int build_body(char *out, size_t cap, const char *target) {
    static char qq[PATH_MAX * 2 + 8], qs[PATH_MAX * 2 + 8], qt[PATH_MAX * 2 + 8], qc[512];
    if (shell_quote(QEMU, qq, sizeof(qq)) < 0) return -1;
    if (shell_quote(SYSROOT, qs, sizeof(qs)) < 0) return -1;
    if (shell_quote(target, qt, sizeof(qt)) < 0) return -1;
    if (shell_quote(CPU_MODEL, qc, sizeof(qc)) < 0) return -1;
    int n = snprintf(out, cap, "#!/bin/sh\nexec %s -cpu %s -L %s %s \"$@\"\n", qq, qc, qs, qt);
    if (n < 0 || (size_t)n >= cap) return -1;
    return n;
}

/* --- target fd pinning -------------------------------------------------
 * Open the target once and verify the ELF header from the open fd.
 * The returned string (ring storage) is /proc/<self>/fd/<fd>; the fd
 * stays open in the ring so the path keeps resolving to the verified
 * inode until long after the exec completes.  Returns NULL when the
 * target is not a 32-bit x86 ELF (or cannot be opened). */
#define PIN_SLOTS 64
static int pin_fds[PIN_SLOTS];
static char pin_paths[PIN_SLOTS][64];
static int pin_next = 0;
static const char *pin_target(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    unsigned char h[20];
    ssize_t n = pread(fd, h, 20, 0);
    int ok = (n == 20 && h[0] == 0x7f && h[1] == 'E' && h[2] == 'L' && h[3] == 'F'
              && h[4] == 1 && h[18] == 3 && h[19] == 0);
    if (!ok) { close(fd); return NULL; }
    int slot = pin_next++ % PIN_SLOTS;
    if (pin_fds[slot] >= 0) close(pin_fds[slot]);
    pin_fds[slot] = fd;
    snprintf(pin_paths[slot], sizeof(pin_paths[slot]), "/proc/%d/fd/%d", getpid(), fd);
    return pin_paths[slot];
}

/* 1 when path names a readable 32-bit x86 ELF. Used only to decide
 * whether a pin failure deserves a diagnostic; the pass-through of
 * scripts and 64-bit ELFs stays silent. */
static int is_elf32_path(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    unsigned char h[20];
    ssize_t n = pread(fd, h, 20, 0);
    close(fd);
    return (n == 20 && h[0] == 0x7f && h[1] == 'E' && h[2] == 'L' && h[3] == 'F'
            && h[4] == 1 && h[18] == 3 && h[19] == 0);
}

/* --- memfd wrapper -----------------------------------------------------
 * The wrapper script lives only in a memfd owned by the supervisor;
 * there is no on-disk file to swap.  Fds are kept in a ring (the
 * tracee's exec and the shell's re-read happen immediately). */
#define WRAP_SLOTS 64
static int wrap_fds[WRAP_SLOTS];
static int wrap_next = 0;
static const char *make_memfd_wrapper(const char *target) {
    static char body[16384];
    static char mp[64];
    int bl = build_body(body, sizeof(body), target);
    if (bl < 0) return NULL;
    int fd = memfd_create("q32wrap", MFD_CLOEXEC);
    if (fd < 0) return NULL;
    if (write(fd, body, bl) != bl) { close(fd); return NULL; }
    int slot = wrap_next++ % WRAP_SLOTS;
    if (wrap_fds[slot] >= 0) close(wrap_fds[slot]);
    wrap_fds[slot] = fd;
    snprintf(mp, sizeof(mp), "/proc/%d/fd/%d", getpid(), fd);
    return mp;
}

/* --- on-disk wrapper (Q32_WRAPPER=disk; also the memfd fallback) ------ */
static unsigned long long fnv1a(const char *s) {
    unsigned long long h = 1469598103934665603ULL;
    for (; *s; s++) { h ^= (unsigned char)*s; h *= 1099511628211ULL; }
    return h;
}
static int file_content_equals(const char *path, const char *body, size_t blen) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 0;
    char buf[16384];
    ssize_t n = read(fd, buf, sizeof(buf));
    close(fd);
    return (n == (ssize_t)blen && memcmp(buf, body, blen) == 0);
}
static const char *make_disk_wrapper(const char *target) {
    static char body[16384];
    static char wpath[PATH_MAX];
    int bl = build_body(body, sizeof(body), target);
    if (bl < 0) return NULL;
    unsigned long long h = fnv1a(body);
    for (int attempt = 0; attempt < 17; attempt++) {
        if (attempt == 0)
            snprintf(wpath, sizeof(wpath), "%s/w%llx.sh", WRAPDIR, h);
        else if (attempt < 16)
            snprintf(wpath, sizeof(wpath), "%s/w%llx-%d.sh", WRAPDIR, h, attempt);
        else {
            /* last resort: a unique name via mkstemp */
            snprintf(wpath, sizeof(wpath), "%s/w%llx-XXXXXX", WRAPDIR, h);
            int tfd = mkstemp(wpath);
            if (tfd < 0) return NULL;
            fchmod(tfd, 0755);
            if (write(tfd, body, bl) != bl) { close(tfd); unlink(wpath); return NULL; }
            close(tfd);
            return wpath;
        }
        if (file_content_equals(wpath, body, bl)) return wpath;  /* verified reuse */
        if (access(wpath, F_OK) != 0) {
            /* create via unique temp + atomic rename */
            char tmp[PATH_MAX];
            snprintf(tmp, sizeof(tmp), "%s/.wrap-XXXXXX", WRAPDIR);
            int tfd = mkstemp(tmp);
            if (tfd < 0) return NULL;
            fchmod(tfd, 0755);
            if (write(tfd, body, bl) != bl) { close(tfd); unlink(tmp); return NULL; }
            close(tfd);
            if (rename(tmp, wpath) < 0) { unlink(tmp); continue; }
            return wpath;
        }
        /* name taken by different content: try the next suffix */
    }
    return NULL;
}

static const char *make_wrapper(const char *target) {
    if (WRAP_MEMFD) {
        const char *w = make_memfd_wrapper(target);
        if (w) return w;
        /* memfd unavailable: fall through to the fixed disk mode */
    }
    return make_disk_wrapper(target);
}

/* read a string from tracee memory; -1 unless a NUL-terminated string
 * fits in the buffer (truncation is an error, never silently accepted) */
static int read_str(pid_t pid, unsigned long addr, char *buf, size_t cap) {
    struct iovec local = { buf, cap - 1 };
    struct iovec remote = { (void *)addr, cap - 1 };
    ssize_t n = process_vm_readv(pid, &local, 1, &remote, 1, 0);
    if (n <= 0) return -1;
    buf[n] = 0;
    if (memchr(buf, 0, (size_t)n) == NULL) return -1;  /* truncated */
    return 0;
}

/* write a string into tracee memory at addr (word-wise via POKEDATA).
 * The final partial word is merged over the tracee's existing bytes
 * (PEEKDATA) instead of zero-filling past the string's end. */
static int write_str(pid_t pid, unsigned long addr, const char *s) {
    size_t len = strlen(s) + 1;
    size_t i = 0;
    while (i < len) {
        size_t chunk = len - i < sizeof(long) ? len - i : sizeof(long);
        long word;
        if (chunk < sizeof(long)) {
            errno = 0;
            word = ptrace(PTRACE_PEEKDATA, pid, addr + i, 0);
            if (word == -1 && errno != 0) return -1;
        } else {
            word = 0;
        }
        memcpy(&word, s + i, chunk);
        if (ptrace(PTRACE_POKEDATA, pid, addr + i, word) < 0) return -1;
        i += chunk;
    }
    return 0;
}

/* Resolve the path an exec refers to, for the ELF check / pin.
 * Relative paths resolve against the execveat dirfd when one is
 * given (and is not AT_FDCWD), else against the tracee's cwd. */
static const char *resolve_check_path(pid_t pid, long nr, const struct user_regs_struct *regs,
                                      const char *path, char *out, size_t cap) {
    if (path[0] == '/') return path;
    char base[PATH_MAX];
    const char *basep = NULL;
    int from_dirfd = 0;
    if (nr == __NR_execveat && (long)regs->rdi != AT_FDCWD) {
        char linkp[64];
        snprintf(linkp, sizeof(linkp), "/proc/%d/fd/%lld", pid, (long long)regs->rdi);
        ssize_t bl = readlink(linkp, base, sizeof(base) - 1);
        if (bl > 0) { base[bl] = 0; basep = base; from_dirfd = 1; }
    }
    if (!basep) {
        char linkp[64];
        snprintf(linkp, sizeof(linkp), "/proc/%d/cwd", pid);
        ssize_t bl = readlink(linkp, base, sizeof(base) - 1);
        if (bl > 0) { base[bl] = 0; basep = base; }
    }
    if (!basep) return NULL;
    /* a dirfd may resolve to "dir (deleted)" etc.; require a clean absolute dir */
    if (basep[0] != '/') return NULL;
    if (path[0] == '\0') {
        /* execveat(dirfd, "", ..., AT_EMPTY_PATH): the target IS the file
         * the dirfd refers to, so the dirfd's own resolved path is the
         * check target, unsuffixed. Without a dirfd resolution or without
         * the flag, an empty path is the kernel's ENOENT to report —
         * pass through untouched. */
        if (!from_dirfd || !(regs->r8 & AT_EMPTY_PATH)) return NULL;
        int n = snprintf(out, cap, "%s", basep);
        if (n < 0 || (size_t)n >= cap) return NULL;
        return out;
    }
    int n = snprintf(out, cap, "%s/%s", basep, path);
    if (n < 0 || (size_t)n >= cap) return NULL;
    return out;
}

static int install_filter(void) {
    struct sock_filter filt[] = {
        /* audit the architecture first: only x86-64 syscall numbers
         * mean execve/execveat; anything else passes untouched */
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, AUDIT_ARCH_X86_64, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execve, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRACE),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_execveat, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_TRACE),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog prog = { .len = (unsigned short)(sizeof(filt) / sizeof(filt[0])), .filter = filt };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0) < 0) {
        fprintf(stderr, "[q32sup] seccomp: prctl(PR_SET_NO_NEW_PRIVS) failed: %s\n", strerror(errno));
        return -1;
    }
    if (prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog) < 0) {
        fprintf(stderr, "[q32sup] seccomp: prctl(PR_SET_SECCOMP) failed: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

/* QEMU cpu model strings ("max", "max,-avx2", "qemu32,+sse4.2", ...)
 * use only this charset; reject anything else up front instead of
 * letting a bad value fail opaquely inside QEMU (or, defence in
 * depth behind shell_quote(), break out of the wrapper). */
static int cpu_model_valid(const char *s) {
    if (!*s) return 0;
    for (const char *p = s; *p; p++) {
        char c = *p;
        int ok = (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                 (c >= '0' && c <= '9') || c == '+' || c == ',' ||
                 c == '.' || c == '_' || c == '=' || c == '-';
        if (!ok) return 0;
    }
    return 1;
}

int main(int argc, char **argv) {
    resolve_paths();
    if (!cpu_model_valid(CPU_MODEL)) {
        fprintf(stderr, "[q32sup] invalid Q32_CPU value \"%s\": allowed characters are [A-Za-z0-9+,._=-]\n", CPU_MODEL);
        return 2;
    }
    for (int i = 0; i < PIN_SLOTS; i++) pin_fds[i] = -1;
    for (int i = 0; i < WRAP_SLOTS; i++) wrap_fds[i] = -1;
    if (argc < 2) { fprintf(stderr, "usage: q32sup <cmd> [args...]\n"); return 2; }
    pid_t child = fork();
    if (child < 0) {
        fprintf(stderr, "[q32sup] fork failed: %s\n", strerror(errno));
        return 1;
    }
    if (child == 0) {
        if (install_filter() < 0) _exit(127);
        ptrace(PTRACE_TRACEME, 0, 0, 0);
        raise(SIGSTOP);
        execvp(argv[1], argv + 1);
        _exit(127);
    }
    int status;
    if (waitpid(child, &status, 0) < 0) { /* initial SIGSTOP */
        fprintf(stderr, "[q32sup] waitpid failed: %s\n", strerror(errno));
        return 1;
    }
    if (WIFEXITED(status) || WIFSIGNALED(status)) {
        /* child died before its first stop (e.g. the seccomp filter
         * could not be installed): propagate its status instead of
         * marching on and reporting success */
        if (WIFEXITED(status)) return WEXITSTATUS(status);
        signal(WTERMSIG(status), SIG_DFL);
        raise(WTERMSIG(status));
        return 1;
    }
    ptrace(PTRACE_SETOPTIONS, child, 0,
           PTRACE_O_TRACESECCOMP | PTRACE_O_TRACEFORK | PTRACE_O_TRACEVFORK |
           PTRACE_O_TRACECLONE | PTRACE_O_EXITKILL);
    ptrace(PTRACE_CONT, child, 0, 0);
    int root_status = 0;
    int alive = 1;
    while (alive) {
        pid_t pid = waitpid(-1, &status, __WALL);
        if (pid < 0) { if (errno == EINTR) continue; break; }
        if (WIFEXITED(status) || WIFSIGNALED(status)) {
            if (pid == child) { root_status = status; alive = 0; }
            continue;
        }
        if (WIFSTOPPED(status)) {
            int sig = WSTOPSIG(status);
            unsigned long event = (unsigned long)status >> 16;
            if (sig == SIGTRAP && event == PTRACE_EVENT_SECCOMP) {
                struct user_regs_struct regs;
                ptrace(PTRACE_GETREGS, pid, 0, &regs);
                long nr = regs.orig_rax;
                if (nr == __NR_execve || nr == __NR_execveat) {
                    unsigned long paddr = (nr == __NR_execve) ? regs.rdi : regs.rsi;
                    char path[PATH_MAX];
                    if (read_str(pid, paddr, path, sizeof(path)) == 0) {
                        char abspath[PATH_MAX];
                        const char *check = resolve_check_path(pid, nr, &regs, path, abspath, sizeof(abspath));
                        if (check) {
                            const char *target = pin_target(check);
                            if (target) {
                                /* memfd mode embeds the pinned fd path;
                                 * disk mode embeds the checked path so
                                 * its wrappers stay reusable (see header) */
                                const char *wrap = make_wrapper(WRAP_MEMFD ? target : check);
                                if (wrap) {
                                    size_t len = strlen(wrap) + 1;
                                    /* below the 128-byte red zone; rsp untouched */
                                    unsigned long scratch = (regs.rsp - 128 - len - 16) & ~15UL;
                                    if (write_str(pid, scratch, wrap) == 0) {
                                        if (nr == __NR_execve) regs.rdi = scratch;
                                        else { regs.rdi = (unsigned long)AT_FDCWD; regs.rsi = scratch; regs.r8 &= ~(unsigned long)AT_EMPTY_PATH; /* the wrapper is passed by pathname */ }
                                        if (ptrace(PTRACE_SETREGS, pid, 0, &regs) == 0) {
                                            fprintf(stderr, "[q32sup] execve %s -> %s (pinned %s)\n", check, wrap, target);
                                        } else {
                                            fprintf(stderr, "[q32sup] execve %s: PTRACE_SETREGS failed (%s); rewrite NOT applied\n",
                                                    check, strerror(errno));
                                        }
                                    } else {
                                        fprintf(stderr, "[q32sup] execve %s: writing the wrapper path failed; rewrite NOT applied\n",
                                                check);
                                    }
                                } else {
                                    fprintf(stderr, "[q32sup] execve %s: wrapper creation failed; rewrite NOT applied\n",
                                            check);
                                }
                            } else if (is_elf32_path(check)) {
                                fprintf(stderr, "[q32sup] execve %s: 32-bit ELF target could not be pinned; rewrite NOT applied\n",
                                        check);
                            }
                        }
                    }
                }
                ptrace(PTRACE_CONT, pid, 0, 0);
            } else if (sig == SIGTRAP) {
                ptrace(PTRACE_CONT, pid, 0, 0);
            } else {
                ptrace(PTRACE_CONT, pid, 0, sig);
            }
        }
    }
    if (WIFEXITED(root_status)) return WEXITSTATUS(root_status);
    if (WIFSIGNALED(root_status)) { signal(WTERMSIG(root_status), SIG_DFL); raise(WTERMSIG(root_status)); }
    return 1;
}
