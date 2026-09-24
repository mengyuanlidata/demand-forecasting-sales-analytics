# Demand Forecasting & Sales Operations Analytics

An end-to-end predictive analytics and business intelligence project combining **Python, scikit-learn, SQL, DuckDB, and Power BI**. The project turns synthetic sales orders into monthly demand forecasts, evaluates them against practical baselines, and connects forecast performance with sales, customer and delivery analysis.

**Latest model result:** Random Forest achieves **3,141.40 MAE**, **4,245.65 RMSE**, and **34.19% WAPE** on the July-December 2025 final test set.

> **Repository status:** the modeling and SQL workflow has been updated in the working project. This repository currently contains the earlier dashboard package, five source CSVs and screenshots. Its `data/demand_forecast.csv` and forecast screenshot show legacy synthetic forecasts with 5.06% WAPE; they do not represent the latest Random Forest evaluation. Updated notebook, SQL scripts, model prediction CSV and dashboard artifacts have not yet been synchronized here.

[Download the bundled PBIX](powerbi/Demand_Forecasting_Sales_Analytics.pbix) ? [Browse the bundled data](data/) ? [Dashboard previews](#dashboard-previews)

## Business objective

Predict **next month's demand units for each product and region**, and provide a reporting framework that answers four questions:

1. How are revenue, order volume and customer activity changing?
2. Which customers, products and regions contribute most to sales?
3. Does machine learning outperform simple demand forecasts, and where does it fail?
4. Which products and regions experience delivery delays?

Demand includes all valid orders, including delayed orders. Forecast errors identify planning uncertainty; they do not directly establish stockouts or excess inventory.

## Data and analytical scope

| Item | Scope |
| --- | --- |
| Data source | Synthetic sales and operations data |
| Order history | 10,000 orders, January 2023-December 2025 |
| Customers | 50 |
| Products and regions | 8 products across 4 regions |
| Monthly modeling grain | Month ? product ? region |
| Complete monthly panel | 1,152 observations |
| Development period after feature warm-up | January 2024-June 2025 |
| Final test period | July-December 2025; 192 observations |

The datasets are generated for portfolio demonstration and do not represent actual company performance or real customer records.

## Updated forecasting methodology

The working project follows this sequence:

1. **Prepare monthly demand.** Validate source orders, aggregate quantities by month/product/region, and complete missing monthly combinations with zero demand.
2. **Create historical features.** Use demand lags of 1, 2, 3, 6 and 12 months, shifted 3- and 6-month rolling averages, and month, quarter and time-index features.
3. **Validate chronologically.** Build three expanding-window cross-validation folds within the development period. Keep every product-region observation from the same month in the same fold.
4. **Select and tune models.** Compare a mean baseline, Random Forest and HistGradientBoosting using development MAE. Refit each selected configuration on the development data.
5. **Evaluate the selected model.** Compare Random Forest against Naive and Seasonal Naive forecasts on the same final-test rows.
6. **Export and diagnose errors.** Save actual demand, all three predictions, signed errors, absolute errors and squared errors. Analyze product, region and monthly performance, then investigate selected errors using source orders.

The first 12 months supply lag history and are excluded from model-ready rows. Features are shifted so they do not include the current month's actual demand.

**Evaluation design:** rolling one-month-ahead prediction. When predicting a later test month, earlier test months' actual demand is available. This differs from forecasting all six months at once. The Random Forest remains fixed during the final test period.

Selected Random Forest configuration: **200 trees**, **maximum depth 12**, **minimum 3 samples per leaf**. Model tuning stopped after final evaluation; subsequent error analysis is descriptive.

## Final model evaluation and benchmarking

All methods are evaluated on **192 observations from July-December 2025**. MAE and RMSE are measured in demand units; lower values are better.

| Model | Forecast definition | MAE | RMSE | WAPE |
| --- | --- | ---: | ---: | ---: |
| **Random Forest** | Selected development model | **3,141.40** | **4,245.65** | **34.19%** |
| Seasonal Naive | Same month in the previous year (`Demand_Lag_12`) | 3,899.38 | 4,910.20 | 42.44% |
| Naive Forecast | Previous month's demand (`Demand_Lag_1`) | 4,258.60 | 5,450.38 | 46.35% |

Random Forest reduces MAE by **26.23%** compared with Naive Forecast and **19.44%** compared with Seasonal Naive. It beats both baselines in **19 of 32 product-region combinations**, showing that overall improvement is not uniform across segments.

The updated dashboard uses compact KPI displays of **3.14K MAE** and **4.25K RMSE**, while preserving full precision in the underlying measures. These values describe the updated working project, not the legacy forecast screenshot below.

## Key findings from the updated analysis

- **P004 ? R04 (Electronic Module, South America)** has the largest product-region MAE at **6,955.75 units**. Demand alternates between high and low months, and the model repeatedly predicts in the opposite direction.
- **P003 ? R04 (Motor Component, South America)** has a missed July peak: actual demand is **31,424 units**, while the model predicts approximately **14,683**. Order count rises from 20 in June to 27 in July; average order quantity rises only about 3.9%.
- The largest July order for that combination represents only **6.2%** of monthly demand. The peak is associated with more orders, rather than one exceptional order.
- **R04** has the highest regional MAE, while **R03** has the highest regional WAPE. Absolute and relative errors highlight different areas for review.
- Overall mean signed error is approximately **-14.98 units**, despite **34.19% WAPE**. Opposing errors nearly cancel in aggregate, so net bias alone understates prediction error.

Only six test months are available per product-region combination. The data has no promotion, stockout or advance-order snapshot fields, so the analysis cannot establish those business causes.

## SQL business analysis

The updated working project uses DuckDB to organize the analysis into four modules and generate **21 result CSVs**:

| Module | Analyses |
| --- | --- |
| Sales performance and growth | Annual trends, regional contribution and product revenue |
| Customer and market intelligence | Customer value, customer segments, growth and market comparisons |
| Demand forecasting | Three-model benchmarking, segment errors, monthly trends, repeated bias and ranked exceptions |
| Delivery operations | On-time rates, delayed orders and revenue, product bottlenecks and demand reconciliation |

The SQL workflow checks unique keys, dimension joins, baseline definitions and demand reconciliation against source orders. SQL forecast metrics are independently reconciled with Python. These checks do not retrain or retune the model.

Sales and operational analysis covers **2023-2025**. Forecast performance covers **July-December 2025 only**.

## Dashboard previews

The four-page report structure is retained in the updated project. The images below document the **earlier bundled dashboard** and are not screenshots of the latest model results.

### 1. Executive Overview

Revenue, orders, active customers, regional contribution and product-line performance.

![Executive Overview](images/01-executive-overview.png)

### 2. Sales & Customer Intelligence

Customer rankings, revenue concentration, customer segments and monthly trends.

![Sales & Customer Intelligence](images/02-sales-customer-intelligence.png)

### 3. Demand Forecasting Analytics

The updated page replaces the legacy accuracy emphasis with MAE, RMSE, WAPE, forecast bias and a three-model benchmark. It uses the six-month final test period.

**Legacy preview:** the 94.94% accuracy and 5.06% WAPE shown below come from the earlier synthetic forecasts. Use the final model table above for the current evaluation.

![Legacy Demand Forecasting Analytics](images/03-demand-forecasting-analytics.png)

### 4. Operational Performance

On-time delivery, delayed orders, delivery speed and product/region comparisons.

![Operational Performance](images/04-operational-performance.png)

## Data model

The report uses two primary fact tables:

- **sales_orders:** transaction-level revenue, quantities, customers and delivery status.
- **demand_forecast:** monthly actual demand and predictions. The updated project retains this internal name for visual compatibility while sourcing the new model results.

Calendar, products and regions support time and segment filtering. Customers support sales and operational analysis; customer filters do not provide customer-level forecast attribution.

In the updated project, the forecast fact has **192 rows with separate prediction columns**. A disconnected **Forecast Models** table supplies the three model names for comparison measures, avoiding duplication of actual demand.

The image below shows the earlier model, before the comparison table was added.

![Earlier Power BI Data Model](images/data-model.png)

## Forecast metric definitions

- **Error = forecast - actual.** Positive values mean overforecast; negative values mean underforecast.
- **MAE = sum of absolute errors / observation count.**
- **RMSE = square root of the mean squared error.**
- **WAPE = sum of absolute errors / sum of actual demand**, expressed as a percentage.
- **Bias % = sum of signed errors / sum of actual demand**, expressed as a percentage.

Calculate errors at the month-product-region grain before aggregation. Do not average subgroup WAPEs or RMSEs. Zero-denominator percentages should remain blank rather than displaying artificial accuracy.

### DAX examples used by the updated model

```DAX
Absolute Forecast Error =
SUMX(
    demand_forecast,
    ABS(demand_forecast[Forecast_Demand] - demand_forecast[Actual_Demand])
)

Forecast MAE =
DIVIDE([Absolute Forecast Error], COUNTROWS(demand_forecast))

Forecast RMSE =
SQRT(
    DIVIDE(
        SUMX(
            demand_forecast,
            POWER(demand_forecast[Forecast_Demand] - demand_forecast[Actual_Demand], 2)
        ),
        COUNTROWS(demand_forecast)
    )
)

WAPE % =
DIVIDE([Absolute Forecast Error], SUM(demand_forecast[Actual_Demand]))

Forecast Bias % =
DIVIDE(
    SUM(demand_forecast[Forecast_Demand]) - SUM(demand_forecast[Actual_Demand]),
    SUM(demand_forecast[Actual_Demand])
)
```

Format WAPE and Bias as percentages in Power BI. These measures operate on the single-row-per-observation forecast table.

## Current repository contents

```text
demand-forecasting-sales-analytics/
|-- README.md
|-- data/
|   |-- customers.csv
|   |-- demand_forecast.csv             Legacy synthetic forecasts
|   |-- products.csv
|   |-- regions.csv
|   `-- sales_orders.csv
|-- images/
|   |-- 01-executive-overview.png
|   |-- 02-sales-customer-intelligence.png
|   |-- 03-demand-forecasting-analytics.png
|   |-- 04-operational-performance.png
|   `-- data-model.png
`-- powerbi/
    `-- Demand_Forecasting_Sales_Analytics.pbix
```

To inspect the bundled report, open the PBIX in Power BI Desktop and update its local CSV source paths to the files in `data/` as needed. Refreshing that package does not generate the latest model predictions.

The latest working project additionally contains a forecasting notebook, a SQL runner and analysis script, processed features, `model_forecast_results.csv`, 21 SQL exports and an editable PBIP report. These artifacts must be synchronized into this repository before the updated end-to-end workflow can be reproduced from a clone.

## Tools and technologies

- **Python:** pandas, NumPy and scikit-learn for preparation, forecasting and evaluation.
- **Model development:** TimeSeriesSplit, GridSearchCV, RandomForestRegressor and HistGradientBoostingRegressor.
- **SQL / DuckDB:** aggregation, window functions, business KPIs and data reconciliation.
- **Power BI / DAX:** semantic modeling, interactive reports and filter-aware measures.
- **Jupyter, VS Code and Git:** analysis development and version control.

## Limitations and project status

The project demonstrates a forecasting and reporting workflow on synthetic data. Completing missing monthly combinations with zero assumes the underlying order history is complete. The test period is short, and performance is not evidence of effectiveness on real production demand.

Current model outputs are **historical test predictions**, not operational future forecasts. No serialized trained model has been exported. Further model tuning was intentionally stopped after final evaluation.
