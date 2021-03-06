suppressPackageStartupMessages({
  library(shiny)
  library(tidyr) 
  library(ggplot2) 
  library(DESeq2)
  library(edgeR)
  library(iheatmapr)
  library(tidyverse)
  library(readr)
  library(dplyr)
  library(shinyjs)
  library(plotly)
  library(shinythemes)
  library(shinyBS)
  library(apeglm)
  library(ashr)
  library("plotly")
  
})
# options(repos = BiocInstaller::biocinstallRepos())

options(shiny.maxRequestSize=1024^3) # Max file upload 1GB 

# default input file
all_cell_lines <- read_csv("ensembleid.csv", col_names = TRUE) ##read in data going to view

# Load gene information data
load("hg38.rda") # human
load("GRCm38.rda") # mouse

transforms <- c("raw counts", 
                "row normalized", 
                "logCPM", 
                "vst",
                "rlog") ##adding "t-score" -> row normalized, ask michelle about normalizing with FTSEC lines, have to add log(CPM+1)

sortby <- c("-no selection-",
            "mean", 
            "standard deviation")
cell.line.clusters <- c("All genes", 
                        "Selected genes") ##do this for cell line cluster heatmaps, changed all to filtered, should "all" be an option?

# This will be used to parse the text areas input
# possibilities of separation , ; \n
parse.textarea.input <- function(text){
  sep <- NULL
  if(grepl(";",text)) sep <- ";"
  if(grepl(",",text)) sep <- ","
  if(grepl("\n",text)) sep <- "\n"
  if(is.null(sep)) {
    text <- text
  } else {
    text <- unlist(stringr::str_split(text,sep))
  }
  return (text)
}


createTable2 <- function(df,tableType = "GENAVi", show.rownames = TRUE){
  DT::datatable(df,
                extensions = c('Buttons',"FixedHeader"),
                class = 'cell-border stripe',
                options = list(dom = 'Blfrtip',
                               buttons =
                                 list('colvis', list(
                                   extend = 'collection',
                                   buttons = list(list(extend='csv',
                                                       filename = tableType),
                                                  list(extend='excel',
                                                       filename = tableType),
                                                  list(extend='pdf',
                                                       title = "",
                                                       filename= tableType)),
                                   text = 'Download'
                                 )),
                               fixedHeader = FALSE,
                               pageLength = 20,
                               scrollX = TRUE,
                               lengthMenu = list(c(10, 20, -1), c('10', '20', 'All'))
                ),
                rownames = show.rownames,
                filter   = 'top'
  )
}

createTable <- function(df,selected_rows=NULL,tableType = "GENAVi", show.rownames = FALSE, hide.first.col = TRUE){
  DT::datatable(df,
                extensions = c('Buttons',"FixedHeader"),
                class = 'cell-border stripe',
                selection = list(mode = "multiple", target= 'row', selected = selected_rows),
                options = list(dom = 'Blfrtip',
                               columnDefs = list(
                                 list(visible=FALSE, targets=c(0))
                               ),
                               order = c(0,"desc"),
                               deferRender = TRUE,
                               paging = T,
                               buttons =
                                 list('colvis', list(
                                   extend = 'collection',
                                   buttons = list(list(extend='csv',
                                                       filename = tableType),
                                                  list(extend='excel',
                                                       filename = tableType),
                                                  list(extend='pdf',
                                                       title = "",
                                                       filename= tableType)),
                                   text = 'Download'
                                 )),
                               fixedHeader = FALSE,
                               pageLength = 20,
                               scrollX = TRUE,
                               lengthMenu = list(c(10, 20, -1), c('10', '20', 'All'))
                ),
                rownames = show.rownames,
                filter   = 'top'
  )
}

rownorm <- function(counts.filtered)
{
  rownorm.tbl <-  (counts.filtered - rowMeans(counts.filtered,na.rm = TRUE)) / apply(counts.filtered,1,sd)
  colnames(rownorm.tbl) <- colnames(counts.filtered)
  rownorm.tbl
}

getEndGeneInfo <- function(data){
  numeric.cols <-   sum(sapply(colnames(data), function(x) {class(data[[x]]) %in% c("integer","numeric")}))
  if(ncol(data) - numeric.cols > 2) { # we have metadata
    idx <- sum(ifelse(grepl("Start",colnames(data),ignore.case = T),class(data[[grep("Start",colnames(data),ignore.case = T)]]) == "integer",0),
               ifelse(grepl("End",colnames(data),ignore.case = T),class(data[[grep("End",colnames(data),ignore.case = T)]]) == "integer",0),
               ifelse(grepl("Chr",colnames(data),ignore.case = T),class(data[[grep("Chr",colnames(data),ignore.case = T)]]) == "integer",0),
               ifelse(grepl("Strand",colnames(data),ignore.case = T),class(data[[grep("Strand",colnames(data),ignore.case = T)]]) == "integer",0),
               ifelse(grepl("Length",colnames(data),ignore.case = T),class(data[[grep("Length",colnames(data),ignore.case = T)]]) == "integer",0))
    ngene <- ncol(data) - numeric.cols + idx
  } else {
    nsamples <- ncol(data) - 1 
    data <- addgeneinfo(data) 
    ngene <-  ncol(data) - nsamples 
  }
  return(list(data = data,ngene = ngene))
}

addgeneinfo <- function(data){
  id <- data %>% pull(1)
  if(all(grepl("ENSG",id))) {
    colnames(data)[1] <- "EnsemblID"
    aux <- strsplit(data$EnsemblID,"\\.")
    data$EnsemblID <- as.character(unlist(lapply(aux,function(x) x[1])))
    data <- merge(hg38,data,by = "EnsemblID")
  } else if(any(id %in% hg38$Symbol)) {
    colnames(data)[1] <- "Symbol"
    data <- merge(hg38,data,by = "Symbol")
  } else  if(all(grepl("ENSMUSG",id))) { # Mouse
    colnames(data)[1] <- "EnsemblID"
    aux <- strsplit(data$EnsemblID,"\\.")
    data$EnsemblID <- as.character(unlist(lapply(aux,function(x) x[1])))
    data <- merge(GRCm38,data,by = "EnsemblID")
  } else if(any(id %in% GRCm38$Symbol)) {
    colnames(data)[1] <- "Symbol"
    data <- merge(GRCm38,data,by = "Symbol")
  } else {
    # we were not able to identify the genome
    return(data) 
  }
  return(data)
}

help_text <-  '<div class="panel panel-default">
  <div class="panel-heading"> <span style="padding-left:10px"><b> Input file description</b> </span></div>
<div class="panel-body">
<style type="text/css">
.tg {
border-collapse: collapse;
border-spacing: 0;
border: none;
}
.tg td {
font-family: Arial, sans-serif;
font-size: 14px;
padding: 10px 5px;
border-style: solid;
border-width: 0px;
overflow: hidden;
word-break: normal;
}
.tg th {
font-family: Arial, sans-serif;
font-size: 14px;
font-weight: normal;
padding: 10px 5px;
border-style: solid;
border-width: 0px;
overflow: hidden;
word-break: normal;
}
.tg .tg-s6z2 {
text-align: center
}
</style>
<table class="tg">
<tr>
<th class="tg-031e"> <span class="label label-default"> Format</span></th>
<th class="tg-031e"> comma-separated values (CSV)
</tr>
<tr>
<th class="tg-031e"> <span class="label label-default"> Column 1</span></th>
<th class="tg-031e"> Gene Identifier -  Gene symbol or ENSEMBL ID
</tr>
<tr>
<th class="tg-031e"> <span class="label label-default"> Column 2-n</span></th>
<th class="tg-031e"> Gene expression raw counts </th>
</tr>
<tr>
</table>
</div>
</div>'

help_text2 <-  '<div class="panel panel-default">
  <div class="panel-heading"> <span style="padding-left:10px"><b> Input file description</b> </span></div>
<div class="panel-body">
<style type="text/css">
.tg {
border-collapse: collapse;
border-spacing: 0;
border: none;
}
.tg td {
font-family: Arial, sans-serif;
font-size: 14px;
padding: 10px 5px;
border-style: solid;
border-width: 0px;
overflow: hidden;
word-break: normal;
}
.tg th {
font-family: Arial, sans-serif;
font-size: 14px;
font-weight: normal;
padding: 10px 5px;
border-style: solid;
border-width: 0px;
overflow: hidden;
word-break: normal;
}
.tg .tg-s6z2 {
text-align: center
}
</style>
<table class="tg">
<tr>
<th class="tg-031e"> <span class="label label-default"> Format</span></th>
<th class="tg-031e"> comma-separated values (CSV)
</tr>
<tr>
<th class="tg-031e"> <span class="label label-default"> Column 1</span></th>
<th class="tg-031e"> Sample ID (same from raw counts data)
</tr>
<tr>
<th class="tg-031e"> <span class="label label-default"> Column 2-n</span></th>
<th class="tg-031e"> Other metadata (condition, covariates) </th>
</tr>
<tr>
</table>
</div>
</div>'