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
	@7za || sudo apt install p7zip-full
	7za x $< $(DEM)
	touch $(DEM)

$(DEMZIP):
	wget --no-check-certificate -O $(DEMZIP) "http://dtm.moi.gov.tw/tif/taiwan_TIF格式.7z"

run: $(EXEC) $(DEM)
	./$(EXEC) -p 8082 $(DEM)

deb:
	rm -rf debian/
	mkdir -p debian/
	cat deb/changelog.in \
		> debian/changelog
	cat deb/compat.in \
		> debian/compat
	cat deb/control.in \
		> debian/control
	cat deb/copyright.in \
		> debian/copyright
	cat deb/moidemd.postinst.in \
		> debian/moidemd.postinst
	cat deb/moidemd.service.in | sed \
		-e 's#%%DEM%%#$(DEM)#g' \
		> debian/moidemd.service
	cat deb/rules.in | sed \
		-e 's#%%VERSION%%#$(VERSION)#g' \
		-e 's#%%DEM%%#$(DEM)#g' \
		> debian/rules
	chmod +x debian/rules
	debuild -b -us -uc

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

.PHONY: all clean run deb docker tags push post-push-hook
