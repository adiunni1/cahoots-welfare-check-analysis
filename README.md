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
