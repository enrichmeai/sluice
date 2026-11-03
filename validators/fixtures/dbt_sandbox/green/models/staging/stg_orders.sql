{{ config(materialized='view') }}

select
    cast(order_id as int64) as order_id,
    cast(customer_id as int64) as customer_id,
    cast(amount as numeric) as amount,
    updated_at
from {{ source('raw', 'orders') }}
