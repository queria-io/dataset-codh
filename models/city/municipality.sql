{# 歴史的行政区域データセットβ版の市区町村。1 行が 1 つの Geoshape 市区町村 ID。
   pipelines/geoshape.py が GeoNLP 地名語辞書の形の一覧を data/codh/municipality.csv に保存する。
   代表点が入る現在の市区町村を nlftp.boundary.municipality から付ける。 #}

with source as (
    select *
    from read_csv('data/codh/municipality.csv', header = true, all_varchar = true)
),

parsed as (
    select
        entry_id as geoshape_city_id,
        -- 1968 年以降のコードが無い市区町村は都道府県のコード（08000 など）が入っている。
        -- 複数入っていること（01206/01000）がある
        list_filter(string_split(code, '/'), c -> c not like '%000')[1] as city_code,
        left(entry_id, 2) as prefecture_code,
        prefname as prefecture,
        nullif(countyname, '') as county_or_city,
        body as name,
        rtrim(suffix, '/') as suffix,
        body || rtrim(suffix, '/') as full_name,
        address,
        string_split(body_variants, '/') as name_variants,
        -- 有効期間は YYYY-MM-DD。年だけ（1870）や年月だけ（1890-04）の値は、その年・月の 1 日にして精度を別に持つ
        cast(rpad(nullif(valid_from, ''), 10, substr('-01-01', length(valid_from) - 3)) as date) as valid_from,
        case length(valid_from) when 10 then 'day' when 7 then 'month' when 4 then 'year' end as valid_from_precision,
        cast(rpad(nullif(valid_to, ''), 10, substr('-01-01', length(valid_to) - 3)) as date) as valid_to,
        case length(valid_to) when 10 then 'day' when 7 then 'month' when 4 then 'year' end as valid_to_precision,
        valid_to is null as is_current,
        cast(longitude as double) as lng,
        cast(latitude as double) as lat,
        string_split(description, '/') as point_parts,
        geolod_id
    from source
),

points as (
    select
        * exclude (point_parts),
        -- 代表点の内訳: <種別>/<施設名>/<所在地>/<国土数値情報のファイル名>/(<境界のファイル>)
        -- 国土数値情報のファイル名（P34-14_01.xml など）の先頭 3 文字が出典。重心は 9/ポリゴンの重心
        case
            when point_parts[2] = 'ポリゴンの重心' then 'centroid'
            else coalesce(
                list_extract(list_filter(list_transform(point_parts, p -> regexp_extract(p, '^(P\d\d)-', 1)), p -> p <> ''), 1),
                'other'
            )
        end as point_source,
        case when point_parts[2] <> 'ポリゴンの重心' then point_parts[2] end as point_name,
        case when point_parts[2] <> 'ポリゴンの重心' and point_parts[3] not like '(%' then point_parts[3] end as point_address,
        st_point(lng, lat) as geometry
    from parsed
),

current_city as (
    -- nlftp の lg_code は 5 桁の市区町村コード。政令指定都市は区の単位
    select p.geoshape_city_id, b.lg_code as current_city_code
    from points as p
    join nlftp.boundary.municipality as b on st_intersects(b.geometry, p.geometry)
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
