library(readxl)
library(tidyverse)
library(purrr)
library(testthat)
library(parallel)
library(rlist)

# Setup =========================================================

# the expected number of items produced when creating the content
# for the repots
content_length = 430

# start a timer 
st = Sys.time()

source("functions folder/source functions.R")

# read in the excel file with all tabs
raw_data = read_CA_data("data/council-area-profiles-dataset.xlsx")

# define the expected shape and characteristics of the data
expectations = set_expectations()

# check whether the raw data matches these expectations
check_results = check_expectations(raw_data, expectations)

# There is a later dependency in the Rmd file where having the 
# updates sublist at the top level of the global env is important.
# However this can't be done before the check_expectations stage.
# So it is done here.
raw_data = list.merge(raw_data, raw_data$updates)

# Create Content =========================================================
# list of Council Areas to produce reports for
##########
Area <- c(
 "Aberdeen City",
 "Aberdeenshire",
 "Angus",
 "Argyll and Bute",
 "City of Edinburgh",
 "Clackmannanshire",
 "Dumfries and Galloway",
 "Dundee City",
 "East Ayrshire",
 "East Dunbartonshire",
 "East Lothian",
 "East Renfrewshire",
 "Falkirk",
 "Fife",
 "Glasgow City",
 "Highland",
 "Inverclyde",
 "Midlothian",
 "Moray",
 "Na h-Eileanan Siar",
 "North Ayrshire",
 "North Lanarkshire",
 "Orkney Islands",
 "Perth and Kinross",
 "Renfrewshire",
 "Scottish Borders",
 "Shetland Islands",
 "South Ayrshire",
 "South Lanarkshire",
 "Stirling",
 "West Dunbartonshire",
 "West Lothian"
)
##########
# # # # # # # # # # # # 
# parallel setup
# # # # # # # # # # # # 



# find the number of cpu cores we have available
n_cores = detectCores()

# NOTE: If the code takes too long to run and memory pressure is high
# reduce the value of n_cores to 2 or 4;
# n_cores = 2


# create a compute cluster with this resource
cl = makeCluster(n_cores)

# export the data to distribute across the 
# cluster nodes
clusterExport(cl, varlist = c("raw_data"))

# call any specific R commands across the nodes
clusterCall(cl, fun = function(){
  # here we call libraries to make sure the nodes can access tidyverse functions
  library(tidyverse)
  # Plot
  library(ggplot2)
  library(ggrepel)
  library(stringr)
  library(stringi)
  library(scales)
  
  # Tables
  library(reshape2)
  library(kableExtra)
  
  # Text
  library(glue)
  
  })

# source custom functions for producing the content across all the nodes
clusterEvalQ(cl, source("functions folder/plot_functions.R" ,local = T))
clusterEvalQ(cl, source("functions folder/table_functions.R" ,local = T))
clusterEvalQ(cl, source("functions folder/text_functions.R" ,local = T))
clusterEvalQ(cl, source("functions folder/produce_CA_content.R" ,local = T))

# check if the temporary folder to hold the content for each report exists

if(!dir.exists("temp")){
  
  # if it doesn't exist then create it
  
  dir.create("temp")
  
}

# # # # # # # # # # # # 
# parallel execution
# # # # # # # # # # # # 

# produce the content for all the areas 
CA_content_status = parLapply(cl, Area, function(CA){
  
  # CA=Area[1]
  
  # produce_CA_content function declared in functions folder/produce_CA_content.R
  CA_data = produce_CA_content(CA, raw_data)
  
  # write the content to file.
  # the Rmd will load it later
  write_rds(CA_data, file = paste0("temp/",CA_data$area,"-content.rds"))
  
  # TODO add QA steps in to check content 
  # check number of items
  # check for NAs
  if(length(CA_data) < content_length){
    
    return(-1)
    
  } else if(length(CA_data) > content_length) {
    
    return(-2)
    
  } else {
    # Check here for any NAs in the CA_data list
  }
  
  # assuming nothing went wrong
  # return 1
  return(1)
  
  
  
}
)

# All parallel output is written to file regardless of whether it worked
# there are some basic checks after it is written and we check for 
# good output here. Any status which is not 1 means there's 
# an issue with the production of the content for that CA
if(any(CA_content_status %>% unlist() !=1)){
  
  # helpful indicator of where to look for missing content
  stop(paste("Please check content for:", paste(Area[which(CA_content_status %>% unlist() !=1)],collapse = ", "), " | inside the 'temp' folder"))
  # if any status is not 1 then we won't even progress to knitting
  
}

# Knit HTML Files =========================================================

knit_result = parLapply(cl, Area, function(area){
  
  # for debugging with a single CA
  # area = Area[1]
  
  # if the content for this CA exists then knit
  if(file.exists(paste0("temp/",area,"-content.rds"))){
    
    res = rmarkdown::render("CA_profile.Rmd",
                      output_dir = "output",
                      output_file = paste0(gsub(" ", "-", tolower(area)),
                                           "-council-profile.html"),
                      params = list(area = area),
                      quiet = ifelse(length(area) > 1, TRUE, FALSE))
    
    # remove the content rds file when done
    file.remove(paste0("temp/",area,"-content.rds"))
    
    return(1)
    
  } else {
    # if the content didn't exist then just return -1
    return(-1)
  }
  
})

stopCluster(cl)

# # # # # # # # # # # # 
# parallel end
# # # # # # # # # # # # 

timed_run = Sys.time() - st

print(paste("Code complete. Run time:",timed_run))

# last check to see if everything went to plan
if(any(knit_result %>% unlist() !=1)){
  
  # helpful indicator of where to look for missing reports
  stop(paste("Please check for missing reports:", paste(Area[which(knit_result %>% unlist() !=1)],collapse = ", ")))
  
}


