Tiempos
-------

> {-# LANGUAGE GADTs
>            , GeneralizedNewtypeDeriving
>            , StandaloneDeriving
>            , DeriveDataTypeable
>            , TypeFamilies
>            #-}
> 

> module Sigym4.Dimension.Time (
>     Time(..)
>   , ForecastTime
>   , ObservationTime
>   , RunTime
>   , Horizon (..)
>   , Horizons
>   , Schedule (..)
> ) where

> import Data.String (IsString(fromString))
> import Data.Attoparsec.Text (parseOnly)
> import Data.Time.Clock (UTCTime(..), NominalDiffTime, addUTCTime)
> import Data.Time ()
> import Data.Typeable (Typeable)
> import System.Cron (CronSchedule, scheduleMatches)
> import System.Cron.Parser (cronSchedule)
> import GHC.Exts (IsList (..))
> import Data.List (sort, nub)
> import Sigym4.Dimension.Types

Preparamos el terreno para definir las dimensiones temporales creando tipos
para los distintos tipos de tiempo, todos son envoltorios de 'UTCTime'

 
ObservationTime es el tiempo asociado a una observación.

> newtype ObservationTime = ObsTime UTCTime
>   deriving (Eq, Ord, Show, Typeable)

RunTime es el tiempo asociado a cuando se realizó una pasada de un proceso
predictivo.

> newtype RunTime = RunTime UTCTime
>   deriving (Eq, Ord, Show, Typeable)

ForecastTime es el tiempo asociado a una prediccón hecha por un sistema
predictivo, es decir, la hora a la cual se predice una situación.

> newtype ForecastTime = FcTime UTCTime
>   deriving (Eq, Ord, Show, Typeable)


Para poder tener código agnostico al tipo de tiempo (pero sin perder la
información de tipado) definimos una clase 'Time' con operaciones
polimórificas.
 
> class (Show t, Eq t, Ord t) => Time t where
>     fromUTCTime :: UTCTime -> t
>     toUTCTime   :: t ->  UTCTime
>     addHorizon  :: Horizon -> t -> t
>     matches     :: Schedule t -> t -> Bool
>     matches (Schedule s) = (s `scheduleMatches`) . toUTCTime
>     {-# MINIMAL fromUTCTime, toUTCTime, addHorizon #-}



Hacemos los tipos de tiempo miembros de la clase 'Time' de manera
simétrica para cada tipo.

Notese que el tiempo se trunca al minuto más cercano limitando la resolución
temporal efectiva del sistema a 1 minuto.
Esta limitación se debe a que la implementación de la instancia de `Dimension`
para los `Time` que itera en incrementos fijos para encontrar los elementos
contiguos al dado en `dpred`, `dsucc`, `dfloor` y `dceiling`. Este incremento
tiene que se <= resolución temporal mínima y sería muy ineficiente hacerlo en
incrementos más finos. Innecesario también, ya que la la implementación de
`Schedule` es similar a cron que tampoco permite intervalos más finos.
En Sigym3 no ha dado problemas tener resolución de minuto, de hecho, la más fina
es cincominutal. 

> instance Time ObservationTime where
>     fromUTCTime = ObsTime . floorToMinute
>     toUTCTime (ObsTime t)  = t
>     addHorizon d (ObsTime t) = ObsTime (addUTCTime (toNominalDiffTime d) t)
> 
> instance Time ForecastTime where
>     fromUTCTime = FcTime . floorToMinute
>     toUTCTime (FcTime t)  = t
>     addHorizon d (FcTime t) = FcTime (addUTCTime (toNominalDiffTime d) t)
> 
> instance Time RunTime where
>     fromUTCTime = RunTime . floorToMinute
>     toUTCTime (RunTime t)  = t
>     addHorizon d (RunTime t) = RunTime (addUTCTime (toNominalDiffTime d) t)
> 
> floorToMinute :: UTCTime -> UTCTime
> floorToMinute (UTCTime d t) = UTCTime d t'
>     where t' = fromIntegral $ tr - (tr `mod` 60)
>           tr = round t :: Int
> 

Periodicidad
------------

Definimos un tipo para poder definir índices temporales periódicos.
 
> newtype Schedule t = Schedule CronSchedule deriving (Eq, Show, Typeable)

 
Lo hacemos de la clase `IsString` para poder escribir constantes como
cadenas de texto en formato de "cron". Ojo, dará error en ejecución
una cadena en formato incorrecto. Se puede arreglar con Template Haskell
parseando la cadena durante la compilación.

> instance IsString (Schedule t) where
>     fromString s = case parseOnly cronSchedule (fromString s) of
>                      Right r -> Schedule r
>                      Left  e -> error $ "fromString(Schedule): " ++ e
> 

Definimos una instancia de 'Dimension' para 'Schedule's de
cualquier tipo de tiempo. Ojo, es bastante ineficiente aunque en Sigym3 no es
de lo que más duele. Se podría mejorar inspeccionando el `CronSchedule` y
adaptando el delta en 'denumFromTo' una vez se encuentra un punto válido.

> instance Time t => Dimension (Schedule t) where
>     type DimensionIx (Schedule t) = t
>     delem t  s   = s `matches` t
>     dpred    s t = Just $ next s (-1) (addHorizon (-1) t)
>     dsucc    s t = Just $ next s 1    (addHorizon 1    t)
>     dfloor   s t = Just $ next s (-1) t
>     dceiling s t = Just $ next s 1    t
> 
> next :: Time t => Schedule t -> Horizon -> t -> t
> next s d = go 
>   where
>     go t | s `matches` t = t
>          | otherwise     = go (addHorizon d t)
> 

Horizontes
----------

Definimos un horizonte de predicción que representa un delta de tiempo en
distintas unidades.

> data Horizon = Minute !Int
>            | Hour   !Int
>            | Day    !Int
>   deriving (Show, Read, Typeable)

Definimos los minutos que contiene cada tipo de horizonte para poder normalizar
y operar con ellos.

> minutes :: Horizon -> Int
> minutes (Day d)    = d * 60 * 24
> minutes (Hour h)   = h * 60
> minutes (Minute m) = m

Definimos instancias para poder comparar horizontes.
 
> instance Eq Horizon where
>     Minute a == Minute b = a         == b
>     Hour a   == Hour b   = a         == b
>     Day a    == Day b    = a         == b
>     a        == b        = minutes a == minutes b
> 
> instance Ord Horizon where
>     Minute a `compare` Minute b = a         `compare` b
>     Hour a   `compare` Hour b   = a         `compare` b
>     Day a    `compare` Day b    = a         `compare` b
>     a        `compare` b        = minutes a `compare` minutes b

Definimos instancia de 'Num' para los horizontes para poder operar
como ellos como si fuesen números y para poder escribirlos como números. 

> instance Num Horizon where
>     Minute a + Minute b = Minute (a         + b        )
>     Hour a   + Hour b   = Hour   (a         + b        )
>     Day a    + Day b    = Day    (a         + b        )
>     a        + b        = Minute (minutes a + minutes b)
> 
>     Minute a * Minute b = Minute (a         * b        )
>     Hour a   * Hour b   = Hour   (a         * b        )
>     Day a    * Day b    = Day    (a         * b        )
>     a        * b        = Minute (minutes a * minutes b)
> 
>     Minute a - Minute b = Minute (a         - b        )
>     Hour a   - Hour b   = Hour   (a         - b        )
>     Day a    - Day b    = Day    (a         - b        )
>     a        - b        = Minute (minutes a - minutes b)
> 
>     negate (Minute a)   = Minute (negate a)
>     negate (Hour   a)   = Hour   (negate a)
>     negate (Day    a)   = Day    (negate a)
> 
>     abs    (Minute a)   = Minute (abs    a)
>     abs    (Hour   a)   = Hour   (abs    a)
>     abs    (Day    a)   = Day    (abs    a)
> 
>     signum (Minute a)   = Minute (signum a)
>     signum (Hour   a)   = Hour   (signum a)
>     signum (Day    a)   = Day    (signum a)
> 
>     fromInteger         = Minute . fromInteger

> toNominalDiffTime :: Horizon -> NominalDiffTime
> toNominalDiffTime = fromIntegral . (* 60) . minutes

Definimos un `newtype` para una lista de horizontes sin exportar su constructor.
Ésto lo hacemos para controlar su construcción en `fromList` la cual verifica
que no es una lista vacía para que el resto del código lo pueda asumir con
seguridad.

Encapsularlo con un `newtype` también permite poder cambiar la implementación
sin afectar al código que lo use, por ejemplo, si se da el caso de conjuntos
de muchos horizontes se puede cambiar la lista por un árbol binario que es
O(log n) en vez de O(n) en `dpred`, `dsucc`, `dfloor` y `dceiling`.

> newtype Horizons = Horizons [Horizon] deriving (Eq,Ord,Show,Read,Typeable)

Definimos una instancia de `IsList` para poder escribir constantes como listas
habilitando la extension `XOverloadedLists`. Ojo, dará error en tiempo de
ejecución una lista vacía, también se puede arreglar con TemplateHaskell.

> instance IsList Horizons where
>     type Item Horizons  = Horizon
>     fromList l
>         | null l    = error "fromList(Horizons): Cannot be an empty list"
>         | otherwise = Horizons . nub . sort $ l
>     toList (Horizons l) = l
 
A continuación se definen las instancias para que `Horizons` sea una dimensión
finita (`BoundedDimension`).
 
> instance Dimension Horizons where
>     type DimensionIx Horizons = Horizon
>     delem d (Horizons ds) = d `elem` ds
>     dpred (Horizons ds) d
>       = case dropWhile (>= d) (reverse ds) of
>           []    -> Nothing
>           (x:_) -> Just x
>     dsucc (Horizons ds) d
>       = case dropWhile (<= d) ds of
>           []    -> Nothing
>           (x:_) -> Just x
>     dfloor (Horizons ds) d
>       = case dropWhile (> d) (reverse ds) of
>           []    -> Nothing
>           (x:_) -> Just x
>     dceiling (Horizons ds) d
>       = case dropWhile (< d) ds of
>           []    -> Nothing
>           (x:_) -> Just x
> 
> instance BoundedDimension Horizons where
>     type Dependent Horizons = RunTime
>     dfirst (Horizons ds) = const $ head ds
>     dlast  (Horizons ds) = const $ last ds
>     denum  (Horizons ds) = const ds
