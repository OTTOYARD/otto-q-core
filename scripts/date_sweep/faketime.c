/* Shifts the wall clock by FAKE_OFFSET_S seconds for one process tree (a scratch PostgreSQL), so that
   a test suite can be run as of a later day. Monotonic clocks are left alone. */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <time.h>
#include <sys/time.h>

static long long offset_s(void) {
  static long long off = 0; static int done = 0;
  if (!done) { const char *s = getenv("FAKE_OFFSET_S"); off = s ? atoll(s) : 0; done = 1; }
  return off;
}

int clock_gettime(clockid_t clk, struct timespec *tp) {
  static int (*real)(clockid_t, struct timespec *) = 0;
  if (!real) real = (int (*)(clockid_t, struct timespec *))dlsym(RTLD_NEXT, "clock_gettime");
  int r = real(clk, tp);
  if (r == 0 && tp && (clk == CLOCK_REALTIME || clk == CLOCK_REALTIME_COARSE)) tp->tv_sec += offset_s();
  return r;
}

int gettimeofday(struct timeval *restrict tv, void *restrict tz) {
  static int (*real)(struct timeval *restrict, void *restrict) = 0;
  if (!real) real = (int (*)(struct timeval *restrict, void *restrict))dlsym(RTLD_NEXT, "gettimeofday");
  int r = real(tv, tz);
  if (r == 0 && tv) tv->tv_sec += offset_s();
  return r;
}

time_t time(time_t *t) {
  struct timespec ts;
  clock_gettime(CLOCK_REALTIME, &ts);
  if (t) *t = ts.tv_sec;
  return ts.tv_sec;
}
