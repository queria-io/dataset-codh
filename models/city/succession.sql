{# 市区町村の前後の組。1 行が、消えた市区町村と、その区域を受け継いだ市区町村の 1 組。
   次のどれかに当たる市区町村を後の市区町村とする。
   - point: 消えた日 (valid_to) 以後の最初の基準日の境界に、消えた市区町村の代表点が入る (合併・編入・改称)。
     その基準日までに受け継いだ市区町村がさらに合併していれば、その基準日の市区町村と組になる
   - split: その日に生まれ、代表点が消えた市区町村の最後の境界に入る (分割)
   - current_city: どちらにも境界が無く、その日に生まれ、代表点の入る現在の市区町村が同じ #}

-- 境界は 54 万行あるので、基準日の一覧 (111 行) と ID ごとの最後の基準日を先に作り、市区町村ごとに境界を走査しない
with reference_dates as (
    select distinct reference_date from {{ ref('boundary') }}
),

last_dates as (
    select geoshape_city_id, max(reference_date) as last_date
    from {{ ref('boundary') }}
    group by geoshape_city_id
),

gone as (
    select
        m.geoshape_city_id,
        m.valid_to,
        m.geometry as point,
        m.current_city_code,
        (select min(d.reference_date) from reference_dates as d where d.reference_date >= m.valid_to) as next_date,
        l.last_date
    from {{ ref('municipality') }} as m
    left join last_dates as l using (geoshape_city_id)
    where m.valid_to is not null
),

by_point as (
    select g.geoshape_city_id, b.geoshape_city_id as successor_geoshape_city_id, 'point' as method
    from gone as g
    join {{ ref('boundary') }} as b
        on b.reference_date = g.next_date and b.geoshape_city_id <> g.geoshape_city_id
        and st_intersects(b.geometry, g.point)
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
    arg_min(p.method, case p.method when 'point' then 1 when 'split' then 2 else 3 end) as method
from pairs as p
join gone as g using (geoshape_city_id)
join {{ ref('municipality') }} as n on n.geoshape_city_id = p.successor_geoshape_city_id
group by all
order by change_date, geoshape_city_id, successor_geoshape_city_id
