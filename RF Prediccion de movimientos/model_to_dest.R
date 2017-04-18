setwd("C:/Users/Ordenador/Desktop/MODEL/Datos")
library(mlbench)
library(caret)
library(randomForest)
library(Hmisc)
library(h2o)
h2o <- h2o.init()

journeys <- read.csv2("hack4good_journeys.csv", sep=',')
mun_dep <- read.csv2("CO_ids_nombres.csv", sep=';')

model_pred_to_dest <- function(dpto)
{
  # ID de los departamentos a predecir
  id <- unique(mun_dep$id_dpto[which(mun_dep$nombre_dpto==dpto)])
  
  # Seleccionamos los departamentos de destino de los departamentos a predecir
  # Predecir cuantos se van al dpto
  journeys_slc <- journeys[which(journeys$cod_mpio_destination==id),] #
  
  if (length(journeys_slc$date_dt) > 0){
    # Formato de las fechas
    journeys_slc$date_dt <- as.Date(journeys_slc$date_dt)
    
    # División en training y test sets de acuerdo a la fecha
    test <- journeys_slc[which(journeys_slc$date_dt>='2015-04-15'), ]
    train <- journeys_slc[which(journeys_slc$date_dt<'2015-04-15'), ]
    train <- train[order(train[,3]), ]
    test <- test[order(test[,3]), ]
    cod_mpio_destinations <- unique(train$cod_mpio_origin)
    
    # Inclusión de retardos en los desplazamientos en el training set
    TRAIN <- list()
    
    for (j in 1:length(cod_mpio_destinations)){
      if (cod_mpio_destinations[j] %in% train$cod_mpio_origin){
        train_dest <- train[which(train$cod_mpio_origin == cod_mpio_destinations[j]), ]
        for (i in 1:7){
          colname = paste('lag',i)
          train_dest[colname] <- NA
          train_dest[colname] <- Lag(train_dest$journeys, i)
          train_dest[colname] <- NA
          train_dest[colname] <- Lag(train_dest$journeys, i)
        }
      }
      TRAIN[[j]] <- train_dest
    }
    
    # Inclusión de retardos en los desplazamientos en el test set
    TEST <- list()
    
    for (j in 1:length(cod_mpio_destinations)){
      if (cod_mpio_destinations[j] %in% test$cod_mpio_origin){
        test_dest <- test[which(test$cod_mpio_origin == cod_mpio_destinations[j]),]
        for (i in 1:7){
          colname = paste('lag',i)
          test_dest[colname] <- NA
          test_dest[colname] <- Lag(test_dest$journeys, i)
          test_dest[colname] <- NA
          test_dest[colname] <- Lag(test_dest$journeys, i)
        }
      }
      TEST[[j]] <- test_dest
    }
    
    # Combinamos el TRAIN  y TEST
    train <- do.call(rbind.data.frame, TRAIN)
    test <- do.call(rbind.data.frame, TEST)
    
    # Seleccionamos las variables independientes y dependientes
    predictors <- colnames(train[, !(names(train) %in% c('journeys','people','cod_mpio_destination'))])
    target <- 'journeys'
    
    # Creamos un training y un test set del training set original
    train.train <- train[1:round(nrow(train)*0.8), ]
    train.test <- train[round(nrow(train)*0.8):nrow(train), ]
    
    # Cargamos estos datos en la nube de H2O
    train.train.frame <- as.h2o(train.train, cod_mpio_destination_frame = "train.train")
    train.test.frame <- as.h2o(train.test, cod_mpio_destination_frame = "train.test")
    
    # Random Forest sobre el train.train set
    rf.train = h2o.randomForest(
      x = predictors,
      y = target,
      training_frame = train.train.frame,
      validation_frame = NULL,
      model_id = "rf_train",
      ntrees = 500, mtries = 8)
    
    # Predicciones y residuales
    test.pred <- as.data.frame(h2o.predict(rf.train, train.test.frame))
    resid.test <- train.test$journeys - test.pred$predict
    
    # Cargamos los datos del training set completo en la nube de H2O
    train.frame <- as.h2o(train, cod_mpio_destination_frame = "train")
    
    # Random Forest sobre el training set completo
    rf.trainf = h2o.randomForest(
      x = predictors,
      y = target,
      training_frame = train.frame,
      validation_frame = NULL,
      model_id = "rf_train_tot",
      ntrees = 500, mtries = 6)
    
    # Cargamos los datos del test set completo en la nube de H2O
    test.frame <- as.h2o(test, cod_mpio_destination_frame = "test")
    
    # Predicciones y resultados finales
    predictions.rf <- as.data.frame(h2o.predict(rf.trainf, test.frame))
    resid.test <- test$journeys - predictions.rf$predict
    
    FINAL <- list(depart = dpto, mae = mean(abs(resid.test)))
  }
  else{ FINAL <- list()}
  
}

# Seleccionamos los departamentos a predecir
DEPT <- unique(mun_dep$nombre_dpto)[2]

RESULTS <- list()
# Ojo! No podemos llamar infinitamente a h20, tenemos que hacerlo paulatinamente

for (i in 1:length(DEPT)) {
  dept <- DEPT[i]
  RESULTS[[i]] <- model_pred_to_dest(dept)
}

RESULTS
