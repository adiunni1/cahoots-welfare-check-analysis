# Stock Price Movement Predictor

I was interested in creating an end-to-end machine learning pipeline that predicts **whether a stock will go UP or DOWN the next trading day** and framed as a binary classification problem instead of a price-prediction problem (which is far more tractable and honest).

Built to practice time-series feature engineering, XGBoost classification, and deploying ML models as serverless REST APIs on AWS.

**Live API:**
```
POST https://<your-api-gateway-url>/prod/predict
{ "ticker": "AAPL" }
```

---

## Why Classification, Not Regression?

We know that predicting exact stock prices is notoriously unreliable, so I didn't have any expectation that I'd be able to make something that'd be 100% accurate but I tried to get as close as possible. What was more imperative to me was understanding how to analyze and approach the problem more so than the solution itself. Predicting *direction* (up or down) is a more tractable problem, which is that it transforms an unbounded regression target into a binary label, and the question "will this go up tomorrow?" maps cleanly to real trading decisions.

---

## Architecture

```
Yahoo Finance API
      │
      ▼
data_pipeline.py        ← Feature engineering + S3 upload
      │
      ▼
  Amazon S3             ← Stores raw features CSV + trained model
      │
      ▼
train_model.py          ← XGBoost, time-aware split, evaluation artifacts
      │
      ▼
  Amazon S3             ← Stores serialised model (.joblib)
      │
      ▼
lambda_function.py      ← Loads model, fetches latest data, returns prediction
      │
      ▼
API Gateway             ← Live REST endpoint
```

**AWS Services:** S3, IAM, Lambda, API Gateway, CloudWatch

---

## Features Engineered

All features are computed from raw OHLCV (Open, High, Low, Close, Volume) data:

| Feature | Description |
|---|---|
| `sma_5/10/20/50` | Simple moving averages — trend direction |
| `ema_5/10/20/50` | Exponential moving averages — recent-weighted trend |
| `price_to_sma20/50` | Close price relative to MA — momentum signal |
| `rsi_14` | Relative Strength Index — overbought/oversold |
| `macd`, `macd_signal`, `macd_hist` | MACD — trend/momentum crossover |
| `bb_width`, `bb_position` | Bollinger Bands — volatility + price position |
| `volume_ratio` | Volume vs. 20-day average — conviction behind moves |
| `daily_return` | Today's percentage return |
| `return_lag_1..5` | Returns from the previous 5 trading days |
| `volatility_10` | 10-day rolling standard deviation of returns |
| `vix_close` | CBOE Volatility Index close — market-wide "fear gauge" |
| `spy_return` | S&P 500 (SPY) daily return — broad market direction/context |

**Target:** `1` if next day's close > today's close, else `0`

---

## Key Design Decision: Time-Aware Train/Test Split

Stock data is sequential. Randomly shuffling before splitting would allow the model to "see the future" during training, which is a form of data leakage that inflates test accuracy but fails in production.

```
────────────────────────────────────────────────────────
  2015              TRAIN (80%)              2023 │ TEST (20%) │ 2025
────────────────────────────────────────────────────────
```

The model is always trained on the **past** and evaluated on the **future**.

---

## Model: XGBoost Classifier

XGBoost was chosen over alternatives (LSTM, logistic regression) because:
- Handles tabular time-series data with engineered features better than recurrent networks out of the box
- Produces interpretable feature importances — critical for understanding *why* a prediction was made
- Fast to train and tune; no GPU required
- Strong industry adoption in quantitative finance

**Hyperparameters:** 300 estimators, max depth 4, learning rate 0.05, subsample 0.8

---

## Results (Test Set, 2015–2025)

After all four rounds of improvement (oversampling, VIX/SPY features, threshold tuning), actual test-set performance across all 5 tickers:

| Ticker | Accuracy | UP Recall |
|---|---|---|
| AAPL | 44% | 7% |
| MSFT | 50% | 21% |
| GOOGL | 48% | 44% |
| AMZN | 49% | 54% |
| NVDA | 45% | 5% |

> **Note:** A naive "always predict UP" baseline lands around ~53% accuracy (markets go up more than they go down long-term). None of these tickers beat it. AMZN and GOOGL showed the strongest signal, with UP recall in a more usable 44–54% range. AAPL and NVDA are the weakest: NVDA's 2023–2024 AI-driven rally was such a sustained, structurally-different regime that historical technical patterns from earlier years no longer transferred, and AAPL similarly struggled to find real signal in this window. These numbers are a reminder that the earlier "Model Development Journey" fixes addressed real bugs (the always-predict-DOWN behavior, the miscalibrated threshold) without guaranteeing genuine predictive edge. The imbalance and threshold fixes make a model's predictions *sane*, not necessarily *accurate*.

---

## Model Development Journey

The model went through several rounds of debugging and iteration after the initial baseline underperformed badly on recent data:

1. **Baseline XGBoost — ~44% accuracy.** The first version, trained on technical indicators alone, barely beat a coin flip and was worse than the "always predict UP" naive baseline. Digging into the confusion matrix showed the model was defaulting to DOWN almost every time and the UP recall was only ~9%.

2. **Class balancing (oversampling).** The label distribution is mildly imbalanced (~53% UP / 47% DOWN), but that alone didn't explain a model that predicted DOWN 90%+ of the time. `scale_pos_weight` was tried first and didn't move the needle enough, so my approach switched to `RandomOverSampler` (imbalanced-learn), duplicating minority-class rows in the *train* split only (never the test split, to avoid leaking duplicated test-like rows into evaluation) until it was 50/50. Model capacity was also reduced (`max_depth=3`, `min_child_weight=5`, fewer estimators) to fight overfitting on the noisier training signal.

3. **Market-context features (VIX + SPY).** Technical indicators derived purely from AAPL's own OHLCV data describe the stock in isolation, but these say nothing about the broader market regime. Two features were added: `vix_close` (CBOE Volatility Index — the market's "fear gauge") and `spy_return` (S&P 500 daily return — broad market direction), both merged onto the AAPL date index and forward-filled. The idea: a stock's next-day move is influenced by whether the whole market is risk-on or risk-off, not just its own recent price action.

4. **Decision threshold tuning.** Even with balanced training data, the default 0.5 classification threshold turned out to be a poor cutoff for this problem. It swept in a train-set threshold search (0.30–0.50 in steps of 0.05, maximizing F1) and applied the winning threshold to test-set predictions. This threshold is persisted to the metrics CSV in S3 and read by `lambda_function.py` at inference time, so the live API and the offline evaluation stay consistent.

**Honest caveat:** even after all four rounds of improvement, technical indicators (even augmented with VIX/SPY context) have a limited ceiling on 2023–2024 AAPL data. That period included unusually concentrated conditions (the AI/mega-cap rally, a fast Fed hiking cycle, and a handful of outsized single-day moves around earnings) that don't resemble the more "normal" price action technical indicators are typically evaluated against. The model's edge over a naive baseline in this window is real but modest, and shouldn't be mistaken for a robust trading signal.

---

## What I Learned

- **A model that "looks" broken (always predicting one class) is usually a class-imbalance or threshold problem before it's an architecture problem.** Reaching for a fancier model before checking the confusion matrix would have wasted time. The fix here was data balancing and threshold calibration, not a different algorithm.
- **`scale_pos_weight` and oversampling are not interchangeable, even though both "address imbalance."** `scale_pos_weight` reweights the loss function but leaves the data untouched, which can be too weak a signal for gradient-boosted trees with shallow depth. Oversampling changes what the trees actually split on. Worth trying both rather than assuming the textbook answer works.
- **The default 0.5 threshold is an assumption, not a law.** It's only optimal when classes are balanced and false positives/negatives are equally costly. Neither is guaranteed to hold, and tuning it on the train set (never the test set) was a cheap, high-leverage fix.
- **A stock's own technical indicators are an incomplete picture.** Two features describing the *entire market's* mood (VIX, SPY) meaningfully diversified the feature set beyond "what has AAPL's price been doing."
- **Time-aware splitting matters even more once you start balancing classes.** It would have been easy to oversample before splitting and leak duplicated rows across train/test. I'd say this is worth double-checking the split boundary every time the pipeline changes.
- **Backtest-period selection matters.** 2023–2024 was an unusually distinctive market regime for AAPL. The results here shouldn't be assumed to generalize to calmer periods or to other tickers without re-validation.

---

## How to Run

### 1. Set up AWS credentials
```bash
aws configure
# Enter your Access Key ID, Secret Access Key, region (e.g. us-west-2)
```

### 2. Create an S3 bucket
```bash
aws s3 mb s3://your-bucket-name
```

### 3. Run the data pipeline
```bash
pip install yfinance xgboost scikit-learn pandas numpy matplotlib seaborn boto3 joblib
python data_pipeline.py --ticker AAPL --bucket your-bucket-name
```

### 4. Train the model
```bash
python train_model.py --ticker AAPL --bucket your-bucket-name
```

### 5. Deploy Lambda + API Gateway
1. Zip `lambda_function.py` with its dependencies (yfinance, xgboost, joblib, boto3)
2. Create a Lambda function (Python 3.12 runtime)
3. Set environment variables: `S3_BUCKET=your-bucket-name`
4. Attach an IAM role with `s3:GetObject` permission on your bucket
5. Create an API Gateway POST route pointing to the Lambda

### 6. Call the live API
```bash
curl -X POST https://<your-api-gateway-url>/prod/predict \
  -H "Content-Type: application/json" \
  -d '{"ticker": "AAPL"}'
```

**Response:**
```json
{
  "ticker": "AAPL",
  "prediction": "UP",
  "confidence": 0.6134,
  "latest_close": 189.42,
  "latest_date": "2025-01-10",
  "model_version": "xgb_v1"
}
```

---

## Project Files

| File | Purpose |
|---|---|
| `data_pipeline.py` | Fetch data, engineer 24 features, upload to S3 |
| `train_model.py` | Time-aware split, XGBoost training, evaluation + plots |
| `lambda_function.py` | Serverless inference handler for API Gateway |
| `README.md` | This file |

---

## Next Steps

- [ ] **Compare XGBoost vs. LSTM** on the same feature set — worth checking whether a sequence model captures temporal patterns (e.g. multi-day momentum regimes) that flattened, per-row technical indicators miss.
- [ ] **Add sentiment features** (news headlines, social media, earnings call tone) — technical + market-context features alone hit a ceiling on 2023–2024 data; sentiment could capture information the price action hasn't priced in yet.
- [ ] Add more tickers (portfolio-level signals)
- [ ] Add EventBridge to retrain the model weekly on fresh data
- [ ] Backtest a simple trading strategy using the model's signals

---

## Tech Stack

**Languages:** Python  
**ML:** XGBoost, scikit-learn  
**Data:** yfinance (Yahoo Finance API), pandas, NumPy  
**Visualisation:** Matplotlib, Seaborn  
**AWS:** S3, IAM, Lambda, API Gateway, CloudWatch  
**Serialisation:** joblib


# CAHOOTS Welfare Check Analysis — Eugene CAD Data 2015–2025

**Author:** Advait Unni | Student ID: 951930906
**Course:** DSCI 410L | University of Oregon | Spring 2026  
**GitHub:** https://github.com/adiunni1/cahoots-welfare-check-analysis  
**Project:** How do welfare check call outcomes differ between EPD and CAHOOTS responses in Eugene?

---

## Overview

This project analyzes eleven years of Eugene 911 Computer-Aided Dispatch (CAD) data to compare how welfare check calls are resolved by the Eugene Police Department (EPD) versus CAHOOTS, Eugene's community-based crisis response program. The analysis covers 93,189 welfare check calls from 2015–2025.

**Key findings:**
- CAHOOTS resolved 48.1% of welfare check calls as "Assisted" vs. 9.2% for EPD
- CAHOOTS made zero arrests across 47,870 welfare check calls
- The chi-square test confirms outcome distributions differ significantly (χ² = 37,531, p < 0.001)

---

## Repository Structure

```
/
├── README.md                             ← This file
├── methods_description.docx              ← Full methods write-up (submitted separately)
├── cahoots_analysis.R                    ← Main cleaning + analysis script (run first)
├── cahoots_visualizations_v2.R           ← Polished visualization script (run second)
├── cahoots_viz_patches.R                 ← Final plot patches (run third)
└── output/                               ← Created automatically by scripts
    ├── wc_clean.csv                      ← Cleaned, analysis-ready dataset
    ├── viz1_outcome_by_agency_final.png  ← Grouped bar chart (final)
    ├── viz2_outcomes_over_time_final.png ← Line chart over time (final)
    └── viz3_volume_by_year_final.png     ← Stacked bar chart of volumes (final)
```

---

## Data

The raw data is **not included** in this repository due to file size. You will need the eleven
Eugene CAD CSV files:

```
EugeneCAD2015noloc.csv
EugeneCAD2016noloc.csv
EugeneCAD2017noloc.csv
EugeneCAD2018noloc.csv
EugeneCAD2019noloc.csv
EugeneCAD2020noloc.csv
EugeneCAD2021noloc.csv
EugeneCAD2022noloc.csv
EugeneCAD2023noloc.csv
EugeneCAD2024noloc.csv
EugeneCAD2025noloc.csv
```

These files were obtained via public records request from the City of Eugene Police Department
and distributed through the DSCI 410L course data repository. The 'noloc' suffix indicates
that precise geographic location fields were removed prior to sharing to protect privacy.

**Note on CAHOOTS identification:** The J-pattern approach used to identify CAHOOTS calls
in `primeunit` (e.g., `_3J79`, `_1J77`) for years prior to 2022 was confirmed as the correct
CAHOOTS unit identifier by the course GE.

---

## Requirements

**R version:** 4.4.2  
**Required packages** (install once before running):

```r
install.packages(c("tidyverse", "scales", "patchwork"))
```

| Package    | Version | Purpose                           |
|------------|---------|-----------------------------------|
| tidyverse  | 2.0.0   | Data cleaning, wrangling, plots   |
| scales     | 1.3.0   | Percent/comma formatting in plots |
| patchwork  | 1.3.0   | Combining plots                   |

---

## How to Run

### Step 1 — Configure the data path

Open `cahoots_analysis.R` and update line 23 to point to the folder containing your 11 CSV files:

```r
DATA_DIR <- "/path/to/your/Eugene_CAD_data_folder"
```

**Example paths:**
```r
# Mac/Linux
DATA_DIR <- "/Users/yourname/Downloads/Eugene_CAD_data_noloc"

# Windows (use forward slashes)
DATA_DIR <- "C:/Users/yourname/Downloads/Eugene_CAD_data_noloc"
```

To verify the path is correct, run this in the R console before proceeding:
```r
list.files("/path/to/your/folder", pattern = "EugeneCAD")
# Should print all 11 filenames
```

### Step 2 — Run the main analysis script

In RStudio, open `cahoots_analysis.R` and click **Source**, or run:

```r
source("cahoots_analysis.R")
```

This script will:
- Load and combine all 11 CSV files (~1.4 million rows)
- Filter for welfare check calls (93,189 rows)
- Identify CAHOOTS via J-pattern in `primeunit` and/or `agency == "CAHE"`
- Convert column types, remove duplicates, flag outliers
- Recode `closed_as` into 8 simplified outcome categories
- Run the chi-square test of independence
- Save `output/wc_clean.csv`
- Save first versions of all three plots to `output/`

**Expected runtime:** ~30–60 seconds depending on your machine.

### Step 3 — Run the visualization script

```r
source("cahoots_visualizations_v2.R")
```

> **Note:** This script uses objects already in your R environment from Step 2.
> Run it in the **same R session** without clearing your workspace.

This produces polished versions of all three plots with white backgrounds,
correct legend labels, and high-contrast color palettes.

### Step 4 — Run the patch script

```r
source("cahoots_viz_patches.R")
```

> **Note:** Also requires the same R session as Steps 2 and 3.

This applies two final fixes:
- Adds an explicit "0%" label to the CAHOOTS Arrest bar in Visualization 1
- Fixes the clipped 2025 annotation in Visualization 3

Saves final versions of Visualizations 1 and 3.

---

## Output Files

| File | Description |
|------|-------------|
| `output/wc_clean.csv` | Cleaned, analysis-ready dataset (93,189 rows × 24 columns) |
| `output/viz1_outcome_by_agency_final.png` | Grouped bar chart: outcome proportions by agency (final) |
| `output/viz2_outcomes_over_time_final.png` | Line chart: outcome proportions over time, faceted by agency (final) |
| `output/viz3_volume_by_year_final.png` | Stacked bar chart: welfare check volumes by year and agency (final) |

---

## Key Analytical Decisions (documented for transparency)

**CAHOOTS identification:**  
The `agency` column only began coding CAHOOTS as `"CAHE"` from 2022 onward. For 2015–2021,
CAHOOTS calls are identified using a regex J-pattern on `primeunit` (e.g., `_3J79`, `_1J77`),
following guidance from the course GE. For 2022–2025, the union of both signals is used
(J-pattern OR `agency == "CAHE"`), since the two coding systems overlapped in transition.

**Outlier threshold for `secs_to_arrv`:**  
Values exceeding 7,200 seconds (2 hours) were set to NA and treated as logging errors,
consistent with stakeholder reports of timestamp recording issues. Affected rows were retained
for outcome analysis; only the timing value was nullified.

**2025 caveat:**  
CAHOOTS was suspended mid-2025. The 2025 CAHOOTS call count (n = 1,126) reflects only a
partial year of operations. All longitudinal visualizations annotate this.

---

## Contact

Adi Unni | aunni | Student ID: 951930906  
DSCI 410L, University of Oregon, Spring 2026  
GitHub: https://github.com/adiunni1/cahoots-welfare-check-analysis
