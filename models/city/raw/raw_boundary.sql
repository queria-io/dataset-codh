{# 歴史的行政区域データセットβ版の市区町村境界。
   pipelines/geoshape.py が基準日ごとの全国の TopoJSON（jp_city.h）を、壊れた形を直し、
   同じ ID の形を 1 つに合わせて data/codh/boundary/<基準日>.parquet にする。取得したままの形 #}

-- ファイルは基準日ごと、中は ID の順なので、並べ直さずにファイル名の順で読む（全部で数 GB あり、並べ直すとメモリに収まらない）
select * from read_parquet('data/codh/boundary/*.parquet')
