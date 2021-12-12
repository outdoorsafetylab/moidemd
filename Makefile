IMAGE_NAME := outdoorsafetylab/moidemd
REPO_NAME ?= outdoorsafetylab/moidemd
VERSION ?= $(subst v,,$(shell git describe --tags --exact-match 2>/dev/null || echo ""))
PORT ?= 8080

# Build docker image.
#
# Usage:
#	make docker/build [no-cache=(no|yes)]

docker/build: $(TIF)
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
	@mkdir -p hooks/
	docker run --rm -i -v "$(PWD)/post_push.tmpl.php":/post_push.php:ro \
		php:alpine php -f /post_push.php -- \
			--image_tags='$(VERSION)' \
		> hooks/post_push
endif

.PHONY: docker/build docker/run docker/tag docker/push
