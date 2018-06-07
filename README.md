# Document Similarity 
## Introduction 
The purpose of this project was to process a dataset of articles in order to measure similarity amongst thems, by implementing a variety of methods. The dataset under examination was the Reuters-21578 collection. The project was developed in R. 

Similarity between document can be defined as the percentage of their common components. One of the most frequent methodologies for this computation is the following:
- Step 1 - Shingling: Each document is broken down to its structural elements (shingles). In this implementation, each shingle contains k number of words. 
- Step 2 - Minhashing: For improved algorithm's performance, representative transformations of shingles (signatures) are extracted in a way that preserves similarity. 
- Step 3 - LSH: Signatures are appropriately used to map documents into bucjets so that similar documents are more likely to land withing the same bucket. 
-Step 4 - Document Comparison: Similarity is computed based on the assumption that only documents from the same bucket are likely to be similar  to each other. Hence, calculations are perfromed just for nearest neighbor's pairs. 

A commonly used metric for document comparison is Jaccard similarity, i.e. the ratio of the shared components between two different documents (intersection) to their total distinct number (union). Jaccard similarity can be computed with the use of either shingles ir signatures, since the main principle of minhashing is that the similarity of signatures is on expectation close to the similarity of shingles. 
