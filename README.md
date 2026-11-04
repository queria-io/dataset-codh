# dataset-codh

ROIS-DS 人文学オープンデータ共同利用センター（CODH）の「歴史的行政区域データセットβ版」を Queria のカタログ（[data.queria.io](https://data.queria.io/)）へ取り込むデータセットです。

## データ出典

[歴史的行政区域データセットβ版](https://geoshape.ex.nii.ac.jp/city/)の、市区町村 ID の一覧と基準日ごとの市区町村境界を表にします。

| 原典 | テーブル |
| --- | --- |
| [歴史的行政区域データセットβ版地名辞書](https://geonlp.ex.nii.ac.jp/dictionary/geoshape-city/)（`geoshape-city-geolod.csv`） | `city.municipality` |
| 基準日ごとの全国の市区町村境界（`topojson/<基準日>/jp_city.h.topojson`、111 時点） | `city.boundary` |
| 上の境界と Queria の `nlftp.boundary.municipality`（国土数値情報 行政区域データ） | `city.current_overlap` |

データセットは [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) で提供されています。使うときは「『歴史的行政区域データセットβ版』（CODH作成） doi:10.20676/00000447」と出典を書き、Queria が加工したことを書いてください。
境界のうち国土数値情報「行政区域データ」から作られた部分は、[国土数値情報の利用規約](https://nlftp.mlit.go.jp/ksj/other/agreement.html)に従います。

## 収録テーブル

| テーブル | 内容 |
| --- | --- |
| `city.municipality` | 1 行が 1 つの Geoshape 市区町村 ID。1889 年以降の市区町村の名前・有効期間・代表点と、代表点が入る現在の市区町村 |
| `city.boundary` | 1 行が 1 基準日の 1 市区町村の境界。1889〜2023 年の 111 時点 |
| `city.current_overlap` | 1 行が ID と現在の市区町村の 1 組。最後の基準日の境界と現在の境界の重なりの面積と割合 |

- 改称や市制施行で名前が変わると別の ID になります。同じ名前の村が別の県や郡に何度も出てくるので、名前で引くときは都道府県と郡も見てください
- 境界の出典は 2 つあり、`source` で分かれます。`n03`（国土数値情報）は 1920 年以降で全国を覆います。`hensen`（筑波大学「行政界変遷データベース」）は 1889〜1968 年の各年 12 月 31 日で、収録している地域は一部の県だけです
- 現在の市区町村への読み替えは、境界があれば `current_overlap` の `past_share` の大きい行、無ければ `municipality` の `current_city_code`（代表点）を使います

```sql
-- 合併前の市町村が、現在のどの市区町村に入っているか
SELECT m.address, m.valid_from, m.valid_to, o.current_city_code, round(o.past_share, 3) AS past_share
FROM codh.city.municipality AS m
JOIN codh.city.current_overlap AS o USING (geoshape_city_id)
WHERE m.prefecture = '三重県' AND m.county_or_city = '員弁郡' AND NOT m.is_current
  AND o.past_share >= 0.5
ORDER BY m.valid_to;
```

## ビルド

```bash
git submodule update --init
uv sync
scripts/build.sh   # fdl checkout → python main.py → fdl commit
```

境界は全部で約 2.5GB あり、取得した基準日は `data/codh/boundary/` の Parquet を使い回します。
元のデータセットは 2023 年 10 月の版から更新されていないので、定期実行はしません。main への push と手動の実行（workflow_dispatch）で Sync が回ります。
PR のビルド確認（`.github/workflows/build.yml`）は 3 時点だけ取ります（`CODH_DATES=18891231,19501001,20230101`）。
