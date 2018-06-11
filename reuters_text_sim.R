
##############################################################################
#                   Loading of all required Libraries
##############################################################################

library(readr)
library(stringr)
library(hashmap)
library(numbers)
library(digest)


##############################################################################
#                   Section A: Data pre-processing
##############################################################################

########## Loading of documents

# User defines here the appropriate path to the files' folder
my_path <- "path/to/data/folder"

# A list is created containing the appropriate file names
files <- list.files(path = my_path, pattern = "*.sgm")

# Initialize an empty dataframe (df) that will host the documents
df <- data.frame(Article=character())

# Recursive visit to path, loading of next sgm file and appropriate splitting into articles
# until all sgm files are processed and appended to df, with the use of a temporary variable
for (i in 1:length(files)){
  temp <- read_file(paste(my_path,files[i], sep = ""))
  temp <- gsub("[\n]", " ", temp)
  temp <- strsplit(temp, "</REUTERS>")
  temp <- as.data.frame(temp)
  names(temp) <- names(df) 
  df   <- rbind(df,temp)
}

# Delete variables that are no longer useful
remove(files)
remove(i)
remove(temp)

########## Cleaning documents' text

# Remove from df all empty rows that occured from splitting (one at the end of each sgm file)
# Change column type from 'factor' to a more convenient one
df <- as.data.frame(df[df$Article!=" ",])
names(df) <- 'Article'
df$Article <- as.character(df$Article)

# Confirm correct loading of files: 21578 rows (each row represents one article)
str(df)

# Add a new column, namely ID, that will contain a unique identifier per article
# OLDID is used for this purpose
df$ID <- sub("\" NEWID.*", "", sub(".*OLDID=\"", "", df$Article))

# Add a new column, namely BODY, that will contain the main text per article in lowercase
# Articles with no BODY tag are removed (2535 in total)
df<-df[grep("<BODY>", df$Article), ]
df$BODY <- sub("</body>.*", "", sub(".*<body>", "", tolower(df$Article)))

# Remove first column containing full article details (we do not need it anymore)
df <- df[,-1]
str(df)

# Replace everything that is not a letter (punctuation, numbers, other symbols etc.) with white space
df$BODY <- stringr::str_replace_all(df$BODY,"[^a-zA-Z\\s]", " ")

# Shrink down to just one white space
df$BODY <- stringr::str_replace_all(df$BODY,"[\\s]+", " ")

########## Splitting documents into words

# Create two new lists from df columns:
# List s contains the BODY of each document split into its words
# List id contains the ID of each document
s  <- strsplit(as.character(df$BODY), split = " ")
id <- df$ID

# Remove from both lists records with less than 8 words (24 documents in total)
# so that we can create up to 7-word shingles
y  <- lapply(s, function(x) {length(x)})
v  <- which(y<8)
s  <- s[-v]
id <- id[-v]
remove(y)
remove(v)

##############################################################################

# Starting the clock (counting of total execution time)
start_time <- Sys.time()

##############################################################################


##############################################################################
#                   Section B: Shinghling
##############################################################################

########## Generation of k-shingles

# Number of words per shingle (k) is user-defined
k <- 4

# Create the shingling function (shingles contain k number of words)
Shingling <- function(document, k) {
  shingles <- character( length = length(document) - k + 1 )
  for( i in 1:( length(document) - k + 1 )) {
    shingles[i] <- paste( document[ i:(i + k - 1) ], collapse = " " )
  }
  return( unique(shingles) )  
}

# Implement the shingling function on all documents
s2 <- lapply(s, function(x) {Shingling(x, k)})

# Confirm correctness of shingling by printing a random document
s2[[5788]]

# Average shingles per document
length(unlist(s2))/length(s2)

########## Mapping of shingles into IDs with the use of a Hash Map

# Create the list of unique shingles amongst all documents
unique_list <- unique(unlist(s2))

# Create a list of unique numeric ids (of the same length)
unique_ids <- 1:length(unique_list)

# Generate a hash map that links each shingle to an id
# Set.seed is used to guarantee identical mapping in every execution
set.seed(42)
Dictionary <- hashmap(unique_list, unique_ids)

# Create the hashing function to replace all shingles of a document with their mapped ids
Hashing <- function(document) {
  hash <- c()
  hash <- lapply(document, function(x) {Dictionary[[x]]})
  return(hash)
}

# Implement the hashing function on all documents' shingles
s2_hash <- lapply(s2, function(x) {Hashing(x)})

# Confirm replacement by printing a random document
s2[[12345]]
s2_hash[[12345]]


##############################################################################
#                   Section C: Minhashing
##############################################################################

# The number of hash functions/signatures (h) is user-defined
h <- 40

# All hash functions are in the form of: h(x)=(ax+b) mod c
# c is the next prime greater than the number of unique shingles
c <- nextPrime(length(unique_list))

# Parameters a & b are retrieved simultaneously and without replacement
# This approach ensures their uniqueness
# Set.seed is used to guarantee identical sampling in every execution
set.seed(42)
params <- sample(1:length(unique_list), 2*h, replace = FALSE)

# Create the minhashing function that applies one hash function on all shingles of a document
# and retains the minimun value (signature) as a result
Minhashing <- function(document) {
  minhash <- c()
  a <- params[2*i-1]
  b <- params[2*i]
  minhash <- lapply(document, function(x){(((a%%c)*(x%%c))%%c+(b%%c))%%c})
  m <- min(unlist(minhash))
  return(m)
}

# Initialize a matrix (s2_minhash) that contains the document ids
s2_minhash <- as.matrix(as.integer(id))

# Implement the minhashing function on all documents and for all hash functions
# The produced signatures for each hash function are stored as a new column of s2_minhash
for (i in 1:h){
  colname <- as.matrix(lapply(s2_hash, function(x){ Minhashing(x)}))
  s2_minhash <- cbind(s2_minhash,colname)
}

# Delete variables that are no longer useful
remove(i)
remove(colname)

# Confirm that s2_minhash has as many rows as the number of documents 
# and as many columns as the number of hash functions (h) plus one (identifier)
dim(s2_minhash)


##############################################################################
#                   Section D: LSH
##############################################################################

# The size of LSH bands (band_size) is user-defined
band_size <- 5

# The number of LSH bands (band_number) can be derived
s2_cols <- ncol(s2_minhash)
band_number <- ceiling((s2_cols-1)/band_size)

# Create the lsh function that divides the signatures of one document into bands
# and hashes each band into a bucket
Lsh <- function(document) {
  bucket <- c() 
  for (i in 1: band_number) {
    start <- 2 + (i-1)*band_size
    if (start + band_size - 1 > s2_cols) {
      end <- s2_cols
    } else {
      end <- start + band_size - 1
    }
    bucket[i] <- digest(object = paste(document[start:end], collapse = "_"),  algo = "crc32")
  }
  return(bucket)  
}

# Implement the lsh function on all documents
s2_lsh <- t(as.matrix(apply(s2_minhash, 1, function(x) {Lsh(x)})))

# Add a column that contains the document ids
s2_lsh <- cbind(s2_minhash[,1],s2_lsh)

# Confirm that s2_lsh has as many rows as the number of documents 
# and as many columns as the number of bands (band_number) plus one (identifier)
dim(s2_lsh)


##############################################################################
#                   Section E: Nearest Neighbours
##############################################################################

# The OLDID of the document to be checked (query_doc) is user-defined
# As well as the number of nearest neighbours (nn)
query_doc <- 6968
nn <- 20

# Create the NearestNeighbours function that returns the n nearest neighbours
# of the document in question in order of descending Signature Similarity (Jaccard)
# Original Similarity (i.e. similarity of shingles) is also computed for comparison

NearestNeighbours <- function(document, n) {
  # Print query details
  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")
  print(paste("Query Document ID:", document, sep = " "))
  print(paste("Requested Number of Neighbours:", n, sep = " "))
  print("Query Document BODY:")
  print(df[df$ID == document, 2])
  cat("\n")
  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")
  
  # Retrieve the bucket ids for this document across all lsh bands
  # Initialize an empty matrix where all neighbours' details will be stored
  # Retrieve all neighbours' ids, i.e. the ids of all documents that have been hashed 
  # to the same bucket with the document in question in any of the bands
  bucket_ids <- s2_lsh[ s2_lsh[,1] == document, ]
  neighbours <- matrix()
  neighbours_list <- c()
  for( i in 2: length(bucket_ids)) {
    neighbours_list <- c(neighbours_list, s2_lsh[s2_lsh[,i] == as.character(bucket_ids[i]),1])
  }
  neighbours <- as.data.frame(as.matrix(unique(neighbours_list[neighbours_list != document])))
  names(neighbours) <- c("ID")
  
  # Inform the user if the document has no neighbours
  if (nrow(neighbours) == 0){
    print("No Neighbours found!")
  }
  else{
    # For all found neighbours, compute original and signature similarity to the given document
    neighbours_OS <- c()
    neighbours_SS <- c()
    for (i in 1: nrow(neighbours)) {
      N <- as.integer(neighbours$ID[i])
      Orig_numenator    <- length(intersect(unlist(s2[which(id == document)]),unlist(s2[which(id == N)])))
      Orig_denominator  <- length(union(unlist(s2[which(id == document)]),unlist(s2[which(id == N)]))) 
      neighbours_OS     <- c(neighbours_OS, 100*Orig_numenator/Orig_denominator)
      Sig_numerator     <- length(intersect(as.list(s2_minhash[which(s2_minhash[,1] == document), 2:(h+1)]),
                                            as.list(s2_minhash[which(s2_minhash[,1] == N), 2:(h+1)])))
      Sig_denominator   <- length(union(as.list(s2_minhash[which(s2_minhash[,1] == document), 2:(h+1)]),
                                        as.list(s2_minhash[which(s2_minhash[,1] == N), 2:(h+1)])))
      neighbours_SS     <- c(neighbours_SS, 100*Sig_numerator/Sig_denominator)
    }
    neighbours <- cbind(neighbours,neighbours_OS,neighbours_SS)
    names(neighbours) <- c("ID", "OS", "SS")
    
    # Sort neighbours' information by descending signature similarity order
    neighbours <- neighbours[order(-neighbours$SS),]
    
    # Print n nearest neighbours, unless total number of neighbours is less than n
    # In that case, print all found neighbours
    for (i in 1:min(nrow(neighbours), n)) {
      N <- as.integer(neighbours$ID[i])
      print(paste("Neighbour ID:", N, sep = " "))
      print(paste("Signature Similarity:", round(neighbours$SS[i], 3),"%", sep = " "))
      print(paste("Original Similarity:", round(neighbours$OS[i], 3),"%", sep = " "))
      print("Neighbour BODY:")
      print(df[df$ID == N, 2])
      cat("\n")
    }
    print(paste(replicate(100, "*"), collapse = ""))
  }
}

# Execute the function for given document and number of neighbours
NearestNeighbours(query_doc, nn)


# Retrieve actual neighbours for false positive/negative analysis

ActualNearestNeighbours <- function(document, kk) {
  # Print query details
  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")
  print(paste("Query Document ID:", document, sep = " "))
  print("Query Document BODY:")
  print(df[df$ID == document, 2])
  cat("\n")
  print(paste("Number of words per shnigle:", kk, sep = " "))
  cat("\n")
  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")
  
  # For all documents, compute original similarity to the given document
  actual_neighbours <- as.data.frame(as.matrix(id[]))
  names(actual_neighbours) <- c("ID")
  actual_neighbours_OS <- c()
  for (i in 1: nrow(actual_neighbours)) {
    N <- actual_neighbours$ID[i]
    Orig_numenator    <- length(intersect(unlist(s2[which(id == document)]),unlist(s2[which(id == N)])))
    Orig_denominator  <- length(union(unlist(s2[which(id == document)]),unlist(s2[which(id == N)]))) 
    actual_neighbours_OS     <- c(actual_neighbours_OS, 100*Orig_numenator/Orig_denominator)
  }
  actual_neighbours <- cbind(actual_neighbours,actual_neighbours_OS)
  names(actual_neighbours) <- c("ID", "OS")
  actual_neighbours <-actual_neighbours[actual_neighbours$ID != document ,]
  
  # Print number of actual neighbours per similarity level
  print(paste("Actual neighbours with similarity above 90%:", sum(actual_neighbours$OS>=90), sep = " "))
  cat("\n")
  print(paste("Actual neighbours with similarity above 80%:", sum(actual_neighbours$OS>=80 
                                                                  & actual_neighbours$OS<90), sep = " "))
  cat("\n")
  print(paste("Actual neighbours with similarity above 70%:", sum(actual_neighbours$OS>=70 
                                                                  & actual_neighbours$OS<80), sep = " "))
  cat("\n")
  print(paste("Actual neighbours with similarity above 60%:", sum(actual_neighbours$OS>=60 
                                                                  & actual_neighbours$OS<70), sep = " "))  
  cat("\n")
  print(paste("Actual neighbours with similarity above 50%:", sum(actual_neighbours$OS>=50 
                                                                  & actual_neighbours$OS<60), sep = " ")) 
  cat("\n")
  print(paste("Actual neighbours with similarity above 10%:", sum(actual_neighbours$OS>=10 
                                                                  & actual_neighbours$OS<50), sep = " ")) 
  cat("\n")
  print(paste(replicate(100, "*"), collapse = ""))
}

# Execute the function for given document
ActualNearestNeighbours(query_doc, k)

##############################################################################

# Stopping the clock
end_time <- Sys.time()

# Compute total execution time for the given set of parameters
time_taken <- c(k, h, band_size, end_time - start_time)
time_taken

##############################################################################

##############################################################################
#                   Appendix: Summary of functions used
##############################################################################

# 1
Shingling <- function(document, k) {
  shingles <- character( length = length(document) - k + 1 )
  for( i in 1:( length(document) - k + 1 )) {
    shingles[i] <- paste( document[ i:(i + k - 1) ], collapse = " " )
  }
  return( unique(shingles) )  
}

# 2
Hashing <- function(document) {
  hash <- c()
  hash <- lapply(document, function(x) {Dictionary[[x]]})
  return(hash)
}

# 3
Minhashing <- function(document) {
  minhash <- c()
  a <- params[2*i-1]
  b <- params[2*i]
  minhash <- lapply(document, function(x){(((a%%c)*(x%%c))%%c+(b%%c))%%c})
  m <- min(unlist(minhash))
  return(m)
}

# 4
Lsh <- function(document) {
  bucket <- c() 
  for (i in 1: band_number) {
    start <- 2 + (i-1)*band_size
    if (start + band_size - 1 > s2_cols) {
      end <- s2_cols
    } else {
      end <- start + band_size - 1
    }
    bucket[i] <- digest(object = paste(document[start:end], collapse = "_"),  algo = "crc32")
  }
  return(bucket)  
}

# 5
NearestNeighbours <- function(document, n) {

  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")
  print(paste("Query Document ID:", document, sep = " "))
  print(paste("Requested Number of Neighbours:", n, sep = " "))
  print("Query Document BODY:")
  print(df[df$ID == document, 2])
  cat("\n")
  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")

  bucket_ids <- s2_lsh[ s2_lsh[,1] == document, ]
  neighbours <- matrix()
  neighbours_list <- c()
  for( i in 2: length(bucket_ids)) {
    neighbours_list <- c(neighbours_list, s2_lsh[s2_lsh[,i] == as.character(bucket_ids[i]),1])
  }
  neighbours <- as.data.frame(as.matrix(unique(neighbours_list[neighbours_list != document])))
  names(neighbours) <- c("ID")

  if (nrow(neighbours) == 0){
    print("No Neighbours found!")
  }
  else{
    neighbours_OS <- c()
    neighbours_SS <- c()
    for (i in 1: nrow(neighbours)) {
      N <- as.integer(neighbours$ID[i])
      Orig_numenator    <- length(intersect(unlist(s2[which(id == document)]),unlist(s2[which(id == N)])))
      Orig_denominator  <- length(union(unlist(s2[which(id == document)]),unlist(s2[which(id == N)]))) 
      neighbours_OS     <- c(neighbours_OS, 100*Orig_numenator/Orig_denominator)
      Sig_numerator     <- length(intersect(as.list(s2_minhash[which(s2_minhash[,1] == document), 2:(h+1)]),
                                            as.list(s2_minhash[which(s2_minhash[,1] == N), 2:(h+1)])))
      Sig_denominator   <- length(union(as.list(s2_minhash[which(s2_minhash[,1] == document), 2:(h+1)]),
                                        as.list(s2_minhash[which(s2_minhash[,1] == N), 2:(h+1)])))
      neighbours_SS     <- c(neighbours_SS, 100*Sig_numerator/Sig_denominator)
    }
    neighbours <- cbind(neighbours,neighbours_OS,neighbours_SS)
    names(neighbours) <- c("ID", "OS", "SS")

    neighbours <- neighbours[order(-neighbours$SS),]

    for (i in 1:min(nrow(neighbours), n)) {
      N <- as.integer(neighbours$ID[i])
      print(paste("Neighbour ID:", N, sep = " "))
      print(paste("Signature Similarity:", round(neighbours$SS[i], 3),"%", sep = " "))
      print(paste("Original Similarity:", round(neighbours$OS[i], 3),"%", sep = " "))
      print("Neighbour BODY:")
      print(df[df$ID == N, 2])
      cat("\n")
    }
    print(paste(replicate(100, "*"), collapse = ""))
  }
}

# 6
ActualNearestNeighbours <- function(document, kk) {

  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")
  print(paste("Query Document ID:", document, sep = " "))
  print("Query Document BODY:")
  print(df[df$ID == document, 2])
  cat("\n")
  print(paste("Number of words per shnigle:", kk, sep = " "))
  cat("\n")
  print(paste(replicate(100, "*"), collapse = ""))
  cat("\n")
  
  actual_neighbours <- as.data.frame(as.matrix(id[]))
  names(actual_neighbours) <- c("ID")
  actual_neighbours_OS <- c()
  for (i in 1: nrow(actual_neighbours)) {
    N <- actual_neighbours$ID[i]
    Orig_numenator    <- length(intersect(unlist(s2[which(id == document)]),unlist(s2[which(id == N)])))
    Orig_denominator  <- length(union(unlist(s2[which(id == document)]),unlist(s2[which(id == N)]))) 
    actual_neighbours_OS     <- c(actual_neighbours_OS, 100*Orig_numenator/Orig_denominator)
  }
  actual_neighbours <- cbind(actual_neighbours,actual_neighbours_OS)
  names(actual_neighbours) <- c("ID", "OS")
  actual_neighbours <-actual_neighbours[actual_neighbours$ID != document ,]
  
  print(paste("Actual neighbours with similarity above 90%:", sum(actual_neighbours$OS>=90), sep = " "))
  cat("\n")
  print(paste("Actual neighbours with similarity above 80%:", sum(actual_neighbours$OS>=80 
                                                                  & actual_neighbours$OS<90), sep = " "))
  cat("\n")
  print(paste("Actual neighbours with similarity above 70%:", sum(actual_neighbours$OS>=70 
                                                                  & actual_neighbours$OS<80), sep = " "))
  cat("\n")
  print(paste("Actual neighbours with similarity above 60%:", sum(actual_neighbours$OS>=60 
                                                                  & actual_neighbours$OS<70), sep = " "))  
  cat("\n")
  print(paste("Actual neighbours with similarity above 50%:", sum(actual_neighbours$OS>=50 
                                                                  & actual_neighbours$OS<60), sep = " ")) 
  cat("\n")
  print(paste("Actual neighbours with similarity above 10%:", sum(actual_neighbours$OS>=10 
                                                                  & actual_neighbours$OS<50), sep = " ")) 
  cat("\n")
  print(paste(replicate(100, "*"), collapse = ""))
}


