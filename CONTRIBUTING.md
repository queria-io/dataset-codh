# ビルドと更新

データセットの概要は [README.md](README.md) にあります。ここにはこのリポジトリでデータセットをビルド・更新する手順を書きます。

## ビルド

```bash
git clone https://github.com/queria-io/dataset-shared.git shared  # 更新は git -C shared pull
uv sync
scripts/build.sh   # fdl checkout → python main.py → fdl commit
```

境界の TopoJSON は全部で約 2.5GB（変換した Parquet は約 3.4GB）あり、取得した基準日は `data/codh/boundary/` の Parquet を使い回します。元のデータセットは 2023 年 10 月から更新されていないため、定期実行はしません。main への push と手動の実行（workflow_dispatch）で Sync が実行されます。PR のビルド確認（`.github/workflows/build.yml`）は 3 時点だけ取得します（`CODH_DATES=18891231,19501001,20230101`）。
