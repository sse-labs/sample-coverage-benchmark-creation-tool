library(xml2)
library(stringr)
library(rvest)
library(httr)
library(dplyr)

universe <- readRDS("universe.rds")
dataset1 <- readRDS("dataset1.rds")
dataset2 <- readRDS("dataset2.rds")

# This function crawls through given webpages of openhub.net, extracts the 
# information for the various categories and stores them in a dataframe.
openHubDataExtraction <- function(x){
  
  DF <- data.frame(Name = character(),
                   MainLanguage = character(),
                   TLOC = integer(),
                   Contributors = integer(),
                   Churn = integer(),
                   Commits = integer(),
                   ProjectAge = character(),
                   Activity = character())
  count <- 0
  
  for(i in x) {
    # To ensure an optimal use of the daily limit for API calls on OpenHub
    # an API key is strongly recommended. It should be stored in the global
    # environment as the "API_Key" variable.
    xml_address <- paste(i, ".xml?api_key=", API_Key, sep = "")
    data_xml <- as_list(read_xml(xml_address))
    
    count <- count + 1
    
    # Making too many API calls in a short time frame might result in the
    # OpenHub server misclassifying the use of this function as a Denial of
    # Service attack. The counter lets the function sleep in regular intervals,
    # which slows down the execution time, but avoids errors that could lead
    # to a premature exiting of the function.
    if(count %% 10 == 0){
      Sys.sleep(5)
    }
    if(count %% 100 == 0){
      Sys.sleep(55)
    }
    
    # Projects whose analysis on OpenHub hasn't been completed are filtered out.
    if (grepl("No Analysis to display for", data_xml)) {
      projectname <- str_remove(data_xml$response$error, "No Analysis to display for ")
      projectname <- gsub(pattern = "\\.", replacement = "", projectname)
      mainLanguage <- NA
      TLOC <- NA
      numContributors <- NA
      churn <- NA
      numCommits <- NA
      age <- NA
      activity <- NA
    }else{
      # Project Name
      projectname <- data_xml$response$result$project$name[[1]]
      
      # Main Language
      mainLanguage <- data_xml$response$result$project$analysis$main_language_name[[1]]
      
      # Total Lines Of Code
      TLOC <- data_xml$response$result$project$analysis$total_code_lines[[1]]
      
      # Contributors in the last 12 months
      numContributors <- data_xml$response$result$project$analysis$twelve_month_contributor_count[[1]]
      
      # Churn in the last 12 months
      # Churn is not found with the rest of the information in the API call.
      # It has to be manually calculated, which requires a second call that
      # does not use the API key and thus is not affected by the daily limit.
      commitSummary <- httr::GET(paste(i, "/commits/summary", sep = ""), config = httr::config(connecttimeout = 60))
      comSumContent <- httr::content(commitSummary, as = "text")
      
      added <- str_extract(
        comSumContent,
        'Lines Added:</td>\\n<td align=\'right\' width=\'25%\'>\\d+</td>\\n<td align=\'right\' width=\'25%\'>\\d+'
      )
      removed <- str_extract(
        comSumContent,
        'Lines Removed</td>\\n<td align=\'right\' width=\'25%\'>\\d+</td>\\n<td align=\'right\' width=\'25%\'>\\d+'
      )
      
      churn <- as.numeric(tail(unlist(strsplit(added, "'25%'>")), n = 1)) + as.numeric(tail(unlist(strsplit(
        removed, "'25%'>"
      )), n =
        1))
      
      # Commits in the last 12 months
      numCommits <- data_xml$response$result$project$analysis$twelve_month_commit_count[[1]]
      
      # Project Age
      ageData <- data_xml$response$result$project$analysis$factoids
      age = ""
      
      if (any(grepl("Short source control history", ageData))) {
        age <- "Young" # Less than 12 months
      } else if (any(grepl("Young, but established codebase", ageData))) {
        age <- "Normal" # 1 to 3 Years Commit Activity
      } else if (any(grepl("Well-established codebase", ageData))) {
        age <- "Old" # 3 to 5 Years Commit Activity
      } else if (any(grepl("Mature, well-established codebase", ageData))) {
        age <- "Very Old" # 5 Years or More Commit Activity
      }
      
      # Project Activity
      activityData <- data_xml$response$result$project$analysis$factoids
      activity = ""
      
      if (any(grepl("Increasing", activityData))) {
        activity <- "Increasing"
      } else if (any(grepl("Stable", activityData))) {
        activity <- "Stable"
      } else if (any(grepl("Decreasing", activityData))) {
        activity <- "Decreasing"
      }
    }
    
    result <- data.frame(
      Name = projectname,
      MainLanguage = mainLanguage,
      TLOC = TLOC,
      Contributors = numContributors,
      Churn = churn,
      Commits = numCommits,
      ProjectAge = age,
      Activity = activity
    )
    
    DF <- rbind(DF, result)
    print(count)
    
    # For every 100 pages that have been crawled through, a temporary csv file
    # is created and overwritten with the current results of the function.
    # This serves as a fail-safe in case any errors interrupt the function.
    if(count %% 100 == 0){
      write.csv(DF, "temp.csv")
    }
  }
  print("success")
  return(DF)
}

# Helper function that compares one string to a vector of strings and returns
# the result as a boolean vector.
similar_strings <- function(p, q){
  result <- c(rep(FALSE, length(q)))
  result[p == q] <- TRUE
  return(result)
}

# Helper function that compares if a numerical value and a vector of numerical
# values are in the same order of magnitude. The formula used is:
# abs( log10(p) - log10(q)) <= 0.5
# In order to correctly use this function the log10 values of the vectors should
# be calculated prior to running the function. This allows a considerably faster
# execution. The function returns a boolean vector.
similar_numbers <- function(p, q){
  return(abs(q - p) <= 0.5)
}

# Helper function that compares one project of the data set to the entire data
# set. It requires the following parameters:
# - One project of the data set in the form of "dataSet[x,]", dataset being a
# generic name for the examined set, x being the row number.
# - The data set that is to be examined in the form of "dataSet".
# - A numerical vector named config consisting of 1s and 2s. 1s are used when
# the category is a string, 2s when the category is numerical. The default form
# for the regular categories chosen is "config = c(1,1,2,2,2,2,1,1)".
# A boolean matrix that shows which values in the data set are considered
# similar to the respective values of the examined project p is returned.
similarity <- function(p, q, config){
  result <- vector()
  for(i in 1:length(config)){
    if(config[i] == 1){
      cache <- similar_strings(p[,i], q[,i])
    }
    if(config[i] == 2){
      cache <- similar_numbers(p[,i], q[,i])
    }
    result <- append(result, cache)
  }
  return(matrix(result, nrow = nrow(q), ncol = length(config)))
}

# An R implementation of the pseudo algorithm introduced by Nagappan et al. in
# "Diversity in Software Engineering Research", found on page 3 as
# "ALGORITHM I. Scoring Projects".
# The function takes a data set and a config vector for the similarity functions
# as parameters. It calculates to what degree each value of a project's category
# covers the values found in the rest of the category.
# For example, a data set consisting of 10 projects, one written in JavaScript,
# the rest in Python, would calculate a coverage score of 0.1 for
# the JavaScript project and 0.9 for each of the Python projects in the 
# category of main language.
score_projects <- function(x, config){
  
  c_dim <- data.frame(C_Language=double(), C_TLOC=double(), C_double=double(), C_Churn=double(),
                      C_Commits=double(), C_Age=double(), C_Activity=double(), stringsAsFactors = FALSE)
  
  score = double()
  
  for(p in 1:nrow(x)){
    c_project <- x
    are_similar <- similarity(x[p,], x, config = config)
    for(d in 2:ncol(x)){
      sim_projects <- x[are_similar[,d],]
      c_dim[p,(d-1)] <- sum(are_similar[,d])/nrow(x)
    }
    booleanVector <- apply(subset(are_similar, select = - are_similar[,1]), 1, all)
    score[p] <- sum(booleanVector)/nrow(x)
    print(p/nrow(x))
  }
  
  DF <- data.frame(Name = x[,1],
                   Score = score,
                   C_Language = c_dim[,1],
                   C_TLOC = c_dim[,2],
                   C_Contributors = c_dim[,3],
                   C_Churn = c_dim[,4],
                   C_Commits = c_dim[,5],
                   C_Age = c_dim[,6],
                   C_Activity = c_dim[,7],
                   stringsAsFactors = FALSE)
  
  return(DF)
}

# This function is based on the pseudo algorithm introduced by Nagappan et al.
# in "Diversity in Software Engineering Research", found on page 3 as
# "ALGORITHM II. Selecting the Next Projects". A number of changes were
# implemented to boost the performance of the function.
# The function takes four parameters:
# - The number of projects the function should return, up to "n" projects. it
# will terminate early if the coverage was maximized prior to reaching n. If the
# goal is to maximize the coverage n should be equal to the number of projects
# in the data set.
# - The data set that is to be examined, in the form of "x".
# - An optional vector "sim", which is used to exclude given categories. For
# example, if the first and third category are to be excluded: sim = c(1,3).
# - A configuration vector "config" to assign the correct similarity functions.
# The function runs through the data set, calculates the similar projects for
# each project of the data set and then returns a sample data set, with the
# goal of maximizing diversity and representativeness via the use of sample coverage.
choose_new_projects <- function(n, x, sim, config){
  
  similarityVector <- vector()
  for(i in 1:nrow(x)){
    similarityVector[i] <- sum(apply(similarity(x[i,-sim], x[,-sim], config = config[-sim]), 1, all))
    print(i/nrow(x))
  }
  
  haveBeenAdded <- rep(FALSE, nrow(x))
  x$Added <- haveBeenAdded
  x$sumOfSimilars <- similarityVector
  
  count <- 0
  resultingProjects <- data.frame(Name = character(), MainLanguage = character(), TLOC = numeric(), Contributors = numeric(),Churn = numeric(), Commits = numeric(),
                                  ProjectAge = character(), Activity = character(), sumOfSimilars = numeric(), Added = logical(), Score = numeric())
  for(i in 1:nrow(x)){
    if(count == n){break}
    decOrder <- order(x$sumOfSimilars, decreasing = T)
    nextOne <- which(x[decOrder,]$Added == FALSE)[1]
    if(any(haveBeenAdded[which(apply(similarity(x[decOrder[nextOne], -c(sim,9,10)], x[,-c(sim,9,10)], config = config[-c(sim,9,10)]), 1, all))])){
      haveBeenAdded[decOrder[nextOne]] <- TRUE
    }else{
      haveBeenAdded[which(apply(similarity(x[decOrder[nextOne], -c(sim,9,10)], x[,-c(sim,9,10)], config = config[-c(sim,9,10)]), 1, all))] <- TRUE
      resultingProjects <- rbind(resultingProjects, x[decOrder[nextOne],])
      count <- count + 1
      print(count)
    }
    x$Added <- haveBeenAdded
    if(sum(haveBeenAdded) >= nrow(x)){break}
  }
  return(resultingProjects)
}