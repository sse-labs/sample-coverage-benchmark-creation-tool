# sample-coverage-benchmark-creation-tool

The R script consists of a series of functions that can be used to create a dataset by crawling through the webpages of openhub.net, determining if different projects are similar to each other, calculate the coverage scores of a dataset and creating a representative and diverse sample dataset. The necessary R packages to run the functions are included. A list of 29549 project URLs is made available as the universe.rds file. The dataset consisting of 13596 projects is made available in the dataset1.rds file in its regular form, as created by the openHubDataExtraction function, while the dataset2.rds file includes the log10 values for all numerical categories to allow faster computing when using the similarity functions.

Similarity is based on the definitions used by Nagappan et al. in „Diversity in Software Engineering Research“ [1]. Two strings are similar if they are identical, two numbers are similar when they are in the same order of magnitude as expressed by the formula abs(log10(x) - log10(y)) <= 0.5.

# openHubDataExtraction:
This function crawls through given webpages of openhub.net, extracts the information for the various categories and stores them in a dataframe.
To ensure an optimal use of the daily limit for API calls on OpenHub an API key is strongly recommended. It should be stored in the global environment as the "API_Key" variable. Making too many API calls in a short time frame might result in the OpenHub server misclassifying the use of this function as a Denial of Service attack. The counter lets the function sleep in regular intervals, which slows down the execution time, but avoids errors that could lead to a premature exiting of the function. For every 100 pages that have been crawled through, a temporary csv file is created and overwritten with the current results of the function. This serves as a fail-safe in case any errors interrupt the function.

An example call of this function looks like this:
openHubDataExtraction(universe[1:1000]), which would crawl through the first 1000 projects and return the valid and active projects as a dataset.

# similar_strings:
This is a helper function that compares one string to a vector of strings and returns the result as a boolean vector.

An example call of this function looks like this:
similar_strings(dataset[1,2], dataset[,2])
In this case the main language of the first project is compared to the main languages of all other projects in the dataset.

# similar_numbers:
This is a helper function that compares one numerical value to a vector of numbers and returns the result as a boolean vector.

An example call of this function looks like this:
similar_strings(dataset[2,3], dataset[,3])
In this case the total lines of code of the second project are compared to the total lines of code of all other projects in the dataset.

# similarity:
This function is used to compare one project to all projects in a dataset. It uses the similar_strings and similar_numbers helper functions based on a config vector and returns a boolean matrix. The config vector assigns the string function to 1 and the number function to 2.

An example call of this function looks like this:
similarity(dataset[3,], dataset, config = c(1,1,2,2,2,2,1,1))
In this case the third project of the dataset is compared to the entire dataset. The config vector is chosen for the categories Name, Main Language, Total Lines of Code, Contributors, Churn, Commits, Project Age, Activity.

# score_projects:
An R implementation of the pseudo algorithm introduced by Nagappan et al. in "Diversity in Software Engineering Research" [1], found on page 3 as "ALGORITHM I. Scoring Projects". It calculates the coverage score for each value of a given dataset.

An example call of this function looks like this:
score_projects(dataset, config = c(1,1,2,2,2,2,1,1))
It is possible to choose certain sections of the dataset, for example using the parameter dataset[1000:2000,] will calculate the scores for all the projects between the 1000th and 2000th project in the dataset.

# choose_new_projects:
This function is based on the pseudo algorithm introduced by Nagappan et al. in "Diversity in Software Engineering Research" [1], found on page 3 as "ALGORITHM II. Selecting the Next Projects“. The function runs through the dataset, calculates the similar projects for each project of the dataset and then returns a sample dataset, with the goal of maximizing diversity and representativeness via the use of sample coverage.

An example call of this function looks like this:
choose_new_projects(13596, dataset, sim = c(1), config = c(1,1,2,2,2,2,1,1))
The first parameter determines if the function should stop prematurely. For example, if n = 10, the project will stop after 10 projects have been added to the set if diversity and representativeness haven’t been maximized yet. If n is sufficiently large the function will exit once the metrics have been maximized. For this use case it is recommended to use an n the same size as the number of projects in the set.
The second parameter is the dataset that is being examined. The third parameter determines which categories should be skipped in the evaluation. In this case only the name of a project is skipped. This can be adjusted, for example the vector sim = c(1, 3:6) would exclude the first as well as the third, fourth, fifth and sixth categories). The final parameter is the configuration vector for the similarity helper functions.

[1] = https://cs.uwaterloo.ca/~m2nagapp/publications/pdfs/Diversity-in-Software-Engineering-Research.pdf
