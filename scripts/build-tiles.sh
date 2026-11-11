#!/usr/bin/env bash
#
# 基準日ごとの市区町村の境界 (city.boundary) を、地図で使うベクタタイル (PMTiles) にして
# R2 (queria-assets) の codh/ に置く。
#
# Queria の公開 DuckLake から決めた基準日の境界を書き出し、tippecanoe で 1 つの PMTiles にする。
# レイヤーは基準日ごとに city_YYYYMMDD、属性は id (geoshape_city_id)・code (その時点の
# 市区町村コード、無ければ省く)・name (郡または市と市区町村名)。地物は落とさない。
# 元のデータセットは更新されないので、定期実行はしない。基準日を変えたときだけ作り直す。
#
# 使い方:
#   scripts/build-tiles.sh             # 作ってアップロード
#   scripts/build-tiles.sh --dry-run   # 作るまで (アップロードしない)
#
# 必要なもの: uv、tippecanoe、tile-join、pmtiles CLI、aws CLI (アップロードするとき)
# 必要な環境変数 (アップロードするとき): R2_ACCOUNT_ID R2_ACCESS_KEY_ID R2_SECRET_ACCESS_KEY
set -euo pipefail

# 地図に出す基準日。国土地理院の年代別空中写真 (1945〜1990 年) の年代に合わせ、
# 国土数値情報由来で全国を覆う時点を選んでいる
DATES="1950-10-01 1965-10-01 1975-10-01 1980-10-01 1985-10-01"
BUCKET="queria-assets"
DATA="https://data.queria.io/datasets/queria"
WORK_DIR="${TMPDIR:-/tmp}/codh-tiles"

dry_run=false
case "${1:-}" in
  --dry-run) dry_run=true ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

for cmd in uv tippecanoe tile-join pmtiles; do
  command -v "$cmd" >/dev/null || { echo "${cmd} が要ります" >&2; exit 1; }
done
if [ "$dry_run" = false ]; then
  command -v aws >/dev/null || { echo "aws CLI が要ります" >&2; exit 1; }
  : "${R2_ACCOUNT_ID:?R2_ACCOUNT_ID が未設定}"
  : "${R2_ACCESS_KEY_ID:?R2_ACCESS_KEY_ID が未設定}"
  : "${R2_SECRET_ACCESS_KEY:?R2_SECRET_ACCESS_KEY が未設定}"
fi

name="city-boundaries-$(date -u +%Y%m%d)"
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "==> 境界を書き出す"
uv run --quiet --with 'duckdb>=1.4,<2' python - "$DATA" $DATES <<'PY'
import sys, duckdb
data, *dates = sys.argv[1:]
c = duckdb.connect()
c.sql("INSTALL spatial; LOAD spatial; INSTALL ducklake; INSTALL httpfs")
c.sql(f"ATTACH 'ducklake:{data}/codh/ducklake.duckdb' AS codh (READ_ONLY)")
for d in dates:
    c.sql(f"""COPY (
      SELECT geoshape_city_id AS id, city_code AS code,
        concat_ws(' ', county_or_city, name) AS name, geometry
      FROM codh.city.boundary WHERE reference_date = DATE '{d}' ORDER BY id
    ) TO 'city_{d.replace("-", "")}.geojsonl' (FORMAT GDAL, DRIVER 'GeoJSONSeq')""")
    n = c.sql(f"SELECT count(*) FROM codh.city.boundary WHERE reference_date = DATE '{d}'").fetchone()[0]
    print(f"{d}: {n}")
PY

echo "==> タイルにする"
# ズームは queria-web の今の市区町村の境界タイル (city: 4〜12) と同じ
common=(--force --no-feature-limit --no-tile-size-limit --detect-shared-borders
  --no-tiny-polygon-reduction -P -q -Z4 -z12)
parts=()
for d in $DATES; do
  layer="city_${d//-/}"
  tippecanoe "${common[@]}" -o "${layer}.pmtiles" -l "$layer" "${layer}.geojsonl"
  parts+=("${layer}.pmtiles")
done
tile-join --force -q --no-tile-size-limit -n "codh city boundaries" \
  -N "CODH 歴史的行政区域データセットβ版の市区町村の境界 (${DATES})" -o "${name}.pmtiles" "${parts[@]}"
pmtiles show "${name}.pmtiles" >/dev/null
echo "==> 生成: ${WORK_DIR}/${name}.pmtiles ($(du -h "${name}.pmtiles" | cut -f1))"

if [ "$dry_run" = true ]; then
  echo "==> --dry-run なのでアップロードはしません"
  exit 0
fi

echo "==> R2 に置く"
export AWS_ACCESS_KEY_ID="$R2_ACCESS_KEY_ID"
export AWS_SECRET_ACCESS_KEY="$R2_SECRET_ACCESS_KEY"
export AWS_DEFAULT_REGION="auto"
endpoint="https://${R2_ACCOUNT_ID}.r2.cloudflarestorage.com"
key="codh/${name}.pmtiles"
# 配信中のファイルは差し替えない。作り直したら日付の違う名前で置き、読む側を向け替える
if aws s3api head-object --bucket "$BUCKET" --key "$key" --endpoint-url "$endpoint" >/dev/null 2>&1; then
  echo "==> ${key} は既にあります。日を改めて流してください" >&2
  exit 1
fi
# PMTiles に Content-Encoding は付けない (中のタイルが gzip 済みで、Range の位置がずれる)
aws s3 cp "${name}.pmtiles" "s3://${BUCKET}/${key}" --endpoint-url "$endpoint" \
  --content-type application/octet-stream \
  --cache-control "public, max-age=31536000, immutable"
echo "==> https://assets.queria.io/codh/${name}.pmtiles"
