lsat_prefix=lsat7_2002_
metadata_path=./nc_ls7.met
scale=1000

# topo.corr variables
# get numeric values from *.met file
# by the way "sun zenith" is derived from the following equation:
#       $sun_zenith = 90 - $sun_elevation
elevation='elevation@PERMANENT'
resampled_elevation=elevation
illumination=illumination
topo_method=c-factor
topo_prefix=T
resampling_method=average
sun_azimuth=120.8810347
sun_elevation=64.7730999
sun_zenith=25.2269001

# setup region
g.region raster=${lsat_prefix}10 align=${lsat_prefix}10 -p

# copy landsat7 images from PERMANENT to the current mapset.
# We also rename the files so that i.landsat.toar can run without problems
g.copy raster=lsat7_2002_10@PERMANENT,lsat7_2002_1
g.copy raster=lsat7_2002_20@PERMANENT,lsat7_2002_2
g.copy raster=lsat7_2002_30@PERMANENT,lsat7_2002_3
g.copy raster=lsat7_2002_40@PERMANENT,lsat7_2002_4
g.copy raster=lsat7_2002_50@PERMANENT,lsat7_2002_5
g.copy raster=lsat7_2002_61@PERMANENT,lsat7_2002_61
g.copy raster=lsat7_2002_62@PERMANENT,lsat7_2002_62
g.copy raster=lsat7_2002_70@PERMANENT,lsat7_2002_7
g.copy raster=lsat7_2002_80@PERMANENT,lsat7_2002_8


###################################################################################################
# Topographic correction preprocess
###################################################################################################
r.resamp.stats \
    -w \
    --verbose \
    --overwrite \
    input=$elevation \
    output=$resampled_elevation \
    method=$resampling_method

# Create illumination model
i.topo.corr \
    -i \
    --verbose \
    --overwrite \
    basemap=$resampled_elevation \
    zenith=$sun_zenith \
    azimuth=$sun_azimuth \
    output=$illumination \
    method=$topo_method

###################################################################################################
# DOS methods (e.g. Automatic Atmospheric Correction)
###################################################################################################

methods=( dos1 dos2 dos3 dos4 )
toar_prefixes=( ref1. ref2. ref3. ref4. )
for ((i=0; i<${#methods[@]}; ++i)); do
    method="${methods[i]}"
    toar_prefix="${toar_prefixes[i]}"
    echo $method $toar_prefix
    # Calculate Radiance
    i.landsat.toar \
        --verbose \
        --overwrite \
        scale=$scale \
        input=$lsat_prefix \
        output=$toar_prefix \
        metfile=$metadata_path \
        method=$method
    # topographic correction
    i.topo.corr \
        -s \
        --verbose \
        --overwrite \
        in=${toar_prefix}1,${toar_prefix}2,${toar_prefix}3,${toar_prefix}4,${toar_prefix}5,${toar_prefix}61,${toar_prefix}62,${toar_prefix}7,${toar_prefix}8 \
        out=$topo_prefix \
        zenith=$sun_zenith \
        basemap=$illumination
done

###################################################################################################
# 6S Atmospheric Correction
###################################################################################################

# Calculate Radiance
method=uncorrected
toar_prefix=rad.
i.landsat.toar \
    -r \
    --verbose \
    --overwrite \
    scale=$scale \
    input=$lsat_prefix \
    output=$toar_prefix \
    metfile=$metadata_path \
    method=$method

# run i.atcorr
radiance_maps=( rad.1 rad.2 rad.3 rad.4 rad.5 rad.7 rad.8 )
reflectance_maps=( ref6.1 ref6.2 ref6.3 ref6.4 ref6.5 ref6.7 ref6.8 )
atcor_input_files=( atcor1.txt atcor2.txt atcor3.txt atcor4.txt atcor5.txt atcor7.txt atcor8.txt )
for ((i=0; i<${#radiance_maps[@]}; ++i)); do
    radiance_map="${radiance_maps[i]}"
    atcor_input_file="${atcor_input_files[i]}"
    reflectance_map="${reflectance_maps[i]}"
    map_min=`r.info $radiance_map -r | grep min | awk -F"=" '{print $2}'`
    map_max=`r.info $radiance_map -r | grep max | awk -F"=" '{print $2}'`
    echo $radiance_map $atcor_input_file $reflectance_map $map_min $map_max
    # atmospherically correct
    i.atcorr \
        -a \
        --verbose \
        --overwrite \
        range=$map_min,$map_max \
        input=$radiance_map \
        parameters=$atcor_input_file \
        output=$reflectance_map
    # cast the reflectance map to DCELL (i.topo.corr does not work with CELL...)
    r.mapcalc \
        --verbose \
        --overwrite \
        expression="$reflectance_map = if($reflectance_map > 0, 1.0 * $reflectance_map)"
done

# topographically correct
i.topo.corr \
    -s \
    --verbose \
    --overwrite \
    in=ref6.1,ref6.2,ref6.3,ref6.4,ref6.5,ref6.7,ref6.8 \
    out=$topo_prefix \
    zenith=$sun_zenith \
    basemap=$illumination

echo "pixels appearing almost white in DN"
for coordinates in '641867.016495,219409.996678' '642574.916135,218187.660654'; do
    for i in 1 2 3 4 5 7 8; do
        r.what \
            --verbose \
            --overwrite \
            separator=tab \
            map=lsat7_2002_${i},ref6.${i},rad.${i},ref1.${i},ref2.${i},ref3.${i},ref4.${i} \
            coordinates=$coordinates
    done
    echo
done


echo "pixels in water"
for coordinates in '635927.878931,215541.227987' '630748.198113,220059.672956'; do
    for i in 1 2 3 4 5 7 8; do
        r.what \
            --verbose \
            --overwrite \
            separator=tab \
            map=lsat7_2002_${i},ref6.${i},rad.${i},ref1.${i},ref2.${i},ref3.${i},ref4.${i} \
            coordinates=$coordinates
    done
    echo
done


echo "pixels on roads"
for coordinates in '633672.103756,223810.732856' '633602.142473,223472.210516'; do
    for i in 1 2 3 4 5 7 8; do
        r.what \
            --verbose \
            --overwrite \
            separator=tab \
            map=lsat7_2002_${i},ref6.${i},rad.${i},ref1.${i},ref2.${i},ref3.${i},ref4.${i} \
            coordinates=$coordinates
    done
    echo
done

echo "pixels on buildings"
for coordinates in '633031.168127,223289.408453' '632943.152319,223271.353928' '632852.879695,223248.785772'; do
    for i in 1 2 3 4 5 7 8; do
        r.what \
            --verbose \
            --overwrite \
            separator=tab \
            map=lsat7_2002_${i},ref6.${i},rad.${i},ref1.${i},ref2.${i},ref3.${i},ref4.${i} \
            coordinates=$coordinates
    done
    echo
done

echo "pixels with mid values (e.g. 120 DN)"
for coordinates in '633031.168127,223289.408453' '632943.152319,223271.353928' '632852.879695,223248.785772'; do
    for i in 1 2 3 4 5 7 8; do
        r.what \
            --verbose \
            --overwrite \
            separator=tab \
            map=lsat7_2002_${i},ref6.${i},rad.${i},ref1.${i},ref2.${i},ref3.${i},ref4.${i} \
            coordinates=$coordinates
    done
    echo
done
