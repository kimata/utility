#!/bin/zsh

# configuration
typeset -r QUEUE_PATH=/storage/encode/queue
typeset -r OUTPUT_PATH=/storage/encode
typeset -r PROCESSED_PATH=/storage/encode/processed
typeset -r LOG_PATH=/storage/encode/log

VIDEO_OPT="--encoder x264 --x264-preset slower --x264-tune ssim --quality 20 --encopts vbv-maxrate=26000:vbv-bufsize=22000"
AUDIO_OPT="--ab 128 --deinterlace slower"

for i in ${QUEUE_PATH}/*.ts; do
    # check if the file is opend
    sudo lsof $i > /dev/null 2>&1
    if (( $? != 1 )); then
	continue
    fi

    fps=`ffprobe ${i} |& grep -m 1 'mpeg2video (Main)' | ruby -n -e 'puts $1 if $_=~/([\d.]+) tbr/'`
    dur=`ffprobe ${i} |& grep -m 1 Duration | ruby -n -e 'puts ($1.to_i*3600+$2.to_i*60+$3.to_i) if $_=~/([\d]+):([\d]+):([\d]+)/'`
    output="${OUTPUT_PATH}/.${i:t:r}.mp4"
    # encode
    echo HandBrakeCLI --input "${i}" ${=VIDEO_OPT} --rate ${fps} ${=AUDIO_OPT} --output ${output}
    HandBrakeCLI --input "${i}" ${=VIDEO_OPT} --rate ${fps} ${=AUDIO_OPT} --output ${output} >& ${LOG_PATH}/${i:t:r}.log
    if (( $? != 0 )); then
	echo "ERROR[handbrake] ${i}" >&2
	continue
    fi

    # check durarion
    dur_out=`ffprobe ${output} |& grep -m 1 Duration | ruby -n -e 'puts ($1.to_i*3600+$2.to_i*60+$3.to_i) if $_=~/([\d]+):([\d]+):([\d]+)/'`
    dur_diff=`echo "sqrt((${dur} - ${dur_out})^2)" | bc`
    if (( $dur_diff > 2 )); then
	echo "ERROR[duration] ${i}" >&2
	continue
    fi
    mv ${output} ${OUTPUT_PATH}/${i:t:r}.mp4
    mv ${i} ${PROCESSED_PATH}/
    echo OK ${i}
done
