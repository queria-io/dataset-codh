-- 1 行が消えた市区町村と後の市区町村の 1 組
select geoshape_city_id, successor_geoshape_city_id, count(*) as n
from {{ ref('succession') }}
group by all
having count(*) > 1
