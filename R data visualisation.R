library(tidyselect)
library(tidyverse)
library(plotly)

#set directory
setwd("~/SBM/Semester 3/Agent-based Modeling and Simulation/run result")

#read data
df <- read.table("TA_1x30.csv", 
          header = T,   # set columns names true
          sep = ",",    # define the separator between       columns
          skip = 6,     # skip first 6 rows 
          quote = "\"", # correct the column separator
          fill = TRUE ) # add blank fields if rows )

head(df)

#subset only last tick
df_subset <- subset(df, X.step. == 14400, select = c("X.run.number.","crane.pick.goal.function","plot.wait","plot.idle"))

#attach dataframe
attach(df_subset)

# Box Plots
#plotting a Boxplot with plot.wait variable and storing it in box_plot
box_plot <- plot_ly(y=plot.wait,
                    type='box',
                    color=crane.pick.goal.function)

#defining labels and title using layout()
layout(box_plot,
       title = "TA = 1.0",
       yaxis = list(title = "Average Wait Time"))
