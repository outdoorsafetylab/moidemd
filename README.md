# Elevation Service with DTM from Taiwan MOI

This provides a REST API service for querying elevations defined in DTM released by Taiwan MOI, which covers:

1. Taiwan
1. Penghu
1. Kinmen

# How to use (as docker)

1. Start a container running our public [docker image](https://hub.docker.com/r/outdoorsafetylab/moidemd):
    ```shell
    docker run -it --rm -p 8082:8080 outdoorsafetylab/moidemd
    ```
1. Try to query the elevation of Mt. Jade, highest peak of Taiwan:
    ```shell
    curl -XPOST --data '[[120.957283,23.47]]' http://127.0.0.1:8082/v1/elevations
    ```

If you need elevation service for other area, please see our [base project](https://github.com/outdoorsafetylab/demd) for detail.
