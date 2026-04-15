function monai-bash(){
	docker run --gpus all --rm -ti --ipc=host --net=host projectmonai/monailabel:latest bash
}

function monai-app1(){
	_dir="${HOME}/23-monai-label/workspace"
	cd ${_dir}
	docker run --name monailabel --rm  -p 8000:8000 -e HF_ENDPOINT=https://hf-mirror.com  -v $(pwd)/radiology:/app/radiology   -v $(pwd)/Task09_Spleen:/app/Task09_Spleen  projectmonai/monailabel:latest   monailabel start_server --app /app/radiology --studies /app/Task09_Spleen/imagesTr --conf models deepedit
}

monai-app1;

echo "DIR:/home/eton/23-monai-label/workspace"

function origin_steps() {
# install MONAI Label
pip install monailabel

# download Radiology sample app to local directory
monailabel apps --name radiology --download --output .

# download Task 2 MSD dataset
monailabel datasets --download --name Task09_Spleen --output .

# start the Radiology app in MONAI label server
# and start annotating the downloaded images using deepedit model
monailabel start_server --app radiology --studies Task09_Spleen/imagesTr --conf models deepedit
}

function docker_steps(){

docker run --rm -v $(pwd):/workspace projectmonai/monailabel:latest monailabel apps --name radiology --download --output /workspace
#monailabel datasets --download --name Task09_Spleen --output .
docker run -d -p 8000:8000 -v $(pwd)/radiology:/app/radiology projectmonai/monailabel:latest monailabel start_server --app_dir /app/radiology --studies /app/data

docker run --rm -v $(pwd):/workspace projectmonai/monailabel:latest monailabel datasets --download --name Task09_Spleen --output /workspace

docker run -d \
  -p 8000:8000 \
  -v $(pwd)/radiology:/app/radiology \
  -v $(pwd)/Task09_Spleen:/app/Task09_Spleen \
  projectmonai/monailabel:latest \
  monailabel start_server --app /app/radiology --studies /app/Task09_Spleen/imagesTr --conf models deepedit

}

function in_docker(){
echo "Downloading resource: /app/radiology/model/pretrained_deepedit_dynunet.pt from https://github.com/Project-MONAI/MONAILabel/releases/download/pretrained/radiology_deepedit_dynunet_multilabel.pt"

}

function fix_hf_download_failed(){
  export HF_ENDPOINT=https://hf-mirror.com
  hf download facebook/sam2.1-hiera-tiny
  echo "~/.cache/huggingface/hub/models--facebook--sam2.1-hiera-tiny/"
}
