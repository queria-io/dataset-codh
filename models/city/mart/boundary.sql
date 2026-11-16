{# 歴史的行政区域データセットβ版の市区町村境界。1 行が 1 基準日の 1 市区町村。
   基準日 → ID の順のまま出すので、並べ直さない（全部で数 GB あり、並べ直すとメモリに収まらない） #}

select
    reference_date,
    geoshape_city_id,
    source,
    prefecture,
    subprefecture,
    county_or_city,
    name,
    city_code,
    geometry
from {{ ref('stg_boundary') }}
