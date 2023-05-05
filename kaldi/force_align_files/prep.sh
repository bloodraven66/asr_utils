folder="../moe_tts/kaldi_files/ljspeech_female"
devfolder=$folder"_dev"

new_folder_name=$(echo $folder | rev | cut -d'/' -f1 | rev)
new_folder=$new_folder_name"_data"
echo $new_folder
echo $new_folder $folder
mkdir -p $new_folder
cp -r $folder $new_folder
cp -r $devfolder $new_folder

./utils/fix_data_dir.sh "$new_folder"/"$new_folder_name"

mkdir -p $new_folder/"local"
mkdir -p $new_folder/"local"/"dict"

cat "$new_folder"/"$new_folder_name"/"text" | cut -d' ' -f2- > "temp_text"
python3 prep.py "temp_text" $new_folder/"local"/"dict"
# # exit
rm "temp_text"
rm $new_folder/local/dict/lexiconp.txt
./utils/data/resample_data_dir_mod.sh 16000 "$new_folder"/"$new_folder_name"
./Run_cnn-tdnn_main.sh "$new_folder" "$new_folder_name" "$new_folder_name"_dev

./Run_FA_BN.sh "$new_folder" "$new_folder_name"
