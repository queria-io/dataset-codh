{# 歴史的行政区域データセットβ版の市区町村。1 行が 1 つの Geoshape 市区町村 ID。
   代表点が入る現在の市区町村を国土数値情報の市区町村界から付ける。 #}

with points as (
    select * from {{ ref('stg_municipality') }}
),

current_city as (
    select p.geoshape_city_id, b.lg_code as current_city_code
    from points as p
    join {{ ref('stg_nlftp_municipality') }} as b on st_intersects(b.geometry, p.geometry)
)

select
    p.geoshape_city_id,
    p.city_code,
    {{ local_government_code('p.city_code') }} as lg_code,
    p.prefecture_code,
    p.prefecture,
    p.county_or_city,
    p.name,
    p.suffix,
    p.full_name,
    p.address,
    p.name_variants,
    p.valid_from,
    p.valid_from_precision,
    p.valid_to,
    p.valid_to_precision,
    p.is_current,
    c.current_city_code,
    {{ local_government_code('c.current_city_code') }} as current_lg_code,
    p.point_source,
    p.point_name,
    p.point_address,
    p.lng,
    p.lat,
    p.geometry,
    p.geolod_id
from points as p
left join current_city as c using (geoshape_city_id)
order by p.geoshape_city_id
