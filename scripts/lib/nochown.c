/* nochown.so — LD_PRELOAD shim for rootless Debian roots.
 * In a single-uid user namespace chown() to any id other than 0 fails with
 * EINVAL. dpkg and maintainer scripts treat that as fatal. This shim reports
 * success instead; real ownership is applied when the filesystem image is
 * written (make-image), exactly like fakeroot but without a daemon. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <errno.h>
#include <sys/types.h>

#define TOLERATE(r) do { if ((r) < 0 && (errno == EINVAL || errno == EPERM)) { errno = 0; return 0; } return (r); } while (0)

int chown(const char *p, uid_t u, gid_t g)
{ static int (*f)(const char *, uid_t, gid_t); if (!f) f = dlsym(RTLD_NEXT, "chown"); int r = f(p, u, g); TOLERATE(r); }
int lchown(const char *p, uid_t u, gid_t g)
{ static int (*f)(const char *, uid_t, gid_t); if (!f) f = dlsym(RTLD_NEXT, "lchown"); int r = f(p, u, g); TOLERATE(r); }
int fchown(int fd, uid_t u, gid_t g)
{ static int (*f)(int, uid_t, gid_t); if (!f) f = dlsym(RTLD_NEXT, "fchown"); int r = f(fd, u, g); TOLERATE(r); }
int fchownat(int d, const char *p, uid_t u, gid_t g, int fl)
{ static int (*f)(int, const char *, uid_t, gid_t, int); if (!f) f = dlsym(RTLD_NEXT, "fchownat"); int r = f(d, p, u, g, fl); TOLERATE(r); }
