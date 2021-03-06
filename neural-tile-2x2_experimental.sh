#! /bin/bash 

#This experimental script requires this script: http://www.fmwconcepts.com/imagemagick/transfercolor/index.php 
#to be placed into your Neural-Style directory.

# Check for output directory, and create it if missing
if [ ! -d "$output" ]; then
  mkdir output
fi


main(){
	# 1. Defines the content image as a variable
	input=$1
	input_file=`basename $input`
	clean_name="${input_file%.*}"
	
	#Defines the style image as a variable
	style=$2
	style_dir=`dirname $style`
	style_file=`basename $style`
	style_name="${style_file%.*}"
	
	#Defines the output directory
	output="./output"
	out_file=$output/$input_file
	
	#Defines the overlap
	overlap_w=50
	overlap_h=50
	
	# 2. Creates your original styled output. This step will be skipped if you place a previously styled image with the same name 
	# as your specified "content image", located in your Neural-Style/output/<Styled_Image> directory.
	if [ ! -s $out_file ] ; then
		neural_style $input $style $out_file
	fi
	
	# 3. Chop the styled image into 2x2 tiles with the specified overlap value.
	out_dir=$output/$clean_name
	mkdir -p $out_dir
	convert $out_file -crop 2x2+"$overlap_w"+"$overlap_h"@ +repage +adjoin $out_dir/$clean_name"_%d.png"
	
	#Finds out the length and width of the first tile as a refrence point for resizing the other tiles.
	original_tile_w=`convert $out_dir/$clean_name'_0.png' -format "%w" info:`
	original_tile_h=`convert $out_dir/$clean_name'_0.png' -format "%h" info:`
	
	 #Resize all tiles to avoid ImageMagick weirdness
	 convert $out_dir/$clean_name'_0.png' -resize "$original_tile_w"x"$original_tile_h"\! $out_dir/$clean_name'_0.png' 
	 convert $out_dir/$clean_name'_1.png' -resize "$original_tile_w"x"$original_tile_h"\! $out_dir/$clean_name'_1.png'
	 convert $out_dir/$clean_name'_2.png' -resize "$original_tile_w"x"$original_tile_h"\! $out_dir/$clean_name'_2.png'
	 convert $out_dir/$clean_name'_3.png' -resize "$original_tile_w"x"$original_tile_h"\! $out_dir/$clean_name'_3.png'				
					#WxH				

	# 4. neural-style each tile
	tiles_dir="$out_dir/tiles"
	mkdir -p $tiles_dir
	for tile in `ls $out_dir | grep $clean_name"_"[0-4]".png"`
	do
		neural_style_tiled $out_dir/$tile $style $tiles_dir/$tile
	done

	# 4.1 transfercolor for each tile
	tiles_c_dir="$out_dir/tiles_c"
	mkdir -p $tiles_c_dir

		sudo bash ./transfercolor.sh -c lab $tiles_dir/$clean_name'_0.png' $out_dir/$clean_name'_0.png' $tiles_c_dir/$clean_name'_0.png' 
		sudo bash ./transfercolor.sh -c lab $tiles_dir/$clean_name'_1.png' $out_dir/$clean_name'_1.png' $tiles_c_dir/$clean_name'_1.png'
		sudo bash ./transfercolor.sh -c lab $tiles_dir/$clean_name'_2.png' $out_dir/$clean_name'_2.png' $tiles_c_dir/$clean_name'_2.png' 
		sudo bash ./transfercolor.sh -c lab $tiles_dir/$clean_name'_3.png' $out_dir/$clean_name'_3.png' $tiles_c_dir/$clean_name'_3.png' 

	#Perform the required mathematical operations:	

	upres_tile_w=`convert $tiles_dir/$clean_name'_0.png' -format "%w" info:`
	upres_tile_h=`convert $tiles_dir/$clean_name'_0.png' -format "%h" info:`
	
	tile_diff_w=`echo $upres_tile_w $original_tile_w | awk '{print $1/$2}'`
	tile_diff_h=`echo $upres_tile_h $original_tile_h | awk '{print $1/$2}'`

	smush_value_w=`echo $overlap_w $tile_diff_w | awk '{print $1*$2}'`
	smush_value_h=`echo $overlap_h $tile_diff_h | awk '{print $1*$2}'`
	
	# 5. feather tiles
	feathered_dir=$out_dir/feathered
	mkdir -p $feathered_dir
	for tile in `ls $tiles_dir | grep $clean_name"_"[0-4]".png"`
	do
		tile_name="${tile%.*}"
		convert $tiles_dir/$tile -alpha set -virtual-pixel transparent -channel A -morphology Distance Euclidean:1,50\! +channel "$feathered_dir/$tile_name.png"
	done

	# 5.1 feather corrected tiles
	feathered_dir_c=$out_dir/feathered_c
	mkdir -p $feathered_dir_c
	for tile in `ls $tiles_c_dir | grep $clean_name"_"[0-4]".png"`
	do
		tile_name="${tile%.*}"
		convert $tiles_c_dir/$tile -alpha set -virtual-pixel transparent -channel A -morphology Distance Euclidean:1,50\! +channel "$feathered_dir_c/$tile_name.png"
	done

	
	# 7. Smush the feathered tiles together
	convert -background transparent \( $feathered_dir/$clean_name'_0.png' $feathered_dir/$clean_name'_1.png' +smush -$smush_value_w -background transparent \) \
			\( $feathered_dir/$clean_name'_2.png' $feathered_dir/$clean_name'_3.png' +smush -$smush_value_w -background transparent \) \
			-background none  -background transparent -smush -$smush_value_h  $output/$clean_name.large_feathered.png

	# 8. Smush the non-feathered tiles together
	convert \( $tiles_dir/$clean_name'_0.png' $tiles_dir/$clean_name'_1.png' +smush -$smush_value_w \) \
			\(  $tiles_dir/$clean_name'_2.png'  $tiles_dir/$clean_name'_3.png' +smush -$smush_value_w \) \
			-background none -smush -$smush_value_h  $output/$clean_name.large.png
			
	# 8. Combine feathered and un-feathered output images to disguise feathering.
	composite $output/$clean_name.large_feathered.png $output/$clean_name.large.png $output/$clean_name.large_final.png


	# 7.1 Smush the corrected feathered tiles together
	convert -background transparent \( $feathered_dir_c/$clean_name'_0.png' $feathered_dir_c/$clean_name'_1.png' +smush -$smush_value_w -background transparent \) \
			\( $feathered_dir_c/$clean_name'_2.png' $feathered_dir_c/$clean_name'_3.png' +smush -$smush_value_w -background transparent \) \
			-background none  -background transparent -smush -$smush_value_h  $output/$clean_name.large_feathered_c.png

	# 8.1 Smush the non-feathered tiles together
	convert \( $out_dir/tiles_c/$clean_name'_0.png' $out_dir/tiles_c/$clean_name'_1.png' +smush -$smush_value_w \) \
			\(  $out_dir/tiles_c/$clean_name'_2.png'  $out_dir/tiles_c/$clean_name'_3.png' +smush -$smush_value_w \) \
			-background none -smush -$smush_value_h  $output/$clean_name.large_c.png

	# 8. Combine feathered and un-feathered output images to disguise feathering.
	composite $output/$clean_name.large_feathered_c.png $output/$clean_name.large_c.png $output/$clean_name.large_final_c.png

	# 9. Combine feathered and un-feathered output images to disguise feathering.
	sudo bash ./transfercolor.sh -c rgb $output/$clean_name.large_final_c.png $output/$clean_name.large_final.png $output/$clean_name.large_final_rgb.png 

	

}

retry=0

#Runs the content image and style image through Neural-Style with your chosen parameters.
neural_style(){
	echo "Neural Style Transfering "$1
	if [ ! -s $3 ]; then
#####################################################################################

th neural_style.lua \
  -content_image $1 \
  -style_image $2 \
  -image_size 640 \
  -output_image out1.png \
  -num_iterations 100 \
  
th neural_style.lua \
  -content_image $1 \
  -style_image $2 \
  -init image -init_image out1.png \
  -output_image $3 \
  -image_size 768 \
  -num_iterations 50 

#####################################################################################
	fi
	if [ ! -s $3 ] && [ $retry -lt 3 ] ;then
			echo "Transfer Failed, Retrying for $retry time(s)"
			retry=`echo 1 $retry | awk '{print $1+$2}'`
			neural_style $1 $2 $3
	fi
	retry=0
}
retry=0

#Runs the tiles through Neural-Style with your chosen parameters. 
neural_style_tiled(){
	echo "Neural Style Transfering "$1
	if [ ! -s $3 ]; then
#####################################################################################	

th neural_style.lua \
  -content_image $1 \
  -style_image $2 \
  -image_size 640 \
  -output_image out1.png \
  -num_iterations 100 \
  
th neural_style.lua \
  -content_image $1 \
  -style_image $2 \
  -init image -init_image out1.png \
  -output_image $3 \
  -image_size 768 \
  -num_iterations 50 

#####################################################################################
	fi
	if [ ! -s $3 ] && [ $retry -lt 3 ] ;then
			echo "Transfer Failed, Retrying for $retry time(s)"
			retry=`echo 1 $retry | awk '{print $1+$2}'`
			neural_style_tiled $1 $2 $3
	fi
	retry=0
}

main $1 $2 $3
