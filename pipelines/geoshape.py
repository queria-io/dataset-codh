"""CODH「歴史的行政区域データセットβ版」の市区町村 ID と境界を取り出す。

1. municipality: GeoNLP 地名語辞書の形の ID 一覧（geoshape-city-geolod.csv）をそのまま保存する
2. boundary: 基準日ごとの全国の市区町村境界（jp_city.h.topojson、111 時点）を
   基準日ごとの Parquet（形は WKB）にする。Parquet がある基準日は取り直さない

出力:
- data/codh/municipality.csv
- data/codh/boundary/<基準日>.parquet

データソース: ROIS-DS 人文学オープンデータ共同利用センター（CODH）
https://geoshape.ex.nii.ac.jp/city/
"""

import logging
import os
import re
from pathlib import Path

import duckdb

from shared.fetch import download, fetch, replacing, write_atomic

logger = logging.getLogger("pipelines")

BASE_URL = "https://geoshape.ex.nii.ac.jp/city"
MUNICIPALITY_URL = "https://geonlp.ex.nii.ac.jp/dictionary/geoshape-city/geoshape-city-geolod.csv"
USER_AGENT = "dataset-codh (+https://github.com/queria-io/dataset-codh)"
OUT = Path("data/codh")
DATE_LINK = re.compile(r'href="(\d{8})\.html"')


def reference_dates(html: str) -> list[str]:
    """基準日の一覧のページ（/city/time/）から基準日（YYYYMMDD）を返す。"""
    return sorted(set(DATE_LINK.findall(html)))


def selected(dates: list[str]) -> list[str]:
    """CODH_DATES（カンマ区切り）があればその基準日だけにする。PR のビルド確認で使う。"""
    wanted = os.environ.get("CODH_DATES")
    if not wanted:
        return dates
    keep = set(wanted.split(","))
    return [d for d in dates if d in keep]


def download_municipality() -> None:
    body = fetch(MUNICIPALITY_URL, user_agent=USER_AGENT)
    if not body.startswith(b"geolod_id,entry_id,"):
        raise RuntimeError("geoshape-city-geolod.csv の見出しが想定と違う")
    OUT.mkdir(parents=True, exist_ok=True)
    write_atomic(OUT / "municipality.csv", body)


def to_parquet(topojson: Path, date: str, out: Path) -> int:
    """TopoJSON の市区町村境界を、基準日を付けた Parquet に書く。行数を返す。

    - 属性は基準日の出典（国土数値情報・行政界変遷データベース）で列が違うので JSON で持つ
    - 座標の丸めで自己交差などの壊れた形が 2〜3% あるので、直してポリゴンだけを残す
    - 同じ ID の形が複数あること（1920 年の舌辛村と舌辛村他）があるので、形は合わせ、属性は面積の大きい方を取る
    """
    con = duckdb.connect()
    con.execute("INSTALL spatial; LOAD spatial; SET enable_progress_bar = false")
    with replacing(out) as partial:
        con.execute(
            f"""
            COPY (
                WITH t AS (SELECT * EXCLUDE (OGC_FID) FROM ST_Read(?)),
                fixed AS (
                    SELECT
                        id,
                        -- null の値は消える（RFC 7386）ので、形を外すのに使う
                        json_merge_patch(to_json(t), '{{"geom": null}}') AS properties,
                        ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3)) AS geom
                    FROM t
                )
                SELECT
                    strptime('{date}', '%Y%m%d')::DATE AS reference_date,
                    arg_max(properties, ST_Area(geom)) AS properties,
                    ST_AsWKB(CASE WHEN count(*) = 1 THEN any_value(geom) ELSE ST_Multi(ST_Union_Agg(geom)) END) AS geometry
                FROM fixed
                GROUP BY id
                ORDER BY id
            ) TO '{partial}' (FORMAT parquet, COMPRESSION zstd)
            """,
            [str(topojson)],
        )
        rows = con.execute(f"SELECT count(*) FROM read_parquet('{partial}')").fetchone()[0]
        if rows == 0:
            raise RuntimeError(f"{date}: 境界が 0 件")
    return rows


def download_boundary() -> None:
    html = fetch(f"{BASE_URL}/time/", user_agent=USER_AGENT).decode()
    dates = selected(reference_dates(html))
    if not dates:
        raise RuntimeError("基準日が見つからない")
    logger.info("boundary: %d 時点", len(dates))
    (OUT / "boundary").mkdir(parents=True, exist_ok=True)
    (OUT / "work").mkdir(parents=True, exist_ok=True)
    for date in dates:
        out = OUT / "boundary" / f"{date}.parquet"
        if out.exists():
            continue
        topojson = OUT / "work" / f"{date}.topojson"
        download(f"{BASE_URL}/topojson/{date}/jp_city.h.topojson", topojson, user_agent=USER_AGENT)
        rows = to_parquet(topojson, date, out)
        topojson.unlink()
        logger.info("boundary: %s %d 件", date, rows)


def download_geoshape() -> None:
    download_municipality()
    download_boundary()
