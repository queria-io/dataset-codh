"""CODH（人文学オープンデータ共同利用センター）データパイプライン。

1. geoshape: 歴史的行政区域データセットβ版の市区町村 ID の一覧と、基準日ごとの境界を取り出す
2. dbt: dbt ビルド
"""

import logging

from dbt.cli.main import dbtRunner

from pipelines.geoshape import download_geoshape

# dbt を読み込むとルートロガーが先に設定されるので、force で上書きする
logging.basicConfig(level=logging.INFO, format="%(message)s", force=True)
logger = logging.getLogger("pipelines")


def dbt_build():
    dbt = dbtRunner()
    for command in (["deps"], ["build"], ["docs", "generate"]):
        result = dbt.invoke(command)
        if not result.success:
            raise SystemExit(f"dbt {' '.join(command)} failed")


def main():
    logger.info("1/2: geoshape (歴史的行政区域データセットβ版)")
    download_geoshape()

    logger.info("2/2: dbt build")
    dbt_build()


if __name__ == "__main__":
    main()
