# api.R - BIOMASS API
# Calcul de biomasse forestière via le package BIOMASS
# Exposed via plumber REST API

library(plumber)
library(jsonlite)
library(BIOMASS)

#* @apiTitle BIOMASS Forest Biomass API
#* @apiDescription API REST pour le calcul de la biomasse aérienne (AGB) à partir d'inventaires forestiers

#* Compute above-ground biomass for a tree inventory
#* @param req The incoming request object
#* @param res The response object
#* @post /compute-biomass
#* @serializer unboxedJSON
function(req, res) {

  start_time <- proc.time()

  # --- Global error handler ---
  tryCatch({

    # --- 1. Parse input JSON ---
    body <- req$body

    if (is.null(body) || is.null(body$trees)) {
      res$status <- 400L
      return(list(
        error = TRUE,
        message = "Invalid payload: 'trees' must be a non-empty array",
        details = NULL
      ))
    }

    trees <- body$trees

    # Handle both list-of-objects and data.frame formats
    if (is.data.frame(trees)) {
      df <- trees
    } else if (is.list(trees)) {
      # Replace NULL values with NA before converting to data.frame
      df <- tryCatch({
        trees_clean <- lapply(trees, function(tree) {
          lapply(tree, function(val) {
            if (is.null(val) || length(val) == 0) NA else val
          })
        })
        as.data.frame(do.call(rbind, lapply(trees_clean, as.data.frame, stringsAsFactors = FALSE)))
      }, error = function(e) NULL)
    } else {
      df <- NULL
    }

    if (is.null(df) || nrow(df) == 0) {
      res$status <- 400L
      return(list(
        error = TRUE,
        message = "Invalid payload: 'trees' must be a non-empty array of tree objects",
        details = NULL
      ))
    }

    n_trees <- nrow(df)
    message(sprintf("[%s] Received request: %d trees", Sys.time(), n_trees))

    # --- 2. Validate required fields ---
    required_fields <- c("longitude", "latitude", "diameter", "speciesName")
    missing_fields <- setdiff(required_fields, names(df))
    if (length(missing_fields) > 0) {
      res$status <- 400L
      return(list(
        error = TRUE,
        message = paste("Missing required fields:", paste(missing_fields, collapse = ", ")),
        details = NULL
      ))
    }

    # Ensure height column exists (optional field)
    if (!"height" %in% names(df)) {
      df$height <- NA_real_
    }

    # Rebuild df as a clean data.frame with proper types
    # (plumber may parse NULL as list(), causing list-columns)
    safe_numeric <- function(val) {
      if (is.null(val) || length(val) == 0 || is.list(val)) return(NA_real_)
      suppressWarnings(as.numeric(val))
    }
    safe_character <- function(val) {
      if (is.null(val) || length(val) == 0 || is.list(val)) return(NA_character_)
      as.character(val)
    }

    df <- data.frame(
      longitude   = vapply(seq_len(n_trees), function(i) safe_numeric(df$longitude[[i]]), numeric(1)),
      latitude    = vapply(seq_len(n_trees), function(i) safe_numeric(df$latitude[[i]]), numeric(1)),
      diameter    = vapply(seq_len(n_trees), function(i) safe_numeric(df$diameter[[i]]), numeric(1)),
      height      = vapply(seq_len(n_trees), function(i) safe_numeric(df$height[[i]]), numeric(1)),
      speciesName = vapply(seq_len(n_trees), function(i) safe_character(df$speciesName[[i]]), character(1)),
      stringsAsFactors = FALSE
    )

    # Initialize per-tree warnings
    tree_warnings <- vector("list", n_trees)
    for (i in seq_len(n_trees)) tree_warnings[[i]] <- character(0)

    # Validate ranges
    for (i in seq_len(n_trees)) {
      if (!is.na(df$longitude[i]) && (df$longitude[i] < -180 || df$longitude[i] > 180)) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "longitude out of range [-180, +180]")
      }
      if (!is.na(df$latitude[i]) && (df$latitude[i] < -90 || df$latitude[i] > 90)) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "latitude out of range [-90, +90]")
      }
      if (!is.na(df$diameter[i]) && df$diameter[i] <= 0) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "diameter must be > 0")
      }
      if (!is.na(df$height[i]) && df$height[i] <= 0) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "height must be > 0")
      }
    }

    # --- 3. Parse speciesName into genus and species ---
    split_names <- strsplit(trimws(df$speciesName), "\\s+")
    df$genus   <- vapply(split_names, function(x) if (length(x) >= 1 && nchar(x[1]) > 0) x[1] else NA_character_, character(1))
    df$species <- vapply(split_names, function(x) if (length(x) >= 2) x[2] else NA_character_, character(1))

    for (i in seq_len(n_trees)) {
      if (is.na(df$genus[i])) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "speciesName is empty or NA, genus/species could not be parsed")
      }
    }

    # --- 4. Estimate wood density (WD) ---
    wd_result <- tryCatch({
      captured_warnings <- character(0)
      result <- withCallingHandlers(
        getWoodDensity(genus = df$genus, species = df$species),
        warning = function(w) {
          captured_warnings <<- c(captured_warnings, conditionMessage(w))
          invokeRestart("muffleWarning")
        }
      )
      list(data = result, warnings = captured_warnings)
    }, error = function(e) {
      list(data = NULL, warnings = paste("getWoodDensity error:", e$message))
    })

    if (!is.null(wd_result$data)) {
      df$wood_density <- wd_result$data$meanWD
    } else {
      df$wood_density <- NA_real_
      for (i in seq_len(n_trees)) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "wood density estimation failed")
      }
    }

    # Add WD warnings for trees with NA wood density
    for (i in seq_len(n_trees)) {
      if (is.na(df$wood_density[i]) && !is.na(df$genus[i])) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "species not found in wood density database, WD=NA")
      }
    }

    # --- 5. Compute environmental parameter E ---
    # Deduplicate coordinates for efficiency
    coord_df <- data.frame(longitude = df$longitude, latitude = df$latitude)
    unique_coords <- unique(coord_df[complete.cases(coord_df), ])

    df$E <- NA_real_

    if (nrow(unique_coords) > 0) {
      e_result <- tryCatch({
        captured_warnings <- character(0)
        result <- withCallingHandlers(
          computeE(unique_coords),
          warning = function(w) {
            captured_warnings <<- c(captured_warnings, conditionMessage(w))
            invokeRestart("muffleWarning")
          }
        )
        list(data = result, warnings = captured_warnings)
      }, error = function(e) {
        list(data = NULL, warnings = paste("computeE error:", e$message))
      })

      if (!is.null(e_result$data)) {
        # Map E values back to all trees
        unique_coords$E <- e_result$data
        for (i in seq_len(n_trees)) {
          if (!is.na(df$longitude[i]) && !is.na(df$latitude[i])) {
            match_idx <- which(unique_coords$longitude == df$longitude[i] &
                               unique_coords$latitude == df$latitude[i])
            if (length(match_idx) > 0) {
              df$E[i] <- unique_coords$E[match_idx[1]]
            }
          }
        }
      } else {
        for (i in seq_len(n_trees)) {
          tree_warnings[[i]] <- c(tree_warnings[[i]], "computeE failed, E=NA")
        }
      }
    }

    for (i in seq_len(n_trees)) {
      if (is.na(df$longitude[i]) || is.na(df$latitude[i])) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "coordinates are NA, E could not be computed")
      }
    }

    # --- 6. Compute AGB ---
    # Note: BIOMASS::computeAGB() returns AGB in Mg (megagrams = tonnes)
    # We convert to kg (* 1000) for the response
    df$AGB_Mg <- NA_real_

    for (i in seq_len(n_trees)) {
      if (is.na(df$diameter[i]) || is.na(df$wood_density[i])) {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "AGB not computed: diameter or wood_density is NA")
        next
      }

      agb_val <- NA_real_
      if (!is.na(df$height[i])) {
        # Use height-based model
        agb_val <- tryCatch(
          computeAGB(D = df$diameter[i], WD = df$wood_density[i], H = df$height[i]),
          error = function(e) { NA_real_ }
        )
        if (is.na(agb_val)) {
          tree_warnings[[i]] <- c(tree_warnings[[i]], "computeAGB failed with height-based model")
        }
      } else if (!is.na(df$E[i])) {
        # Use E-based model (Chave 2014) when height is not available
        tree_warnings[[i]] <- c(tree_warnings[[i]], "height is NA, using E-based model (Chave 2014)")
        agb_val <- tryCatch(
          computeAGB(D = df$diameter[i], WD = df$wood_density[i],
                     coord = data.frame(longitude = df$longitude[i], latitude = df$latitude[i])),
          error = function(e) { NA_real_ }
        )
        if (is.na(agb_val)) {
          tree_warnings[[i]] <- c(tree_warnings[[i]], "computeAGB failed with E-based model")
        }
      } else {
        tree_warnings[[i]] <- c(tree_warnings[[i]], "AGB not computed: height and E are both NA")
      }

      df$AGB_Mg[i] <- agb_val
    }

    # Convert Mg to kg
    df$AGB_kg <- df$AGB_Mg * 1000

    # --- 7. Assemble response ---
    results <- vector("list", n_trees)
    n_warnings_total <- 0
    n_failed <- 0

    for (i in seq_len(n_trees)) {
      w <- tree_warnings[[i]]
      if (length(w) > 0) n_warnings_total <- n_warnings_total + 1
      if (is.na(df$AGB_kg[i])) n_failed <- n_failed + 1

      results[[i]] <- list(
        longitude    = df$longitude[i],
        latitude     = df$latitude[i],
        diameter     = df$diameter[i],
        height       = if (is.na(df$height[i])) NULL else df$height[i],
        speciesName  = df$speciesName[i],
        genus        = if (is.na(df$genus[i])) NULL else df$genus[i],
        species      = if (is.na(df$species[i])) NULL else df$species[i],
        wood_density = if (is.na(df$wood_density[i])) NULL else round(df$wood_density[i], 4),
        E            = if (is.na(df$E[i])) NULL else round(df$E[i], 4),
        AGB_kg       = if (is.na(df$AGB_kg[i])) NULL else round(df$AGB_kg[i], 2),
        AGB_Mg       = if (is.na(df$AGB_Mg[i])) NULL else round(df$AGB_Mg[i], 4),
        warnings     = w
      )
    }

    total_agb <- sum(df$AGB_kg, na.rm = TRUE)

    elapsed <- (proc.time() - start_time)["elapsed"]
    message(sprintf("[%s] Completed: %d trees, %.2f kg total AGB, %d warnings, %.2fs",
                    Sys.time(), n_trees, total_agb, n_warnings_total, as.numeric(elapsed)))

    response <- list(
      results = results,
      summary = list(
        total_AGB_kg = round(total_agb, 2),
        n_trees      = n_trees,
        n_warnings   = n_warnings_total,
        n_failed     = n_failed
      )
    )

    return(response)

  }, error = function(e) {
    elapsed <- (proc.time() - start_time)["elapsed"]
    message(sprintf("[%s] ERROR after %.2fs: %s", Sys.time(), elapsed, e$message))

    res$status <- 500L
    return(list(
      error = TRUE,
      message = paste("Internal server error:", e$message),
      details = NULL
    ))
  })
}
