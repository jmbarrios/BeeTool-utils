# Install necessary packages
install.packages('lubridate')
install.packages('dplyr')
install.packages('tidyverse')
install.packages('tidyr')
install.packages('sf')
install.packages('rgbif')
install.packages('data.table')

# Setting system memory
Sys.setenv('R_MAX_VSIZE'=64000000000)

# Clear unused memory
gc()

# If you just need to import a data frame so you can spatial join
all_bees <- read.delim("clipboard")

# Once you download a GBIF dataset, save the .csv file into your working directory
importFilename <- "may1.csv"

# This will be what the final exported .csv file will be called
exportFilename <- "export.csv"

# This is the largest GBIF ID in the pollinator database
largestGbifID <- 0

# This is the location of the county shapefile for the entire United States which is needed for spatial join
# NORTH AMERICA
require(sf)
require(dplyr)
counties_shp <- st_read("C:/Users/jrweaver/OneDrive - DOI/BEE_RICHNESS_TOOL/NA_Shapefile/NA_Shapefile.shp")
counties_shp <- select(counties_shp, -c(STATEFP, COUNTYFP, COUNTYNS, GEOID,	NAME,	NAMELSAD,	LSAD,	CLASSFP,	MTFCC,	CSAFP,	CBSAFP,	METDIVFP,	FUNCSTAT,	ALAND,	AWATER,	INTPTLAT,	INTPTLON,	new_value,	PRUID,	PRNAME,	PRENAME,	PRFNAME,	PREABBR,	PRFABBR,	ADM1_ES,	ADM1_PCODE,	ADM1_REF,	ADM1ALT1ES,	ADM1ALT2ES,	ADM0_ES,	ADM0_PCODE,	date,	validOn,	validTo,	Shape_Leng,	Shape_Le_1,	Shape_Area))

# EPA L3
EPAL3 <- st_read("C:\\Users\\jrweaver\\OneDrive - DOI\\EPA LEVEL 3\\NA_CEC_Eco_Level3.shp")
EPAL3 <- select(EPAL3, -c(NA_L3NAME, NA_L2CODE, NA_L2NAME, NA_L1CODE, NA_L1NAME, NA_L3KEY, NA_L2KEY, NA_L1KEY, Shape_Leng, Shape_Area))

# This batch code filters and edits the raw GBIF dataset
for(i in 1:1){
  
  require(sf)
  require(lubridate)
  require(dplyr)
  require(tidyverse)
  require(tidyr)
  require(data.table)
  
  # Import raw dataset from GBIF (6 families in North America)
  all_bees <- fread(importFilename, quote = "", select = c("gbifID", "individualCount", "decimalLatitude", "decimalLongitude", "speciesKey", "basisOfRecord", "institutionCode", "collectionCode", "identifiedBy","eventDate", "day","month","year", "species", "infraspecificEpithet"), na.strings = "")
  
  # When updating a GBIF dataset, this is how you delete all records that are less than the highest GBIF record in he database
  all_bees <- all_bees[!(all_bees$gbifID <= largestGbifID), ]
  
  # Remove all records that do not have coordinates (should be zero if the GBIF data query requires coordinates)
  all_bees <- filter(all_bees, decimalLatitude != "NA")
  all_bees <- filter(all_bees, decimalLongitude != "NA")
  
  # Remove all records that are not identified to species (this tends to remove quite a few occurrences)
  all_bees <- filter(all_bees, species != "")
  
  # Remove all records that have taxonRank marked as UNRANKED
  # all_bees <- filter(all_bees, taxonRank != "UNRANKED")
  
  # Replace "NA" values in subspecies with blank field
  all_bees$infraspecificEpithet <- sapply(all_bees$infraspecificEpithet, as.character)
  all_bees$infraspecificEpithet[is.na(all_bees$infraspecificEpithet)] <- ""
  
  # If there is a variety or subspecies, add it to full name. 
  all_bees$fullName <- paste(all_bees$species, all_bees$infraspecificEpithet)
  
  # Trim whitespace (if any) from fullName field
  all_bees$fullName <- str_trim(all_bees$fullName, side = c("both", "left", "right"))
  
  # Finding all values in Individual count that are NA and making them 1
  all_bees$individualCount[is.na(all_bees$individualCount)] <- 1
  
  # Finding all values in Individual count that are 0 and making them 1
  # This may seem counterintuitive but 0 does not mean absence data. 
  # There are many museum curated specimens erroneously marked as 0 for individualCount
  all_bees$individualCount[all_bees$individualCount == 0] <- 1
  
  # Create a date field
  all_bees$date <- as.Date(paste(all_bees$month,all_bees$day,all_bees$year,sep="-"),format = "%m-%d-%Y")
  all_bees$date <- format(strptime(all_bees$date, format = "%Y-%m-%d"), "%m/%d/%Y")
  
  # Remove unneeded date and species/subspecies fields
  all_bees <- select(all_bees, -c(species, infraspecificEpithet))
  all_bees <- select(all_bees, -c(day, month, year, eventDate))
  
  # Replace NA values in the date field with blanks
  all_bees$date[is.na(all_bees$date)] <- ""
  
}

# NORTH AMERICA DATASET - This batch code spatially joins the records to a county field (location_ID) and exports a CSV
for (i in 1:1){
  # Add county fields with GIS spatial join
  all_bees <- st_as_sf(all_bees,
                       coords = c(x = "decimalLongitude", 
                                  y = "decimalLatitude"),
                       crs = "NAD83",
                       remove = FALSE)
  
  # Only use the below code if you need to convert the coordinate system to NAD83 or something else
  # st_transform(counties_shp, crs = st_crs("NAD83"))
  
  # Set the counties_shp to NAD83
  st_crs(counties_shp) <- "NAD83"
  
  # Make any invalid lines in the shapefile valid (this takes a little while)
  counties_shp <- st_make_valid(counties_shp)
  
  # Use S2 geometry TRUE or FALSE
  sf_use_s2(TRUE)
  
  # This is the actual join function
  all_bees <- st_join(all_bees, counties_shp, join = st_within)
  # all_bees <- st_join(all_bees, refuges, join = st_within)
  
  # This removes all the unnecessary columns added by the join function
  all_bees <- data.frame(all_bees)
  all_bees <- select(all_bees, -c(geometry))
  # names(all_bees)[names(all_bees) == "date.x"] <- "date"
  
  # Remove all records where the occurrence was not geo-referenced within a county boundary
  # all_bees <- filter(all_bees, GEOID != "NA")
  all_bees <- filter(all_bees, ID != "NA")
  names(all_bees)[names(all_bees) == "ID"] <- "location_ID"
  
  # Export CSV file
  write.csv(all_bees, exportFilename, row.names = FALSE)
}

# NORTH AMERICA DATASET - This batch code spatially joins the records to a EPA LIII field (NA_L3CODE) and exports a CSV
for (i in 1:1){
# Add county fields with GIS spatial join
all_bees <- st_as_sf(all_bees,
                     coords = c(x = "decimalLongitude", y = "decimalLatitude"),
                     crs = "NAD83",
                     remove = FALSE)

# Only use the below code if you need to convert the coordinate system to NAD83 or something else
# st_transform(counties_shp, crs = st_crs("NAD83"))

# Set the counties_shp to NAD83
st_crs(EPAL3) <- "NAD83"
EPAL3 <- st_transform(EPAL3, "NAD83")

# Make any invalid lines in the shapefile valid (take a little while)
EPAL3 <- st_make_valid(EPAL3)
# refuges <- st_make_valid(refuges)

sf_use_s2(TRUE)

# This is the actual join function
all_bees <- st_join(all_bees, EPAL3, join = st_within)
# all_bees <- st_join(all_bees, refuges, join = st_within)

# This removes all the unnecessary columns added by the join function
all_bees <- data.frame(all_bees)
all_bees <- select(all_bees, -c(geometry))
names(all_bees)[names(all_bees) == "date.x"] <- "date"

# Remove all records where the occurrence was not geo-referenced within a county boundary
# all_bees <- filter(all_bees, GEOID != "NA")
all_bees <- filter(all_bees, ID != "NA")
names(all_bees)[names(all_bees) == "ID"] <- "location_ID"

# Export CSV file
write.csv(all_bees, exportFilename, row.names = FALSE)
}

# IF YOU JUST NEED TO CREATE A TAXONOMIC LIST OF UNIQUE SPECIES
for(i in 1:1){
  
  require(lubridate)
  require(dplyr)
  require(tidyverse)
  require(tidyr)
  require(sf)
  require(data.table)
  
  # Import raw dataset from GBIF (Present, 6 families, United States)
  # Just change the CSV filename to whatever I called it
  all_bees <- fread(importFilename, quote = "", select = c("family", "genus", "species", "infraspecificEpithet", "taxonRank", "scientificName", "speciesKey"), na.strings = "")
  
  # Remove all records that are not identified to species
  all_bees <- filter(all_bees, species != "")
  
  # Remove all records that have taxonRank marked as UNRANKED
  all_bees <- filter(all_bees, taxonRank != "UNRANKED")
  
  # Replace "NA" values in subspecies with blank field
  all_bees$infraspecificEpithet <- sapply(all_bees$infraspecificEpithet, as.character)
  all_bees$infraspecificEpithet[is.na(all_bees$infraspecificEpithet)] <- ""
  
  # If there is a variety or subspecies, add it to full name. 
  all_bees$fullName <- paste(all_bees$species, all_bees$infraspecificEpithet)
  
  # Trim whitespace from right side of fullName field
  all_bees$fullName <- str_trim(all_bees$fullName, side = c("both", "left", "right"))
  
  # Filter the taxa dataset to only include unique values
  all_bees <- unique(all_bees)
  
  #Export the taxa list
  write.csv(all_bees, exportFilename, row.names = FALSE)
  
}
