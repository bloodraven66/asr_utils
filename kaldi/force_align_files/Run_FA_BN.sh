#Author: Saurabh 2023

#!/bin/bash
clear
#set-up for single machine or cluster based execution
. ./cmd.sh
#set the paths to binaries and other executables
[ -f path.sh ] && . ./path.sh
train_cmd=run.pl
decode_cmd=run.pl

train_nj=50
decode_nj=30

#================================================
#	SET SWITCHES
#================================================

data_prep=0

MFCC_extract=0

cnn_test=1

#================================================
# Set Directories
#================================================

tag="hf_fh"
data_folder="$1"
# data_folder="Marathi_Male_data"
test_set_folder="$2"

# test_set_folder="Marathi_Male"

train_data=train_$tag

train_dir=${data_folder}/$train_data

#test_sets="dev_bh100_5h_reseg test_bh100_5h_reseg"
test_sets=$test_set_folder

expdir=exp_"$data_folder"_"$tag"
# expdir=exp_"$data_folder"_"$tag"
dumpdir=dump
mfccdir="$dumpdir/mfcc_$data_folder"

#================================================
# Set LM Directories
#================================================

train_lang=lang

train_lang_dir=${data_folder}/$train_lang

test_lang_dir=${data_folder}/lang_test_srilm_hf
lmtype=srilm_hf

#================================================================================

if [ $MFCC_extract == 1 ]; then

echo ============================================================================
echo "         		MFCC Feature Extration & CMVN + Validation	        "
echo ============================================================================

#extract MFCC features and perfrom CMVN

for datadir in $test_sets; do # $train_data 
	
	utils/fix_data_dir.sh ${data_folder}/${datadir}
	utils/validate_data_dir.sh ${data_folder}/${datadir}

	steps/make_mfcc.sh --cmd "$train_cmd" --nj 10 ${data_folder}/${datadir} $expdir/make_mfcc/${datadir} $mfccdir/${datadir} || exit 1;
	steps/compute_cmvn_stats.sh ${data_folder}/${datadir} $expdir/make_mfcc/${datadir} $mfccdir/${datadir} || exit 1;

done
fi


if [ $cnn_test == 1 ]; then

echo ============================================================================
echo "                          chain TDNN Testing                                "
echo ============================================================================

test_stage=1
. ./utils/parse_options.sh
nnet3_affix=_fmllr_8000_160000
affix=1a_7000
dir=$expdir/chain${nnet3_affix}/tdnn_cnn${affix:+_$affix}_sp
tree_dir=$expdir/chain${nnet3_affix}/tree_a_sp${tree_affix:+_$tree_affix}
graph_dir=$dir/graph_$lmtype

if [ $test_stage -le 1 ]; then
  for datadir in $test_sets; do #
    utils/fix_data_dir.sh ${data_folder}/$datadir
    utils/copy_data_dir.sh ${data_folder}/$datadir ${data_folder}/${datadir}_hires
  done

  for datadir in $test_sets; do #
    steps/make_mfcc.sh --nj 100 --mfcc-config conf/mfcc_hires.conf  --cmd "$train_cmd" \
     ${data_folder}/${datadir}_hires $expdir/make_mfcc/${datadir}_hires $mfccdir/${datadir}_hires || exit 1;
     
    utils/fix_data_dir.sh ${data_folder}/${datadir}_hires
    
    steps/compute_cmvn_stats.sh ${data_folder}/${datadir}_hires $expdir/make_mfcc/${datadir}_hires \
     $mfccdir/${datadir}_hires || exit 1;
  done
  
fi

if [ $test_stage -le 2 ]; then
  for datadir in $test_sets; do #
    steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 40 \
     ${data_folder}/${datadir}_hires $expdir/nnet3${nnet3_affix}/extractor $expdir/nnet3${nnet3_affix}/ivectors_${datadir}_hires || exit 1;
  done
fi

if [ $test_stage -le 3 ]; then
  scale_opts="--transition-scale=1.0 --acoustic-scale=1.0 --self-loop-scale=1.0"
  for part in $test_sets;do
    # nj=100
    if [ $(wc -l <$data_folder/$part/spk2utt) -le 10 ];then nj=$(wc -l <$data_folder/$part/spk2utt) ;else nj=30; fi

    steps/nnet3/align.sh --retry_beam 200 --nj "$nj" --use_gpu "false" --scale-opts "$scale_opts" \
   --online_ivector_dir $expdir/nnet3${nnet3_affix}/ivectors_${part}_hires --cmd "$train_cmd" \
          $data_folder/${part}_hires $test_lang_dir $dir force_align_$part || exit 1;
  done
fi

if [ $test_stage -le 4 ];then
        
        for part in $test_sets;do
        FA_dir=force_align_${part}

        ali-to-phones --frame-shift=0.03 --ctm-output "$FA_dir"/final.mdl "ark:gunzip -c ${FA_dir}/ali.*.gz|" "$FA_dir"/FA_int_${part}.ctm

        int2sym.pl -f 5- $test_lang_dir/phones.txt "$FA_dir"/FA_int_${part}.ctm > "$FA_dir"/FA_${part}.txt

        ali-to-pdf "$FA_dir"/final.mdl "ark:gunzip -c ${FA_dir}/ali.*.gz|" ark,t: >"$FA_dir"/PDFID_alignment_"$part".txt
        done
fi

if [ $test_stage -le 5 ];then
        for part in $test_sets;do
        FA_dir=force_align_$part

        ali-to-pdf "$FA_dir"/final.mdl "ark:gunzip -c ${FA_dir}/ali.*.gz|" ark,t: >"$FA_dir"/PDFID_alignment_"$part".txt
	done

fi

if [ $test_stage -le 6 ];then
        for part in $test_sets;do
        FA_dir=force_align_$part

        steps/get_train_ctm.sh $data_folder/$part $test_lang_dir $FA_dir
	mv $FA_dir/ctm $FA_dir/ctm_$part
	done
fi

fi # Testing finished

echo ============================================================================
echo "                     Training Testing Finished                      "
echo ============================================================================
