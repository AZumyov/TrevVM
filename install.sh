set -e

git clone https://github.com/TrevorTesch/TrevVM
cd TrevVM
python3 -m pip install -r requirements.txt
sleep 2
python3 installer.py
docker build -t trevvm . --no-cache
cd ..

sudo apt update
sudo apt install -y jq

mkdir Save
cp -r TrevVM/root/config/* Save

json_file="TrevVM/options.json"
if jq ".enablekvm" "$json_file" | grep -q true; then
    docker run -d --name=TrevVM -e PUID=1000 -e PGID=1000 --device=/dev/kvm --security-opt seccomp=unconfined -e TZ=Etc/UTC -e SUBFOLDER=/ -e TITLE=TrevVM -p 3000:3000 --shm-size="2gb" -v $(pwd)/Save:/config --restart unless-stopped trevvm
else
    docker run -d --name=TrevVM -e PUID=1000 -e PGID=1000 --security-opt seccomp=unconfined -e TZ=Etc/UTC -e SUBFOLDER=/ -e TITLE=TrevVM -p 3000:3000 --shm-size="2gb" -v $(pwd)/Save:/config --restart unless-stopped trevvm
fi
clear
echo "If you are seeing this, you have sucessfully installed the VM. There may be an issue, if there is then tell me in the issues tab on github. Thanks!"
