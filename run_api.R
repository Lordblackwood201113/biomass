# run_api.R - Launch the BIOMASS plumber API server

library(plumber)

# Configuration
port <- as.integer(Sys.getenv("API_PORT", unset = "8000"))
host <- "0.0.0.0"

# Load and start API
pr <- plumb("api.R")

message(sprintf("[%s] Starting BIOMASS API on %s:%d", Sys.time(), host, port))

pr$run(host = host, port = port)
