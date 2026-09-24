# Demand Forecasting & Sales Operations Analytics

An end-to-end portfolio project connecting **Python forecasting, SQL analysis, and Power BI** to evaluate monthly demand and support sales operations planning.

**Main result:** Random Forest reduced final-test MAE by **26.23% versus Naive Forecast** and **19.44% versus Seasonal Naive** across 32 product-region series. The project uses synthetic sales data; results demonstrate the analytical workflow rather than real business impact.

[Forecasting notebook](Python/demand_forecasting.ipynb) | [Model benchmark](outputs/sql/model_benchmark.csv) | [SQL analysis](SQL/business_analysis.sql) | [Power BI project](powerbi/demand_forecasting.pbip)

## Final Model Evaluation & Benchmarking

All three models are evaluated on the **same 192 monthly product-region observations, July-December 2025**. Lower values are better.

| Model | Forecast rule | MAE (units) | RMSE (units) | WAPE |
| --- | --- | ---: | ---: | ---: |
| **Random Forest** | Trained on historical demand features | **3,141.40** | **4,245.65** | **34.19%** |
| Seasonal Naive | `Demand_Lag_12` | 3,899.38 | 4,910.20 | 42.44% |
| Naive Forecast | `Demand_Lag_1` | 4,258.60 | 5,450.38 | 46.35% |

Relative MAE improvement = `(baseline MAE - model MAE) / baseline MAE`. The dashboard displays Forecast MAE as **3.14K** and RMSE as **4.25K**.

These are **historical rolling one-month-ahead test predictions**. Each month uses demand observed before that month, including earlier test months. Model parameters remain fixed. This is not a six-month forecast made in June or a future forecast beyond December 2025.

## Business Questions and Workflow

The project asks whether machine learning improves on simple demand baselines, where forecast errors require planning attention, and how sales, customer, and delivery patterns provide operational context.

```text
Sales orders + customer/product/region dimensions
    -> Monthly product-region demand
    -> Historical features + chronological model selection
    -> Frozen test predictions + two naive baselines
    -> SQL benchmarks, segment diagnostics, and operational reports
    -> Power BI decision-support dashboard
```

- **Data preparation:** 10,000 synthetic orders from January 2023 to December 2025; 8 products, 4 regions, and 50 customers. Aggregation creates 1,152 monthly observations across 32 series.
- **Prediction:** Python builds lag and rolling features, selects a model using development-period validation, and exports the final test results.
- **Business analysis:** SQL produces 21 exports covering sales, customer and market intelligence, forecast errors, and delivery operations. Metrics are reconciled against the saved predictions.
- **Reporting:** Power BI combines transactional sales and forecast facts with shared dimensions. It reads raw CSVs and the frozen prediction file directly; SQL outputs provide reproducible analysis alongside the dashboard.

## Modeling Decisions

| Decision | Implementation and purpose |
| --- | --- |
| Prediction grain | One monthly demand prediction per product-region pair |
| Historical features | Demand lags 1, 2, 3, 6, and 12; shifted rolling averages over 3 and 6 months; month, quarter, and time index |
| Warm-up period | First 12 months provide history; 768 observations remain for modeling |
| Development set | January 2024-June 2025: 576 observations |
| Model selection | Three expanding-window, chronological validation folds; MAE-based selection across a mean baseline, Random Forest, and Histogram Gradient Boosting |
| Final model | Random Forest: 200 trees, maximum depth 12, minimum samples per leaf 3 |
| Final test | July-December 2025: 192 observations reserved from model selection |
| Meaningful benchmarks | Previous-month and same-month-last-year demand evaluated on identical test rows |

Features use past demand only. The final test results are frozen; later error analysis is descriptive and does not feed further parameter tuning.

## Key Findings and Planning Implications

- **Aggregate improvement is not universal:** Random Forest beats Naive Forecast in 28 of 32 series and Seasonal Naive in 22; it beats both in 19. Segment-level performance matters when prioritizing review.
- **Accurate totals can hide large local errors:** actual and predicted demand both round to 1.76M, but WAPE is 34.19%. Overforecasts and underforecasts offset in totals; MAE and WAPE retain their magnitude.
- **Investigate difficult series:** P004-R04 has MAE of approximately 6.96K and WAPE of 63.57%. Its fluctuating monthly demand is a useful planning-review case.
- **Use orders to explain exceptions cautiously:** P003-R04 demand rose from 22,398 in June to 31,424 in July 2025 while order count rose from 20 to 27. This supports reviewing order activity, but does not establish a promotion or other causal explanation.

See [series comparisons](outputs/sql/series_benchmark_comparison.csv) and [planning exceptions](outputs/sql/planning_exceptions.csv). Exceptions identify forecast deviations; they do not establish stockouts or excess inventory.

## Power BI Dashboard

Open [demand_forecasting.pbip](powerbi/demand_forecasting.pbip). The editable report and TMDL semantic model are included. See [Power BI setup](powerbi/README.md) before refreshing.

| Page | Analytical purpose |
| --- | --- |
| Executive Overview | Revenue, orders, customers, and high-level performance |
| Sales & Customer Intelligence | Customer concentration, product contribution, and regional trends |
| Demand Forecasting Analytics | Actual versus predicted demand, MAE, RMSE, WAPE, and baseline comparison |
| Operational Performance | Delivery performance and operational exceptions |

The model separates order-level sales from monthly product-region forecasts. Customer-level filters cannot be interpreted as customer-level forecasts. Forecast summaries cover the six-month test window, even when grouped by year.

<details>
<summary>Earlier dashboard screenshots (legacy design reference)</summary>

These images predate the updated forecasting pipeline. Forecast values and measures shown here are not the current model evaluation. Updated screenshots still need to be captured from the current Power BI project.

![Earlier executive overview](images/01-executive-overview.png)
![Earlier sales and customer page](images/02-sales-customer-intelligence.png)
![Earlier demand forecasting page](images/03-demand-forecasting-analytics.png)
![Earlier operations page](images/04-operational-performance.png)
![Earlier data model](images/data-model.png)

</details>

## Repository Structure

```text
data/
  raw/                         Four source CSVs
  processed/                   Monthly demand and modeling features
Python/
  demand_forecasting.ipynb      Preparation, model selection, evaluation, diagnostics
  run_sql_analysis.py          SQL execution and data/metric consistency checks
SQL/
  business_analysis.sql        Business views and export definitions
  README.md                    Metrics, grain, and output documentation
outputs/
  forecasts/                   Frozen model_forecast_results.csv
  sql/                         21 business-analysis CSV exports
powerbi/
  demand_forecasting.pbip       Current project entry point
  demand_forecasting.Report/    Editable report definition
  demand_forecasting.SemanticModel/  TMDL model and measures
images/                        Earlier dashboard screenshots
archive/                       Legacy forecast CSV and PBIX
requirements.txt               Pinned analysis dependencies
```

## Reproduce the Analysis

The saved predictions and SQL exports are included for inspection without retraining. From the repository root, using Python 3.14 and PowerShell:

```powershell
python -m venv Python/.venv
./Python/.venv/Scripts/python.exe -m pip install -r requirements.txt
./Python/.venv/Scripts/python.exe Python/run_sql_analysis.py
```

The SQL runner uses the frozen predictions, checks source keys, baseline values, actual demand, and error aggregations, then recreates `outputs/database/analytics.duckdb` and the 21 SQL exports. These are data and calculation checks; no model training or tuning occurs.

To inspect modeling, open the notebook in VS Code or Jupyter using this environment. Running the full notebook retrains models and overwrites generated results. Sections 7-8 support diagnostics from saved CSVs without rerunning training.

Power BI requires its `ProjectRoot` parameter to point to the cloned repository. Refresh after setting the path. Local environments, database files, and Power BI caches are excluded from version control.

Metric definitions and aggregation rules are documented in [SQL/README.md](SQL/README.md). WAPE is calculated from total absolute error divided by total actual demand, rather than averaging subgroup percentages.

## Limitations and Next Steps

- Synthetic data and a six-month test window limit conclusions about real-world reliability and longer seasonal patterns.
- Forecasts use demand history and calendar features; price, promotions, inventory availability, and external demand drivers are not included.
- The project contains evaluated predictions and reproducible analysis, but no deployed forecasting service, serialized production model, or future forecast output.
- The next presentation step is to replace legacy screenshots with captures of the current report. A future production phase would need new unseen data, business error tolerances, and a defined refresh/monitoring process.
