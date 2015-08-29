#!/bin/zsh

# configuration
typeset -r QUEUE_PATH=/storage/encode/queue
typeset -r OUTPUT_PATH=/storage/encode
typeset -r FAIL_PATH=/storage/encode/fail
typeset -r TEMP_PATH=/storage/encode/temp
typeset -r PROCESSED_PATH=/storage/encode/processed
typeset -r LOG_PATH=/storage/encode/log

VIDEO_OPT="--encoder x264 --x264-preset slow --deinterlace slow --quality 20 --encopts vbv-maxrate=26000:vbv-bufsize=22000"
AUDIO_OPT="--ab 128"

function scan_and_encode {
    for i in ${QUEUE_PATH}/*.ts; do
        # check if the file is opend
	sudo lsof $i > /dev/null 2>&1
	if (( $? != 1 )); then
	    continue
	fi

	fps=`avprobe ${i} |& grep -m 1 'mpeg2video (Main)' | ruby -n -e 'puts $1 if $_=~/([\d.]+) tbr/'`
	par=`avprobe ${i} |& grep -m 1 'Video: ' | ruby -n -e 'puts $1 if $_=~/\[PAR (\d+:\d+) /'`
	dur=`avprobe ${i} |& grep -m 1 'Duration' | ruby -n -e 'puts ($1.to_i*3600+$2.to_i*60+$3.to_i) if $_=~/([\d]+):([\d]+):([\d]+)/'`
	temp=`mktemp -u "${TEMP_PATH}/${i:t:r}.XXXXXX"`.mp4
        # encode
	echo HandBrakeCLI --input "${i}" ${=VIDEO_OPT} ${=AUDIO_OPT} --rate ${fps} --pixel-aspect $par --large-file --output "${temp}" | tee ${LOG_PATH}/${i:t:r}.log
	HandBrakeCLI --input "${i}" ${=VIDEO_OPT} ${=AUDIO_OPT} --rate ${fps} --pixel-aspect $par --large-file --output "${temp}" >>& ${LOG_PATH}/${i:t:r}.log
	if (( $? != 0 )); then
	    echo "ERROR[handbrake] ${i}" >&2
	    continue
	fi

        # check durarion
	dur_out=`avprobe ${temp} |& grep -m 1 Duration | ruby -n -e 'puts ($1.to_i*3600+$2.to_i*60+$3.to_i) if $_=~/([\d]+):([\d]+):([\d]+)/'`

	# check format
	if (( ${#dur_out} == 0 )); then
	    mv ${temp} ${FAIL_PATH}/${i:t:r}.mp4
	    mv ${i} ${FAIL_PATH}/
	    echo "ERROR[invalid] ${i}" >&2
	    continue
	fi

	dur_diff=`echo "sqrt((${dur} - ${dur_out})^2)" | bc`
	if (( $dur_diff < 2 )); then
	    mv ${temp} ${OUTPUT_PATH}/${i:t:r}.mp4
	    mv ${i} ${PROCESSED_PATH}/
	    echo OK ${i}
	else
	    echo "ERROR[duration] ${i}" >&2
	    continue
	fi
    done
}

scan_and_encode
while inotifywait -e close_write,moved_to ${QUEUE_PATH} &>/dev/null; do
    scan_and_encode
done
