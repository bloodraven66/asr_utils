#!/usr/bin/env bash

set -euo pipefail

if [ $# -ne 4 ]; then
	echo -e "missing arguments!\nexiting now!"
	exit 1;
fi

stage=$1
#suffix="kf"
suffix=$2
#days="list_days/list_days_kf"
days=$3
#rdir="/data/Database/Bhashini_TTSData/Kannada_Female"
rdir=$4

. ./cmd.sh
. ./path.sh
. ./utils/parse_options.sh


sets="$(cat ${days})"
export wdir="${rdir}"
export cdir=`pwd`

ndays=$(wc -l ${days} |awk '{print $1}')
n1=$[$ndays/2]
n2=$[$ndays-$n1]

s1=$(cat $days |head -$n1)
s2=$(cat $days |tail -$n2)
sf=$(cat $days |head -1)
sl=$(cat $days |tail -1)


mkdir -p ${cdir}/data_${suffix}

#for x in $sets; do
#echo -e "$x"

if [ $stage -le 0 ]; then
	utils/combine_data.sh data_${suffix}/train_${suffix} data_${suffix}/test_${suffix}_* || exit 1;
	
	cp data_${suffix}/train_${suffix}/text data_${suffix}/train_${suffix}/text_org
	sed -i 's/[^[:print:]]//g' data_${suffix}/train_${suffix}/text
	perl -CSDA -plE 's/\s/ /g' data_${suffix}/train_${suffix}/text >data_${suffix}/train_${suffix}/text_clean
	cp data_${suffix}/train_${suffix}/text_clean data_${suffix}/train_${suffix}/text

	cat data_${suffix}/train_${suffix}/text |sed -e 's/#/ /g' -e 's/%/ /g' -e 's/\&/ /g' -e 's/\"/ /g' -e 's/\!/ /g' -e 's/(/ /g' -e 's/)/ /g' -e "s/'/ /g" -e 's/+/ /g' -e 's/\\/ /g' -e 's/\// /g' -e 's/\।/ /g' -e 's/\॥/ /g' -e 's/*/ /g' -e 's/‘/ /g' -e 's/\॥/ /g' -e 's/,/ /g' -e 's/’/ /g' -e 's/“/ /g' -e 's/”/ /g' -e 's/-/ /g' -e 's/:/ /g' -e 's/;/ /g' -e 's/=/ /g' -e 's/?/ /g' -e 's/\[/ /g' -e 's/]/ /g' >data_${suffix}/train_${suffix}/text_clean
	cat data_${suffix}/train_${suffix}/text_clean |sed -e 's/    / /g' -e 's/   / /g' -e 's/  / /g' -e 's/  / /g' -e 's/  / /g' -e 's/  / /g' |sort -u -k1,1 >data_${suffix}/train_${suffix}/text_clean_v2
	#mv data_${suffix}/train_${suffix}/text data_${suffix}/train_${suffix}/text_org
	cp data_${suffix}/train_${suffix}/text_clean_v2 data_${suffix}/train_${suffix}/text

	cat data_${suffix}/train_${suffix}/text |awk '{for(i=2;i<=NF;i++){print $i}}' |sort -u >data_${suffix}/train_${suffix}/words.txt
	cat data_${suffix}/train_${suffix}/words.txt |sed -E 's/.{1}/& /g' |awk '{for(i=1;i<=NF;i++){print $i}}' >data_${suffix}/train_${suffix}/chars.txt

	utils/validate_text.pl data_${suffix}/train_${suffix}/text
	utils/fix_data_dir.sh data_${suffix}/train_${suffix}
fi

if [ $stage -le 1 ]; then
	if [ ! -d data_${suffix}/uttinfo_${suffix} ]; then
		mkdir -p data_${suffix}/uttinfo_${suffix}
	fi
	
	rm data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_fh 2>/dev/null || true
	for x in $s1; do
		cat data_${suffix}/test_${suffix}_${x}/wav.scp |awk '{print $1}' >>data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_fh
	done
	cat data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_fh |sort -u >data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_fh_us
	
	rm data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_lh 2>/dev/null || true
	for x in $s2; do
		cat data_${suffix}/test_${suffix}_${x}/wav.scp |awk '{print $1}' >>data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_lh
	done

	for x in $sets; do
		cat data_${suffix}/train_${suffix}/text |grep -Fwf data_${suffix}/test_${suffix}_${x}/uttids >data_${suffix}/test_${suffix}_${x}/text || exit 1;
		./utils/fix_data_dir.sh data_${suffix}/test_${suffix}_${x}
	done
	cat data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_lh |sort -u >data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_lh_us

	utils/subset_data_dir.sh --utt-list data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_fh data_${suffix}/train_${suffix} data_${suffix}/train_${suffix}_fh || exit 1;
	utils/subset_data_dir.sh --utt-list data_${suffix}/uttinfo_${suffix}/uttids_${suffix}_lh data_${suffix}/train_${suffix} data_${suffix}/train_${suffix}_lh || exit 1;
fi

if [ $stage -le 2 ]; then
	if [ ! -d data_${suffix}/local/dict_${suffix} ]; then
		mkdir -p data_${suffix}/local/{dict_${suffix},data}
	fi
	#cat data_${suffix}/train_${suffix}/text |awk '{for(i=2;i<=NF;i++){print $i}}' |sort -u >data_${suffix}/local/data/words.txt
        #cat data_${suffix}/train_${suffix}/words.txt |sed -E 's/.{1}/& /g' |awk '{for(i=1;i<=NF;i++){print $i}}' >data_${suffix}/local/data/chars.txt

	cat data_${suffix}/train_${suffix}/words.txt |sed -E 's/.{1}/& /g' >data_${suffix}/local/data/words_space.txt
	paste data_${suffix}/train_${suffix}/words.txt data_${suffix}/local/data/words_space.txt >data_${suffix}/local/data/lexicon.txt
	echo -e "<unk>\tSIL\n!SIL\tSIL\nSIL\tSIL" >data_${suffix}/local/data/nonscored_words.txt
	cat data_${suffix}/local/data/nonscored_words.txt data_${suffix}/local/data/lexicon.txt >data_${suffix}/local/dict_${suffix}/lexicon.txt
	cat data_${suffix}/local/dict_${suffix}/lexicon.txt |awk '{for(i=2;i<=NF;i++){print $i}}' |sort -u >data_${suffix}/local/dict_${suffix}/phones.txt
	echo -e 'SIL' >data_${suffix}/local/dict_${suffix}/silence_phones.txt
	cp data_${suffix}/local/dict_${suffix}/silence_phones.txt data_${suffix}/local/dict_${suffix}/optional_silence.txt
	cat data_${suffix}/local/dict_${suffix}/phones.txt |grep -Fxvf data_${suffix}/local/dict_${suffix}/silence_phones.txt >data_${suffix}/local/dict_${suffix}/nonsilence_phones.txt
fi

if [ $stage -le 3 ]; then
	cat data_${suffix}/test_${suffix}_evaluation/wav.scp |awk '{print $1}' |sort -u >data_${suffix}/uttinfo_${suffix}/uttids_eval
	cat data_${suffix}/train_${suffix}/wav.scp |awk '{print $1}' |sort -u >data_${suffix}/uttinfo_${suffix}/uttids_train
	cat data_${suffix}/uttinfo_${suffix}/uttids_train |grep -Fwvf data_${suffix}/uttinfo_${suffix}/uttids_eval >data_${suffix}/uttinfo_${suffix}/uttids_train_lm

	./utils/subset_data_dir.sh --utt-list data_${suffix}/uttinfo_${suffix}/uttids_train_lm data_${suffix}/train_${suffix} data_${suffix}/train_${suffix}_lm
fi

#if [ $stage -eq 4 ]; then
#fi
#done
