VERSION := 1.1.0
TAGS ?= 1.1.0-ubuntu-18.04,latest
IMAGE_NAME := outdoorsafetylab/moidemd
GPROJ := outdoorsafetylab

comma := ,

GITURL := https://github.com/outdoorsafetylab/demd.git
BRANCH := v$(VERSION)
SOURCE := ./source
DEBIAN := $(SOURCE)/debian
BUILD := ./build

DEM := ./dem
DEM_TW := DEMg_geoid2014_20m_20190515.tif
DEM_KM := DEMg_20m_KM_20190521.tif
DEM_PH := DEMg_20m_PH_20190521.tif
DEMS := $(DEM_TW) $(DEM_KM) $(DEM_PH)
DEMFILES := $(addprefix $(DEM)/,$(DEMS))
TEMP7Z := /tmp/dem.7z

WGET := wget --no-check-certificate

$(DEM)/$(DEM_TW):
	$(WGET) -O $(TEMP7Z) "http://dtm.moi.gov.tw/tif/taiwan_TIF格式.7z"
	$(call un7z.do,$@)

$(DEM)/$(DEM_KM):
	$(WGET) -O $(TEMP7Z) "http://dtm.moi.gov.tw/tif/金門.7z"
	$(call un7z.do,$@)

$(DEM)/$(DEM_PH):
	$(WGET) -O $(TEMP7Z) "http://dtm.moi.gov.tw/tif/澎湖.7z"
	$(call un7z.do,$@)

define un7z.do
	$(eval file := $(strip $(1)))
	@which 7za || sudo apt install p7zip-full
	7za x $(TEMP7Z) $(file)
	touch $(file)
	rm -f $(TEMP7Z)
endef

all: deb docker tags

clean:
	rm -rf $(BUILD)
	rm -rf $(SOURCE)

$(SOURCE):
	rm -rf $(SOURCE)
	git clone $(GITURL) $(SOURCE)
	cd $(SOURCE) && git checkout $(BRANCH)
	rm -rf $(DEBIAN)/
	mkdir -p $(DEBIAN)/
	cat deb/changelog.in \
		> $(DEBIAN)/changelog
	cat deb/compat.in \
		> $(DEBIAN)/compat
	cat deb/control.in \
		> $(DEBIAN)/control
	cat deb/copyright.in \
		> $(DEBIAN)/copyright
	cat deb/moidemd.postinst.in \
		> $(DEBIAN)/moidemd.postinst
	cat deb/moidemd.service.in \
		> $(DEBIAN)/moidemd.service
	cat deb/rules.in | sed \
		-e 's#%%VERSION%%#$(VERSION)#g' \
		-e 's#%%DEMS%%#$(addprefix /dem/,$(DEMS))#g' \
		> $(DEBIAN)/rules
	chmod +x $(DEBIAN)/rules

deb: $(SOURCE)
	$(call docker.debuild.do,$@/ubuntu/18.04,$(IMAGE_NAME)-debuild-ubuntu:18.04)

define docker.debuild.do
	$(eval dir := $(strip $(1)))
	$(eval image_name := $(strip $(2)))
	docker build \
	 	--network=host --force-rm \
		-t $(image_name) \
		-f $(dir)/Dockerfile \
		$(dir)
	mkdir -p $(BUILD)
	docker run -it \
		-v $(abspath $(SOURCE)):/source:ro \
		-v $(abspath $(DEM)):/dem:ro \
		-v $(abspath $(BUILD)):/output \
		-v $(abspath $(dir))/build.sh:/build.sh:ro \
		-e USER=$(shell id -u) \
		-e GROUP=$(shell id -g) \
		$(image_name) \
		/build.sh
endef

docker:
	$(call docker.build.do,$@/ubuntu/18.04,$(VERSION))

define docker.build.do
	$(eval dir := $(strip $(1)))
	$(eval tag := $(strip $(2)))
	docker build \
	 	--network=host --force-rm \
		-t $(IMAGE_NAME):$(tag) \
		-f $(dir)/Dockerfile \
		$(dir)
endef

tags:	
	$(foreach tag, $(subst $(comma), ,$(TAGS)),$(call docker.tag.do,$(VERSION)-ubuntu-18.04,$(tag)))

define docker.tag.do
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

cloudbuild:
	gcloud builds submit --project $(GPROJ) --config ./cloudrun/cloudbuild.yaml --substitutions=TAG_NAME="v$(VERSION)"

.PHONY: all clean $(SOURCE) deb docker tags
