#!/bin/bash
### Mirror helm chart for airgapped installs
# Pulls a helm chart, all its dependanceis and required images.
# Add the helm repoistory manually via `helm repo add`
# then run the script, where the first parameter is the chart name (repo/name)
# the second parameter is the chart version (latest if empty)
# and the third parameter (if specified) is the values.yaml to use as a reference when pulling images.
# (Will only pull images which would actually be used in the coreespoding default/specified values.yaml)
# Additional parameters will be passed to skopeo (For example --src-tls-verify=false)
# REQUIRES: Skopeo, Helm, yq
set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

chart_name=$(echo $1 | tr / -)
mkdir -p ./$chart_name-mirror
cd ./$chart_name-mirror

echo "## Downloading chart images (according to default${3:+/provided ($3)} valuefile) ##"

for image in $(cd .. && helm template ${1:?Chart name is required.} ${2:+--version $2} ${3:+-f $3} | yq '..|.image? | select(.)' | grep -ve "^---$" | sort -u)
do
  resolved_name=$(skopeo inspect docker://$image --format "{{.Name}}@{{.Digest}}")
  output_dir=$(echo $resolved_name | sed "s|/|#|g")
  mkdir -p ./images/$output_dir
  echo "Downlading $image ($resolved_name) to ./images/$output_dir"
  skopeo copy --all --preserve-digests ${@:4} docker://$resolved_name dir:./images/$output_dir
done

echo "## Pulling chart $1 ##"
helm pull $1 ${2:+--version $2}

cat << 'EOF' > upload_images.sh
#!/bin/bash
### Uploads mirroed docker images to registry
# Specify registry as the only parameter to upload all files.
# optionally instead of the script you can do it manually if you want more control.
# Accepts additional args to pass to skopeo (for example --dest-tls-verify=false)
# REQUIRES: Skopeo

for image_dir in $(ls ./images)
do
  image=$(echo ${image_dir#*#} | sed "s|#|/|g")
  echo "Uploading to $1/$image (from images/$image_dir), original registry was ${image_dir%%#*}"
  skopeo copy --all ${@:2} dir:./images/$image_dir docker://${1:?Destination registry is required.}/$image
done

echo "== DONE =="
EOF
chmod +x upload_images.sh

echo "## Checking Downloaded Images ##"

for image_dir in $(ls ./images)
do
  image=$(echo $image_dir | sed "s|#|/|g")
  echo "Checking $image (from $image_dir)"
  skopeo copy -q --all dir:./images/$image_dir dir:./tmp || echo "Failed with $image. If you try to upload it to your registry it will *NOT* succeed."
  rm -r ./tmp || true
done

echo "## Creating tar archive ##"

cd ..
tar -cf "$chart_name-mirror.tar" ./$chart_name-mirror && rm -r ./$chart_name-mirror

echo "== DONE =="
echo "Transfer $chart_name-mirror.tar to your airgapped environment, then upload the helm chart and images (Optionally using upload_images.sh)"
