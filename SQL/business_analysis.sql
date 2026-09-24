-- Demand Forecasting & Sales Operations Analytics
-- Dialect: DuckDB. Run with Python/run_sql_analysis.py.
-- Sales/customer/operations: all available order history (2023-2025 currently).
-- Forecasting: FINAL TEST ONLY (2025-07 to 2025-12 currently), rolling one month ahead.
-- Source: outputs/forecasts/model_forecast_results.csv. Legacy forecasts are archived.
-- Forecast_Demand is the frozen Random Forest. No model fitting or parameter selection.
-- Error = forecast - actual. Positive = overforecast. Units include delayed orders.
-- WAPE = SUM(absolute_error)/SUM(actual). RMSE = SQRT(SUM(squared_error)/COUNT(*)).
-- Compute errors at month-product-region grain BEFORE aggregation.
-- Forecast metrics retain full precision. Existing sales/operations reports round display values.
-- Zero-demand percentage denominators return NULL, not fabricated zero accuracy.
-- Long forecast facts repeat actuals for each model: always filter/group by Model.

CREATE OR REPLACE VIEW forecast_evaluation_detail AS
WITH predictions AS (
    SELECT Month::DATE AS forecast_month, Product_ID, Region_ID, Actual_Demand,
           'Random Forest' AS Model, Forecast_Demand AS forecast_demand
    FROM model_forecast_results
    UNION ALL
    SELECT Month::DATE, Product_ID, Region_ID, Actual_Demand,
           'Naive Forecast', Naive_Forecast FROM model_forecast_results
    UNION ALL
    SELECT Month::DATE, Product_ID, Region_ID, Actual_Demand,
           'Seasonal Naive', Seasonal_Naive_Forecast FROM model_forecast_results
)
SELECT f.*, p.Product_Category, p.Product_Line, r.Region,
       'Final test / rolling one-month-ahead' AS evaluation_scope,
       forecast_demand - Actual_Demand AS forecast_error,
       ABS(forecast_demand - Actual_Demand) AS absolute_error,
       POWER(forecast_demand - Actual_Demand, 2) AS squared_error
FROM predictions f
JOIN products p USING (Product_ID)
JOIN regions r USING (Region_ID);

-- MODULE 1: Sales performance and growth
-- Existing business questions retained across all available sales history.

-- export: annual_sales_trend
CREATE OR REPLACE VIEW annual_sales_trend AS
WITH annual_sales AS (
    SELECT
        EXTRACT(YEAR FROM CAST(Order_Date AS DATE))::INTEGER AS sales_year,
        ROUND(SUM(Revenue)::NUMERIC, 2) AS total_revenue,
        SUM(Quantity) AS total_units_sold,
        COUNT(DISTINCT Order_ID) AS total_orders,
        ROUND(
            SUM(Revenue)::NUMERIC / NULLIF(COUNT(DISTINCT Order_ID), 0),
            2
        ) AS average_order_value
    FROM sales_orders
    GROUP BY
        EXTRACT(YEAR FROM CAST(Order_Date AS DATE))
),
annual_growth AS (
    SELECT
        sales_year,
        total_revenue,
        total_units_sold,
        total_orders,
        average_order_value,
        LAG(total_revenue) OVER (
            ORDER BY sales_year
        ) AS previous_year_revenue,
        LAG(total_units_sold) OVER (
            ORDER BY sales_year
        ) AS previous_year_units
    FROM annual_sales
)
SELECT
    sales_year,
    total_revenue,
    total_units_sold,
    total_orders,
    average_order_value,
    ROUND(
        100.0 * (total_revenue - previous_year_revenue)
        / NULLIF(previous_year_revenue, 0),
        2
    ) AS revenue_yoy_growth_pct,
    ROUND(
        100.0 * (total_units_sold - previous_year_units)
        / NULLIF(previous_year_units, 0),
        2
    ) AS units_yoy_growth_pct
FROM annual_growth
ORDER BY
    sales_year;

-- export: regional_sales_contribution
CREATE OR REPLACE VIEW regional_sales_contribution AS
WITH regional_sales AS (
    SELECT
        so.Region_ID,
        r.Region,
        ROUND(SUM(so.Revenue)::NUMERIC, 2) AS total_revenue,
        SUM(so.Quantity) AS total_units_sold,
        COUNT(DISTINCT so.Order_ID) AS total_orders,
        COUNT(DISTINCT so.Customer_ID) AS active_customers,
        ROUND(
            SUM(so.Revenue)::NUMERIC
            / NULLIF(COUNT(DISTINCT so.Order_ID), 0),
            2
        ) AS average_order_value
    FROM sales_orders AS so
    INNER JOIN regions AS r
        ON so.Region_ID = r.Region_ID
    GROUP BY
        so.Region_ID,
        r.Region
)
SELECT
    Region_ID,
    Region,
    total_revenue,
    total_units_sold,
    total_orders,
    active_customers,
    average_order_value,
    ROUND(
        100.0 * total_revenue / NULLIF(SUM(total_revenue) OVER (), 0),
        2
    ) AS revenue_contribution_pct,
    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS revenue_rank
FROM regional_sales
ORDER BY
    revenue_rank,
    Region_ID;

-- export: product_revenue_contribution
CREATE OR REPLACE VIEW product_revenue_contribution AS
WITH product_sales AS (
    SELECT
        so.Product_ID,
        p.Product_Category,
        p.Product_Line,
        ROUND(SUM(so.Revenue)::NUMERIC, 2) AS total_revenue,
        SUM(so.Quantity) AS total_units_sold,
        COUNT(DISTINCT so.Order_ID) AS total_orders,
        ROUND(
            SUM(so.Revenue)::NUMERIC / NULLIF(SUM(so.Quantity), 0),
            2
        ) AS average_selling_price
    FROM sales_orders AS so
    INNER JOIN products AS p
        ON so.Product_ID = p.Product_ID
    GROUP BY
        so.Product_ID,
        p.Product_Category,
        p.Product_Line
)
SELECT
    Product_ID,
    Product_Category,
    Product_Line,
    total_revenue,
    total_units_sold,
    total_orders,
    average_selling_price,
    ROUND(
        100.0 * total_revenue / NULLIF(SUM(total_revenue) OVER (), 0),
        2
    ) AS revenue_contribution_pct,
    SUM(total_revenue) OVER (
        ORDER BY total_revenue DESC, Product_ID
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_revenue,
    ROUND(
        100.0 * SUM(total_revenue) OVER (
            ORDER BY total_revenue DESC, Product_ID
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) / NULLIF(SUM(total_revenue) OVER (), 0),
        2
    ) AS cumulative_revenue_pct,
    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS revenue_rank
FROM product_sales
ORDER BY
    revenue_rank,
    Product_ID;

-- MODULE 2: Customer and market intelligence
-- Growth compares latest two observed calendar years (not a completeness guarantee).
-- Customer momentum/opportunity bands are descriptive business rules, not model outputs.

-- export: customer_value_ranking
CREATE OR REPLACE VIEW customer_value_ranking AS
WITH customer_value AS (
    SELECT
        c.Customer_ID,
        c.Customer_Name,
        c.Customer_Type,
        r.Region,
        ROUND(SUM(so.Revenue)::NUMERIC, 2) AS total_revenue,
        SUM(so.Quantity) AS total_units_sold,
        COUNT(DISTINCT so.Order_ID) AS total_orders,
        ROUND(
            SUM(so.Revenue)::NUMERIC
            / NULLIF(COUNT(DISTINCT so.Order_ID), 0),
            2
        ) AS average_order_value,
        MAX(CAST(so.Order_Date AS DATE)) AS last_order_date
    FROM sales_orders AS so
    INNER JOIN customers AS c
        ON so.Customer_ID = c.Customer_ID
    INNER JOIN regions AS r
        ON c.Region_ID = r.Region_ID
    GROUP BY
        c.Customer_ID,
        c.Customer_Name,
        c.Customer_Type,
        r.Region
)
SELECT
    Customer_ID,
    Customer_Name,
    Customer_Type,
    Region,
    total_revenue,
    total_units_sold,
    total_orders,
    average_order_value,
    last_order_date,
    ROUND(
        100.0 * total_revenue / NULLIF(SUM(total_revenue) OVER (), 0),
        2
    ) AS revenue_contribution_pct,
    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS customer_revenue_rank
FROM customer_value
ORDER BY
    customer_revenue_rank,
    Customer_ID;

-- export: customer_type_performance
CREATE OR REPLACE VIEW customer_type_performance AS
WITH segment_performance AS (
    SELECT
        c.Customer_Type,
        COUNT(DISTINCT c.Customer_ID) AS active_customers,
        COUNT(DISTINCT so.Order_ID) AS total_orders,
        SUM(so.Quantity) AS total_units_sold,
        ROUND(SUM(so.Revenue)::NUMERIC, 2) AS total_revenue
    FROM sales_orders AS so
    INNER JOIN customers AS c
        ON so.Customer_ID = c.Customer_ID
    GROUP BY
        c.Customer_Type
)
SELECT
    Customer_Type,
    active_customers,
    total_orders,
    total_units_sold,
    total_revenue,
    ROUND(
        total_revenue / NULLIF(active_customers, 0),
        2
    ) AS revenue_per_customer,
    ROUND(
        total_revenue / NULLIF(total_orders, 0),
        2
    ) AS average_order_value,
    ROUND(
        100.0 * total_revenue / NULLIF(SUM(total_revenue) OVER (), 0),
        2
    ) AS revenue_contribution_pct,
    DENSE_RANK() OVER (
        ORDER BY total_revenue DESC
    ) AS segment_revenue_rank
FROM segment_performance
ORDER BY
    segment_revenue_rank,
    Customer_Type;

-- export: customer_growth_and_risk
CREATE OR REPLACE VIEW customer_growth_and_risk AS
WITH analysis_period AS (
    SELECT
        MAX(EXTRACT(YEAR FROM CAST(Order_Date AS DATE)))::INTEGER
            AS latest_year,
        (
            MAX(EXTRACT(YEAR FROM CAST(Order_Date AS DATE))) - 1
        )::INTEGER AS previous_year
    FROM sales_orders
),
customer_yearly_revenue AS (
    SELECT
        c.Customer_ID,
        c.Customer_Name,
        c.Customer_Type,
        r.Region,
        ap.previous_year,
        ap.latest_year,
        SUM(so.Revenue) FILTER (
            WHERE EXTRACT(YEAR FROM CAST(so.Order_Date AS DATE))
                = ap.previous_year
        ) AS previous_year_revenue,
        SUM(so.Revenue) FILTER (
            WHERE EXTRACT(YEAR FROM CAST(so.Order_Date AS DATE))
                = ap.latest_year
        ) AS latest_year_revenue
    FROM customers AS c
    CROSS JOIN analysis_period AS ap
    INNER JOIN regions AS r
        ON c.Region_ID = r.Region_ID
    LEFT JOIN sales_orders AS so
        ON c.Customer_ID = so.Customer_ID
    GROUP BY
        c.Customer_ID,
        c.Customer_Name,
        c.Customer_Type,
        r.Region,
        ap.previous_year,
        ap.latest_year
),
customer_growth AS (
    SELECT
        Customer_ID,
        Customer_Name,
        Customer_Type,
        Region,
        previous_year,
        latest_year,
        ROUND(
            COALESCE(previous_year_revenue, 0)::NUMERIC,
            2
        ) AS previous_year_revenue,
        ROUND(
            COALESCE(latest_year_revenue, 0)::NUMERIC,
            2
        ) AS latest_year_revenue,
        ROUND(
            100.0 * (
                COALESCE(latest_year_revenue, 0)
                - COALESCE(previous_year_revenue, 0)
            ) / NULLIF(previous_year_revenue, 0),
            2
        ) AS revenue_yoy_growth_pct
    FROM customer_yearly_revenue
)
SELECT
    Customer_ID,
    Customer_Name,
    Customer_Type,
    Region,
    previous_year,
    latest_year,
    previous_year_revenue,
    latest_year_revenue,
    revenue_yoy_growth_pct,
    CASE
        WHEN previous_year_revenue = 0 AND latest_year_revenue > 0
            THEN 'New or Returning'
        WHEN latest_year_revenue = 0 AND previous_year_revenue > 0
            THEN 'No Orders in Latest Year'
        WHEN revenue_yoy_growth_pct >= 10 THEN 'High Growth'
        WHEN revenue_yoy_growth_pct <= -10 THEN 'At Risk'
        ELSE 'Stable'
    END AS customer_momentum
FROM customer_growth
ORDER BY
    revenue_yoy_growth_pct DESC NULLS LAST,
    latest_year_revenue DESC;

-- export: regional_market_opportunity
CREATE OR REPLACE VIEW regional_market_opportunity AS
WITH analysis_period AS (
    SELECT
        MAX(EXTRACT(YEAR FROM CAST(Order_Date AS DATE)))::INTEGER
            AS latest_year,
        (
            MAX(EXTRACT(YEAR FROM CAST(Order_Date AS DATE))) - 1
        )::INTEGER AS previous_year
    FROM sales_orders
),
market_segment AS (
    WITH market_grid AS (
        SELECT
            r.Region_ID,
            r.Region,
            ct.Customer_Type
        FROM regions AS r
        CROSS JOIN (
            SELECT DISTINCT Customer_Type
            FROM customers
        ) AS ct
    )
    SELECT
        mg.Region,
        mg.Customer_Type,
        ap.previous_year,
        ap.latest_year,
        COUNT(DISTINCT c.Customer_ID) FILTER (
            WHERE EXTRACT(YEAR FROM CAST(so.Order_Date AS DATE))
                = ap.latest_year
        ) AS active_customers,
        SUM(so.Revenue) FILTER (
            WHERE EXTRACT(YEAR FROM CAST(so.Order_Date AS DATE))
                = ap.previous_year
        ) AS previous_year_revenue,
        SUM(so.Revenue) FILTER (
            WHERE EXTRACT(YEAR FROM CAST(so.Order_Date AS DATE))
                = ap.latest_year
        ) AS latest_year_revenue
    FROM market_grid AS mg
    CROSS JOIN analysis_period AS ap
    LEFT JOIN customers AS c
        ON mg.Region_ID = c.Region_ID
       AND mg.Customer_Type = c.Customer_Type
    LEFT JOIN sales_orders AS so
        ON c.Customer_ID = so.Customer_ID
    GROUP BY
        mg.Region,
        mg.Customer_Type,
        ap.previous_year,
        ap.latest_year
),
market_metrics AS (
    SELECT
        Region,
        Customer_Type,
        previous_year,
        latest_year,
        active_customers,
        ROUND(
            COALESCE(previous_year_revenue, 0)::NUMERIC,
            2
        ) AS previous_year_revenue,
        ROUND(
            COALESCE(latest_year_revenue, 0)::NUMERIC,
            2
        ) AS latest_year_revenue,
        COALESCE(
            ROUND(
                COALESCE(latest_year_revenue, 0)::NUMERIC
                / NULLIF(active_customers, 0),
                2
            ),
            0
        ) AS revenue_per_customer,
        ROUND(
            100.0 * (
                COALESCE(latest_year_revenue, 0)
                - COALESCE(previous_year_revenue, 0)
            ) / NULLIF(previous_year_revenue, 0),
            2
        ) AS revenue_yoy_growth_pct
    FROM market_segment
),
market_benchmark AS (
    SELECT
        *,
        SUM(latest_year_revenue) OVER ()
        / NULLIF(SUM(active_customers) OVER (), 0) AS company_revenue_per_customer
    FROM market_metrics
)
SELECT
    Region,
    Customer_Type,
    previous_year,
    latest_year,
    active_customers,
    previous_year_revenue,
    latest_year_revenue,
    revenue_per_customer,
    revenue_yoy_growth_pct,
    ROUND(company_revenue_per_customer, 2) AS company_revenue_per_customer,
    ROUND(
        company_revenue_per_customer - COALESCE(revenue_per_customer, 0),
        2
    ) AS revenue_per_customer_gap,
    CASE
        WHEN active_customers = 0 THEN 'No Active Customers'
        WHEN revenue_yoy_growth_pct >= 5 THEN 'High Growth Market'
        WHEN revenue_yoy_growth_pct <= 0
             AND revenue_per_customer < company_revenue_per_customer
            THEN 'Expansion Opportunity'
        WHEN revenue_yoy_growth_pct <= 0 THEN 'Defend and Grow'
        ELSE 'Stable Growth'
    END AS opportunity_segment
FROM market_benchmark
ORDER BY
    revenue_yoy_growth_pct DESC NULLS LAST,
    revenue_per_customer_gap DESC;

-- MODULE 3: Final model evaluation, benchmarking and error review

-- export: forecast_detail
CREATE OR REPLACE VIEW forecast_detail AS
SELECT * FROM forecast_evaluation_detail ORDER BY forecast_month, Product_ID, Region_ID, Model;

-- export: model_benchmark
CREATE OR REPLACE VIEW model_benchmark AS
SELECT Model, MIN(forecast_month) AS evaluation_start,
    MAX(forecast_month) AS evaluation_end,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT forecast_month) AS evaluated_months,
    SUM(Actual_Demand) AS actual_demand,
    SUM(forecast_demand) AS forecast_demand,
    SUM(absolute_error) AS absolute_error_sum,
    SUM(squared_error) AS squared_error_sum,
    SUM(forecast_error) AS error_sum,
    AVG(absolute_error) AS mae,
    SQRT(AVG(squared_error)) AS rmse,
    100.0 * SUM(absolute_error) / NULLIF(SUM(Actual_Demand), 0) AS wape_pct,
    AVG(forecast_error) AS mean_bias,
    100.0 * SUM(forecast_error) / NULLIF(SUM(Actual_Demand), 0) AS forecast_bias_pct,
    COUNT(*) FILTER (WHERE forecast_error > 0) AS overforecast_count,
    COUNT(*) FILTER (WHERE forecast_error < 0) AS underforecast_count
FROM forecast_evaluation_detail GROUP BY Model ORDER BY mae, Model;

-- export: annual_forecast_accuracy
CREATE OR REPLACE VIEW annual_forecast_accuracy AS
SELECT EXTRACT(YEAR FROM forecast_month)::INTEGER AS forecast_year, Model, MIN(forecast_month) AS evaluation_start,
    MAX(forecast_month) AS evaluation_end,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT forecast_month) AS evaluated_months,
    SUM(Actual_Demand) AS actual_demand,
    SUM(forecast_demand) AS forecast_demand,
    SUM(absolute_error) AS absolute_error_sum,
    SUM(squared_error) AS squared_error_sum,
    SUM(forecast_error) AS error_sum,
    AVG(absolute_error) AS mae,
    SQRT(AVG(squared_error)) AS rmse,
    100.0 * SUM(absolute_error) / NULLIF(SUM(Actual_Demand), 0) AS wape_pct,
    AVG(forecast_error) AS mean_bias,
    100.0 * SUM(forecast_error) / NULLIF(SUM(Actual_Demand), 0) AS forecast_bias_pct,
    COUNT(*) FILTER (WHERE forecast_error > 0) AS overforecast_count,
    COUNT(*) FILTER (WHERE forecast_error < 0) AS underforecast_count
FROM forecast_evaluation_detail GROUP BY ALL ORDER BY forecast_year, mae;

-- export: product_forecast_accuracy
CREATE OR REPLACE VIEW product_forecast_accuracy AS
SELECT Product_ID, Product_Category, Product_Line, Model, MIN(forecast_month) AS evaluation_start,
    MAX(forecast_month) AS evaluation_end,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT forecast_month) AS evaluated_months,
    SUM(Actual_Demand) AS actual_demand,
    SUM(forecast_demand) AS forecast_demand,
    SUM(absolute_error) AS absolute_error_sum,
    SUM(squared_error) AS squared_error_sum,
    SUM(forecast_error) AS error_sum,
    AVG(absolute_error) AS mae,
    SQRT(AVG(squared_error)) AS rmse,
    100.0 * SUM(absolute_error) / NULLIF(SUM(Actual_Demand), 0) AS wape_pct,
    AVG(forecast_error) AS mean_bias,
    100.0 * SUM(forecast_error) / NULLIF(SUM(Actual_Demand), 0) AS forecast_bias_pct,
    COUNT(*) FILTER (WHERE forecast_error > 0) AS overforecast_count,
    COUNT(*) FILTER (WHERE forecast_error < 0) AS underforecast_count
FROM forecast_evaluation_detail GROUP BY ALL ORDER BY Product_ID, mae;

-- export: regional_forecast_accuracy
CREATE OR REPLACE VIEW regional_forecast_accuracy AS
SELECT Region_ID, Region, Model, MIN(forecast_month) AS evaluation_start,
    MAX(forecast_month) AS evaluation_end,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT forecast_month) AS evaluated_months,
    SUM(Actual_Demand) AS actual_demand,
    SUM(forecast_demand) AS forecast_demand,
    SUM(absolute_error) AS absolute_error_sum,
    SUM(squared_error) AS squared_error_sum,
    SUM(forecast_error) AS error_sum,
    AVG(absolute_error) AS mae,
    SQRT(AVG(squared_error)) AS rmse,
    100.0 * SUM(absolute_error) / NULLIF(SUM(Actual_Demand), 0) AS wape_pct,
    AVG(forecast_error) AS mean_bias,
    100.0 * SUM(forecast_error) / NULLIF(SUM(Actual_Demand), 0) AS forecast_bias_pct,
    COUNT(*) FILTER (WHERE forecast_error > 0) AS overforecast_count,
    COUNT(*) FILTER (WHERE forecast_error < 0) AS underforecast_count
FROM forecast_evaluation_detail GROUP BY ALL ORDER BY Region_ID, mae;

-- export: product_market_forecast_accuracy
CREATE OR REPLACE VIEW product_market_forecast_accuracy AS
SELECT Product_ID, Product_Category, Product_Line, Region_ID, Region, Model, MIN(forecast_month) AS evaluation_start,
    MAX(forecast_month) AS evaluation_end,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT forecast_month) AS evaluated_months,
    SUM(Actual_Demand) AS actual_demand,
    SUM(forecast_demand) AS forecast_demand,
    SUM(absolute_error) AS absolute_error_sum,
    SUM(squared_error) AS squared_error_sum,
    SUM(forecast_error) AS error_sum,
    AVG(absolute_error) AS mae,
    SQRT(AVG(squared_error)) AS rmse,
    100.0 * SUM(absolute_error) / NULLIF(SUM(Actual_Demand), 0) AS wape_pct,
    AVG(forecast_error) AS mean_bias,
    100.0 * SUM(forecast_error) / NULLIF(SUM(Actual_Demand), 0) AS forecast_bias_pct,
    COUNT(*) FILTER (WHERE forecast_error > 0) AS overforecast_count,
    COUNT(*) FILTER (WHERE forecast_error < 0) AS underforecast_count
FROM forecast_evaluation_detail GROUP BY ALL ORDER BY Product_ID, Region_ID, mae;

-- export: monthly_forecast_trend
CREATE OR REPLACE VIEW monthly_forecast_trend AS
SELECT forecast_month, Model, MIN(forecast_month) AS evaluation_start,
    MAX(forecast_month) AS evaluation_end,
    COUNT(*) AS observation_count,
    COUNT(DISTINCT forecast_month) AS evaluated_months,
    SUM(Actual_Demand) AS actual_demand,
    SUM(forecast_demand) AS forecast_demand,
    SUM(absolute_error) AS absolute_error_sum,
    SUM(squared_error) AS squared_error_sum,
    SUM(forecast_error) AS error_sum,
    AVG(absolute_error) AS mae,
    SQRT(AVG(squared_error)) AS rmse,
    100.0 * SUM(absolute_error) / NULLIF(SUM(Actual_Demand), 0) AS wape_pct,
    AVG(forecast_error) AS mean_bias,
    100.0 * SUM(forecast_error) / NULLIF(SUM(Actual_Demand), 0) AS forecast_bias_pct,
    COUNT(*) FILTER (WHERE forecast_error > 0) AS overforecast_count,
    COUNT(*) FILTER (WHERE forecast_error < 0) AS underforecast_count
FROM forecast_evaluation_detail GROUP BY ALL ORDER BY forecast_month, mae;

-- export: series_benchmark_comparison
CREATE OR REPLACE VIEW series_benchmark_comparison AS
WITH scores AS (
    SELECT Product_ID, Product_Category, Region_ID, Region,
           MAX(mae) FILTER (WHERE Model = 'Random Forest') AS random_forest_mae,
           MAX(mae) FILTER (WHERE Model = 'Naive Forecast') AS naive_mae,
           MAX(mae) FILTER (WHERE Model = 'Seasonal Naive') AS seasonal_naive_mae
    FROM product_market_forecast_accuracy GROUP BY ALL
)
SELECT *, random_forest_mae < naive_mae AS beats_naive,
       random_forest_mae < seasonal_naive_mae AS beats_seasonal_naive,
       random_forest_mae < LEAST(naive_mae, seasonal_naive_mae) AS beats_both_baselines,
       100.0 * (naive_mae - random_forest_mae) / NULLIF(naive_mae, 0) AS mae_reduction_vs_naive_pct,
       100.0 * (seasonal_naive_mae - random_forest_mae) / NULLIF(seasonal_naive_mae, 0) AS mae_reduction_vs_seasonal_pct
FROM scores ORDER BY random_forest_mae DESC, Product_ID, Region_ID;

-- export: repeated_forecast_bias
CREATE OR REPLACE VIEW repeated_forecast_bias AS
-- Flag 5 or more of exactly 6 test months in one direction, not necessarily consecutive.
-- Descriptive only: six observations do not establish long-term systematic bias.
SELECT Product_ID, Product_Category, Region_ID, Region, observation_count,
       mae, wape_pct, mean_bias, overforecast_count, underforecast_count,
       CASE WHEN overforecast_count >= 5 THEN 'Overforecast in at least 5 of 6 months'
            ELSE 'Underforecast in at least 5 of 6 months' END AS review_reason
FROM product_market_forecast_accuracy
WHERE Model = 'Random Forest' AND observation_count = 6
  AND (overforecast_count >= 5 OR underforecast_count >= 5)
ORDER BY mae DESC, Product_ID, Region_ID;

-- export: planning_exceptions
CREATE OR REPLACE VIEW planning_exceptions AS
-- Historical forecast-error review, not proof of stockouts or excess inventory.
-- All test rows are ranked: no unapproved business tolerance threshold.
SELECT *, 100.0 * forecast_error / NULLIF(Actual_Demand, 0) AS forecast_error_pct,
       CASE WHEN forecast_error > 0 THEN 'Overforecast'
            WHEN forecast_error < 0 THEN 'Underforecast' ELSE 'Exact' END AS forecast_direction,
       DENSE_RANK() OVER (ORDER BY absolute_error DESC) AS exception_priority
FROM forecast_evaluation_detail WHERE Model = 'Random Forest'
ORDER BY exception_priority, forecast_month, Product_ID, Region_ID;

-- MODULE 4: Order delivery status and demand reconciliation
-- Completed/Delayed are recorded order statuses, not inventory or shipment balances.
-- Delivery service convention in this dataset: Completed <=26 days, Delayed >26 days.

-- export: annual_fulfillment_kpi
CREATE OR REPLACE VIEW annual_fulfillment_kpi AS
WITH annual_operations AS (
    SELECT
        EXTRACT(YEAR FROM CAST(Order_Date AS DATE))::INTEGER AS sales_year,
        COUNT(DISTINCT Order_ID) AS total_orders,
        COUNT(DISTINCT Order_ID) FILTER (
            WHERE Order_Status = 'Completed'
        ) AS on_time_orders,
        COUNT(DISTINCT Order_ID) FILTER (
            WHERE Order_Status = 'Delayed'
        ) AS delayed_orders,
        SUM(Quantity) AS ordered_units,
        SUM(Quantity) FILTER (
            WHERE Order_Status = 'Completed'
        ) AS on_time_units,
        ROUND(SUM(Revenue)::NUMERIC, 2) AS total_revenue,
        ROUND(
            SUM(Revenue) FILTER (
                WHERE Order_Status = 'Delayed'
            )::NUMERIC,
            2
        ) AS delayed_revenue,
        ROUND(AVG(Delivery_Days), 2) AS average_delivery_days
    FROM sales_orders
    GROUP BY
        EXTRACT(YEAR FROM CAST(Order_Date AS DATE))
)
SELECT
    sales_year,
    total_orders,
    on_time_orders,
    delayed_orders,
    ordered_units,
    on_time_units,
    total_revenue,
    delayed_revenue,
    average_delivery_days,
    ROUND(
        100.0 * on_time_orders / NULLIF(total_orders, 0),
        2
    ) AS on_time_order_rate_pct,
    ROUND(
        100.0 * on_time_units / NULLIF(ordered_units, 0),
        2
    ) AS on_time_unit_rate_pct,
    ROUND(
        100.0 * delayed_revenue / NULLIF(total_revenue, 0),
        2
    ) AS delayed_revenue_exposure_pct
FROM annual_operations
ORDER BY
    sales_year;

-- export: regional_fulfillment_performance
CREATE OR REPLACE VIEW regional_fulfillment_performance AS
WITH regional_operations AS (
    SELECT
        so.Region_ID,
        r.Region,
        COUNT(DISTINCT so.Order_ID) AS total_orders,
        COUNT(DISTINCT so.Order_ID) FILTER (
            WHERE so.Order_Status = 'Completed'
        ) AS on_time_orders,
        COUNT(DISTINCT so.Order_ID) FILTER (
            WHERE so.Order_Status = 'Delayed'
        ) AS delayed_orders,
        SUM(so.Quantity) AS ordered_units,
        SUM(so.Quantity) FILTER (
            WHERE so.Order_Status = 'Completed'
        ) AS on_time_units,
        ROUND(AVG(so.Delivery_Days), 2) AS average_delivery_days,
        ROUND(
            SUM(so.Revenue) FILTER (
                WHERE so.Order_Status = 'Delayed'
            )::NUMERIC,
            2
        ) AS delayed_revenue
    FROM sales_orders AS so
    INNER JOIN regions AS r
        ON so.Region_ID = r.Region_ID
    GROUP BY
        so.Region_ID,
        r.Region
),
regional_service_level AS (
    SELECT
        *,
        ROUND(
            100.0 * on_time_orders / NULLIF(total_orders, 0),
            2
        ) AS on_time_order_rate_pct,
        ROUND(
            100.0 * delayed_orders / NULLIF(total_orders, 0),
            2
        ) AS delayed_order_rate_pct,
        ROUND(
            100.0 * on_time_units / NULLIF(ordered_units, 0),
            2
        ) AS on_time_unit_rate_pct
    FROM regional_operations
)
SELECT
    Region_ID,
    Region,
    total_orders,
    on_time_orders,
    delayed_orders,
    ordered_units,
    on_time_units,
    average_delivery_days,
    delayed_revenue,
    on_time_order_rate_pct,
    delayed_order_rate_pct,
    on_time_unit_rate_pct,
    DENSE_RANK() OVER (
        ORDER BY delayed_order_rate_pct DESC
    ) AS fulfillment_risk_rank
FROM regional_service_level
ORDER BY
    fulfillment_risk_rank,
    Region_ID;

-- export: product_fulfillment_bottlenecks
CREATE OR REPLACE VIEW product_fulfillment_bottlenecks AS
WITH product_operations AS (
    SELECT
        so.Product_ID,
        p.Product_Category,
        p.Product_Line,
        COUNT(DISTINCT so.Order_ID) AS total_orders,
        COUNT(DISTINCT so.Order_ID) FILTER (
            WHERE so.Order_Status = 'Delayed'
        ) AS delayed_orders,
        SUM(so.Quantity) AS ordered_units,
        SUM(so.Quantity) FILTER (
            WHERE so.Order_Status = 'Delayed'
        ) AS delayed_units,
        ROUND(AVG(so.Delivery_Days), 2) AS average_delivery_days,
        ROUND(
            SUM(so.Revenue) FILTER (
                WHERE so.Order_Status = 'Delayed'
            )::NUMERIC,
            2
        ) AS delayed_revenue
    FROM sales_orders AS so
    INNER JOIN products AS p
        ON so.Product_ID = p.Product_ID
    GROUP BY
        so.Product_ID,
        p.Product_Category,
        p.Product_Line
),
product_service_level AS (
    SELECT
        *,
        ROUND(
            100.0 * delayed_orders / NULLIF(total_orders, 0),
            2
        ) AS delayed_order_rate_pct,
        ROUND(
            100.0 * delayed_units / NULLIF(ordered_units, 0),
            2
        ) AS delayed_unit_rate_pct
    FROM product_operations
)
SELECT
    Product_ID,
    Product_Category,
    Product_Line,
    total_orders,
    delayed_orders,
    ordered_units,
    delayed_units,
    average_delivery_days,
    delayed_revenue,
    delayed_order_rate_pct,
    delayed_unit_rate_pct,
    DENSE_RANK() OVER (
        ORDER BY
            delayed_order_rate_pct DESC,
            delayed_revenue DESC
    ) AS bottleneck_rank
FROM product_service_level
ORDER BY
    bottleneck_rank,
    Product_ID;

-- export: monthly_demand_fulfillment_reconciliation
CREATE OR REPLACE VIEW monthly_demand_fulfillment_reconciliation AS
WITH ordered AS (
    SELECT DATE_TRUNC('month', Order_Date)::DATE AS forecast_month,
           Product_ID, Region_ID, COUNT(*) AS total_orders,
           SUM(Quantity) AS ordered_units,
           SUM(CASE WHEN Order_Status = 'Completed' THEN Quantity ELSE 0 END) AS on_time_units,
           SUM(CASE WHEN Order_Status = 'Delayed' THEN Quantity ELSE 0 END) AS delayed_units
    FROM sales_orders GROUP BY ALL
), matched AS (
    SELECT f.*, COALESCE(o.total_orders, 0) AS total_orders,
           COALESCE(o.ordered_units, 0) AS ordered_units,
           COALESCE(o.on_time_units, 0) AS on_time_units,
           COALESCE(o.delayed_units, 0) AS delayed_units
    FROM forecast_evaluation_detail f
    LEFT JOIN ordered o USING (forecast_month, Product_ID, Region_ID)
    WHERE f.Model = 'Random Forest'
)
SELECT forecast_month, COUNT(*) AS evaluated_series,
       SUM(Actual_Demand) AS actual_demand, SUM(forecast_demand) AS forecast_demand,
       SUM(total_orders) AS total_orders, SUM(ordered_units) AS ordered_units,
       SUM(on_time_units) AS on_time_units, SUM(delayed_units) AS delayed_units,
       SUM(ordered_units - Actual_Demand) AS reconciliation_difference,
       SUM(ABS(ordered_units - Actual_Demand)) AS absolute_reconciliation_difference,
       SUM(forecast_error) AS forecast_variance,
       100.0 * SUM(on_time_units) / NULLIF(SUM(ordered_units), 0) AS on_time_unit_rate_pct
FROM matched GROUP BY forecast_month ORDER BY forecast_month;
