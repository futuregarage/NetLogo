library(tidyselect)
library(tidyverse)
library(plotly)

#set directory
setwd("~/SBM/Semester 3/Agent-based Modeling and Simulation/run result")

#read data
df <- read.table("truck arrival 1.0 30runs.csv", 
          header = T,   # set columns names true
          sep = ",",    # define the separator between       columns
          skip = 6,     # skip first 6 rows 
          quote = "\"", # correct the column separator
          fill = TRUE ) # add blank fields if rows )

head(df)

#subset only last tick
df_subset <- subset(df, X.step. == 14400, select = c("X.run.number.","crane.pick.goal.function","plot.wait","plot.idle"))

#attach dataframe
attach(df)

#set outliers
outliers <- boxplot(df$plot.wait)$out

#remove outliers
df_clean <- df[-which(df$plot.wait %in% outliers),]

# Box Plots
#plotting a Boxplot with plot.wait variable and storing it in box_plot
box_plot_wait <- plot_ly(y=plot.wait,
                    type='box',
                    color=crane.pick.goal.function)

#plotting a Boxplot with plot.crane variable and storing it in box_plot
box_plot_crane <- plot_ly(y=plot.crane,
                         type='box',
                         color=crane.pick.goal.function)

#defining labels and title using layout() wait time
layout(box_plot_wait,
       title = "TA = 1.0 - plot.wait",
       yaxis = list(title = "Average Wait Time"))

#defining labels and title using layout() wait time
layout(box_plot_crane,
       title = "TA = 1.0 - plot.crane",
       yaxis = list(title = "Movements per Truck Serviced"))

#summary
summary(df)

#How to use this code: example for plot.crane column
#
#set outliers fot plot.crane
#outliers <- boxplot(df$plot.crane)$out
#
#remove outliers
#df_clean <- df[-which(df$plot.crane %in% outliers),]
#
#attach new df
#attach(df)
#
#plotting a Boxplot with plot.crane variable and storing it in box_plot
#box_plot_crane <- plot_ly(y=plot.crane,
#                          type='box',
#                          color=crane.pick.goal.function)
#
#defining labels and title using layout() wait time
#layout(box_plot_crane,
#       title = "TA = 0.5",
#       yaxis = list(title = "Movements per Truck Serviced"))