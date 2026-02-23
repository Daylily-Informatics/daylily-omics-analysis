library(dplyr)
library(ggplot2)
library(grid)

exclude_classes <- c("All","INS_gt50","DEL_gt50","Indel_gt50","Indel_50")

df_slice <- d %>%
  filter(
    SNVCaller == "gatk",
    ROI == "giabHC",
    PrimaryCoverageBin == 35,
    !VariantClass %in% exclude_classes,
    !is.na(Precision),
    !is.na(Sensitivity.Recall),
    !is.na(Fscore)
  ) %>%
  mutate(Fscore_lbl = sprintf("%.3f", Fscore))

# ---- Legend labels: append per-class Fscore ----
fscore_map <- df_slice %>%
  group_by(VariantClass) %>%
  summarize(Fscore_legend = median(Fscore, na.rm = TRUE), .groups = "drop")

legend_labels <- setNames(
  paste0(fscore_map$VariantClass, "  F=", sprintf("%.3f", fscore_map$Fscore_legend)),
  fscore_map$VariantClass
)

details_txt <- paste(
  "Genome build: hg38",
  "Sample: HG003",
  "Platform: Illumina NovaSeq",
  "Reads: 2×150",
  "GATK analysis (Sentieon-tuned)",
  "BQSR + VQSR",
  "ROI: GIAB high-confidence regions",
  sep = "\n"
)

xlim <- c(0.99, 1.00)
ylim <- c(0.99, 1.00)

ggplot(df_slice, aes(
  x = Sensitivity.Recall,
  y = Precision,
  color = VariantClass,
  shape = VariantClass
)) +
  geom_point(size = 3) +

  geom_text(
    aes(label = Fscore_lbl),
    nudge_x = 0.00025,
    nudge_y = 0.00025,
    size = 3,
    show.legend = FALSE
  ) +

  annotate(
    "label",
    x = xlim[2] - 0.00005,
    y = ylim[1] + 0.00005,
    label = details_txt,
    hjust = 1,
    vjust = 0,
    size = 3.5,
    linewidth = 0,
    label.padding = unit(4, "pt"),
    label.r = unit(0, "lines"),
    fill = "grey20",
    alpha = 0.12
  ) +

  scale_x_continuous(
    breaks = seq(0.99, 1.00, 0.002),
    labels = function(x) sprintf("%.3f", x)
  ) +

  scale_y_continuous(
    breaks = seq(0.99, 1.00, 0.002),
    labels = function(x) sprintf("%.3f", x)
  ) +

  scale_color_discrete(labels = legend_labels) +
  scale_shape_discrete(labels = legend_labels) +

  coord_fixed(
    ratio = 1,
    xlim = xlim,
    ylim = ylim,
    expand = FALSE
  ) +

  labs(
    x = "Recall",
    y = "Precision",
    title = "The Human 30× Genome",
    color = "Variant Class",
    shape = "Variant Class"
  ) +

  theme_bw(base_size = 14) +
  theme(
    plot.title = element_text(hjust = 0.5)
  )