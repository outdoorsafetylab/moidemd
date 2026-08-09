# Elevation Service with DTM from Taiwan MOI

A ready-to-run elevation API serving the Ministry of the Interior's 20 m grid
DTM. It is [demd](https://github.com/outdoorsafetylab/demd) with the MOI
rasters baked in; the API, options and behaviour are demd's.

```shell
docker run -it --rm -p 8080:8080 outdoorsafetylab/moidemd
curl -XPOST --data '[[120.957283,23.47]]' http://127.0.0.1:8080/v1/elevations
```

## Coverage

The MOI 20 m DTM does not cover everything under Taiwanese administration, and
the gaps are not obvious from the dataset titles. A query outside coverage
returns `null` rather than an error, so it is worth knowing where the edges are
before relying on a result.

### Covered

| Area | |
|---|---|
| 臺灣本島 Taiwan main island | |
| 澎湖 Penghu | |
| 金門 Kinmen | incl. 烈嶼 Lieyu |
| 基隆嶼 Keelung Islet | |
| 蘭嶼 Orchid Island | |
| 小琉球 Liuqiu | |

### Dropped by the 2025 release

| Area | Last covered |
|---|---|
| 綠島 Green Island | 2020 |
| 龜山島 Guishan Island (partial) | 2020 |

The 2025 release is newer everywhere it overlaps, but it dropped these two:
they are in neither the unsegmented mosaic nor the 臺東縣 / 宜蘭縣 sheet sets.
The dataset titles record the change — the 2020 and 2022 releases are titled
「全臺灣**及部分離島**」, the 2024 and 2025 ones just 「全臺灣」.

If you need them, pin the previous image, which serves the 2020 rasters:

```shell
docker run -it --rm -p 8080:8080 outdoorsafetylab/moidemd:2020
```

Tracked in [#2](https://github.com/outdoorsafetylab/moidemd/issues/2).

### Not covered by any MOI 20 m DTM release

| Area | |
|---|---|
| 馬祖列島 Matsu (連江縣) | 南竿、北竿、東引… |
| 北方三島 | 彭佳嶼、棉花嶼、花瓶嶼 |
| 烏坵 Wuqiu | |
| 東沙島 Pratas | |
| 太平島 Itu Aba | 南沙 |

連江縣 has never appeared in the county sheet list, and the northern islets and
the South China Sea territories fall outside every published raster's extent.
These are not regressions — no MOI release has included them. Serving them
would mean introducing a second, non-MOI data source, which would change what
this image claims to be.

## Data provenance

Every raster is the published file, unpacked from its distribution archive and
**otherwise untouched** — no reprojection, no resampling, no compression, no
clipping. Elevations this service returns are the government's numbers, and can
be checked against the originals byte for byte.

| Dataset | data.gov.tw | Files used |
|---|---|---|
| 2025年版全臺灣20公尺網格數值地形模型DTM資料 | [176927](https://data.gov.tw/dataset/176927) | 不分幅_台灣 / 澎湖 / 金門 |

政府資料開放授權條款第 1 版 (Open Government Data License v1.0), free of
charge, published by 內政部地政司.

To fetch them:

```shell
make dem
```

The rasters are TWD97 (EPSG:3826 for the main island, the 119°E zone for
Penghu and Kinmen), 20 m grid, Float32, vertical datum TWVD2001. Requests are
in WGS84 longitude/latitude, as before.

## Relationship to demd

This repository holds only the data and packaging. Everything else — the API,
the coordinate handling, options such as `-A` and `-m`, and the test suite —
lives in [demd](https://github.com/outdoorsafetylab/demd). If you need an
elevation service for a different region, start there.
