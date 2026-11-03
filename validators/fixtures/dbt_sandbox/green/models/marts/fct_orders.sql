{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key='order_id'
) }}

select
    order_id,
    customer_id,
    amount,
    updated_at
from {{ ref('stg_orders') }}
{% if is_incremental() %}
where updated_at > (select coalesce(max(t.updated_at), timestamp('1970-01-01')) from {{ this }} as t)
{% endif %}
