{# 過去の市区町村と現在の市区町村の重なり。1 行が 1 つの Geoshape 市区町村 ID と現在の市区町村の 1 組。
   ID ごとに最後の基準日の境界を、nlftp.boundary.municipality（国土数値情報 N03 の最新版）と重ねる。
   面積は度の面積を境界の重心の緯度で平方キロメートルに直す。 #}

with last_date as (
    select geoshape_city_id, max(reference_date) as reference_date
    from {{ ref('boundary') }}
    group by geoshape_city_id
),

last_boundary as (
    select b.geoshape_city_id, b.reference_date, b.source, b.geometry
    from {{ ref('boundary') }} as b
    semi join last_date as l using (geoshape_city_id, reference_date)
),

piece as (
    select
        l.geoshape_city_id,
        l.reference_date,
        l.source,
        b.lg_code as current_city_code,
        st_area(st_intersection(l.geometry, b.geometry)) as overlap_deg2,
        st_area(l.geometry) as past_deg2,
        st_area(b.geometry) as current_deg2,
        cos(radians(st_y(st_centroid(l.geometry)))) as lat_factor
    from last_boundary as l
    join nlftp.boundary.municipality as b on st_intersects(l.geometry, b.geometry)
)

select
    geoshape_city_id,
    reference_date as boundary_date,
    source as boundary_source,
    current_city_code,
    {{ local_government_code('current_city_code') }} as current_lg_code,
    overlap_deg2 * 111.32 * 111.32 * lat_factor as overlap_area_km2,
    overlap_deg2 / past_deg2 as past_share,
    overlap_deg2 / current_deg2 as current_share
from piece
where overlap_deg2 > 0
order by geoshape_city_id, past_share desc
