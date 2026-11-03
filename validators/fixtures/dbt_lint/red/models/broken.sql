selec order_id, customer_id
from {{ source('raw', 'orders') }}
where
