
--------------Business Request – 1: Monthly Circulation Drop Check
;WITH CirculationWithLag AS (
    SELECT
        c.city,
        MONTH(TRY_CAST('01-' + month AS DATE)) AS [MONTH],
        YEAR(TRY_CAST('01-' + month AS DATE)) AS period_start,
        net_circulation,
        LAG(net_circulation) OVER (PARTITION BY city ORDER BY YEAR(TRY_CAST('01-' + month AS DATE)), MONTH(TRY_CAST('01-' + month AS DATE))) AS prev_net_circulation
    FROM fact_print_sales s
    JOIN dim_city c on s.city_id =c.city_id
    WHERE YEAR(TRY_CAST('01-' + month AS DATE)) BETWEEN 2019 AND 2024
),
Declines AS (
    SELECT
        city,
        month,
        period_start,
        net_circulation,
        prev_net_circulation,
        (net_circulation - prev_net_circulation) AS mom_change
    FROM CirculationWithLag
    WHERE prev_net_circulation IS NOT NULL
),
RankedDeclines AS (
    SELECT
        city,
        month,
        period_start,
        net_circulation,
        prev_net_circulation,
        mom_change,
        RANK() OVER (ORDER BY mom_change ASC) AS decline_rank
    FROM Declines
)
SELECT TOP 3
    city,
    month,
    period_start,
    net_circulation,
    prev_net_circulation,
    mom_change
FROM RankedDeclines
ORDER BY decline_rank;


---------------Business Request – 2: Yearly Revenue Concentration by Category
WITH YearlyRevenue AS (
    SELECT
        YEAR(TRY_CAST('01-' + s.[Month] AS DATE)) AS [YEAR],
        c.standard_ad_category AS category_name,
        SUM( ad_revenue) AS category_revenue
    FROM fact_ad_revenue r
    join fact_print_sales s on r.edition_id = s.edition_id
    join dim_ad_category c on r.ad_category = c.ad_category_id
    GROUP BY  YEAR(TRY_CAST('01-' + s.[Month] AS DATE)),c.standard_ad_category
),
TotalRevenue AS (
    SELECT
        year,
        SUM(category_revenue) AS total_revenue_year
    FROM YearlyRevenue
    GROUP BY year
),
RevenueWithPct AS (
    SELECT
        y.year,
        y.category_name,
        y.category_revenue,
        t.total_revenue_year,
        CAST(100.0 * y.category_revenue / t.total_revenue_year AS DECIMAL(5,2)) AS pct_of_year_total
    FROM YearlyRevenue y
    JOIN TotalRevenue t ON y.year = t.year
)
SELECT
    year,
    category_name,
    category_revenue,
    total_revenue_year,
    pct_of_year_total
FROM RevenueWithPct
WHERE pct_of_year_total > 20
ORDER BY year, pct_of_year_total DESC;

--------------Business Request – 3: 2024 Print Efficiency Leaderboard
WITH CityEfficiency AS (
    SELECT
        city,
        SUM(Copies_Sold + copies_returned) AS copies_printed_2024,
        SUM(net_circulation) AS net_circulation_2024,
        CAST(SUM(net_circulation) AS DECIMAL(18,2)) / NULLIF(SUM(Copies_Sold + copies_returned), 0) AS efficiency_ratio
    FROM fact_print_sales s
    JOIN dim_city c on s.city_id = c.city_id
    WHERE YEAR(TRY_CAST('01-' + [Month] AS DATE)) = 2024
    GROUP BY city
),
RankedEfficiency AS (
    SELECT
        city,
        copies_printed_2024,
        net_circulation_2024,
        efficiency_ratio,
        RANK() OVER (ORDER BY efficiency_ratio DESC) AS efficiency_rank_2024
    FROM CityEfficiency
)
SELECT TOP 5
    city,
    copies_printed_2024,
    net_circulation_2024,
    efficiency_ratio,
    efficiency_rank_2024
FROM RankedEfficiency
ORDER BY efficiency_rank_2024;


-----------------------Business Request – 4 : Internet Readiness Growth (2021)
WITH Internet2021 AS (
    SELECT
        city AS city_name,
        CAST(LEFT(quarter, 4) AS INT) AS year_value,
        CAST(RIGHT(quarter, 2) AS VARCHAR(2)) AS quarter_value,
        internet_penetration AS internet_rate
    FROM fact_city_readiness r
    JOIN dim_city c on r.city_id = c.city_id
    WHERE CAST(LEFT(quarter, 4) AS INT) = 2021 AND CAST(RIGHT(quarter, 2) AS VARCHAR(2)) IN ('Q1', 'Q4')
),
Pivoted AS (
    SELECT
        city_name,
        MAX(CASE WHEN quarter_value = 'Q1' THEN internet_rate END) AS internet_rate_q1_2021,
        MAX(CASE WHEN quarter_value = 'Q4' THEN internet_rate END) AS internet_rate_q4_2021
    FROM Internet2021
    GROUP BY city_name
),
Delta AS (
    SELECT
        city_name,
        internet_rate_q1_2021,
        internet_rate_q4_2021,
        internet_rate_q4_2021 - internet_rate_q1_2021 AS delta_internet_rate
    FROM Pivoted
)
SELECT TOP 1
    city_name,
    internet_rate_q1_2021,
    internet_rate_q4_2021,
    delta_internet_rate
FROM Delta
ORDER BY delta_internet_rate DESC;

