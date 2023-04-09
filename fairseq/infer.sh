#!/bin/bash

set -e

exp_tag="bh-indicwav2vec"
subset="test"
kenlm="/home1/Sathvik/fairseq_models/kenlm/bh_models/bh_utt_text_NBH_AG_2gram.arpa"
results="/home1/Sathvik/fairseq_results"
wav2vec2_path="/home/wtc9/fairseq/examples/wav2vec/outputs/2023-02-10/12-03-15/checkpoints/checkpoint_best.pt"
data="/home1/Sathvik/fairseq_datasets/bh/raw/"
lexicon="/home1/Sathvik/fairseq_datasets/bh/raw/lexicon.lst"
beam="70"
lm="kenlm"
final_results_folder="/home1/Sathvik/fairseq_results/bh"

[ -e $results/hypo.units-checkpoint_best.pt-test.txt ] && rm $results/*.txt
[ -e $results/hypo.units-checkpoint_best.pt-valid.txt ] && rm $results/*.txt

python3 examples/speech_recognition/infer.py $data \
                --task audio_finetuning \
                --nbest 1 \
                --path $wav2vec2_path \
                --gen-subset $subset  \
                --results-path $results \
                --w2l-decoder $lm \
                --lm-model $kenlm \
                --lm-weight 2 \
                --word-score -1 \
                --sil-weight 0 \
                --criterion ctc \
                --labels ltr \
                --max-tokens 4000000 \
                --post-process letter \
                --lexicon $lexicon \
                --beam $beam \

python3 metrics.py $results $subset $kenlm $final_results_folder $exp_tag
