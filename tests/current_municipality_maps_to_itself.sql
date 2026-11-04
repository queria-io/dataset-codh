-- 現存する市区町村の代表点は、ほぼすべて自分の市区町村に入る。
-- 役場が区域の外にある町村（竹富町・三島村・十島村）と、代表点の無い北方領土の村などが例外で、
-- それより増えたら代表点か現在の市区町村の付け方が崩れている。
-- 2023 年 1 月より後に改編された市区町村（浜松市の区など）は nlftp の境界に無いので数えない
select count(*) as mismatches
from {{ ref('municipality') }}
where is_current
  and city_code in (select lg_code from nlftp.boundary.municipality)
  and current_city_code is distinct from city_code
having count(*) > 10
