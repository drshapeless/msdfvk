BIN = test

# compiler
CC = clang

# includes and libs
INCS =
LIBS = -lm

# flags
CFLAGS = $(INCS) -O2 -std=c23
LDFLAGS = $(LIBS)
