The 3 slide progression, briefly :

# 1

poster title, authors, attributions( LSMC url)



Plot title

The human 30x genome 

( ILMN nova 2x150, giabHC, gatk, HG003)



One plot: 

precision vs recall, plot each variant class, shape indicates class and fscore size of shape.



Message

 ( spoken, no slide text )



this is the colloquialy understood ‘30x genome’ . It has become increasingly uninformative to reduce assessing genomes this way for 2 reasons: 

1) in reality, there is a great deal of diversity of performance in these and many other metrics if we look at different treatments of the genome  

2) further, when taking an application centric approach to what one needs from a genome, the application dictates differing  metrics priorities.



# 2



Slide title



The human 30x genome -- Common Decision Gating Performance Characteristics 

( HG003, multiple platforms: Accuracy, time to result, cost)


One plot

X-axis: bins for performance metrics to assess a 30x genome:



Fscore ( all analysis platforms ), one category per genome build and variant class, so like  



Each category is a box plot of points, not yet revealing more than the y-axis distribution per category



##Y-axis Fscore

hg38-SNP

hg38-DEL_50

hg38-INS_50

hg38Hybrid-SNP

hg38Hybrid-DEL_50

hg38Hybrid-INS_50

hg38Pan-SNP

hg38Pan-DEL_50

hg38Pan-INS_50

where the x-axis key is <genomecode>-<variant class>

plot in the boxplot ALL data from all platforms and callers, but only from the 30x category


##Y-axis dollars

Secondary-analysis-cost 


## Time, hours

Time for sequencing 

Time for analysis pipeline 



message: these are just some of the criteria we can use to evaluate a 30x genome. Which, in contrast to the simplified 30x, has quite varied performance characteristics in any category you consider & your applications  will dictate prioritization of their importance.



# 3



 The human application centric human genome 

( HG003, multiple platforms & platform combos, multiple performance factors  by multiple depths )



Message: ( I’m not going to try and review the data , but make the point the 30x genome proxy for quality has served its purpose : depth of coverage ( and varied depths!)) is one of many factors that need to be considered in an application first world.



here I show the big heat map and a bottom slide tagline like: for more, visit the poster 
