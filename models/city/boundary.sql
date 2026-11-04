{# 歴史的行政区域データセットβ版の市区町村境界。1 行が 1 基準日の 1 市区町村。
   pipelines/geoshape.py が基準日ごとの全国の TopoJSON（jp_city.h）を data/codh/boundary/<基準日>.parquet にする。
   属性は出典で列が違う。行政界変遷データベースは STARTYEAR などを持つ。
   同じ基準日に同じ ID の形が複数あることがある（1920 年の舌辛村と舌辛村他）。形は合わせ、属性は面積の大きい方を取る。
   所属未定地など、municipality に無い ID の境界は入れない。 #}

with source as (
    select
        reference_date,
        replace(properties ->> 'id', 'gci:', '') as geoshape_city_id,
        case when properties ->> 'STARTYEAR' is not null then 'hensen' else 'n03' end as source,
        properties ->> 'N03_001' as prefecture,
        nullif(properties ->> 'N03_002', '') as subprefecture,
        nullif(properties ->> 'N03_003', '') as county_or_city,
        properties ->> 'N03_004' as name,
        case when properties ->> 'N03_007' not like '%000' then properties ->> 'N03_007' end as city_code,
        -- 座標の丸めで自己交差などの壊れた形が 2〜3% ある。直してポリゴンだけを残す
        st_multi(st_collectionextract(st_makevalid(st_geomfromwkb(geometry)), 3)) as geometry
    from read_parquet('data/codh/boundary/*.parquet')
),

merged as (
    select
        reference_date,
        geoshape_city_id,
        arg_max(source, st_area(geometry)) as source,
        arg_max(prefecture, st_area(geometry)) as prefecture,
        arg_max(subprefecture, st_area(geometry)) as subprefecture,
        arg_max(county_or_city, st_area(geometry)) as county_or_city,
        arg_max(name, st_area(geometry)) as name,
        arg_max(city_code, st_area(geometry)) as city_code,
        case when count(*) = 1 then any_value(geometry) else st_multi(st_union_agg(geometry)) end as geometry
    from source
    group by reference_date, geoshape_city_id
)

select m.*
from merged as m
semi join {{ ref('municipality') }} as u using (geoshape_city_id)
order by m.reference_date, m.geoshape_city_id
