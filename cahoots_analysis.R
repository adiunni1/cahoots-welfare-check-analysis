# =============================================================================
# CAHOOTS Welfare Check Analysis — Eugene CAD Data, 2015–2025
# Research Question: How do welfare check call outcomes differ between
#                    EPD and CAHOOTS responses in Eugene?
# =============================================================================
# SETUP NOTES:
#   Before running, install required packages if you haven't already:
#   install.packages(c("tidyverse", "scales", "patchwork"))
#
#   Set your working directory to wherever you saved the 11 CAD CSV files,
#   OR update the DATA_DIR path below.
# =============================================================================

library(tidyverse)   # dplyr, readr, stringr, ggplot2, tidyr, purrr
library(scales)      # for percent formatting in plots
library(patchwork)   # for combining plots side-by-side if needed

# -----------------------------------------------------------------------------
# 0. CONFIGURATION
# -----------------------------------------------------------------------------

# !! UPDATE THIS to the folder containing your 11 EugeneCADXXXXnoloc.csv files
DATA_DIR <- "."

# Output folder for saved plots
OUTPUT_DIR <- "output"
dir.create(OUTPUT_DIR, showWarnings = FALSE)


# =============================================================================
# STEP 1: LOAD & COMBINE ALL 11 CSV FILES
# =============================================================================
# NOTE ON SCHEMA DIFFERENCE:
#   2015–2024 files have 19 columns (no 'month' column).
#   2025 file has 20 columns (adds 'month' as the 2nd column).
#   We use read_csv with col_types = cols(.default = "c") to read everything
#   as character first, which safely handles this mismatch. We'll convert
#   types after combining.

cat("Loading all CAD files...\n")

csv_files <- list.files(DATA_DIR, pattern = "EugeneCAD\\d{4}noloc\\.csv", full.names = TRUE)
cat(sprintf("  Found %d files: %s\n", length(csv_files), paste(basename(csv_files), collapse = ", ")))

raw <- map_dfr(csv_files, function(f) {
  read_csv(f, col_types = cols(.default = "c"), show_col_types = FALSE)
})

cat(sprintf("  Total rows loaded: %s\n", format(nrow(raw), big.mark = ",")))
cat(sprintf("  Columns: %s\n", paste(names(raw), collapse = ", ")))


# =============================================================================
# STEP 2: FILTER FOR WELFARE CHECK CALLS
# =============================================================================
# The proposal identifies two relevant nature values:
#   "CHECK WELFARE"          — used across all years
#   "CHECK WELFARE, CAHOOTS" — appears in 2021 onward as an alternate coding
# We trim whitespace from nature before filtering to be safe.

wc_raw <- raw %>%
  mutate(nature = str_trim(nature)) %>%
  filter(nature %in% c("CHECK WELFARE", "CHECK WELFARE, CAHOOTS"))

cat(sprintf("\nStep 2 — Welfare check rows: %s\n", format(nrow(wc_raw), big.mark = ",")))


# =============================================================================
# STEP 3: IDENTIFY CAHOOTS VS EPD
# =============================================================================
# CAHOOTS identification strategy (from proposal + data audit):
#
#   2015–2021: The 'agency' column only records "EPD". CAHOOTS calls are
#              identified by a J-pattern in the 'primeunit' column,
#              e.g. _3J79, _1J77. Regex: "_[0-9]J[0-9]+"
#
#   2022–2025: 'agency' column explicitly codes CAHOOTS as "CAHE".
#              Both the J-pattern AND agency == "CAHE" are present.
#              We use OR logic (union) to catch all CAHOOTS calls.
#
# AUDIT FINDINGS (documented for transparency):
#   2022: J-only=1711, CAHE-only=1157, both=3811
#         (J-pattern catches ~1711 calls not yet coded as CAHE)
#   2023: J-only=0,    CAHE-only=1135, both=4429
#   2024: J-only=1,    CAHE-only=799,  both=4081
#   2025: J-only=0,    CAHE-only=202,  both=924
#
# Decision: Use UNION of J-pattern + agency=="CAHE" as the CAHOOTS indicator.
# This is the most inclusive and conservative approach and is clearly documented.

wc <- wc_raw %>%
  mutate(
    primeunit  = str_trim(primeunit),
    agency_raw = str_trim(agency),
    yr         = as.integer(yr),

    # Two CAHOOTS signals
    is_j_pattern = str_detect(primeunit, "_[0-9]J[0-9]+"),
    is_cahe      = agency_raw == "CAHE",

    # Final agency label: CAHOOTS if either signal is TRUE
    agency = case_when(
      is_j_pattern | is_cahe ~ "CAHOOTS",
      TRUE                   ~ "EPD"
    )
  )

# Summarise agency identification by year
cat("\nStep 3 — Agency identification by year:\n")
wc %>%
  group_by(yr, agency) %>%
  summarise(n = n(), .groups = "drop") %>%
  pivot_wider(names_from = agency, values_from = n, values_fill = 0) %>%
  print(n = Inf)


# =============================================================================
# STEP 4: TYPE CONVERSION & BASIC CLEANING
# =============================================================================

wc <- wc %>%
  mutate(
    calltime      = as.POSIXct(calltime, format = "%Y-%m-%d %H:%M:%S"),

    # Convert timing columns: "NULL" strings → NA, then to numeric
    secs_to_disp  = as.numeric(na_if(secs_to_disp, "NULL")),
    secs_to_arrv  = as.numeric(na_if(secs_to_arrv, "NULL")),
    secs_to_close = as.numeric(na_if(secs_to_close, "NULL")),

    disp          = as.integer(na_if(disp, "NULL")),
    arrv          = as.integer(na_if(arrv, "NULL")),
    units_dispd   = as.integer(na_if(units_dispd, "NULL")),
    units_arrived = as.integer(na_if(units_arrived, "NULL")),

    # Trim text fields
    closed_as     = str_trim(closed_as),
    closecode     = str_trim(closecode),
    nature        = str_trim(nature),
    primeunit     = str_trim(primeunit)
  )

cat("\nStep 4 — Column types after conversion:\n")
glimpse(wc)


# =============================================================================
# STEP 5: REMOVE DUPLICATES
# =============================================================================
# The course GE flagged potential duplicate entries. We identify duplicates
# by inci_id within each year (since inci_id resets annually).
# We keep the first occurrence of each inci_id + yr combination.

n_before <- nrow(wc)
wc <- wc %>%
  distinct(yr, inci_id, .keep_all = TRUE)
n_after <- nrow(wc)

cat(sprintf("\nStep 5 — Duplicates removed: %d (rows before: %s, after: %s)\n",
            n_before - n_after,
            format(n_before, big.mark = ","),
            format(n_after,  big.mark = ",")))


# =============================================================================
# STEP 6: FLAG & REMOVE IMPLAUSIBLE secs_to_arrv OUTLIERS
# =============================================================================
# Stakeholders noted that stop times are sometimes not logged promptly,
# producing implausibly large secs_to_arrv values. We:
#   (a) Document the missingness rate by agency
#   (b) Flag and remove values above a reasonable upper threshold
#       We use 7200 seconds (2 hours) as the cutoff — any arrival time
#       longer than 2 hours is almost certainly a logging error, not a
#       real response time. Adjust this threshold if needed.
#
# NOTE: secs_to_arrv is NOT used in the primary outcome analysis
# (which uses closed_as). It's included for potential supplemental analysis.
# Missingness here does not affect the main research question.

cat("\nStep 6 — secs_to_arrv missingness by agency:\n")
wc %>%
  group_by(agency) %>%
  summarise(
    n          = n(),
    n_missing  = sum(is.na(secs_to_arrv)),
    pct_missing = round(100 * n_missing / n, 1)
  ) %>%
  print()

ARRV_THRESHOLD <- 7200  # 2 hours in seconds

cat(sprintf("  Flagging secs_to_arrv > %d seconds as implausible...\n", ARRV_THRESHOLD))
n_outliers <- sum(!is.na(wc$secs_to_arrv) & wc$secs_to_arrv > ARRV_THRESHOLD)
cat(sprintf("  Outliers flagged: %d\n", n_outliers))

wc <- wc %>%
  mutate(secs_to_arrv = if_else(secs_to_arrv > ARRV_THRESHOLD, NA_real_, secs_to_arrv))

cat("  Outliers set to NA (not removed — row kept for outcome analysis).\n")


# =============================================================================
# STEP 7: RECODE closed_as INTO SIMPLIFIED OUTCOME VARIABLE
# =============================================================================
# Full list of closed_as values and their frequencies across 2015–2025
# (welfare check calls only), from data audit:
#
#  27201  ASSISTED
#  15692  UNABLE TO LOCATE
#   9609  DISREGARD
#   9575  WELFARE CHECK DONE
#   8030  GONE ON ARRIVAL
#   4074  ADVISED
#   3326  PATROL CHECK
#   2322  RESOLVED
#   2157  REPORT TAKEN
#   1987  REFERRED TO OTHER AGENCY
#   1571  INFORMATION ONLY
#   1337  DISREGARDED BY DISPATCH
#    875  ARREST
#    693  TRANSPORT MADE
#    ...and many low-frequency values
#
# Recoding rationale:
#   ASSISTED          → "Assisted"          (person was helped directly)
#   WELFARE CHECK DONE→ "Welfare Check Done" (explicit welfare completion)
#   UNABLE TO LOCATE  → "Unable to Locate"   (subject not found)
#   GONE ON ARRIVAL   → "Gone on Arrival"    (subject left before arrival)
#   ARREST            → "Arrest"             (law enforcement outcome)
#   REFERRED TO OTHER AGENCY → "Referred"    (handoff to another service)
#   TRANSPORT MADE    → "Referred"           (transport = service handoff)
#   NON CRIMINAL HOLD → "Referred"           (psychiatric hold = referral)
#   DISREGARD / DISREGARDED BY DISPATCH /    → "Disregarded"
#     DISREGARDED BY PATROL SUPERVISOR /
#     ACCIDENTALLY CHOSE NEW EVENT /
#     UNABLE TO DISPATCH                     (call cancelled/not actioned)
#   All others        → "Other"

wc <- wc %>%
  mutate(
    outcome = case_when(
      closed_as == "ASSISTED"                          ~ "Assisted",
      closed_as == "WELFARE CHECK DONE"                ~ "Welfare Check Done",
      closed_as == "UNABLE TO LOCATE"                  ~ "Unable to Locate",
      closed_as == "GONE ON ARRIVAL"                   ~ "Gone on Arrival",
      closed_as == "ARREST"                            ~ "Arrest",
      closed_as %in% c(
        "REFERRED TO OTHER AGENCY",
        "TRANSPORT MADE",
        "NON CRIMINAL HOLD",
        "RELAYED TO LANE COUNTY SHERIFFS OFFICE",
        "RELAYED TO UNIVERSITY OF OREGON POLICE",
        "RELAYED TO OREGON STATE POLICE",
        "RELAYED TO JUNCTION CITY DISPATCH",
        "RELAYED TO LINN COUNTY 911",
        "RELAYED TO BENTON COUNTY"
      )                                                ~ "Referred",
      closed_as %in% c(
        "DISREGARD",
        "DISREGARDED BY DISPATCH",
        "DISREGARDED BY PATROL SUPERVISOR",
        "ACCIDENTALLY CHOSE NEW EVENT",
        "UNABLE TO DISPATCH",
        "CANCEL WHILE ENROUTE"
      )                                                ~ "Disregarded",
      is.na(closed_as) | closed_as == "NULL"           ~ NA_character_,
      TRUE                                             ~ "Other"
    ),
    # Set factor order for plots (most meaningful first)
    outcome = factor(outcome, levels = c(
      "Assisted", "Welfare Check Done", "Unable to Locate",
      "Gone on Arrival", "Referred", "Arrest", "Disregarded", "Other"
    ))
  )

cat("\nStep 7 — Outcome distribution:\n")
wc %>%
  count(outcome, sort = TRUE) %>%
  mutate(pct = round(100 * n / sum(n), 1)) %>%
  print(n = Inf)

# Drop rows with NA outcome (26 "NULL" closed_as entries across all years)
n_na_outcome <- sum(is.na(wc$outcome))
cat(sprintf("\n  Rows with NA outcome dropped: %d\n", n_na_outcome))
wc <- wc %>% filter(!is.na(outcome))


# =============================================================================
# STEP 8: FINAL DATASET SUMMARY
# =============================================================================

cat("\n=== FINAL CLEANED DATASET SUMMARY ===\n")
cat(sprintf("  Total welfare check rows: %s\n", format(nrow(wc), big.mark = ",")))
cat(sprintf("  Years covered: %s\n", paste(sort(unique(wc$yr)), collapse = ", ")))
cat(sprintf("  EPD calls:     %s\n", format(sum(wc$agency == "EPD"),     big.mark = ",")))
cat(sprintf("  CAHOOTS calls: %s\n", format(sum(wc$agency == "CAHOOTS"), big.mark = ",")))

cat("\n  Missing values check:\n")
wc %>%
  select(yr, agency, nature, calltime, closed_as, outcome,
         secs_to_arrv, secs_to_close) %>%
  summarise(across(everything(), ~ sum(is.na(.)))) %>%
  pivot_longer(everything(), names_to = "column", values_to = "n_missing") %>%
  mutate(pct_missing = round(100 * n_missing / nrow(wc), 2)) %>%
  print()

cat("\n  .describe() equivalent (secs_to_arrv, secs_to_close):\n")
wc %>%
  select(secs_to_arrv, secs_to_close) %>%
  summary() %>%
  print()

# Save the cleaned dataset for use in visualization scripts
write_csv(wc, file.path(OUTPUT_DIR, "wc_clean.csv"))
cat(sprintf("\n  Cleaned data saved to: %s/wc_clean.csv\n", OUTPUT_DIR))


# =============================================================================
# STEP 9: OUTCOME PROPORTIONS BY AGENCY (for chi-square + Viz 1)
# =============================================================================

outcome_by_agency <- wc %>%
  group_by(agency, outcome) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(agency) %>%
  mutate(
    total = sum(n),
    prop  = n / total
  ) %>%
  ungroup()

cat("\nStep 9 — Outcome proportions by agency:\n")
outcome_by_agency %>%
  select(agency, outcome, n, prop) %>%
  mutate(prop = round(prop, 4)) %>%
  print(n = Inf)


# =============================================================================
# STEP 10: CHI-SQUARE TEST OF INDEPENDENCE
# =============================================================================
# Tests whether outcome distribution differs significantly between EPD and CAHOOTS.
# H0: Outcome distribution is the same for EPD and CAHOOTS.
# H1: Outcome distribution differs between agencies.
# Assumption: Expected cell counts >= 5 (we'll verify below).

contingency_table <- wc %>%
  count(agency, outcome) %>%
  pivot_wider(names_from = outcome, values_from = n, values_fill = 0) %>%
  column_to_rownames("agency") %>%
  as.matrix()

cat("\nStep 10 — Contingency table (raw counts):\n")
print(contingency_table)

# Verify expected counts assumption
expected <- chisq.test(contingency_table)$expected
cat("\n  Expected cell counts (all should be >= 5):\n")
print(round(expected, 1))
cat(sprintf("  Any expected count < 5? %s\n", any(expected < 5)))

# Run the test
chi_result <- chisq.test(contingency_table)
cat("\n  --- Chi-Square Test Results ---\n")
cat(sprintf("  Chi-square statistic: %.2f\n", chi_result$statistic))
cat(sprintf("  Degrees of freedom:   %d\n",   chi_result$parameter))
cat(sprintf("  p-value:              %s\n",
            ifelse(chi_result$p.value < 0.001, "< 0.001", round(chi_result$p.value, 4))))

# Plain-language interpretation
cat("\n  Plain-language interpretation:\n")
if (chi_result$p.value < 0.05) {
  cat("  The chi-square test is statistically significant (p < 0.05), meaning\n")
  cat("  the distribution of welfare check outcomes differs significantly between\n")
  cat("  EPD and CAHOOTS. This is unlikely to be due to chance alone.\n")
} else {
  cat("  The chi-square test is not statistically significant (p >= 0.05),\n")
  cat("  meaning we cannot conclude that outcome distributions differ between\n")
  cat("  EPD and CAHOOTS based on this data.\n")
}


# =============================================================================
# STEP 11: OUTCOME PROPORTIONS BY AGENCY & YEAR (for Viz 2 — time series)
# =============================================================================

outcome_by_agency_year <- wc %>%
  group_by(yr, agency, outcome) %>%
  summarise(n = n(), .groups = "drop") %>%
  group_by(yr, agency) %>%
  mutate(
    total = sum(n),
    prop  = n / total
  ) %>%
  ungroup()

cat("\nStep 11 — Outcome proportions by agency & year (first 20 rows):\n")
print(head(outcome_by_agency_year, 20))


# =============================================================================
# STEP 12: WELFARE CHECK VOLUMES BY YEAR & AGENCY (for Viz 3 — stacked bar)
# =============================================================================

volume_by_agency_year <- wc %>%
  group_by(yr, agency) %>%
  summarise(n = n(), .groups = "drop")

cat("\nStep 12 — Welfare check volumes by year and agency:\n")
print(volume_by_agency_year, n = Inf)


# =============================================================================
# STEP 13: VISUALIZATION 1 — Grouped Bar Chart of Outcome Proportions by Agency
# =============================================================================
# Overall proportions, EPD vs CAHOOTS, annotated with chi-square result.

p_value_label <- ifelse(
  chi_result$p.value < 0.001,
  "Chi-square test: p < 0.001",
  sprintf("Chi-square test: p = %.3f", chi_result$p.value)
)

viz1 <- outcome_by_agency %>%
  ggplot(aes(x = outcome, y = prop, fill = agency)) +
  geom_col(position = "dodge", width = 0.7, color = "white", linewidth = 0.3) +
  geom_text(
    aes(label = percent(prop, accuracy = 0.1)),
    position = position_dodge(width = 0.7),
    vjust = -0.4, size = 3, fontface = "bold"
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, max(outcome_by_agency$prop) * 1.2),
    expand = c(0, 0)
  ) +
  scale_fill_manual(
    values = c("EPD" = "#2166ac", "CAHOOTS" = "#4dac26"),
    name   = "Responding Agency"
  ) +
  scale_x_discrete(labels = function(x) str_wrap(x, width = 12)) +
  annotate(
    "text", x = Inf, y = Inf,
    label  = p_value_label,
    hjust  = 1.05, vjust = 1.5,
    size   = 3.5, fontface = "italic", color = "gray30"
  ) +
  labs(
    title    = "Welfare Check Call Outcomes by Agency, 2015–2025",
    subtitle = sprintf("EPD (n = %s) vs. CAHOOTS (n = %s), J-pattern + agency identification",
                       format(sum(wc$agency == "EPD"),     big.mark = ","),
                       format(sum(wc$agency == "CAHOOTS"), big.mark = ",")),
    x        = "Outcome",
    y        = "Proportion of Welfare Check Calls",
    caption  = "Source: Eugene CAD Data 2015–2025. CAHOOTS identified via J-pattern in primeunit and/or agency == 'CAHE'."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 14),
    plot.subtitle    = element_text(color = "gray40", size = 10),
    plot.caption     = element_text(color = "gray50", size = 8, hjust = 0),
    axis.title       = element_text(face = "bold"),
    legend.position  = "top",
    legend.title     = element_text(face = "bold"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank()
  )

ggsave(file.path(OUTPUT_DIR, "viz1_outcome_by_agency.png"),
       plot = viz1, width = 10, height = 6, dpi = 300)
cat("\nVisualization 1 saved: output/viz1_outcome_by_agency.png\n")


# =============================================================================
# STEP 14: VISUALIZATION 2 — Line Chart of Outcome Proportions Over Time
# =============================================================================
# Faceted by agency, one line per outcome category.

viz2 <- outcome_by_agency_year %>%
  ggplot(aes(x = yr, y = prop, color = outcome, group = outcome)) +
  geom_line(linewidth = 0.9) +
  geom_point(size = 2) +
  facet_wrap(~ agency, ncol = 2, labeller = labeller(agency = c(
    "EPD"     = "EPD",
    "CAHOOTS" = "CAHOOTS"
  ))) +
  scale_y_continuous(labels = percent_format(accuracy = 1), expand = c(0.01, 0.01)) +
  scale_x_continuous(breaks = 2015:2025) +
  scale_color_brewer(palette = "Dark2", name = "Outcome") +
  labs(
    title    = "Welfare Check Outcome Proportions Over Time by Agency, 2015–2025",
    subtitle = "Each line represents one outcome category; proportions sum to 1 within each agency-year",
    x        = "Year",
    y        = "Proportion of Welfare Check Calls",
    caption  = "Source: Eugene CAD Data 2015–2025."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 13),
    plot.subtitle    = element_text(color = "gray40", size = 10),
    plot.caption     = element_text(color = "gray50", size = 8, hjust = 0),
    axis.title       = element_text(face = "bold"),
    axis.text.x      = element_text(angle = 45, hjust = 1),
    strip.text       = element_text(face = "bold", size = 12),
    legend.position  = "bottom",
    legend.title     = element_text(face = "bold"),
    panel.grid.minor = element_blank()
  )

ggsave(file.path(OUTPUT_DIR, "viz2_outcomes_over_time.png"),
       plot = viz2, width = 12, height = 6, dpi = 300)
cat("Visualization 2 saved: output/viz2_outcomes_over_time.png\n")


# =============================================================================
# STEP 15: VISUALIZATION 3 — Stacked Bar Chart of Welfare Check Volumes
# =============================================================================
# Call volumes by year, stacked by agency.

viz3 <- volume_by_agency_year %>%
  ggplot(aes(x = factor(yr), y = n, fill = agency)) +
  geom_col(position = "stack", width = 0.75, color = "white", linewidth = 0.3) +
  geom_text(
    aes(label = format(n, big.mark = ",")),
    position = position_stack(vjust = 0.5),
    size = 3, color = "white", fontface = "bold"
  ) +
  scale_y_continuous(labels = comma_format(), expand = c(0, 0)) +
  scale_fill_manual(
    values = c("EPD" = "#2166ac", "CAHOOTS" = "#4dac26"),
    name   = "Responding Agency"
  ) +
  labs(
    title    = "Welfare Check Call Volumes by Year and Agency, 2015–2025",
    subtitle = "CAHOOTS identified via J-pattern in primeunit and/or agency == 'CAHE'",
    x        = "Year",
    y        = "Number of Welfare Check Calls",
    caption  = "Source: Eugene CAD Data 2015–2025."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title       = element_text(face = "bold", size = 14),
    plot.subtitle    = element_text(color = "gray40", size = 10),
    plot.caption     = element_text(color = "gray50", size = 8, hjust = 0),
    axis.title       = element_text(face = "bold"),
    legend.position  = "top",
    legend.title     = element_text(face = "bold"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank()
  )

ggsave(file.path(OUTPUT_DIR, "viz3_volume_by_year.png"),
       plot = viz3, width = 10, height = 6, dpi = 300)
cat("Visualization 3 saved: output/viz3_volume_by_year.png\n")


# =============================================================================
# DONE
# =============================================================================
cat("\n=== Analysis complete! ===\n")
cat("Output files in ./output/:\n")
cat("  wc_clean.csv                  — cleaned analysis-ready dataset\n")
cat("  viz1_outcome_by_agency.png    — grouped bar chart (Visualization 1)\n")
cat("  viz2_outcomes_over_time.png   — line chart over time (Visualization 2)\n")
cat("  viz3_volume_by_year.png       — stacked bar chart of volumes (Visualization 3)\n")
