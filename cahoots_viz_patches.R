# =============================================================================
# CAHOOTS — Patch fixes (run after cahoots_analysis.R + cahoots_visualizations_v2.R)
# Fixes:
#   Viz 1: Add a "0%" label for CAHOOTS Arrest bar so it's clear it's not missing
#   Viz 3: Fix clipped annotation text (shorten + move inward)
# =============================================================================

library(tidyverse)
library(scales)

OUTPUT_DIR <- "output"

agency_colors <- c("CAHOOTS" = "#4dac26", "EPD" = "#2166ac")
agency_labels <- c("CAHOOTS" = "CAHOOTS", "EPD" = "EPD")
n_epd     <- format(sum(wc$agency == "EPD"),     big.mark = ",")
n_cahoots <- format(sum(wc$agency == "CAHOOTS"), big.mark = ",")

# -----------------------------------------------------------------------------
# VIZ 1 PATCH — Add explicit "0%" label on CAHOOTS Arrest bar
# -----------------------------------------------------------------------------

viz1_patched <- outcome_by_agency %>%
  ggplot(aes(x = outcome, y = prop, fill = agency)) +
  geom_col(position = position_dodge(width = 0.72), width = 0.68,
           color = "white", linewidth = 0.3) +
  # Labels on bars >= 2%
  geom_text(
    data = . %>% filter(prop >= 0.02),
    aes(label = percent(prop, accuracy = 0.1)),
    position = position_dodge(width = 0.72),
    vjust = -0.45, size = 2.8, fontface = "bold", color = "gray20"
  ) +
  # Explicit "0%" label for CAHOOTS Arrest (no bar to sit on, so place at y=0.005)
  annotate(
    "text", x = 6.77, y = 0.013,
    label = "0%", size = 2.8, fontface = "bold", color = "#4dac26"
  ) +
  scale_y_continuous(
    labels = percent_format(accuracy = 1),
    limits = c(0, 0.58), expand = c(0, 0)
  ) +
  scale_fill_manual(values = agency_colors, labels = agency_labels,
                    name = "Responding agency") +
  scale_x_discrete(labels = function(x) str_wrap(x, width = 11)) +
  annotate("text", x = 7.6, y = 0.555,
           label = "Chi-square test: p < 0.001",
           hjust = 1, size = 3.3, fontface = "italic", color = "gray40") +
  labs(
    title    = "Welfare check call outcomes by agency, 2015–2025",
    subtitle = sprintf("EPD (n = %s) vs. CAHOOTS (n = %s)", n_epd, n_cahoots),
    x = NULL, y = "Proportion of welfare check calls",
    caption  = "Source: Eugene CAD Data 2015–2025. CAHOOTS identified via J-pattern in primeunit and/or agency == 'CAHE'.\nNote: CAHOOTS made zero arrests across 47,870 welfare check calls."
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
    legend.position    = "top", legend.justification = "left",
    legend.title       = element_text(face = "bold", size = 10, color = "gray20"),
    legend.text        = element_text(size = 10, color = "gray20"),
    legend.key.size    = unit(0.5, "cm"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.y = element_line(color = "gray90")
  )

ggsave(file.path(OUTPUT_DIR, "viz1_outcome_by_agency_final.png"),
       plot = viz1_patched, width = 11, height = 6.5, dpi = 300, bg = "white")
cat("Viz 1 final saved.\n")


# -----------------------------------------------------------------------------
# VIZ 3 PATCH — Fix clipped annotation
# -----------------------------------------------------------------------------

viz3_patched <- volume_by_agency_year %>%
  ggplot(aes(x = factor(yr), y = n, fill = agency)) +
  geom_col(position = "stack", width = 0.75, color = "white", linewidth = 0.4) +
  geom_text(
    aes(label = format(n, big.mark = ",")),
    position = position_stack(vjust = 0.5),
    size = 3.2, color = "white", fontface = "bold"
  ) +
  scale_y_continuous(
    labels = comma_format(), limits = c(0, 13500), expand = c(0, 0)
  ) +
  scale_fill_manual(values = agency_colors, labels = agency_labels,
                    name = "Responding agency") +
  # Fixed annotation: shorter text, positioned clearly above the 2025 bar
  annotate("text", x = 10.6, y = 12600,
           label = "2025: partial year\n(CAHOOTS suspended)",
           size = 2.9, color = "gray40", hjust = 0.5, fontface = "italic") +
  annotate("segment", x = 11, xend = 11, y = 7400, yend = 12000,
           color = "gray60", linewidth = 0.4, linetype = "dashed") +
  labs(
    title    = "Welfare check call volumes by year and agency, 2015–2025",
    subtitle = "CAHOOTS identified via J-pattern in primeunit and/or agency == 'CAHE'",
    x = "Year", y = "Number of welfare check calls",
    caption  = "Source: Eugene CAD Data 2015–2025."
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.background    = element_rect(fill = "white", color = NA),
    panel.background   = element_rect(fill = "white", color = NA),
    plot.title         = element_text(face = "bold", size = 14, color = "gray10"),
    plot.subtitle      = element_text(color = "gray40", size = 10, margin = margin(b = 8)),
    plot.caption       = element_text(color = "gray55", size = 8, hjust = 0, margin = margin(t = 10)),
    plot.margin        = margin(16, 20, 12, 16),
    axis.title         = element_text(face = "bold", color = "gray30"),
    axis.text          = element_text(color = "gray30"),
    legend.position    = "top", legend.justification = "left",
    legend.title       = element_text(face = "bold", size = 10, color = "gray20"),
    legend.text        = element_text(size = 10, color = "gray20"),
    legend.key.size    = unit(0.5, "cm"),
    panel.grid.major.x = element_blank(),
    panel.grid.minor   = element_blank(),
    panel.grid.major.y = element_line(color = "gray90")
  )

ggsave(file.path(OUTPUT_DIR, "viz3_volume_by_year_final.png"),
       plot = viz3_patched, width = 11, height = 6.5, dpi = 300, bg = "white")
cat("Viz 3 final saved.\n")
cat("\nDone! Check output/ for viz1_outcome_by_agency_final.png and viz3_volume_by_year_final.png\n")
