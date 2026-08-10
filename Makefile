IMAGE_NAME := outdoorsafetylab/moidemd
REPO_NAME ?= outdoorsafetylab/moidemd
VERSION ?= $(subst v,,$(shell git describe --tags --exact-match 2>/dev/null || echo ""))
PORT ?= 8080

DEM := dem
# The published filenames contain parentheses and non-ASCII characters and are
# kept exactly as distributed, so a marker file stands in for them here.
DEM_STAMP := $(DEM)/.fetched

# Download the published MOI rasters. They are unpacked from their
# distribution archives and not otherwise modified; see README.md.
#
# Usage:
#	make dem

dem: $(DEM_STAMP)

$(DEM_STAMP):
	python3 scripts/fetch-dem.py $(DEM)

# Build docker image.
#
# Usage:
#	make docker/build [no-cache=(no|yes)]

docker/build: dem
	docker build --network=host --force-rm \
		$(if $(call eq,$(no-cache),yes),--no-cache --pull,) \
		-t $(IMAGE_NAME) .

# Run docker image.
#
# Usage:
#	make docker/run

docker/run:
	docker run -it --rm \
		-p $(PORT):$(PORT) \
		$(IMAGE_NAME)

# Unit tests for the downloader's retry and resume behaviour.
#
# Usage:
#	make test

test:
	python3 test/test_fetch.py

# Confirm every published archive URL still resolves. The index's 圖資名稱 and
# its 連結網址 filename are not the same string for every entry, so a typo in
# one looks exactly like a withdrawn file.
#
# Usage:
#	make check-urls

check-urls:
	python3 scripts/fetch-dem.py --check

# Check the image answers for every area README.md claims to cover.
#
# Depends on docker/build on purpose: without it this verifies whatever image
# happens to carry that name locally, and on a clean machine docker would pull
# the published one -- so a run against freshly fetched rasters would pass
# without ever touching them.
#
# To check an already-published image instead, call the script directly:
#	./scripts/verify-coverage.sh outdoorsafetylab/moidemd:2020
#
# Usage:
#	make verify

verify: docker/build
	./scripts/verify-coverage.sh $(IMAGE_NAME)

# Tag docker images.
#
# Usage:
#	make docker/tag [VERSION=<image-version>]

docker/tag:
	docker tag $(IMAGE_NAME) $(REPO_NAME):latest
ifneq ($(VERSION),)
	docker tag $(IMAGE_NAME) $(REPO_NAME):$(VERSION)
endif

# Push docker images.
#
# Usage:
#	make docker/push

docker/push:
	docker push $(REPO_NAME):latest
ifneq ($(VERSION),)
	docker push $(REPO_NAME):$(VERSION)
endif

.PHONY: dem test check-urls docker/build docker/run verify docker/tag docker/push
