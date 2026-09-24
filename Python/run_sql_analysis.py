"""Build SQL reports from frozen predictions. Does not train or tune any model."""
from pathlib import Path
import re

import duckdb
import numpy as np
import pandas as pd

PROJECT_ROOT = Path(__file__).resolve().parent.parent
RAW_DATA_DIR = PROJECT_ROOT / "data" / "raw"
FORECAST_DIR = PROJECT_ROOT / "outputs" / "forecasts"
SQL_FILE = PROJECT_ROOT / "SQL" / "business_analysis.sql"
RESULTS_DIR = PROJECT_ROOT / "outputs" / "sql"
DATABASE_FILE = PROJECT_ROOT / "outputs" / "database" / "analytics.duckdb"
TABLE_FILES = {
    "sales_orders": "sales_orders.csv",
    "customers": "customers.csv",
    "products": "products.csv",
    "regions": "regions.csv",
    "model_forecast_results": "model_forecast_results.csv",
}
MODEL_COLUMNS = {
    "Random Forest": "Forecast_Demand",
    "Naive Forecast": "Naive_Forecast",
    "Seasonal Naive": "Seasonal_Naive_Forecast",
}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def load_tables(connection):
    frames = {}
    for table, filename in TABLE_FILES.items():
        source_dir = FORECAST_DIR if table == "model_forecast_results" else RAW_DATA_DIR
        frame = pd.read_csv(source_dir / filename)
        date = {"sales_orders": "Order_Date", "model_forecast_results": "Month"}.get(table)
        if date:
            frame[date] = pd.to_datetime(frame[date], errors="raise")
        frames[table] = frame
        connection.register("csv_input", frame)
        connection.execute(f"CREATE OR REPLACE TABLE {table} AS SELECT * FROM csv_input")
        connection.unregister("csv_input")
    return frames


def validate_inputs(frames):
    orders = frames["sales_orders"]
    forecast = frames["model_forecast_results"]
    keys = ["Month", "Product_ID", "Region_ID"]
    require(not orders.empty and not forecast.empty, "Orders and forecasts must be populated.")
    for table, key in [("sales_orders", "Order_ID"), ("products", "Product_ID"),
                       ("regions", "Region_ID"), ("customers", "Customer_ID")]:
        values = frames[table][key]
        require(values.notna().all() and values.is_unique, f"Invalid or duplicate {table}.{key}")
    require(forecast[keys].notna().all().all(), "Missing forecast keys.")
    require(not forecast.duplicated(keys).any(), "Duplicate forecast grain.")
    require(forecast["Month"].dt.is_month_start.all(), "Forecast dates must be month starts.")
    for frame in [orders, forecast]:
        for table, key in [("products", "Product_ID"), ("regions", "Region_ID")]:
            require(frame[key].isin(frames[table][key]).all(), f"Unmatched {key}")
    require(orders["Customer_ID"].isin(frames["customers"]["Customer_ID"]).all(), "Unmatched customer.")
    require(frames["customers"]["Region_ID"].isin(frames["regions"]["Region_ID"]).all(), "Unmatched customer region.")
    require(orders["Order_Date"].notna().all(), "Missing order date.")
    require(np.isfinite(orders[["Quantity", "Revenue", "Delivery_Days"]]).all().all(), "Invalid order numeric values.")
    require(orders["Quantity"].gt(0).all(), "Non-positive order quantity.")
    require(orders["Order_Status"].isin(["Completed", "Delayed"]).all(), "Unknown delivery status.")
    require(((orders["Order_Status"].eq("Completed") & orders["Delivery_Days"].le(26)) |
             (orders["Order_Status"].eq("Delayed") & orders["Delivery_Days"].gt(26))).all(),
            "Delivery status does not support the documented 26-day convention.")
    require(np.isfinite(forecast[["Actual_Demand", *MODEL_COLUMNS.values()]]).all().all(), "Invalid forecast values.")
    require(forecast["Actual_Demand"].ge(0).all(), "Negative actual demand.")
    error = forecast["Forecast_Demand"] - forecast["Actual_Demand"]
    for column, expected in [("Forecast_Error", error), ("Absolute_Error", error.abs()), ("Squared_Error", error ** 2)]:
        np.testing.assert_allclose(forecast[column], expected)
    monthly = orders.assign(Month=orders["Order_Date"].dt.to_period("M").dt.to_timestamp()).groupby(keys)["Quantity"].sum()
    observed = monthly.reindex(pd.MultiIndex.from_frame(forecast[keys]), fill_value=0)
    np.testing.assert_allclose(observed, forecast["Actual_Demand"])
    for months, column in [(1, "Naive_Forecast"), (12, "Seasonal_Naive_Forecast")]:
        lag_keys = forecast[keys].copy()
        lag_keys["Month"] -= pd.DateOffset(months=months)
        lag_values = monthly.reindex(pd.MultiIndex.from_frame(lag_keys), fill_value=0)
        np.testing.assert_allclose(lag_values, forecast[column])


def validate_results(connection, frames):
    forecast = frames["model_forecast_results"]
    benchmark = connection.sql("SELECT * FROM model_benchmark").df().set_index("Model")
    require(connection.sql("SELECT COUNT(*) FROM forecast_evaluation_detail").fetchone()[0] == 3 * len(forecast),
            "Forecast joins changed the row count.")
    for model, column in MODEL_COLUMNS.items():
        error = forecast[column] - forecast["Actual_Demand"]
        denominator = forecast["Actual_Demand"].sum()
        expected = [error.abs().mean(), np.sqrt((error ** 2).mean()),
                    100 * error.abs().sum() / denominator if denominator else np.nan, error.mean()]
        np.testing.assert_allclose(
            benchmark.loc[model, ["mae", "rmse", "wape_pct", "mean_bias"]].to_numpy(dtype=float),
            expected, equal_nan=True,
        )
        for view in ["annual_forecast_accuracy", "product_forecast_accuracy", "regional_forecast_accuracy",
                     "product_market_forecast_accuracy", "monthly_forecast_trend"]:
            totals = connection.execute(
                f"SELECT SUM(observation_count), SUM(absolute_error_sum), SUM(squared_error_sum) FROM {view} WHERE Model = ?",
                [model],
            ).fetchone()
            np.testing.assert_allclose(totals, [len(forecast), error.abs().sum(), (error ** 2).sum()])
    difference = connection.sql(
        "SELECT SUM(absolute_reconciliation_difference) FROM monthly_demand_fulfillment_reconciliation"
    ).fetchone()[0]
    require(difference == 0, "Orders and forecast actuals do not reconcile.")


def main():
    sql = SQL_FILE.read_text(encoding="utf-8")
    exports = re.findall(r"^-- export: ([a-z][a-z0-9_]*)$", sql, flags=re.MULTILINE)
    require(bool(exports) and len(exports) == len(set(exports)), "Missing or duplicate SQL export names.")
    DATABASE_FILE.parent.mkdir(parents=True, exist_ok=True)
    with duckdb.connect(str(DATABASE_FILE)) as connection:
        connection.begin()
        try:
            frames = load_tables(connection)
            validate_inputs(frames)
            connection.execute(sql)
            validate_results(connection, frames)
            outputs = {name: connection.sql(f"SELECT * FROM {name}").df() for name in exports}
            connection.commit()
        except Exception:
            connection.rollback()
            raise
    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    for name, result in outputs.items():
        path = RESULTS_DIR / f"{name}.csv"
        result.to_csv(path, index=False, encoding="utf-8-sig", date_format="%Y-%m-%d")
        require(len(pd.read_csv(path)) == len(result), f"Export row mismatch: {path.name}")
        print(f"{path.name}: {len(result)} rows")
    print("Passed: unique keys, joins, raw-order reconciliation, baseline definitions, SQL/Python metrics and grouped totals.")
    print(f"Database: {DATABASE_FILE}")
    print(f"Results: {RESULTS_DIR}")


if __name__ == "__main__":
    main()
