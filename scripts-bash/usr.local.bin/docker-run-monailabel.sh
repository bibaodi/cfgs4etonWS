function dicom_web_studies(){
	curl -v -u eton:Orthanc.133 http://192.168.0.241:8042/dicom-web/studies
}
function dicom_web_upload(){
	curl -u eton:Orthanc.133 -X POST -H "Expect:" -F "file=@/mnt/datas/42workspace/44-dicoms/carotid_plaqueNone_R-260327.dcm" http://192.168.0.241:8042/instances
}

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

function monai4ohif(){
	# monailabel start_server --app apps/radiology --studies http://127.0.0.1:8042/dicom-web --conf models deepedit
	#docker run --name monailabel --rm  -p 8000:8000  -v $(pwd)/radiology:/app/radiology -v $(pwd)/Task09_Spleen:/app/Task09_Spleen  projectmonai/monailabel:latest   monailabel start_server --app /app/radiology --studies http://192.168.0.241:8042/dicom-web --conf models deepedit
	#not work.docker run --name monailabel --rm  -p 8000:8000  -v $(pwd)/radiology:/app/radiology -v $(pwd)/Task09_Spleen:/app/Task09_Spleen  projectmonai/monailabel:latest   monailabel start_server --app /app/radiology --studies http://eton:Orthanc1.33@192.168.0.241:8042/dicom-web --conf models deepedit
	docker run --name monailabel --rm  -p 8000:8000  -v $(pwd)/radiology:/app/radiology -v $(pwd)/Task09_Spleen:/app/Task09_Spleen -e MONAI_LABEL_DICOMWEB_USERNAME="eton" -e MONAI_LABEL_DICOMWEB_PASSWORD="Orthanc.133" projectmonai/monailabel:latest   monailabel start_server --app /app/radiology --studies http://192.168.0.241:8042/dicom-web --conf models deepedit

	echo "then http://localhost:8000/ohif/ will show studies, can view images on web browser"

	echo "At this point OHIF can be used to annotate the data in the DICOM server via the MONAI Label server /ohif endpoint (e.g. via http://127.0.0.1:8000/ohif)."
}
