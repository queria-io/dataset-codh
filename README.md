# 歴史的行政区域データセット（CODH）

ROIS-DS 人文学オープンデータ共同利用センター（CODH）の「歴史的行政区域データセットβ版」を、SQL で検索・集計できるテーブルにしたデータセットです。1889 年の市制・町村制以降に存在した市区町村に Geoshape 市区町村 ID を付け、有効期間・代表点・基準日ごとの境界を収録しています。合併や改称で消えた市町村も 1 つの ID で検索でき、現在のどの市区町村に入るかも持っています。

## 出典と利用条件

[歴史的行政区域データセットβ版](https://geoshape.ex.nii.ac.jp/city/)の、市区町村 ID の一覧と基準日ごとの市区町村境界を加工しています。

| 原典 | テーブル |
| --- | --- |
| [歴史的行政区域データセットβ版地名辞書](https://geonlp.ex.nii.ac.jp/dictionary/geoshape-city/)（`geoshape-city-geolod.csv`、2023 年 10 月 18 日版） | `city.municipality` |
| 基準日ごとの全国の市区町村境界（`topojson/<基準日>/jp_city.h.topojson`、111 時点） | `city.boundary` |
| 上の境界と Queria の `nlftp.boundary.municipality`（国土数値情報 行政区域データ） | `city.current_overlap` |
| 上の市区町村 ID の一覧と境界 | `city.succession` |

- データセットは [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/) で提供されています。使うときは「『歴史的行政区域データセットβ版』（CODH作成） doi:10.20676/00000447」と出典を書き、Queria が加工したものであることを明記してください
- 境界のうち国土数値情報「行政区域データ」から作られた部分は、[国土数値情報の利用規約](https://nlftp.mlit.go.jp/ksj/other/agreement.html)に従います

## テーブル

| テーブル | 内容 |
| --- | --- |
| `city.municipality` | 1 行が 1 つの Geoshape 市区町村 ID。1889 年以降の市区町村の名前・有効期間・代表点と、代表点が入る現在の市区町村 |
| `city.boundary` | 1 行が 1 基準日の 1 市区町村の境界。1889〜2023 年の 111 時点で 54 万行 |
| `city.current_overlap` | 1 行が ID と現在の市区町村の 1 組。最後の基準日の境界と現在の境界の重なりの面積と割合 |
| `city.succession` | 1 行が消えた市区町村と、その区域を受け継いだ市区町村の 1 組。合併・編入・改称・分割をたどれます |

## 使い方

合併前の市町村が、現在のどの市区町村に入っているか:

```sql
SELECT m.address, m.valid_from, m.valid_to, o.current_city_code, round(o.past_share, 3) AS past_share
FROM codh.city.municipality AS m
JOIN codh.city.current_overlap AS o USING (geoshape_city_id)
WHERE m.prefecture = '三重県' AND m.county_or_city = '員弁郡' AND NOT m.is_current
  AND o.past_share >= 0.5
ORDER BY m.valid_to;
```

ある市区町村が、合併や改称でどう移り変わったか（田無町 → 田無市 → 西東京市）:

```sql
WITH RECURSIVE chain AS (
  SELECT geoshape_city_id, 0 AS step FROM codh.city.municipality WHERE address = '東京都北多摩郡田無町'
  UNION ALL
  SELECT s.successor_geoshape_city_id, c.step + 1
  FROM chain AS c JOIN codh.city.succession AS s USING (geoshape_city_id)
)
SELECT c.step, m.address, m.valid_from, m.valid_to
FROM chain AS c JOIN codh.city.municipality AS m USING (geoshape_city_id)
ORDER BY c.step;
```

現在の市区町村への読み替えは、境界があれば `current_overlap` の `past_share` の大きい行、なければ `municipality` の `current_city_code`（代表点）を使います。

## 市区町村 ID と有効期間

- ID は CODH が付けたものです。1968 年以降の市区町村コードを持つものは「コード 5 桁 + A + コードの開始年」（24322A1968）、持たないものは「都道府県コード 2 桁 + B + 7 桁」（24B0050015）です。各市区町村のページは `https://geoshape.ex.nii.ac.jp/city/resource/<ID>.html` です
- 改称や市制施行で名前が変わると別の ID になります。同じ名前の村が別の県や郡に何度も出てくるため、名前で検索するときは都道府県と郡も指定してください
- 有効期間は `valid_from` から `valid_to` までです（`valid_to` の日に消えました）。`valid_to` が NULL なら現存します。原典が年だけ・年月だけの値はその年・月の 1 日にして、精度を `valid_from_precision`・`valid_to_precision` に持ちます

## 代表点と現在の市区町村

- 代表点は CODH が選んだ点です。市区町村役場（国土数値情報 P34）、なければ旧役場の支所などの公的施設（P05）、郵便局（P30）、警察署（P18）、消防署（P17）、国の機関（P28）の順に選び、どれもなければ境界の重心を使っています（`point_source`）
- `current_city_code` は代表点が入る現在の市区町村です（`nlftp.boundary.municipality`、国土数値情報 N03 の最新版。政令指定都市は区）。海岸の埋立地などで代表点が現在の境界の外に出ると NULL になります
- `current_overlap` は、ID ごとに最後の基準日の境界を現在の市区町村の境界と重ねたものです。`past_share` は過去の市区町村の面積のうち現在の市区町村に入る割合で、CODH のページの「過去の行政区域と重なる現在の市区町村一覧」と同じ計算です
- 元の資料が違う境界を重ねるため、境界沿いに数 % 以下の小さな重なりが出ます。現存する市区町村も入ります（自分自身とほぼ 100% で重なります）
- 境界のない ID（行政界変遷データベースの範囲外で 1920 年より前に消えた市町村など）は `current_overlap` に行がありません

## 前後の市区町村

- `succession` は、消えた日（`valid_to`）に存在した市区町村のうち、その日以後の最初の基準日の境界に、消えた市区町村の代表点を含むものを後の市区町村にしています（`method` が `point`）。合併・改称では新しくできた市区町村、編入では続いている市区町村と組になります（`successor_is_new`）
- 分割では、その日に生まれた市区町村の代表点が、消えた市区町村の最後の境界に入るものも後にしています（`split`）
- 境界がどちらにも無い組は、その日に生まれ、代表点の入る現在の市区町村が同じものを後にしています（`current_city`）
- 代表点が境界の外に出る市区町村や、消えた日の後に境界の時点が無い市区町村（500 ほど）は、後の市区町村がありません

## 境界の注意

- 境界の出典は 2 つあり、`source` で分かれます
  - `n03`: 国土数値情報「行政区域データ」。1920 年 1 月 1 日、1950〜1965 年の国勢調査の年（10 月 1 日）と、1970 年以降の時点。全国を覆います
  - `hensen`: 筑波大学「行政界変遷データベース」。1889〜1968 年の各年 12 月 31 日。1995 年の町丁字界を単位に所属を年ごとに記録したものです。1889〜1919 年は一部の県だけ（370 市町村ほど）で、1920 年からは全国を覆います。行政界変遷データベースにない地域（北海道の一部など）は、同じ時点に国土数値情報の形が数十行入っています
- 同じ年に 2 つの出典の時点があるとき（1950 年 10 月 1 日と 12 月 31 日など）、作り方が違うため境界は一致しません。1985 年以前の境界は 1995 年以降と元の資料が違い、隣の市区町村と小さく重なったり離れたりすることがあります
- 境界は CODH が配布する高解像度の TopoJSON（`jp_city.h`）で、座標は約 3m 単位に丸められています。小さな飛地が省かれていることがあります。丸めで壊れた形（自己交差など、全体の約 2.5%）は `ST_MakeValid` で修正しています。同じ基準日に同じ ID の形が複数あるもの（1920 年の舌辛村など）は 1 つに統合しています
- 政令指定都市は区の単位です。所属未定地（`municipality` にない ID）は収録していません

## 地図のタイル

`scripts/build-tiles.sh` は、5 つの基準日（1950・1965・1975・1980・1985 年の 10 月 1 日）の境界を 1 つの PMTiles にして、`https://assets.queria.io/codh/city-boundaries-<作成日>.pmtiles` に置きます。

- レイヤーは基準日ごとに `city_19501001` のように分かれ、ズームは 4〜12 です
- 地物の属性は `id`（geoshape_city_id）・`code`（その時点の市区町村コード。無い市町村は省きます）・`name`（郡または市と市区町村名）です
- 元のデータセットは更新されないため、基準日を変えたときだけ作り直します。作り直したファイルは日付の違う名前で置き、配信中のファイルは差し替えません

```bash
scripts/build-tiles.sh --dry-run   # 作るまで（tippecanoe・tile-join・pmtiles CLI が要ります）
scripts/build-tiles.sh             # R2 に置く（R2_ACCOUNT_ID・R2_ACCESS_KEY_ID・R2_SECRET_ACCESS_KEY が要ります）
```

## ビルド

```bash
git submodule update --init
uv sync
scripts/build.sh   # fdl checkout → python main.py → fdl commit
```

境界の TopoJSON は全部で約 2.5GB（変換した Parquet は約 3.4GB）あり、取得した基準日は `data/codh/boundary/` の Parquet を使い回します。元のデータセットは 2023 年 10 月から更新されていないため、定期実行はしません。main への push と手動の実行（workflow_dispatch）で Sync が実行されます。PR のビルド確認（`.github/workflows/build.yml`）は 3 時点だけ取得します（`CODH_DATES=18891231,19501001,20230101`）。
