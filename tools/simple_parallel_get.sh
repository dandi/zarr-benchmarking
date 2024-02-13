#!/bin/bash

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

part=${PART:-0/0/0/0/0/}
: ${CONCUR:=20}

OUT="/tmp/zarr-bm"
rm -rf "$OUT"/* || :


#set -x
# simple download directly from S3
get_aws_s3() {
	aws configure set default.s3.max_concurrent_requests $CONCUR
	/usr/bin/time chronic aws s3 --no-sign-request sync s3://dandiarchive/zarr/$zarr/$part "$1"
}

get_rclone_s3() {
	aws configure set default.s3.max_concurrent_requests $CONCUR
	/usr/bin/time rclone sync --transfers $CONCUR DANDI-S3:dandiarchive/zarr/$zarr/$part "$1"
}

get_rclone_dandisets() {
	/usr/bin/time rclone sync --transfers $CONCUR DANDI-WEBDAV:dandisets/$ds/draft/$path/$part "$1"
}

get_rclone_zarr_manifest() {
	/usr/bin/time rclone sync --transfers $CONCUR DANDI-WEBDAV:zarrs/${zarr:0:3}/${zarr:3:3}/${zarr}/$version/$part "$1"
}

echo "Downloading part $part within zarr $zarr asking for up to $CONCUR processes"
#for method in get_aws_s3 get_rclone_s3 get_rclone_dandisets get_rclone_zarr_manifest; do
for method in get_rclone_zarr_manifest; do
	out="$OUT/$method"
	echo "---------------"
	echo "$method:  $out"
	$method "$out"
	checksum=$(TQDM_DISABLE=1 zarrsum local "$out" | tail -n 1)
	if [ -z "$part" ] && [ $checksum != "$version" ]; then
		echo "wrong checksum $checksum != $version"
	fi
	if [ -n "$part" ]; then
		echo "checksum $checksum"
	fi
done
