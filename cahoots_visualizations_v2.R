# =============================================================================
# CAHOOTS Welfare Check — Visualizations v2 (fixed)
# Run this AFTER cahoots_analysis.R has already been run, so that
# outcome_by_agency, outcome_by_agency_year, volume_by_agency_year,
# chi_result, and wc are already in your environment.
#
# Fixes applied vs v1:
#   - bg = "white" added to all ggsave() calls (fixes black background)
#   - Legend labels explicitly set in scale_fill_manual (fixes missing text)
#   - Data labels repositioned to avoid overlap in Viz 1
#   - Viz 3 uses manually chosen high-contrast colors + larger legend
#   - Viz 3 legend moved inside plot area to avoid cutoff
# =============================================================================

library(tidyverse)
library(scales)

OUTPUT_DIR <- "output"
dir.create(OUTPUT_DIR, showWarnings = FALSE)

# Agency counts for subtitles
n_epd     <- format(sum(wc$agency == "EPD"),     big.mark = ",")
n_cahoots <- format(sum(wc$agency == "CAHOOTS"), big.mark = ",")

p_value_label <- "Chi-square test: p < 0.001"

# Agency color scale (reused across all plots)
agency_colors  <- c("CAHOOTS" = "#4dac26", "EPD" = "#2166ac")
agency_labels  <- c("CAHOOTS" = "CAHOOTS", "EPD" = "EPD")

# -----------------------------------------------------------------------------
# VISUALIZATION 1 — Grouped bar chart of outcome proportions by agency
# -----------------------------------------------------------------------------

viz1 <- outcome_by_agency %>%
  ggplot(aes(x = outcome, y = prop, fill = agency)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.68,
           color = "white", linewidth = 0.3) +
  # Labels only on bars taller than 2% to avoid clutter
  geom_text(
    data = . %>% filter(prop >= 0.02),
    aes(label = percent(prop, accuracy = 0.1)),
    position = position_dodge(width = 0.72),
    vjust = -0.45, size = 2.8, fontface = "bold",
    color = "gray20"
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, 0.58),
    expand = c(0, 0)
  ) +
  scale_fill_manual(
    values = agency_colors,
    labels = agency_labels,
    name   = "Responding agency"
  ) +
  scale_x_discrete(labels = function(x) str_wrap(x, width = 11)) +
  annotate(
    "text", x = 7.6, y = 0.555,
    label  = p_value_label,
    hjust  = 1, vjust = 1,
    size   = 3.3, fontface = "italic", color = "gray40"
  ) +
  labs(
    title    = "Welfare check call outcomes by agency, 2015–2025",
    subtitle = sprintf("EPD (n = %s) vs. CAHOOTS (n = %s)", n_epd, n_cahoots),
    x        = NULL,
    y        = "Proportion of welfare check calls",
    caption  = "Source: Eugene CAD Data 2015–2025. CAHOOTS identified via J-pattern in primeunit and/or agency == 'CAHE'."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.background    = element_rect(fill = "white", color = NA),
    panel.background   = element_rect(fill = "white", color = NA),
    plot.title         = element_text(face = "bold", size = 14, color = "gray10"),
    plot.subtitle      = element_text(color = "gray40", size = 10, margin = margin(b = 8)),
    plot.caption       = element_text(color = "gray55", size = 8, hjust = 0, margin = margin(t = 10)),
    plot.margin        = margin(16, 16, 12, 16),
    axis.title.y       = element_text(face = "bold", color = "gray30"),
    axis.text          = element_text(color = "gray30"),
    legend.position    = "top",
    legend.justification = "left",
    legend.title       = element_text(face = "bold", size = 10, color = "gray20"),
    legend.text        = element_text(size = 10, color = "gray20"),
    legend.key.size    = unit(0.5, "cm"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.y = element_line(color = "gray90")
  )

ggsave(file.path(OUTPUT_DIR, "viz1_outcome_by_agency_v2.png"),
       plot = viz1, width = 11, height = 6.5, dpi = 300, bg = "white")
cat("Viz 1 saved.\n")


# -----------------------------------------------------------------------------
# VISUALIZATION 2 — Line chart of outcome proportions over time, faceted
# -----------------------------------------------------------------------------
# 8 high-contrast colors, chosen to be distinguishable on white background

outcome_colors <- c(
  "Assisted"           = "#1b7837",   # dark green
  "Welfare Check Done" = "#4393c3",   # medium blue
  "Unable to Locate"   = "#7b3294",   # purple
  "Gone on Arrival"    = "#e08214",   # amber/orange
  "Referred"           = "#41ab5d",   # light green
  "Arrest"             = "#d6604d",   # red
  "Disregarded"        = "#878787",   # gray
  "Other"              = "#bf812d"    # brown
)

viz2 <- outcome_by_agency_year %>%
  ggplot(aes(x = yr, y = prop, color = outcome, group = outcome)) +
  geom_line(linewidth = 1.0) +
  geom_point(size = 2.2, shape = 21, fill = "white", stroke = 1.2) +
  facet_wrap(~ agency, ncol = 2) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, 0.60),
    expand = c(0.01, 0)
  ) +
  scale_x_continuous(breaks = seq(2015, 2025, by = 2)) +
  scale_color_manual(values = outcome_colors, name = "Outcome") +
  labs(
    title    = "Welfare check outcome proportions over time by agency, 2015–2025",
    subtitle = "Each line = one outcome category; proportions sum to 1 within each agency-year",
    x        = "Year",
    y        = "Proportion of welfare check calls",
    caption  = "Source: Eugene CAD Data 2015–2025."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.background    = element_rect(fill = "white", color = NA),
    panel.background   = element_rect(fill = "white", color = NA),
    plot.title         = element_text(face = "bold", size = 13, color = "gray10"),
    plot.subtitle      = element_text(color = "gray40", size = 10, margin = margin(b = 8)),
    plot.caption       = element_text(color = "gray55", size = 8, hjust = 0, margin = margin(t = 10)),
    plot.margin        = margin(16, 16, 12, 16),
    strip.text         = element_text(face = "bold", size = 12, color = "gray15"),
    strip.background   = element_rect(fill = "gray96", color = NA),
    axis.title         = element_text(face = "bold", color = "gray30"),
    axis.text          = element_text(color = "gray30"),
    axis.text.x        = element_text(angle = 45, hjust = 1),
    legend.position    = "bottom",
    legend.title       = element_text(face = "bold", size = 10, color = "gray20"),
    legend.text        = element_text(size = 9, color = "gray20"),
    legend.key.size    = unit(0.55, "cm"),
    legend.spacing.x   = unit(0.3, "cm"),
    panel.grid.minor   = element_blank(),
    panel.grid.major   = element_line(color = "gray92")
  )

ggsave(file.path(OUTPUT_DIR, "viz2_outcomes_over_time_v2.png"),
       plot = viz2, width = 13, height = 7, dpi = 300, bg = "white")
cat("Viz 2 saved.\n")


# -----------------------------------------------------------------------------
# VISUALIZATION 3 — Stacked bar chart of welfare check volumes by year
# -----------------------------------------------------------------------------

viz3 <- volume_by_agency_year %>%
  ggplot(aes(x = factor(yr), y = n, fill = agency)) +
  geom_col(position = "stack", width = 0.75, color = "white", linewidth = 0.4) +
  geom_text(
    aes(label = format(n, big.mark = ",")),
    position  = position_stack(vjust = 0.5),
    size      = 3.2, color = "white", fontface = "bold"
  ) +
  scale_y_continuous(
    labels = comma_format(),
    limits = c(0, 13500),
    expand = c(0, 0)
  ) +
  scale_fill_manual(
    values = agency_colors,
    labels = agency_labels,
    name   = "Responding agency"
  ) +
  # Annotate 2025 partial year
  annotate(
    "text", x = 11, y = 12800,
    label = "2025: partial year\n(CAHOOTS suspended)", 
    size = 3, color = "gray40", hjust = 0.5, fontface = "italic"
  ) +
  annotate(
    "segment", x = 11, xend = 11, y = 7400, yend = 12400,
    color = "gray60", linewidth = 0.4, linetype = "dashed"
  ) +
  labs(
    title    = "Welfare check call volumes by year and agency, 2015–2025",
    subtitle = "CAHOOTS identified via J-pattern in primeunit and/or agency == 'CAHE'",
    x        = "Year",
    y        = "Number of welfare check calls",
    caption  = "Source: Eugene CAD Data 2015–2025."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.background    = element_rect(fill = "white", color = NA),
    panel.background   = element_rect(fill = "white", color = NA),
    plot.title         = element_text(face = "bold", size = 14, color = "gray10"),
    plot.subtitle      = element_text(color = "gray40", size = 10, margin = margin(b = 8)),
    plot.caption       = element_text(color = "gray55", size = 8, hjust = 0, margin = margin(t = 10)),
    plot.margin        = margin(16, 16, 12, 16),
    axis.title         = element_text(face = "bold", color = "gray30"),
    axis.text          = element_text(color = "gray30"),
    legend.position    = "top",
    legend.justification = "left",
    legend.title       = element_text(face = "bold", size = 10, color = "gray20"),
    legend.text        = element_text(size = 10, color = "gray20"),
    legend.key.size    = unit(0.5, "cm"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.y = element_line(color = "gray90")
  )

ggsave(file.path(OUTPUT_DIR, "viz3_volume_by_year_v2.png"),
       plot = viz3, width = 11, height = 6.5, dpi = 300, bg = "white")
cat("Viz 3 saved.\n")

cat("\nAll v2 visualizations saved to output/ folder!\n")
