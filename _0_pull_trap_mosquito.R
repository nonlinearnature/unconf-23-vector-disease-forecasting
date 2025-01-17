library(duckdbfs)
library(neonstore)
library(dplyr)
library(lubridate)

if(!file.exists("./DATA/PROCESSED/mos_individualCount_all_sites.Rdata")){
  df <-  neonstore:::neon_data(product = "DP1.10043.001",
                               start_date = "2014-01-01", 
                               end_date = "2022-01-01",
                               site = NA,
                               type="basic"
  )
}else{
  load("./DATA/PROCESSED/mos_individualCount_all_sites.Rdata")
}

urls_samp <- df |>
  dplyr::filter(grepl("mos_sorting", name)) |>
  pull(url)

ds_samp <- duckdbfs::open_dataset(urls_samp,
                                  format="csv",
                                  filename = TRUE,
                                  unify_schemas = FALSE) %>%
  select(siteID,plotID,setDate,collectDate,subsampleID,proportionIdentified)

df_samp <- ds_samp %>% collect()

urls_expert <- df |>
  dplyr::filter(grepl("mos_expertTaxonomistIDProcessed", name)) |>
  pull(url)

ds_expert <- duckdbfs::open_dataset(urls_expert,
                                    format="csv",
                                    filename = TRUE,
                                    unify_schemas = FALSE) %>%
  select(subsampleID, sex, genus, taxonID, scientificName, individualCount)
  
v_scientific_name <- c(`Culex tarsalis`="CULTAR",`Culex pipiens`="CULPIP")

# NEED FIX: this is getting rid of true 0s.
df_expert_Culex <- ds_expert %>%
  filter(sex=="F") %>%
  group_by(subsampleID) %>%
  # filter(genus=="Culex") %>%
  collect()


df_expert_summary <-  df_expert_Culex %>%
  summarise(mos_all = sum(individualCount),na.rm=T,
            mos_Culex_all = sum(individualCount * (genus=="Culex"),na.rm=T),
            mos_Culex_tarsalis = sum(individualCount * (taxonID=="CULTAR"),na.rm=T),
            mos_Culex_pipiens = sum(individualCount * (taxonID=="CULPIP"),na.rm=T))

df_total_counts_by_plot <- right_join(df_samp,df_expert_summary,by="subsampleID") %>%
  mutate(across(starts_with("mos"), ~./proportionIdentified)) %>%
  filter(proportionIdentified>0) %>% # proportionIdentified = 0 for a few measurements but makes no sense.
  select(-proportionIdentified)
  
df_total_counts_by_site <- df_total_counts_by_plot %>%
  mutate(Month = month(collectDate),Year = year(collectDate)) %>%
  group_by(siteID,Year,Month) %>%
  summarise(across(starts_with("mos"),mean),.groups = "keep") %>% # using "mean" to account for changing sampling effoort
  select(siteID,Year,Month,everything())

save(df,
     df_total_counts_by_plot,
     df_total_counts_by_site,
     file="./DATA/PROCESSED/mos_total_counts.Rdata")

# ds %>% select(siteID,setDate,collectDate,proportionIdentified)

# left join mos_expertTaxonomistIDProcessed with mos_sorting taking by subsampleID
# mos_sorting; subsampleID, proportionIdentified
# mos_expertTaxonomistIDProcessed; subsampleID, taxonID, scientificName, individualCount

