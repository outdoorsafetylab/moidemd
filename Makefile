MOIDEMD=moidemd
DEMZIP=全台灣新版_不分幅_臺灣本島.zip
DEM=DEM_20m.tif
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

$(DEM): $(DEMZIP)
	unzip -D $< $(DEM)

$(DEMZIP):
	wget --no-check-certificate -O $(DEMZIP) http://dtm.moi.gov.tw/$(DEMZIP) 

run: $(MOIDEMD) $(DEM)
	./$(MOIDEMD) -p 8080 $(DEM)

docker_builder:
	docker build --target build -t $(MOIDEMD)/build .

docker_runtime: $(DEM)
	docker build -t $(MOIDEMD)/run .

docker_run:
	docker run -d --rm -p 8080:8080 --name $(MOIDEMD) $(MOIDEMD)/run

clean:
	@rm -f $(MOIDEMD)

.PHONY: all clean
