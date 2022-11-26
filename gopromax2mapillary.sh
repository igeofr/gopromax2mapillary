#!/bin/bash

# VARIABLES DATES
export DATE_YM=$(date "+%Y%m")
export DATE_YMD=$(date "+%Y%m%d")

# LECTURE DU FICHIER DE CONFIGURATION
. './config.env'

# REPERTOIRE DE TRAVAIL
cd $REPER
echo $REPER

# SUPPRESSION DES FICHIERS ET DOSSIERS
rm -r -f $REPER'/tmp/'*
rm -r -f $REPER'/out/'*
rm -r -f $REPER'/list/'*

# COPIE DES IMAGES
cp $REPER'/in/'*.* $REPER'/tmp/'

# EXTRACTION DES PARAMETRES IMG
exiftool -filename -gpstimestamp -gpsdatestamp -gpslatitude -gpslongitude -n -csv -r $REPER'/tmp' > './list/'$DATE_YMD'_img.csv'

# REPERTOIRE LIST
cd $REPER'/list'

# DETECTION DES IMAGES INUTILES
for csvfile in *.csv;
do
ogr2ogr -f "SQLite" -dsco SPATIALITE=YES  -lco LAUNDER=NO -oo X_POSSIBLE_NAMES=gpslongitude -oo Y_POSSIBLE_NAMES=gpslatitude ${csvfile%.*}.sqlite ${csvfile%.*}.csv
ogr2ogr -f CSV -dialect sqlite -sql 'WITH RECURSIVE clean_sequence as (
  SELECT g.*,
  cast(null as geometry) as aproximite,
  cast(null as integer) as id_ref,
  cast(null as real) AS distance
  FROM (SELECT * FROM conf LIMIT 1) g
  UNION ALL
  SELECT T.*,
    CASE
    WHEN C.aproximite IS NULL AND PtDistWithin(T.geom, C.geom,3) THEN T.geom_prev
    WHEN not (C.aproximite IS NULL) AND PtDistWithin(T.geom, C.aproximite,3) THEN C.aproximite
    ELSE NULL
    END as aproximite,
    CASE
    WHEN C.aproximite IS NULL AND PtDistWithin(T.geom, C.geom,3) THEN t.prev_val
    WHEN not (C.aproximite IS NULL) AND PtDistWithin(T.geom, C.aproximite,3) THEN C.id_ref
    ELSE NULL
    END as id_ref,
    CASE
    WHEN C.aproximite IS NULL AND PtDistWithin(T.geom, C.geom,3) THEN ST_Distance(T.geom, C.geom)
    WHEN not (C.aproximite IS NULL) AND PtDistWithin(T.geom, C.aproximite,3) THEN ST_Distance(T.geom, C.aproximite)
    ELSE NULL
    END as distance
    FROM clean_sequence as C
    INNER JOIN (SELECT * FROM conf) as T
    ON T.id_photo = C.id_photo + 1),
  conf AS (SELECT
    sourcefile,
    filename,
    substr(filename,1,4) as sequence,
    cast(substr(filename,5,4) AS integer) as id_photo,
    CAST(gpslatitude AS REAL) AS gpslatitude,
    CAST(gpslongitude AS REAL) AS gpslongitude,
    ST_Transform(SetSRID(MakePoint(CAST(gpslongitude AS REAL), CAST(gpslatitude AS REAL)), 4326),2154)as geom,
    LEAD(ST_Transform(SetSRID(MakePoint(CAST(gpslongitude AS REAL), CAST(gpslatitude AS REAL)), 4326),2154)) over (order by filename) AS geom_next,
    LAG(ST_Transform(SetSRID(MakePoint(CAST(gpslongitude AS REAL), CAST(gpslatitude AS REAL)), 4326),2154)) over (order by filename) AS geom_prev,
    LAG(cast(substr(filename,5,4) AS integer)) OVER (ORDER BY cast(substr(filename,5,4) AS integer)) AS prev_val,
    LEAD(cast(substr(filename,5,4) AS integer)) OVER (ORDER BY cast(substr(filename,5,4) AS integer)) AS next_val
  FROM "'${csvfile%.*}'" ORDER BY filename)
  SELECT sourcefile
   FROM clean_sequence WHERE NOT (aproximite IS NULL)
  ' ${csvfile%.*}"_a_sup.csv" ${csvfile%.*}".sqlite"

  rm ${csvfile}
  rm ${csvfile%.*}".sqlite"
done

# SUPPRESSION DES IMAGES INUTILES
for csvfile_sup in *.csv;
do
    sed 1d ${csvfile_sup} | xargs rm -f | bash
    rm ${csvfile_sup}
done

# APPLICATION DU LOGO
cd $REPER
rm -r -f $REPER'/out/'*
python3 nadir-patcher.py $REPER'/tmp' $REPER'/logo_ccpl.png' 17 $REPER'/out'
