# SQL business analysis

The original four-module structure is retained: sales performance, customer and
market intelligence, demand forecasting, and delivery operations. The forecast
module uses the frozen model predictions in `outputs/forecasts/model_forecast_results.csv`.
The legacy `archive/legacy_demand_forecast.csv` is not loaded or referenced.

## Run

From the Python directory:

```powershell
.\.venv\Scripts\python.exe run_sql_analysis.py
```

Dependencies: duckdb, pandas, numpy. The runner resolves paths relative to its
own location, so it can also be called from another working directory.
It replaces the five source tables and analysis views in `outputs/database/analytics.duckdb`,
then overwrites the 21 CSV exports in `outputs/sql`. No training is performed.
The SQL file contains persistent DuckDB views and `-- export:` markers naming
views to export. Source tables must be loaded before running the SQL alone.

## Sources and periods

- Sales, customer and operational reports use all available orders, currently
  January 2023 to December 2025. Growth compares the latest two observed years.
- Forecast reports cover only July-December 2025: 192 month-product-region rows.
  These are historical, rolling one-month-ahead test predictions, not future
  forecasts or a full-year evaluation. Annual summaries retain actual evaluation
  start/end dates and the number of evaluated months.
- Random Forest uses `Forecast_Demand`, Naive uses `Naive_Forecast`, and Seasonal
  Naive uses `Seasonal_Naive_Forecast`. Parameters and predictions remain fixed.
- All valid orders count as demand, including delayed orders. In these data,
  Completed maps to delivery within 26 days, Delayed to more than 26 days.
  The runner verifies this convention. Status is not an inventory balance.

## Outputs

| Module | CSV exports (without extension) |
| --- | --- |
| Sales | annual_sales_trend, regional_sales_contribution, product_revenue_contribution |
| Customers and market | customer_value_ranking, customer_type_performance, customer_growth_and_risk, regional_market_opportunity |
| Forecast detail and benchmark | forecast_detail, model_benchmark, series_benchmark_comparison |
| Forecast breakdown | annual_forecast_accuracy, product_forecast_accuracy, regional_forecast_accuracy, product_market_forecast_accuracy, monthly_forecast_trend |
| Error review | repeated_forecast_bias, planning_exceptions |
| Operations | annual_fulfillment_kpi, regional_fulfillment_performance, product_fulfillment_bottlenecks, monthly_demand_fulfillment_reconciliation |

## Metrics and Power BI integration

- Error = forecast minus actual. Positive is overforecast, negative underforecast.
- MAE = sum of absolute errors / observation count.
- RMSE = square root of (sum of squared errors / observation count).
- WAPE (%) = 100 * sum of absolute errors / sum of actual demand.
- Bias (%) = 100 * sum of signed errors / sum of actual demand.
- Zero denominators produce NULL. Aggregate from error sums and counts, never
  average subgroup WAPEs or RMSEs. Summaries retain these additive components.
- `forecast_detail` has 576 rows: three models for each of 192 observations.
  Its key is forecast_month + Product_ID + Region_ID + Model. Always filter or
  group by Model, including when summing actual demand. For a single actuals
  fact, use the 192-row source table or Random Forest-filtered detail.
- Forecast errors are calculated before aggregation, so offsetting errors do
  not disappear from MAE/WAPE. Monthly net bias is a separate measure.
- `planning_exceptions` ranks all 192 Random Forest errors. It does not infer
  stockouts/excess inventory or impose a business tolerance threshold.
- `repeated_forecast_bias` flags at least 5 of exactly 6 months in one direction,
  not necessarily consecutive. It is descriptive, not a statistical finding.
- Existing report filenames are retained where possible, but forecast output
  schemas now include Model and revised metrics. Refresh Power BI queries and
  field mappings before use. The old forecast_accuracy_pct / MAPE fields are
  omitted. Prefer MAE and WAPE. Customer filters do not identify forecast rows,
  since forecasts are at product-region grain, not customer grain.

## Validation performed by the runner

Check source keys, dimension joins, finite values, stored errors, baseline
values against raw history, and forecast actuals against source orders. Compare
SQL metrics with independent pandas calculations and reconcile every grouped
forecast view to total absolute/squared errors. Validate order reconciliation
before exporting. These are data and calculation checks, not model tuning.

Raw sources are in `data/raw`, modeling intermediates in `data/processed`.
Legacy forecast data and the earlier dashboard PBIX are in `archive`.
All 21 result CSVs are generated in `outputs/sql`.
