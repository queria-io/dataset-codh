{# 歴史的行政区域データセットβ版の市区町村境界。1 行が 1 基準日の 1 市区町村。
   pipelines/geoshape.py が基準日ごとの全国の TopoJSON（jp_city.h）を、壊れた形を直し、
   同じ ID の形を 1 つに合わせて data/codh/boundary/<基準日>.parquet にする。
   属性は出典で列が違う。行政界変遷データベースは STARTYEAR などを持つ。
   所属未定地など、municipality に無い ID の境界は入れない。 #}

select
    reference_date,
    replace(properties ->> 'id', 'gci:', '') as geoshape_city_id,
    case when properties ->> 'STARTYEAR' is not null then 'hensen' else 'n03' end as source,
    properties ->> 'N03_001' as prefecture,
    nullif(properties ->> 'N03_002', '') as subprefecture,
    nullif(properties ->> 'N03_003', '') as county_or_city,
    properties ->> 'N03_004' as name,
    case when properties ->> 'N03_007' not like '%000' then properties ->> 'N03_007' end as city_code,
    st_geomfromwkb(geometry) as geometry
-- ファイルは基準日ごと、中は ID の順なので、並べ直さずにファイル名の順で読む（全部で数 GB あり、並べ直すとメモリに収まらない）
from read_parquet('data/codh/boundary/*.parquet')
where replace(properties ->> 'id', 'gci:', '') in (select geoshape_city_id from {{ ref('municipality') }})
