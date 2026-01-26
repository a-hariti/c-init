#include <stdlib.h>

#define ACUTEST_IMPLEMENTATION
#include "acutest.h"

static void test_tutorial(void) {
  void *mem;

  mem = malloc(10);
  TEST_CHECK(mem != NULL);

  void *mem2 = realloc(mem, 20);
  TEST_CHECK(mem2 != NULL);
  mem = mem2;

  free(mem);
}

static void test_addition(void) {
  int a = 1;
  int b = 2;
  TEST_CHECK(a + b == 3);
}

TEST_LIST = {
    {"tutorial", test_tutorial},
    {"addition", test_addition},
    {NULL, NULL},
};
