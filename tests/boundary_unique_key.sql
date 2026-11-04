-- 1 行が 1 基準日の 1 市区町村
select reference_date, geoshape_city_id, count(*) as n
from {{ ref('boundary') }}
group by all
having count(*) > 1
