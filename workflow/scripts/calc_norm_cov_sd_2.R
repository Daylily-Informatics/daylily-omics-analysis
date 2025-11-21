require(data.table)

args = commandArgs(trailingOnly=TRUE)
in_tsv <- args[1]
sample <- args[2]
chrm <- args[3]
alnr <- args[4]

dcov <- fread(
  in_tsv,
  header = FALSE,
  sep = "\t",
  na.strings = "",
  col.names = c("CHR", "START", "END", "COV"),
  colClasses = c("factor", "integer", "integer", "numeric")
)

# Normalize by median
med_cov <- median(dcov$COV)
dcov[, COVnorm := COV / med_cov]

# Basic stats
meanRCov    <- mean(dcov$COV)
medianRCov  <- med_cov
sdRCov      <- sd(dcov$COV)
RCcoefvar   <- sdRCov / meanRCov

meanNCov    <- mean(dcov$COVnorm)
medianNCov  <- median(dcov$COVnorm)
sdNCov      <- sd(dcov$COVnorm)
NCcoefvar   <- sdNCov / meanNCov

# Percentiles / IQR for normalized coverage
q <- quantile(dcov$COVnorm, probs = c(0.10, 0.25, 0.50, 0.75, 0.90), na.rm = TRUE)
P10   <- q[1]
P25   <- q[2]
P50   <- q[3]
P75   <- q[4]
P90   <- q[5]
IQRcv <- P75 - P25
P90P10ratio <- P90 / max(P10, 1e-6)  # avoid division by zero

# Dropout / low-depth
N <- nrow(dcov)
pct0    <- sum(dcov$COV == 0L)  / N
pctLT5  <- sum(dcov$COV < 5L)   / N
pctLT10 <- sum(dcov$COV < 10L)  / N

# Output
out <- c(
  sample,
  chrm,
  meanRCov,
  medianRCov,
  sdRCov,
  RCcoefvar,
  meanNCov,
  medianNCov,
  sdNCov,
  NCcoefvar,
  P10,
  P25,
  P50,
  P75,
  P90,
  IQRcv,
  P90P10ratio,
  pct0,
  pctLT5,
  pctLT10,
  alnr
)

write.table(
  t(out),
  sep = "\t",
  row.names = FALSE,
  col.names = FALSE,
  quote = FALSE
)
