EXEC := moidemd
CC := g++
LDFLAGS ?=
LIBS ?= -lgdal -levent -ljson-c
SOURCES := main.cpp
# Objs are all the sources, with .cpp replaced by .o
OBJS := $(SOURCES:.cpp=.o)

DEMZIP := dem.7z
DEM := DEMg_geoid2014_20m_20190515.tif

IMAGE_NAME := outdoorsafetylab/moidemd
REPO_NAME := $(IMAGE_NAME)
VERSION ?= 1.0.0-dem-20190515
TAGS ?= 1.0.0-dem-20190515,latest

comma := ,
eq = $(if $(or $(1),$(2)),$(and $(findstring $(1),$(2)),\
                                $(findstring $(2),$(1))),1)

all: $(EXEC)

$(EXEC): $(OBJS)
	$(CC) $(CFLAGS) -o $(EXEC) $< $(LDFLAGS) $(LIBS)

.cpp.o:
	$(CC) $(CFLAGS) $(INCLUDES) -c $<

$(DEM): $(DEMZIP)
	7za x $< $(DEM)
	touch $(DEM)

$(DEMZIP):
	wget --no-check-certificate -O $(DEMZIP) http://dtm.moi.gov.tw/tif/$(DEMZIP) 

run: $(EXEC) $(DEM)
	./$(EXEC) -p 8082 $(DEM)

docker:
	docker build --network=host --force-rm \
		$(if $(call eq,$(no-cache),yes),--no-cache --pull,) \
		-t $(IMAGE_NAME):$(VERSION) .

tags:	
	$(foreach tag, $(subst $(comma), ,$(TAGS)),$(call docker.tags.do,$(VERSION),$(tag)))
define docker.tags.do
	$(eval from := $(strip $(1)))
	$(eval to := $(strip $(2)))
	docker tag $(IMAGE_NAME):$(from) $(IMAGE_NAME):$(to)
endef

post-push-hook:
	@mkdir -p hooks/
	docker run --rm -i -v "$(PWD)/post_push.tmpl.php":/post_push.php:ro \
		php:alpine php -f /post_push.php -- \
			--image_tags='$(TAGS)' \
		> hooks/post_push

push:
	docker push $(REPO_NAME):$(VERSION)

clean:
	@rm -f $(MOIDEMD)

.PHONY: all clean run docker tags push post-push-hook
