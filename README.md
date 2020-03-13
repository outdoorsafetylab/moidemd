# Elevation Service of DTM from Taiwan MOI

This provides a REST API service for querying elevations defined in DTM released by Taiwan MOI.

# How to use this image

1. Start a container running this image:
    ```shell
    docker run -it --rm -p 8082:8082 outdoorsafetylab/moidemd
    ```
1. Try to query the elevation of Mt. Jade, highest peak of Taiwan:
    ```shell
    curl -XPOST --data '[[120.957283,23.47]]' http://127.0.0.1:8082/v1/elevations
    ```

For more detail, see our [base project](https://github.com/outdoorsafetylab/demd) and [base image](https://hub.docker.com/r/outdoorsafetylab/demd).
