# Power BI project

Open `demand_forecasting.pbip` in Power BI Desktop with PBIP support. Keep the
adjacent `.Report` and `.SemanticModel` folders together.

## Data setup

1. Set the `ProjectRoot` Power Query parameter to the repository's absolute path,
   using forward slashes, for example `C:/Projects/demand-forecasting-sales-analytics`.
   The supplied copy points to the current local GitHub repository.
2. Refresh the model. Sources are `data/raw/*.csv` and
   `outputs/forecasts/model_forecast_results.csv` relative to that root.
3. The forecast page evaluates July-December 2025: 192 product-region-month rows.
   Default Random Forest metrics are MAE 3.14K, RMSE 4.25K, and WAPE 34.19%.

The parameter is stored in
`demand_forecasting.SemanticModel/definition/expressions.tmdl` and can also be
changed there while Desktop is closed. The report references the adjacent model
through `definition.pbir`. Local caches are excluded, so refresh is required.

## Scope

Four pages cover executive performance, sales/customers, forecasting, and
operations. Forecast Models is a disconnected benchmark selector; the forecast
fact retains one row per observation and separate prediction columns for the
three models. Actual demand must not be summed across repeated model rows.

This folder contains the current editable project. The earlier binary PBIX is
preserved under `archive/`; screenshots under `images/` are also legacy previews.
No new binary PBIX or updated screenshots have been exported in this sync.
