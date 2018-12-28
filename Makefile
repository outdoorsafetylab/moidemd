MOIDEMD=moidemd
CC=g++
LDFLAGS=-lgdal -levent -ljson-c
SOURCES := main.cpp
# Objs are all the sources, with .cpp replaced by .o
OBJS := $(SOURCES:.cpp=.o)

all: $(MOIDEMD)

$(MOIDEMD): $(OBJS)
	$(CC) $(CFLAGS) -o $(MOIDEMD) $< $(LDFLAGS) $(LIBS)

.cpp.o:
	$(CC) $(CFLAGS) $(INCLUDES) -c $<

clean:
	@rm -f $(MOIDEMD)

.PHONY: all clean
