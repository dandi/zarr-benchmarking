#!/bin/bash
#
# Relies on following configuration for rclone:
#
# $> cat ~/.config/rclone/rclone.conf 
# [DANDI-WEBDAV]
# type = webdav
# url = https://dandi.centerforopenneuroscience.org
# vendor = other
# 
# [DANDI-WEBDAV-LOCAL]
# type = webdav
# url = http://localhost:8080
# vendor = other
# 
# [DANDI-S3]
# type = s3
# provider = AWS
# region = us-east-2


set -eu

ds=000108
asset=0dfbb4b4-be63-45a6-8354-347cb98fdb5b
if false; then
	# just ot cut/paste outputs below
 	curl --silent https://api.dandiarchive.org/api/dandisets/000108/versions/draft/assets/$asset/ | { echo -n "version="; jq -r '.digest["dandi:dandi-zarr-checksum"]'; }
 	curl --silent https://api.dandiarchive.org/api/dandisets/000108/versions/draft/assets/$asset/ | { echo -n "zarr="; jq -r '.contentUrl[1]' | sed -e 's,.*zarr/,,g' -e 's,/,,g'; }
	curl --silent https://api.dandiarchive.org/api/dandisets/000108/versions/draft/assets/$asset/ | { echo -n "path="; jq -r '.path' ; }
fi
# too big already
#zarr=04767811-3cea-43c8-956d-81da5e496f80
#version=WRONG!!
#path=sub-MITU01/ses-20211002h21m40s58/micr/sub-MITU01_ses-20211002h21m40s58_sample-37_stain-YO_run-1_chunk-10_SPIM.ome.zarr

# a little smaller
version=0395d0a3767524377b58da3945b3c063-48379--27115470
zarr=0d5b9be5-e626-4f6a-96da-b6b602954899
path=sub-U01hm15x/ses-20220731h17m24s47/micr/sub-U01hm15x_ses-20220731h17m24s47_sample-mEhmAD031x15R2_ABETA_stain-ABETA_run-1_chunk-1_SPIM.ome.zarr

# "Options" to be passed via env vars
: "${RCLONE_DANDI_WEBDAV:=DANDI-WEBDAV}"
: "${PART:=0/0/0/0/0/}"
if [ -z "${METHODS:-}" ]; then
	METHODS="get_aws_s3 get_s5cmd_s3 get_rclone_s3 get_rclone_dandisets get_rclone_zarr_manifest"
	# METHODS="get_s5cmd_s3 get_rclone_zarr_manifest"
fi
# autoscale (if does) by default
: "${CONCUR:=}"

# Custom format for /usr/bin/time
export TIME="TIME: %E real\t%U user\t%S sys\t%P CPU"

OUT="/tmp/zarr-bm"
rm -rf "${OUT:?}"/* || :


#set -x
# simple download directly from S3
get_aws_s3() {
	# TODO: check how to make it "auto scale" or to force to stick to defaults
	# for now just set to high 255 alike s5cmd does
	aws configure set default.s3.max_concurrent_requests "${CONCUR:-255}"
	/usr/bin/time chronic aws s3 --no-sign-request sync s3://dandiarchive/zarr/$zarr/"$PART" "$1"
}

my_rclone() {
	/usr/bin/time rclone copy ${CONCUR:+--transfers $CONCUR} "$1" "$2"
}

get_rclone_s3() {
	my_rclone DANDI-S3:dandiarchive/zarr/$zarr/"$PART" "$1"
}

get_rclone_dandisets() {
	my_rclone ${RCLONE_DANDI_WEBDAV}:dandisets/$ds/draft/$path/"$PART" "$1"
}

get_rclone_zarr_manifest() {
	my_rclone ${RCLONE_DANDI_WEBDAV}:zarrs/${zarr:0:3}/${zarr:3:3}/${zarr}/$version/"$PART" "$1"
}

get_s5cmd_s3() {
	# note: if we do not set --numworkers -- it would be 255
	# https://github.com/peak/s5cmd?tab=readme-ov-file#configuring-concurrency on howto control
	/usr/bin/time s5cmd --log error --no-sign-request ${CONCUR:+--numworkers $CONCUR} cp --source-region us-east-2 s3://dandiarchive/zarr/$zarr/"${PART}"* "$1/"
}

echo -n "Downloading part $PART within zarr $zarr "
[ -n "${CONCUR}" ] && echo "asking for up to $CONCUR processes" || echo "without specifying explicit number of processes"
echo "$METHODS" | tr " " "\n" | while read -r method; do
	out="$OUT/$method"
	echo "---------------"
	echo "$method:  $out"
	#set -x
	$method "$out"
	#set +x
	checksum=$(TQDM_DISABLE=1 zarrsum local "$out" | tail -n 1)
	if [ -z "$PART" ] && [ "$checksum" != "$version" ]; then
		echo "wrong checksum $checksum != $version"
	fi
	if [ -n "$PART" ]; then
		echo "checksum $checksum"
	fi
done
