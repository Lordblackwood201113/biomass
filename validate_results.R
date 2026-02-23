# validate_results.R - STORY-012: Scientific validation
# Compares API results with direct BIOMASS package calculations
# Usage: Rscript validate_results.R [BASE_URL]

library(BIOMASS)
library(jsonlite)
library(httr)

base_url <- commandArgs(trailingOnly = TRUE)[1]
if (is.na(base_url)) base_url <- "http://localhost:8000"
endpoint <- paste0(base_url, "/compute-biomass")

cat("==============================================\n")
cat("  BIOMASS API - Scientific Validation\n")
cat(sprintf("  Endpoint: %s\n", endpoint))
cat("==============================================\n\n")

# --- Test data: 5 well-known tropical species ---
test_trees <- data.frame(
  longitude = c(-52.68, -52.68, -52.68, -53.20, -53.20),
  latitude  = c(4.08, 4.08, 4.08, 3.95, 3.95),
  diameter  = c(46.2, 31.0, 22.5, 55.0, 40.1),
  height    = c(25.5, 22.0, 18.0, 30.0, 24.0),
  speciesName = c(
    "Symphonia globulifera",
    "Dicorynia guianensis",
    "Eperua falcata",
    "Vouacapoua americana",
    "Goupia glabra"
  ),
  stringsAsFactors = FALSE
)

cat("Test data:\n")
print(test_trees)
cat("\n")

# --- Step 1: Compute expected results directly with BIOMASS ---
cat("--- Computing expected results with BIOMASS package ---\n\n")

# Parse species
genus   <- vapply(strsplit(test_trees$speciesName, "\\s+"), `[`, character(1), 1)
species <- vapply(strsplit(test_trees$speciesName, "\\s+"), `[`, character(1), 2)

# Wood density
wd_result <- getWoodDensity(genus = genus, species = species)
expected_wd <- wd_result$meanWD
cat("Expected Wood Density (WD):\n")
print(data.frame(species = test_trees$speciesName, WD = expected_wd))
cat("\n")

# AGB with height
expected_agb <- computeAGB(
  D  = test_trees$diameter,
  WD = expected_wd,
  H  = test_trees$height
)
cat("Expected AGB (kg):\n")
print(data.frame(species = test_trees$speciesName, AGB_kg = expected_agb))
cat("\n")

# --- Step 2: Call the API ---
cat("--- Calling API ---\n\n")

payload <- list(trees = lapply(seq_len(nrow(test_trees)), function(i) {
  list(
    longitude   = test_trees$longitude[i],
    latitude    = test_trees$latitude[i],
    diameter    = test_trees$diameter[i],
    height      = test_trees$height[i],
    speciesName = test_trees$speciesName[i]
  )
}))

response <- tryCatch({
  POST(
    endpoint,
    body = toJSON(payload, auto_unbox = TRUE),
    content_type_json(),
    encode = "raw"
  )
}, error = function(e) {
  cat(sprintf("ERROR: Could not reach API at %s\n", endpoint))
  cat(sprintf("Details: %s\n", e$message))
  cat("\nMake sure the API is running: Rscript run_api.R\n")
  quit(status = 1)
})

if (status_code(response) != 200) {
  cat(sprintf("ERROR: API returned HTTP %d\n", status_code(response)))
  cat(content(response, as = "text"), "\n")
  quit(status = 1)
}

api_result <- fromJSON(content(response, as = "text"))
cat("API response received.\n\n")

# --- Step 3: Compare results ---
cat("--- Comparing Results ---\n\n")

api_wd  <- api_result$results$wood_density
api_agb <- api_result$results$AGB_kg

pass <- 0
fail <- 0

check <- function(name, expected, actual, tol = 1e-4) {
  if (is.na(expected) && is.na(actual)) {
    cat(sprintf("  PASS: %s (both NA)\n", name))
    pass <<- pass + 1
    return(TRUE)
  }
  if (is.na(expected) || is.na(actual)) {
    cat(sprintf("  FAIL: %s (expected=%s, actual=%s)\n", name,
                as.character(expected), as.character(actual)))
    fail <<- fail + 1
    return(FALSE)
  }
  if (abs(expected - actual) <= tol * max(1, abs(expected))) {
    cat(sprintf("  PASS: %s (expected=%.4f, actual=%.4f, diff=%.6f)\n",
                name, expected, actual, abs(expected - actual)))
    pass <<- pass + 1
    return(TRUE)
  } else {
    cat(sprintf("  FAIL: %s (expected=%.4f, actual=%.4f, diff=%.6f)\n",
                name, expected, actual, abs(expected - actual)))
    fail <<- fail + 1
    return(FALSE)
  }
}

for (i in seq_len(nrow(test_trees))) {
  cat(sprintf("\nTree %d: %s (D=%.1f, H=%.1f)\n",
              i, test_trees$speciesName[i],
              test_trees$diameter[i], test_trees$height[i]))

  check(
    sprintf("WD[%d]", i),
    expected_wd[i],
    api_wd[i]
  )
  check(
    sprintf("AGB[%d]", i),
    expected_agb[i],
    api_agb[i]
  )
}

# Summary comparison
cat("\n--- Summary ---\n")
expected_total <- sum(expected_agb, na.rm = TRUE)
api_total <- api_result$summary$total_AGB_kg
check("total_AGB_kg", expected_total, api_total)

cat(sprintf("\n==============================================\n"))
cat(sprintf("  RESULTS: %d passed, %d failed\n", pass, fail))
cat(sprintf("==============================================\n"))

if (fail > 0) {
  quit(status = 1)
} else {
  cat("\nScientific validation PASSED: API results match direct BIOMASS calculations.\n")
  quit(status = 0)
}
