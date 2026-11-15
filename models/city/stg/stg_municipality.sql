{# 市区町村の一覧を型付けし、有効期間と代表点の内訳を正規化する。1 行が 1 つの Geoshape 市区町村 ID #}

with parsed as (
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
        nullif(valid_to, '') is null as is_current,
        cast(longitude as double) as lng,
        cast(latitude as double) as lat,
        string_split(description, '/') as point_parts,
        geolod_id,
        filename as source_path
    from {{ ref('raw_municipality') }}
)

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
