{# 歴史的行政区域データセットβ版の市区町村の一覧（GeoNLP 地名語辞書の形）。
   pipelines/geoshape.py が data/codh/municipality.csv に保存する。取得したままの形 #}

select * from read_csv('data/codh/municipality.csv', header = true, all_varchar = true, filename = true)
