Таблица dwh.products - информация о товаре	
	
Столбец	Описание
itemid	код товара в системе
name_ax	наименование товара в системе
brand_name_ax	бренд товара
category	категория товара
	
Таблица dwh.sales - данные о продажах	
	
Столбец	Описание
sale_id	идентификатор продажи
date	дата
itemid	код товара в системе
qty	количество проданных единиц
price	цена продажи
	
Таблица dwh.stock - данные об остатках	
Столбец	Описание
date	дата
itemid	код товара в системе
qty	количество на складе



___________________________________
--Задание 4.													
--Написать SQL-запросы на основе описанных таблиц в Clickhouse													
--1) Для каждого товара вывести следующую информацию													
 -- код товара													
 -- название товара													
 -- бренд													
 -- категорию													
 -- сумму продаж в шт, за последний полный месяц													
 -- сумму продаж в рублях, за последний полный месяц													
 -- среднюю цену на товара, за последний полный месяц													
 -- средний объем продаж в штуках за последние 3 месяца (включая последний месяц)													
 -- разницу между текущим остатком и средним объемом продаж в штуках за последние 3 месяца													
													
--В итоговом результате должны быть только товары, у которых были продажи за последний месяц.													
--Прошлый месяц должен прописываться в коде, нахождением этого месяца, а не "2025-05-01"													


-- =============================================================================
-- Задача 4.1. Сводная информация по каждому товару
-- Диалект: ClickHouse
-- =============================================================================

WITH
    -- 1. Границы последнего полного месяца (определяются в коде, не хардкодом)
    toStartOfMonth(today() - INTERVAL 1 MONTH) AS last_month_start,
    toStartOfMonth(today()) - INTERVAL 1 DAY   AS last_month_end,
    -- 2. Начало 3-месячного окна (последний месяц + 2 предыдущих)
    toStartOfMonth(today() - INTERVAL 3 MONTH) AS three_month_start
SELECT
    p.itemid AS itemid,
    p.name_ax AS name_ax,
    p.brand_name_ax AS brand_name_ax,
    p.category AS category,
    -- Продажи за последний полный месяц
    sum(s.qty) AS sales_qty_month,
    sum(s.qty * s.price) AS sales_rub_month,
    -- Средневзвешенная цена за последний полный месяц
    sum(s.qty * s.price) / sum(s.qty) AS avg_price_month,
    -- Средний объём продаж в шт. за последние 3 месяца (включая последний)
    -- = продажи за 3 месяца / 3 месяца
    m3.avg_qty_3m AS avg_qty_3m,
    -- Разница между текущим остатком и средним объёмом продаж за 3 месяца
    st.stock_current - m3.avg_qty_3m AS stock_diff
FROM dwh.sales AS s
INNER JOIN dwh.products AS p
    ON p.itemid = s.itemid
-- Текущий остаток: значение qty на самую свежую дату в dwh.stock
LEFT JOIN (
    SELECT itemid, qty AS stock_current
    FROM dwh.stock
    WHERE date = (SELECT max(date) FROM dwh.stock)
) AS st
    ON st.itemid = s.itemid
-- Средний объём продаж за 3 месяца (включая последний)
LEFT JOIN (
    SELECT
        itemid,
        sum(qty) / 3 AS avg_qty_3m
    FROM dwh.sales
    WHERE date >= toStartOfMonth(today() - INTERVAL 3 MONTH)
      AND date <  toStartOfMonth(today())
    GROUP BY itemid
) AS m3
    ON m3.itemid = s.itemid
-- Фильтр: только продажи за последний полный месяц
WHERE s.date >= last_month_start
  AND s.date <= last_month_end
GROUP BY
    p.itemid,
    p.name_ax,
    p.brand_name_ax,
    p.category,
    m3.avg_qty_3m,
    st.stock_current
-- Убираем товары без продаж за последний месяц
HAVING sum(s.qty) > 0

-- =============================================================================
-- Задача 4.2. Топ-5 брендов по выручке за последний полный месяц
--             с сравнением с предыдущим месяцем
-- =============================================================================

WITH
    -- Границы последнего полного месяца
    toStartOfMonth(today() - INTERVAL 1 MONTH) AS last_month_start,
    toStartOfMonth(today()) - INTERVAL 1 DAY   AS last_month_end,
    -- Границы предыдущего полного месяца
    toStartOfMonth(today() - INTERVAL 2 MONTH) AS prev_month_start,
    toStartOfMonth(today() - INTERVAL 1 MONTH) - INTERVAL 1 DAY AS prev_month_end

SELECT
    p.brand_name_ax AS brand_name_ax,
    -- Выручка за последний полный месяц
    sumIf(s.qty * s.price,
          s.date >= last_month_start AND s.date <= last_month_end) AS revenue_last_month,
    -- Выручка за предыдущий полный месяц
    sumIf(s.qty * s.price,
          s.date >= prev_month_start AND s.date <= prev_month_end) AS revenue_prev_month,
    -- Абсолютное изменение
    revenue_last_month - revenue_prev_month AS delta_rub,
    -- Процентное изменение
    round(
        (revenue_last_month - revenue_prev_month) / revenue_prev_month * 100,
        1
    ) AS delta_pct
FROM dwh.sales AS s
INNER JOIN dwh.products AS p
    ON p.itemid = s.itemid
-- Ограничиваем диапазон двумя месяцами
WHERE s.date >= prev_month_start
  AND s.date <= last_month_end
GROUP BY p.brand_name_ax
-- Оставляем только бренды, у которых были продажи за последний месяц
HAVING revenue_last_month > 0
ORDER BY revenue_last_month DESC
LIMIT 5;