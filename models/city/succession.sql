{# 市区町村の前後の組。1 行が、消えた市区町村と、その区域を受け継いだ市区町村の 1 組。
   消えた日 (valid_to) に存在した市区町村のうち、次のどれかに当たるものを後の市区町村とする。
   - point: その日以後の最初の基準日の境界に、消えた市区町村の代表点が入る (合併・編入・改称)
   - split: その日に生まれ、代表点が消えた市区町村の最後の境界に入る (分割)
   - current_city: どちらにも境界が無く、その日に生まれ、代表点の入る現在の市区町村が同じ #}

with gone as (
    select
        m.geoshape_city_id,
        m.valid_to,
        m.geometry as point,
        m.current_city_code,
        (select min(b.reference_date) from {{ ref('boundary') }} as b where b.reference_date >= m.valid_to)
            as next_date,
        (select max(b.reference_date) from {{ ref('boundary') }} as b where b.geoshape_city_id = m.geoshape_city_id)
            as last_date
    from {{ ref('municipality') }} as m
    where m.valid_to is not null
),

by_point as (
    select g.geoshape_city_id, b.geoshape_city_id as successor_geoshape_city_id, 'point' as method
    from gone as g
    join {{ ref('boundary') }} as b
        on b.reference_date = g.next_date and b.geoshape_city_id <> g.geoshape_city_id
        and st_intersects(b.geometry, g.point)
    join {{ ref('municipality') }} as n
        on n.geoshape_city_id = b.geoshape_city_id and n.valid_from <= g.valid_to
),

by_split as (
    select g.geoshape_city_id, n.geoshape_city_id, 'split'
    from gone as g
    join {{ ref('boundary') }} as b on b.geoshape_city_id = g.geoshape_city_id and b.reference_date = g.last_date
    join {{ ref('municipality') }} as n
        on n.valid_from = g.valid_to and n.geoshape_city_id <> g.geoshape_city_id
        and st_intersects(b.geometry, n.geometry)
),

by_city as (
    select g.geoshape_city_id, n.geoshape_city_id, 'current_city'
    from gone as g
    join {{ ref('municipality') }} as n
        on n.valid_from = g.valid_to and n.current_city_code = g.current_city_code
        and n.geoshape_city_id <> g.geoshape_city_id
    where g.last_date is null
        and not exists (select 1 from {{ ref('boundary') }} as b where b.geoshape_city_id = n.geoshape_city_id)
),

pairs as (
    select * from by_point
    union all
    select * from by_split
    union all
    select * from by_city
)

select
    p.geoshape_city_id,
    p.successor_geoshape_city_id,
    g.valid_to as change_date,
    n.valid_from = g.valid_to as successor_is_new,
    min(p.method order by case p.method when 'point' then 1 when 'split' then 2 else 3 end) as method
from pairs as p
join gone as g using (geoshape_city_id)
join {{ ref('municipality') }} as n on n.geoshape_city_id = p.successor_geoshape_city_id
group by all
order by change_date, geoshape_city_id, successor_geoshape_city_id
