-- 1 行が ID と現在の市区町村の 1 組
select geoshape_city_id, current_city_code, count(*) as n
from {{ ref('current_overlap') }}
group by all
having count(*) > 1
