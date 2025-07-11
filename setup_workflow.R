## Workflow for Uncalibrated Setup Preparation ---------------------------------
## 
## Version 0.0.3
## Date: 2023-11-15
## Developers: Svajunas Plunge    svajunas_plunge@sggw.edu.pl
##             Christoph Schürz   christoph.schuerz@ufz.de
##             Micheal Strauch    michael.strauch@ufz.de
##
## 

# ------------------------------------------------------------------------------
## Please read before starting!!! The preparation of input data is not part of 
## this workflow and needs to be done externally. However, if you have already 
## prepared and tested the data using the scripts provided by the developer 
## team, you can proceed with this setup generation workflow. Its primary 
## objective is to regenerate the complete setup in (hopefully) a single run. 
## This could be crucial if you've updated the input data, discovered errors in
## the setup, and more. The workflow enables you to progress from pre-processed 
## data to a pre-calibrated model setup. Additionally, you can utilize other 
## workflows provided by the development team for soft and hard calibration/
## validation of the model, running scenarios, etc.

##------------------------------------------------------------------------------
## 
##------------------------------------------------------------------------------

library(SWATprepR)
library(SWATfarmR)
source('settings.R')
source('functions.R')

## If the directory exists, delete the results directory. (Please be careful!!!)
if (file.exists(res_path)) unlink(res_path, recursive = TRUE)
## Creating results directory
dir.create(res_path, recursive = TRUE)

##------------------------------------------------------------------------------
## 2) Running SWATbuildR'er
##------------------------------------------------------------------------------

## Please make sure SWATbuildR'er settings are provided in settings file
source(paste0(lib_path, '/buildr_script/swatbuildr.R'), chdir=TRUE)

##------------------------------------------------------------------------------
## 3) Adding weather data to model setup
##------------------------------------------------------------------------------

## Description of functions and how data example was prepared is on this webpage
## https://biopsichas.github.io/SWATprepR/articles/weather.html

## Identifying path to the database
db_path <- list.files(path = getwd(), pattern = paste0(project_name, ".sqlite"), 
                      recursive = TRUE, full.names = TRUE)
if(length(db_path)>1){
 stop(paste0("You have more than one database named ", 
             paste0(project_name, ".sqlite in you working directory. 
                    Please remove/rename or set path to db manually!!")))
} else {
  zip(paste0(res_path,"/db_backup.zip"), db_path)
}

## Loading weather data 
# met <- load_template(weather_path, epsg_code)
# met_int <- interpolate(met, "Data/for_buildr/basin.shp", 
#                        "Data/for_buildr/DEM.tif", 5000) 

met <- readRDS(weather_path)

## Calculating weather generator statistics
wgn <- prepare_wgn(met)

## Adding weather and atmospheric deposition data into setup
add_weather(db_path, met, wgn)

##------------------------------------------------------------------------------
## 4) Adding small modification to model setup .sqlite 
##------------------------------------------------------------------------------

## This is needed for write.exe to work (writing a dot in project_config table)
db <- dbConnect(RSQLite::SQLite(), db_path)
project_config <- dbReadTable(db, 'project_config')
project_config$input_files_dir <- "."
dbWriteTable(db, 'project_config', project_config, overwrite = TRUE)
dbDisconnect(db)

## After this step, the model setup .sqlite database is fully prepared. If you 
## wish to investigate, review, or update parameters, you can use tools such as 
## SWATPlusEditor, DB Browser for SQLite, or any other open-source tools. 
## Additionally, R packages like RSQLite could be applied for these purposes."

##------------------------------------------------------------------------------
## 5) Writing model setup text files into folder with write.exe
##------------------------------------------------------------------------------

## Directory of setup .sqlite database 
dir_path <- file.path(dirname(db_path))

## Copy write.exe into TxtInOut directory and run it
## (In case you get error in this step the workaround can be opening database 
## with SWATPluseditor and writing SWAT input files with it.)
exe_copy_run(lib_path, dir_path, "write.exe")

if (file.exists(paste0(dir_path, "/plants.plt"))) unlink(paste0(dir_path, "/plants.plt"))
file.copy("plants.plt", dir_path)
##------------------------------------------------------------------------------
## 6) Linking aquifers and channels with geomorphic flow
##------------------------------------------------------------------------------

# A SWATbuildR model setup only has one single aquifer (in its current 
# version). This aquifer is linked with all channels through a channel-
# aquifer-link file (aqu_cha.lin) in order to maintain recharge from the
# aquifer into the channels using the geomorphic flow option of SWAT+

link_aquifer_channels(dir_path)

##------------------------------------------------------------------------------
## 7) Adding point sources and atmospheric deposition data 
##------------------------------------------------------------------------------

## Description of how data should be prepared (template) is on this webpage
## https://biopsichas.github.io/SWATprepR/articles/psources.html

## Load data from template
pnt_data <- load_template(temp_path)
## Add to the model
prepare_ps(pnt_data, dir_path, constant = TRUE)

##Downloading atmo deposition data https://biopsichas.github.io/SWATprepR/reference/get_atmo_dep.html
df <- get_atmo_dep(basin_path)
## Add atmo deposition https://biopsichas.github.io/SWATprepR/reference/add_atmo_dep.html
add_atmo_dep(df, dir_path, t_ext = "annual")

##------------------------------------------------------------------------------
## 8) Running SWATfamR'er input preparation script
##------------------------------------------------------------------------------

## Setting directory and running Micha's SWAtfarmR'er input script
in_dir <- paste0(lib_path, "/farmR_input")
source(paste0(in_dir, "/write_SWATfarmR_input.R"), chdir=TRUE)

## Coping results into results folder
files <- list.files(in_dir, pattern = "\\.csv$")
out_dir <- paste0(res_path, "/farmR_input")
if (dir.exists(out_dir)) unlink(out_dir, recursive = TRUE)
dir.create(out_dir)
file.copy(paste0(in_dir, "/", files), paste0(res_path, "/farmR_input"))

## Cleaning calculation directory
file.remove(paste0(in_dir, "/", files))

##------------------------------------------------------------------------------
## 9) Additional editing of the farmR_input.csv file
##------------------------------------------------------------------------------

## Reading the file 
mgt <- paste0(out_dir, "/farmR_input.csv")
mgt_file <- read.csv(mgt)

## Updating farmR_input.csv for providing management schedules in drained areas
mgt_file <- bind_rows(mgt_file, mgt_file %>% 
                        mutate(land_use = gsub("_lum", "_drn_lum", land_use)))
write_csv(mgt_file, file = mgt, quote = "needed", na = '')

##------------------------------------------------------------------------------
## 10) Updating landuse.lum file
##------------------------------------------------------------------------------

## Backing up landuse.lum file
if(!file.exists(paste0(dir_path, "/", "landuse.lum.bak"))) {
  file.copy(from = paste0(dir_path, "/", "landuse.lum"),
            to = paste0(dir_path, "/", "landuse.lum", ".bak"), overwrite = TRUE)
}

## Updating it
source(paste0(lib_path, '/read_and_modify_landuse_lum.R'))

##------------------------------------------------------------------------------
## 11) Updating nutrients.sol file
##------------------------------------------------------------------------------

## Soil P data mapping and adding to model files scripts are provided by WP3. 
## Please utilize WPs&Task>WP3>Scrips and tools> App8_Map_soilP_content.R and 
## App9_Add_soilP_content_to_HRU.r
## Following lines provide way to update single value in nutrients.sol file

## Updating single value of labile phosphorus in nutrients.sol 
f_write <- paste0(dir_path, "/", "nutrients.sol")
nutrients.sol <- read.delim(f_write)
nutrients.sol[2,1] <- gsub("5.00000", lab_p, nutrients.sol[2,1])
update_file(nutrients.sol, f_write)

##------------------------------------------------------------------------------
## 12) Updating time.sim
##------------------------------------------------------------------------------

## Reading time.sim
f_write <- paste0(dir_path, "/", "time.sim")
time_sim <- read.delim(f_write)

## Updating with values provided in settings
y <- as.numeric(unlist(strsplit(time_sim[2,1], "\\s+"))[-1])
if(min(y[y>0]) != st_year){
  time_sim[2,1] <- gsub(min(y[y>0]), st_year, time_sim[2,1])
}
if(max(y[y>0]) != end_year){
  time_sim[2,1] <- gsub(max(y[y>0]), end_year, time_sim[2,1])
}

##Writing out updated time.sim file
update_file(time_sim, f_write)

##------------------------------------------------------------------------------
## 13) Preparing land_connections_as_lines.shp layer to visualise connectivities
## (needed, if file rout_unit.con should be updated manually)
##------------------------------------------------------------------------------

source(paste0(lib_path, '/create_connectivity_line_shape.R'))
print(paste0("land_connections_as_lines.shp is prepared in ", dir_path, 
             '/data folder' ))

## Guidelines for investigation and manual updating of 'rout_unit.con is 
## provided in OPTAIN Cloud > WPs & Tasks > WP4 > Task 4.4 > Tools to share >
## check_connectiviness > connectivity_chech_showcase.pdf

##------------------------------------------------------------------------------
## 14) Running SWAT+ model setup
##------------------------------------------------------------------------------

##Copy swat.exe into txtinout directory and run it
exe_copy_run(lib_path, dir_path, swat_exe)

##------------------------------------------------------------------------------
## 15) Running SWATfamR'er to prepare management files
##------------------------------------------------------------------------------

## Please read https://chrisschuerz.github.io/SWATfarmR/ to understand how to 
## apply this tool. Below are a minimal set of lines to access management files. 
## However, these might not be suitable in your case. Review before using

## Generating .farm project
frm <- SWATfarmR::farmr_project$new(project_name = 'frm', project_path = 
                                      dir_path, project_type = 'environment')
## Adding dependence to precipitation 
api <- variable_decay(frm$.data$variables$pcp, -5,0.8)
asgn <- select(frm$.data$meta$hru_var_connect, hru, pcp)
frm$add_variable(api, "api", asgn)

## Reading schedules, scheduling operations and writing management files
frm$read_management(mgt, discard_schedule = TRUE)
frm$schedule_operations(start_year = st_year, end_year = end_year, 
                        replace = 'all')
frm$write_operations(start_year = st_year, end_year = end_year)

##------------------------------------------------------------------------------
## 16) Running final SWAT model pre-calibrated setup
##------------------------------------------------------------------------------

## Copy swat.exe into txtinout directory and run it
exe_copy_run(lib_path, dir_path, swat_exe)

##------------------------------------------------------------------------------
## 17) Extracting SWAT input files and overwriting with a set of files 
##------------------------------------------------------------------------------

## Preparing directory
clean_path <- paste0(res_path, "/", "clean_setup")
## If the directory exists, delete the results directory. (Please be careful!!!)
if (file.exists(clean_path)) unlink(clean_path, recursive = TRUE)
## Creating results directory
dir.create(clean_path, recursive = TRUE)

## Coping only input files
file.copy(setdiff(list.files(path = dir_path, full.names = TRUE), 
                  list.files(path = dir_path, 
                             pattern = ".*.txt|.*.zip|.*success.fin|.*co2.out|.*.exe|.*simulation.out|.*.bak|.*.mgts|.*.farm|.*area_calc.out|.*checker.out|.*sqlite|.*diagnostics.out|.*erosion.out|.*files_out.out|.*.swf", full.names = TRUE)), 
          clean_path)

## Overwriting with a set of manually adjusted files (if needed)
## Directory could be empty, if you don't have any files to be used.
file.copy(list.files(
  path = paste0(lib_path, "/files_to_overwrite_at_the_end"), full.names = TRUE), 
  clean_path, overwrite = TRUE)

cat("Congradulations!!! You have pre-calibrated model!!! \n
Please continue to soft-calibration workflow (softcal_workflow.R)")
print(paste0("Your setup is located in the ", getwd(), "/", clean_path))
