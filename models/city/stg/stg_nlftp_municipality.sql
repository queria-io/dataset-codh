{# 国土数値情報 N03 の最新版の市区町村界（nlftp.boundary.municipality）。
   lg_code は 5 桁の市区町村コードで、政令指定都市は区の単位。
   他のデータセットを読むので、カタログに残さない #}
{{ config(materialized='ephemeral') }}

select lg_code, geometry
from nlftp.boundary.municipality
