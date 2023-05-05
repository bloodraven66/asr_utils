#Author: Saurabh 2023


#!/bin/bash
#set -euo pipefail
clear
#set-up for single machine or cluster based execution
. ./cmd.sh
#set the paths to binaries and other executables
[ -f path.sh ] && . ./path.sh
train_cmd=run.pl
decode_cmd=run.pl

train_nj=15
decode_nj=5

#================================================
#	SET SWITCHES
#================================================

lm_data_prep=0
lm_prep=1

MFCC_extract=1

mono_train=1
mono_test=0

tri1_train=1
tri1_test=0

tri2_train=1
tri2_test=0

tri3_train=1
tri3_test=0

tdnn_train=1
tdnn_test=0

#================================================
# Set data prep vars
#================================================
data_prep_stage=0
suffix="hf"
rdir="/data/Database/Bhashini_TTSData/Hindi_Female"

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh




#================================================
# Set Directories
#================================================

tags="fh lh"

data_folder=$1
echo data $data_folder
train_data_lm=$2
echo train $train_data_lm
dev_set=$3
echo dev $dev_set
test_sets=""

#expdir=exp_$tag
#dumpdir=dump
#mfccdir="$dumpdir/mfcc_$data_folder"

#================================================
# Set LM Directories
#================================================
lmtype=srilm_${suffix}

train_lang=lang

train_lang_dir=${data_folder}/$train_lang

test_lang=lang_test_${lmtype}

test_lang_dir=${data_folder}/$test_lang

lmdir=lmDir_${lmtype}

#================================================================================
if [ $lm_data_prep == 1 ]; then
	./exp_data_prep_main_asr.sh ${data_prep_stage} ${suffix} $days $rdir || exit 1;
fi

if [ $lm_prep == 1 ]; then

	echo ============================================================================
	echo "				Language Model Preparation			"
	echo ============================================================================

	utils/prepare_lang.sh $data_folder/local/dict \
		"!SIL" $data_folder/local/$train_lang $data_folder/$train_lang || exit 1;
	echo $train_data_lm
	echo $data_folder/$train_data_lm 
	echo $data_folder/$dev_set 
		
	echo	$data_folder 
	echo	$data_folder/local/$lmdir 
	echo	$train_lang 
	echo "done"
	bash utils/train_lms_srilm.sh $data_folder/$train_data_lm $data_folder/$dev_set \
		$data_folder $data_folder/local/$lmdir $train_lang || exit 1;
	mkdir -p $data_folder/$test_lang
	rm -r $data_folder/$test_lang/* 2>/dev/null ||true
	cp -r $data_folder/$train_lang/* $data_folder/$test_lang/
	bash utils/arpa2G.sh $data_folder/local/$lmdir/lm.gz $data_folder/$train_lang $data_folder/$test_lang || exit 1;
	echo ============================================================================
	echo "                   Language Model created successfully     	        "
	echo ============================================================================
fi

for set1 in $tags; do
tag="${suffix}_$set1"

train_data="$train_data_lm"
train_dir=${data_folder}/$train_data

expdir=exp_"$data_folder"_"$tag"
echo $expdir
dumpdir=dump
mfccdir="$dumpdir/mfcc_$data_folder"

if [ $MFCC_extract == 1 ]; then
	echo ============================================================================
	echo "         		MFCC Feature Extration & CMVN + Validation	        "
	echo ============================================================================

	for datadir in $train_data; do # $train_data
		utils/fix_data_dir.sh ${data_folder}/${datadir}
		utils/validate_data_dir.sh --no-feats ${data_folder}/${datadir}

		steps/make_mfcc.sh --cmd "$train_cmd" --nj 40 ${data_folder}/${datadir} $expdir/make_mfcc/${datadir} $mfccdir/${datadir} || exit 1;
		steps/compute_cmvn_stats.sh ${data_folder}/${datadir} $expdir/make_mfcc/${datadir} $mfccdir/${datadir} || exit 1;
	done
fi

if [ $mono_train == 1 ]; then
	echo ============================================================================
	echo "                   MonoPhone Training                	        "
	echo ============================================================================
	steps/train_mono.sh --nj "$train_nj" --cmd "$train_cmd" $train_dir $train_lang_dir $expdir/mono || exit 1;
fi

if [ $mono_test == 1 ]; then
	echo ============================================================================
	echo "                   MonoPhone Testing             	        "
	echo ============================================================================
	utils/mkgraph.sh --mono $test_lang_dir $expdir/mono $expdir/mono/graph || exit 1;
	for datadir in $test_sets; do #
		steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" $expdir/mono/graph \
			${data_folder}/${datadir} $expdir/mono/decode_${datadir} || exit 1;
	done
fi

if [ $tri1_train == 1 ]; then
	echo ============================================================================
	echo "           tri1 : Deltas + Delta-Deltas Training      "
	echo ============================================================================
	steps/align_si.sh --boost-silence 1.25 --nj "$train_nj" --cmd "$train_cmd" $train_dir \
		$train_lang_dir $expdir/mono $expdir/mono_ali || exit 1;
	for sen in 5000; do
		for gauss in 20; do
			gauss=$(($sen * $gauss))
			steps/train_deltas.sh --cmd "$train_cmd" $sen $gauss $train_dir $train_lang_dir $expdir/mono_ali \
			       	$expdir/tri1_${sen}_${gauss} || exit 1;
		done
	done
fi

if [ $tri1_test == 1 ]; then
	echo ============================================================================
	echo "           tri1 : Deltas + Delta-Deltas  Decoding            "
	echo ============================================================================
	for sen in 5000; do
		for gauss in 20; do
			gauss=$(($sen * $gauss))
			utils/mkgraph.sh $test_lang_dir $expdir/tri1_${sen}_${gauss} $expdir/tri1_${sen}_${gauss}/graph || exit 1;
			for datadir in $test_sets; do #
				steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" $expdir/tri1_${sen}_${gauss}/graph \
					${data_folder}/${datadir} $expdir/tri1_${sen}_${gauss}/decode_${datadir} || exit 1;
			done
		done
	done
fi

if [ $tri2_train == 1 ]; then
	echo ============================================================================
	echo "                 tri2 : LDA + MLLT Training                    "
	echo ============================================================================
	steps/align_si.sh --nj "$train_nj" --cmd "$train_cmd" $train_dir $train_lang_dir $expdir/tri1_5000_100000 \
		$expdir/tri1_ali || exit 1
	for sen in 6000; do
		for gauss in 20; do
			gauss=$(($sen * $gauss))
			steps/train_lda_mllt.sh --cmd "$train_cmd" --splice-opts "--left-context=3 --right-context=3" \
				$sen $gauss $train_dir $train_lang_dir $expdir/tri1_ali $expdir/tri2_${sen}_${gauss} || exit 1;
		done
	done
fi

if [ $tri2_test == 1 ]; then
	echo ============================================================================
	echo "                 tri2 : LDA + MLLT Decoding                "
	echo ============================================================================
	for sen in 6000; do
		for gauss in 20; do
			gauss=$(($sen * $gauss))
			utils/mkgraph.sh $test_lang_dir $expdir/tri2_${sen}_${gauss} $expdir/tri2_${sen}_${gauss}/graph || exit 1;
			for datadir in $test_sets; do #
				steps/decode.sh --nj "$decode_nj" --cmd "$decode_cmd" $expdir/tri2_${sen}_${gauss}/graph ${data_folder}/${datadir} \
					$expdir/tri2_${sen}_${gauss}/decode_${datadir} || exit 1;
			done
		done
	done
fi

if [ $tri3_train == 1 ]; then
	echo ============================================================================
	echo "              tri3 : LDA + MLLT + SAT Training               "
	echo ============================================================================
	# Align tri2 system with train data.
	steps/align_si.sh --nj "$train_nj" --cmd "$train_cmd" \
		--use-graphs true $train_dir $train_lang_dir $expdir/tri2_6000_120000 $expdir/tri2_ali || exit 1;
	for sen in 8000; do
		for gauss in 20; do
			gauss=$(($sen * $gauss))
			# From tri2 system, train tri3 which is LDA + MLLT + SAT.
			steps/train_sat.sh --cmd "$train_cmd" \
				$sen $gauss $train_dir $train_lang_dir $expdir/tri2_ali $expdir/tri3_${sen}_${gauss} || exit 1;
		done
	done
fi

if [ $tri3_test == 1 ]; then
	echo ============================================================================
	echo "              tri3 : LDA + MLLT + SAT Decoding    Start             "
	echo ============================================================================
	for sen in 8000; do
		for gauss in 20; do
			gauss=$(($sen * $gauss))
			utils/mkgraph.sh $test_lang_dir $expdir/tri3_${sen}_${gauss} $expdir/tri3_${sen}_${gauss}/graph || exit 1;
			for datadir in $test_sets; do #
				steps/decode_fmllr.sh --nj "$decode_nj" --cmd "$decode_cmd" $expdir/tri3_${sen}_${gauss}/graph \
				       	${data_folder}/${datadir} $expdir/tri3_${sen}_${gauss}/decode_${datadir} || exit 1;
			done
		done
	done
fi

if [ $tdnn_train == 1 ]; then
	echo ============================================================================
	echo "                    	Chain CNN-TDNN Training         		"
	echo ============================================================================
	tdnn_stage=0
        tdnn_train_iter=-10 #default=-10
        . ./utils/parse_options.sh
        gmm=tri3_8000_160000
        nnet3_affix=_fmllr_8000_160000
        affix=cnn_1a_7000
        tree_affix=7000
		rm $1/$2"_sp"/feats.scp
		rm -r $expdir/"tri3_8000_160000_ali_"$2"_sp"
		rm $expdir/chain_fmllr_8000_160000/tree_sp_7000/final.mdl
        local/chain/Run_cnn_tdnn_1a.sh --stage $tdnn_stage --train_stage $tdnn_train_iter \
                --data_folder $data_folder --expdir $expdir \
                --train_set $train_data --gmm $gmm \
                --nnet3_affix $nnet3_affix \
                --affix $affix \
                --tree_affix $tree_affix \
                --mfccdir $mfccdir || exit 1;
fi

if [ $tdnn_test == 1 ]; then
	echo ============================================================================
	echo "                          Chain CNN-TDNN Testing                          "
	echo ============================================================================
	test_stage=1
	. ./utils/parse_options.sh
	nnet3_affix=_fmllr_8000_160000
	affix=cnn_1a_7000
	dir=$expdir/chain${nnet3_affix}/tdnn${affix:+_$affix}_sp
	graph_dir=$dir/graph_${lmtype}
	
	if [ $test_stage -le 1 ]; then
		for datadir in $test_sets; do #
			utils/fix_data_dir.sh ${data_folder}/$datadir
			utils/copy_data_dir.sh ${data_folder}/$datadir ${data_folder}/${datadir}_hires
		done

		for datadir in $test_sets; do #
			steps/make_mfcc.sh --nj 5 --mfcc-config conf/mfcc_hires.conf --cmd "$train_cmd" \
				${data_folder}/${datadir}_hires $expdir/make_mfcc/${datadir}_hires $mfccdir/${datadir}_hires || exit 1;
			utils/fix_data_dir.sh ${data_folder}/${datadir}_hires
			steps/compute_cmvn_stats.sh ${data_folder}/${datadir}_hires $expdir/make_mfcc/${datadir}_hires \
				$mfccdir/${datadir}_hires || exit 1;
		done
	fi

	if [ $test_stage -le 2 ]; then
		for datadir in $test_sets; do #
			steps/online/nnet2/extract_ivectors_online.sh --cmd "$train_cmd" --nj 5 \
				${data_folder}/${datadir}_hires $expdir/nnet3${nnet3_affix}/extractor \
				$expdir/nnet3${nnet3_affix}/ivectors_${datadir}_hires || exit 1;
		done
	fi

	if [ $test_stage -le 3 ]; then
		# Note: it might appear that this $lang directory is mismatched, and it is as
		# far as the 'topo' is concerned, but this script doesn't read the 'topo' from
		# the lang directory.
		utils/mkgraph.sh --self-loop-scale 1.0 --remove-oov ${data_folder}/lang_test_${lmtype} $dir $graph_dir
	fi

	iter_opts=
	decode_iter=
	if [ ! -z $decode_iter ]; then
		iter_opts=" --iter $decode_iter "
	fi
	if [ $test_stage -le 4 ]; then
		rm $dir/.error 2>/dev/null || true
		for decode_set in $test_sets; do
			(
			steps/nnet3/decode.sh --use-gpu false --acwt 1.0 --post-decode-acwt 10.0 --nj $decode_nj \
				--cmd "$decode_cmd" $iter_opts --online-ivector-dir \
				$expdir/nnet3${nnet3_affix}/ivectors_${decode_set}_hires $graph_dir \
				${data_folder}/${decode_set}_hires $dir/decode_${decode_set}${decode_iter:+_$decode_iter}_${lmtype} || exit 1;
#			steps/lmrescore.sh --cmd "$decode_cmd" --self-loop-scale 1.0 ${data_folder}/lang_test_{tgsmall,tgmed} \
#				${data_folder}/${decode_set}_hires \
#				$dir/decode_${decode_set}${decode_iter:+_$decode_iter}_{tgsmall,tgmed} || exit 1;
#			steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" ${data_folder}/lang_test_{tgsmall,tglarge} \
#				${data_folder}/${decode_set}_hires \
#				$dir/decode_${decode_set}${decode_iter:+_$decode_iter}_{tgsmall,tglarge} || exit 1;
#			steps/lmrescore_const_arpa.sh --cmd "$decode_cmd" ${data_folder}/lang_test_{tgsmall,fglarge} \
#				${data_folder}/${decode_set}_hires \
#				$dir/decode_${decode_set}${decode_iter:+_$decode_iter}_{tgsmall,fglarge} || exit 1;
			) || touch $dir/.error &
		done
		wait
		if [ -f $dir/.error ]; then
			echo "$0: something went wrong in decoding"
			exit 1
		fi
	fi # Decoding finished

	if [ $test_stage -le 5 ]; then
		rm $dir/.error 2>/dev/null || true
		for score_set in $test_sets; do
			(
				steps/scoring/score_kaldi_cer.sh --cmd "$decode_cmd" ${data_folder}/${score_set}_hires $graph_dir \
					$dir/decode_${score_set}${decode_iter:+_$decode_iter}_${lmtype} || exit 1;
			) || touch $dir/.error &
		done
		wait
		if [ -f $dir/.error ]; then
			echo "$0: something went wrong in scoring"
			exit 1;
		fi
	fi # Scoring finished
fi  # Testing finished
done

#./Run_cnn-tdnn_hf_0822_0901.sh
#./Run_cnn-tdnn_mf.sh
echo ============================================================================
echo "                     Training Testing Finished                      "
echo ============================================================================
