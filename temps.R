

##Obtain DF and make factors a numeric variables as appropiate 

file.choose()
library(foreign)
tempsdata <- read.spss("J:\\psych\\Neurocognition Lab\\Heterogeneity\\Data_Heterogeneity\\TEMPS machine learning project\\Temps_pure.sav", 
                       to.data.frame=TRUE)

library(dplyr)
temps <- subset(tempsdata, select = -c(gender, race, diagnosis))
temps <- as.data.frame(lapply(temps, as.numeric))

tempsfac <- select(tempsdata, id, gender, race, diagnosis)
tempstot <- full_join(temps, tempsfac, by = "id")
head(tempstot)
str(tempstot$diagnosis)


##Removing ID, wrat3
tempstot$id <- NULL
tempstot$wrat3_raw <- NULL
tempstot$wrat3_standard <- NULL
head(tempstot)


##Training and testing the model

tempstot <- na.omit(tempstot)
head(tempstot)

set.seed(1)
trainIndex <- createDataPartition(tempstot$diagnosis, p = .8,
                                  list = FALSE, times = 1)
trainIndex %>% head()

training.y <- tempstot[trainIndex, "diagnosis"]
testing.y <- tempstot[-trainIndex, "diagnosis"]

training <- tempstot %>%
  select(-matches("diagnosis")) %>%
  slice(trainIndex)

testing <- tempstot %>%
  select(-matches("diagnosis")) %>%
  slice(-trainIndex)
str(training)


##Dimension reduction via zero-variance

nzv <- nearZeroVar(training)
if(length(nzv) >0) {
  training <- training[, -nzv];
  testing <- testing[, -nzv]
}
dim(testing)
dim(temps)


##Since some predictors are factors:
sapply(training, is.factor) # shows which are factors
f.pos <- which( sapply(training, is.factor) ) # finds position of factors
f.pos

#split to two data frames - one with factors, another with numbers
training.f <- select(training, f.pos)
training.n <- select(training, -f.pos)
testing.f <- select(testing, f.pos)
testing.n <- select(testing, -f.pos)


##Complete some analysis with numerics only

preProcValues <- preProcess(training.n, method = c("center", "scale", "knnImpute",
                                                   "YeoJohnson"))
training.n <- predict(preProcValues, training.n)
testing.n <- predict(preProcValues, testing.n)

##Correlations

descrCor <- cor(training.n)
highlyCorDescr <- findCorrelation(descrCor, cutoff = .75)

if(length(highlyCorDescr) >0) {
  training <- training[, -highlyCorDescr];
  testing <- testing[, -highlyCorDescr]
}


##Linear Dependencies

comboInfo <- findLinearCombos(training.n)
comboInfo

if(length(comboInfo$remove) >0) {
  training.n <- training.n[, -comboInfo$remove];
  testing.n <- testing.n[, -comboInfo$remove]
}

##Combine them back

head(training.n)
head(testing.n)
head(training.f)
head(testing.f)
training.full <- cbind(training.n, training.f)
testing.full <- cbind(testing.n, testing.f)
str(training.full)

##Compute dummy variables for factor variables

dummies <- dummyVars(~ ., data = training.full, sep = "__") 
training.full <- data.frame( predict(dummies, training.full)) 
testing.full <- data.frame( predict(dummies, testing.full) ) 

dim(training.full)
nrow(training.full)/ncol(training.full)

##I have .98 observations per factor; need to reduce (LASSO)

##Do logistic regression (using all predictors (n=115))

training.full$diagnosis <- training.y 
testing.full$diagnosis <- testing.y 
glm <- glm(diagnosis~., family=binomial(), data=training.full)
summary(glm)

length(coef(glm))

library(stringr); library(dplyr) 
c.n <- names(coef(glm))
c.n %>%
  subset( str_detect( c.n, pattern = "__") ) %>% str_split_fixed("__", n=2) %>%
  data.frame() %>%
  select(1) %>%
  unique()

shapiro.test(glm$residuals)

library(car) 
durbinWatsonTest(glm)

##LASSO REGRESSION

enetGrid <- expand.grid(.alpha = c(1), 
                        .lambda = seq(0, 20, by = 0.1))

########################################## training model 
ctrl <- trainControl(method = "cv", number = 10,
                     verboseIter = T)
set.seed(1)
enetTune <- train(diagnosis ~ ., data = training.full,
                  method = "glmnet",
                  tuneGrid = enetGrid,
                  trControl = ctrl)

enetTune
enetTune$bestTune
plot(enetTune)

#which predictors have zero-coefficients?

fin_model <- enetTune$finalModel
#which are non-zero
non.zero.ind <- predict(fin_model, s = enetTune$bestTune$lambda,
                        type = "nonzero")
non.zero.ind

enetCoef <- predict(fin_model, s = enetTune$bestTune$lambda, 
                    type = "coef" )
enetCoef[1:20, ]

enetCoef[enetCoef != 0] %>% head
as.matrix(enetCoef) %>% head

##Rerun regression with lasso subset of predictors

training.full.subset <- data.frame( 
  training.full[, unlist(non.zero.ind) ], 
  diagnosis = training.full$diagnosis)
dim(training.full.subset)

glm2 <- glm(diagnosis~., family=binomial(), data=training.full.subset)
summary(glm2)

library(stringr); library(dplyr) 
c.n <- names(coef(glm2))
c.n %>%
  subset( str_detect( c.n, pattern = "__") ) %>% 
  str_split_fixed("__", n=2) %>%
  data.frame() %>%
  select(1) %>%
  unique()

plot(glm2)
shapiro.test(glm2$residuals)

library(car) 
durbinWatsonTest(lmFit2)

##Using testing set:

testing.full.subset <- data.frame( 
  testing.full[, unlist(non.zero.ind) ], 
  diagnosis = testing.full$diagnosis)
dim(testing.full.subset)

glm3 <- glm(diagnosis~., family=binomial(), data = testing.full.subset) 
summary(glm3)

plot(glm3)
shapiro.test(glm3$residuals)

library(car) 
durbinWatsonTest(lmFit3)
