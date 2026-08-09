# 內政部 20 公尺網格 DTM 高程服務

> Elevation API serving Taiwan's Ministry of the Interior 20 m grid DTM.
> Coverage is Taiwan and its offshore islands only — see the coverage table
> below. For elevation service in other regions, start from
> [demd](https://github.com/outdoorsafetylab/demd).

以 [demd](https://github.com/outdoorsafetylab/demd) 為基底、預先包好內政部 20 公尺網格數值地形模型（DTM）的高程查詢服務。API、參數與行為皆同 demd，這個 repo 只負責資料與封裝。

```shell
docker run -it --rm -p 8080:8080 outdoorsafetylab/moidemd
curl -XPOST --data '[[120.957283,23.47]]' http://127.0.0.1:8080/v1/elevations
```

## 覆蓋範圍

內政部這套 20 公尺 DTM 並未涵蓋所有中華民國轄區，而且**缺口從資料集標題完全看不出來**。查詢落在範圍外時回傳的是 `null` 而不是錯誤，所以在倚賴回傳值之前，值得先知道邊界在哪。

### 有涵蓋

| 區域 | 備註 |
|---|---|
| 臺灣本島 | |
| 澎湖 | |
| 金門 | 含烈嶼（小金門） |
| 基隆嶼 | |
| 蘭嶼 | |
| 小琉球 | |

### 2025 年版移除的

| 區域 | 最後涵蓋版本 |
|---|---|
| 綠島 | 2020 年版 |
| 龜山島（部分涵蓋） | 2020 年版 |

2025 年版在重疊處全面較新，唯獨掉了這兩座島 —— 不分幅檔沒有，臺東縣／宜蘭縣的分幅檔也沒有。資料集標題本身就記錄了這個變化：2020 與 2022 年版名為「全臺灣**及部分離島**」，2024 與 2025 年版只剩「全臺灣」。

需要這兩座島的話，請釘選前一版 image（服務的是 2020 年版資料）：

```shell
docker run -it --rm -p 8080:8080 outdoorsafetylab/moidemd:2020
```

追蹤於 [#2](https://github.com/outdoorsafetylab/moidemd/issues/2)。

### 任何內政部 20 公尺版本都未涵蓋

| 區域 | 備註 |
|---|---|
| 馬祖列島（連江縣） | 南竿、北竿、東引… |
| 北方三島 | 彭佳嶼、棉花嶼、花瓶嶼 |
| 烏坵 | |
| 東沙島 | |
| 太平島 | 南沙 |

連江縣從未出現在分幅清單中，北方三島與南海諸島則落在所有已發布圖幅的範圍之外。**這些不是退步** —— 沒有任何一版內政部資料收錄過它們。要提供這些區域就得引入內政部以外的第二個資料源，那會改變這個 image 的定位。

## 資料出處

每一顆 raster 都是政府發布的原始檔案，只從封存檔解壓，**其餘完全未經處理** —— 不重投影、不重取樣、不壓縮、不裁切。本服務回傳的高程就是政府自己的數字。

這個宣稱是被強制執行的，不是嘴上說說：`scripts/fetch-dem.py` 為每一個解壓出來的 raster 記錄 SHA-256，不符即中止。截斷的下載、被掉包的檔案、無聲的改版，都到不了 image 裡。

| 資料集 | data.gov.tw | 使用檔案 |
|---|---|---|
| 2025年版全臺灣20公尺網格數值地形模型DTM資料 | [176927](https://data.gov.tw/dataset/176927) | 不分幅_台灣 / 澎湖 / 金門 |

授權為政府資料開放授權條款第 1 版，免費，發布機關為內政部地政司。

取得資料：

```shell
make dem
```

Raster 為 TWD97（本島 EPSG:3826，澎湖與金門為 119°E 分帶）、20 公尺網格、Float32，高程基準 TWVD2001。請求座標仍為 WGS84 經緯度。

### 內政部改版時

更新是不定期的，所以雜湊值遲早會對不上 —— 那本身不必然是故障。但它代表本服務回傳的高程將會改變，這應該是一個經過確認的決定，而不是某次建置自己撿回來的東西。要採用新版：

```shell
rm -rf dem && make dem          # 會失敗，並印出新的 digest
sha256sum dem/2025/*            # 填回 scripts/fetch-dem.py
make verify                     # 重建 image 後，比對覆蓋範圍是否仍符合本文件
```

`make verify` 會先重建 image，所以被檢查的是新抓的 raster，不是上次發佈的那顆。

合併前請挑幾個已知點與前一版 image 比對 —— 2025 年版無聲無息地掉了兩座島，而那正是單純更新雜湊值會直接放行的那種改變。

## 建置環境

`scripts/fetch-dem.py` 取用的 tgos.tw **對台灣以外的來源 IP 回傳 403**。實測 Cloud Build worker：

| region | 對外 IP | 結果 |
|---|---|---|
| `asia-east1` | 34.81.101.227 | 200 |
| `asia-northeast1` | 35.189.159.151 | 403 |
| `global`（us-central1） | 34.61.42.12 | 403 |

阻擋依據是地理位置，不是 User-Agent 或 ASN —— 換成瀏覽器 UA 一樣被拒。因此 **Cloud Build trigger 必須建在 `asia-east1`**，把它移到其他區域或改回 global，唯一的症狀就是取檔步驟失敗。

在台灣本地執行 `make dem` 不受影響。

## 與 demd 的關係

這個 repo 只有資料與封裝。其餘的一切 —— API、座標處理、`-A` 與 `-m` 等參數、測試套件 —— 都在 [demd](https://github.com/outdoorsafetylab/demd)。若你需要的是其他地區的高程服務，請從那裡開始。

## 開發

```shell
make dem      # 下載並驗證內政部資料
make test     # 下載器的重試／續傳／雜湊驗證測試
make verify   # 重建 image，並確認覆蓋範圍與本文件一致
```
