EXEC := moidemd
CC := g++
LDFLAGS ?=
LIBS ?= -lgdal -levent -ljson-c
SOURCES := $(wildcard *.cpp)
# Objs are all the sources, with .cpp replaced by .o
OBJS := $(SOURCES:.cpp=.o)

DEM_TW_7Z := dem_tw.7z
DEM_TW := DEMg_geoid2014_20m_20190515.tif
DEM_KM_7Z := dem_km.7z
DEM_KM := DEMg_20m_KM_20190521.tif
DEM_PH_7Z := dem_ph.7z
DEM_PH := DEMg_20m_PH_20190521.tif
DEMS := $(DEM_TW) $(DEM_KM) $(DEM_PH)

IMAGE_NAME := outdoorsafetylab/moidemd
REPO_NAME := $(IMAGE_NAME)
VERSION ?= 1.0.0-dem-20190515
TAGS ?= 1.0.0-dem-20190515,latest

comma := ,
eq = $(if $(or $(1),$(2)),$(and $(findstring $(1),$(2)),\
                                $(findstring $(2),$(1))),1)

all: $(EXEC)

$(EXEC): $(OBJS)
	$(CC) $(strip $(CFLAGS) )$^ -o $@ $(strip $(LDFLAGS) $(LIBS))

%.o: %.cpp
	$(CC) $(strip $(CFLAGS) $(INCLUDES) )-c $< -o $@

$(DEM_TW_7Z):
	wget --no-check-certificate -O $@ "http://dtm.moi.gov.tw/tif/taiwan_TIF格式.7z"

$(DEM_TW): $(DEM_TW_7Z)
	$(call un7z.do,$<,$@)

$(DEM_KM_7Z):
	wget --no-check-certificate -O $@ "http://dtm.moi.gov.tw/tif/金門.7z"

$(DEM_KM): $(DEM_KM_7Z)
	$(call un7z.do,$<,$@)

$(DEM_PH_7Z):
	wget --no-check-certificate -O $@ "http://dtm.moi.gov.tw/tif/澎湖.7z"

$(DEM_PH): $(DEM_PH_7Z)
	$(call un7z.do,$<,$@)

define un7z.do
	$(eval archive := $(strip $(1)))
	$(eval file := $(strip $(2)))
	@7za || sudo apt install p7zip-full
	7za x $(archive) $(file)
	touch $(file)
endef

run: $(EXEC) $(DEMS)
	./$(EXEC) -p 8082 .

deb: $(EXEC) $(DEMS)
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
	cat deb/moidemd.service.in \
		> debian/moidemd.service
	cat deb/rules.in | sed \
		-e 's#%%VERSION%%#$(VERSION)#g' \
		-e 's#%%DEMS%%#$(DEMS)#g' \
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
	@rm -f $(MOIDEMD) $(OBJS)

.PHONY: all clean run deb docker tags push post-push-hook
