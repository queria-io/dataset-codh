# dataset-codh

Queria のデータセット `codh`（歴史的行政区域データセット（CODH））のリポジトリです。データセットの説明は [docs/index.md](docs/index.md) にあります。

## ビルド

```bash
git submodule update --init
uv sync
scripts/build.sh   # fdl checkout → python main.py → fdl commit
```

境界の TopoJSON は全部で約 2.5GB（変換した Parquet は約 3.4GB）あり、取得した基準日は `data/codh/boundary/` の Parquet を使い回します。元のデータセットは 2023 年 10 月から更新されていないため、定期実行はしません。main への push と手動の実行（workflow_dispatch）で Sync が実行されます。PR のビルド確認（`.github/workflows/build.yml`）は 3 時点だけ取得します（`CODH_DATES=18891231,19501001,20230101`）。
