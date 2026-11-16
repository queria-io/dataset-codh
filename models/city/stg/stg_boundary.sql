{# 市区町村境界の属性を列にする。1 行が 1 基準日の 1 市区町村。
   属性は出典で列が違う。行政界変遷データベースは STARTYEAR などを持つ。
   所属未定地・公有水面など municipality に無い ID（02C9990001 のように 4〜6 文字目が 999、または「岡山県所属未定地」）は入れない。
   municipality との結合で絞ると読む順が崩れて基準日の順に並ばなくなるので、ID の形で絞る。
   ほかに municipality に無い ID が出てきたら、_schema.yml の relationships のテストが止める。 #}

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
from {{ ref('raw_boundary') }}
where regexp_full_match(replace(properties ->> 'id', 'gci:', ''), '[0-9]{2}[A-Z0-9][0-9A-Z]{7}')
  and not regexp_matches(replace(properties ->> 'id', 'gci:', ''), '^[0-9]{2}[A-Z]999')
