if [ $# -ne 4 ]; then
	echo -e "missing arguments!\nexiting now!"
	exit 1;
fi

stage=$1
suffix=$2
days=$3
rdir=$4
sets="$(cat ${days})"

#sets="$(cat list_days/list_days_${suffix}_v2)"

export wdir="${rdir}"
#export wdir=/data/Database/Bhashini_TTSData/English_Female
export cdir=`pwd`

mkdir -p ${cdir}/data_${suffix}

for x in $sets; do
echo -e "$x"

if [ $stage -le 1 ]; then
#for x in $sets; do
	mkdir -p $wdir/${x}/data
	find ${wdir} -type f -iname *.wav |grep -F "$x" >$wdir/${x}/data/wavpath || exit 1;
	cat $wdir/${x}/data/wavpath |rev |cut -d '/' -f1 |rev |cut -d '.' -f1 >$wdir/${x}/data/uttids || exit 1;
	paste $wdir/${x}/data/uttids $wdir/${x}/data/wavpath >$wdir/${x}/data/wav.scp
	rm $wdir/${x}/data/wavpath
	paste $wdir/${x}/data/uttids $wdir/${x}/data/uttids >$wdir/${x}/data/utt2spk
	paste $wdir/${x}/data/uttids $wdir/${x}/data/uttids >$wdir/${x}/data/spk2utt
#done
fi

if [ $stage -le 2 ]; then
	for f in ${cdir}/make_text_file_${suffix}; do
	echo -e "$f"
	if [ -f $f ]; then
		echo "file $f to exists!\nremoving it!"
		exit 1;
	fi
	done

	find ${wdir} -type f -iname *.txt |grep -F "$x" >$wdir/${x}/data/txtpath || exit 1;
	cat $wdir/${x}/data/txtpath |rev |cut -d '/' -f1 |rev |cut -d '.' -f1 >$wdir/${x}/data/txtids || exit 1;
	paste $wdir/${x}/data/txtids $wdir/${x}/data/txtpath >$wdir/${x}/data/txt.scp
	rm $wdir/${x}/data/txtpath
	cat $wdir/${x}/data/txt.scp |awk -v wdir="$wdir" -v x="$x" '{print "echo -e \"" $1 " $(cat " $2 ")\" >>" wdir "/" x "/data/text"}' >>${cdir}/make_text_file_${suffix}.sh || exit 1;


fi

if [ $stage -le 3 ]; then
	chmod 777 ${cdir}/make_text_file_${suffix}.sh
	${cdir}/make_text_file_${suffix}.sh
fi

if [ $stage -le 4 ]; then
	cp -r ${wdir}/${x}/data ${cdir}/data_${suffix}/test_${suffix}_$x
fi
done

if [ $stage -le 5 ]; then
	rm list_test_sets/list_sets_${suffix} 2>/dev/null ||true
	for x in $(cat ${days}); do
		echo -e "test_${suffix}_$x" >>list_test_sets/list_sets_${suffix}
	done
fi
