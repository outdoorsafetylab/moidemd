# Elevation Service with DTM from Taiwan MOI

This is a packager/docker builder project of our [Elevation Service](https://github.com/outdoorsafetylab/demd). It builds the following artifacts:

- Debian package for VM-based installation
- Docker image for general dockerized deployment (and also published on [Docker Hub](https://hub.docker.com/r/outdoorsafetylab/moidemd).
- Docker image for Google Cloud Run, which is a fully managed dockerized deployment service specifically for HTTP-based stateless service.

## Prerequisites

- All the builds require `docker`. Please make sure it was installed.
- Cloud Run build require `gcloud` command. Please [check](https://cloud.google.com/sdk/docs/downloads-interactive) here for installation instructions.

## Debian Package

Currently it only build Debian package for Ubuntu 18.04 LTS, pull request or patch files are welcome for other `dpkg` distributions or for `.rpm` builds.

To build Debian package:

```shell
make deb
```

After success build, the `.deb` file(s) can be found under `./build`.

## Docker Image

To build general purpose docker image:

```shell
make docker
```

After success build, you can find docker image with name of `outdoorsafetylab/moidemd`.

```shell
docker images --filter=reference='outdoorsafetylab/moidemd:*'
```

## Cloud Run Image

This build leverages Google's Cloud Build to build and push docker image onto Google Container Registry. You have to [setup your Google project for Cloud Builds](https://cloud.google.com/cloud-build/docs/quickstart-docker) first.

To build docker image for Cloud Run:

```shell
make GPROJ=<your google project ID> cloudrun
```

After success build, docker image will be pushed to Google Container Registry with image name of `asia.gcr.io/<your google project ID>/moidemd`. You can adjust settings by modifying `cloudbuild.yaml`.

However, the best practice to use Cloud Build is to setup Trigger(s) for CI/CD. Please check Cloud Build documentation for detail.
