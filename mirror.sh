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

chart_name=$(echo $1 | tr / -)
mkdir -p ./$chart_name-mirror
cd ./$chart_name-mirror

for image in $(cd .. && helm template $1 ${2:+--version $2} ${3:+-f $3} | yq '..|.image? | select(.)' | grep -ve "^---$")
do
  mkdir -p ./images/$image
  echo Downlading $image
  skopeo copy --all ${@:4} docker://$image dir:./images/$image
done

echo Pulling $1 and dependanceis
helm pull $1 ${2:+--version $2}

cat << 'EOF' > upload_images.sh
#!/bin/bash
### Uploads mirroed docker images to registry
# Specify registry as the only parameter to upload all files.
# optionally instead of the script you can do it manually if you want more control.
# Accepts additional args to pass to skopeo (for example --dest-tls-verify=false)
# REQUIRES: Skopeo

for registry in $(ls ./images)
do
  for repo in $(ls ./images/$registry)
  do
    for image in $(ls ./images/$registry/$repo)
    do
      echo "Uploading $1/$repo/$image ($registry/$repo/$image)"
      skopeo copy --all ${@:2} dir:./images/$registry/$repo/$image docker://$1/$repo/$image
    done
  done
done

echo "== DONE =="
EOF
chmod +x upload_images.sh

cd ..
tar -cf "$chart_name-mirror.tar" ./$chart_name-mirror && rm -r ./$chart_name-mirror

echo "Transfer $chart_name-mirror.tar to your airgapped environment, then upload the helm chart and images (Optionally using upload_images.sh)"
echo "== DONE =="