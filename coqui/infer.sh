#!/bin/bash
chk_folder=""
chk=$chk_folder/"/heckpoint_60000.pth"
text="ट्रैक्टर के केतना प्रकार होला"
config=$chk_folder/"config.json"
savepath=$chk_folder/"demo.wav"
speakers=$chk_folder/"speakers.pth"
spkid=16779140

tts --text "$text" --model_path $chk --config_path $config --out_path $savepath --speakers_file_path $speakers --speaker_idx $spkid

