FROM rocker/geospatial:latest

# Install R packages
RUN R -e "install.packages(c('plumber', 'jsonlite', 'BIOMASS'), repos='https://cran.r-project.org/')"

# Set working directory
WORKDIR /app

# Copy API files
COPY api.R .
COPY run_api.R .

# Expose API port
EXPOSE 8000

# Start the API
CMD ["Rscript", "run_api.R"]
