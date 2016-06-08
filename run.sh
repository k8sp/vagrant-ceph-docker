# This is not a one-shot script, but an illustration of how to run a  demo of
# dockerized ceph in a Vagrant cluster. It's comprised of steps on different
# host and guests.
# See [http://ceph.com/planet/bootstrap-your-ceph-cluster-in-docker/] for
# details, and a video demo is also available at
# [https://www.youtube.com/watch?v=FUSTjTBA8f8]

# Step 0, git clone the coreos-vagrant repo, modify the Vagrant file such that
# each VM will have an additional block device for the ceph OSD use.
# Operate on the host
git clone https://github.com/coreos/coreos-vagrant.git
cd coreos-vagrant
git apply ../add-disk.patch
vagrant up

# Step 1, some preparations.
# Make directories on core-01, core-02, and core-03
docker pull ceph/daemon
sudo mkdir /var/lib/ceph

# On core-01, generate ssh keys, and share them with the vagrant's shared folder
# to the other two VMs
sudo su
ssh-keygen
cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
cp ~/.ssh/id_rsa ~/.ssh/id_rsa.pub /home/core/share
exit

# On core-02 and core-03, install the keys
sudo su
mkdir ~/.ssh
cp -i /home/core/share/id_rsa ~/.ssh/
cat /home/core/share/id_rsa.pub >> ~/.ssh/authorized_keys
exit

# Step 2, start a monitor daemon on each VM.
# On core-01, start the first monitor
docker run -d --net=host -v /etc/ceph:/etc/ceph -v /var/lib/ceph:/var/lib/ceph \
           -e MON_IP=$(ip addr | grep -o '172.17.8.10[[:digit:]]') \
           -e CEPH_PUBLIC_NETWORK=172.17.8.0/24 ceph/daemon mon
# On core-01, distribute the keyrings and other shared files to core-02 and
# core-03. This method shall be revised. A possible way is to use etcd2 to share
# these contents.
sudo scp -r /etc/ceph 172.17.8.102:/etc/
sudo scp -r /etc/ceph 172.17.8.103:/etc/
sudo scp -r /var/lib/ceph/bootstrap-{mds,osd,rgw} 172.17.8.102:/var/lib/ceph/
sudo scp -r /var/lib/ceph/bootstrap-{mds,osd,rgw} 172.17.8.103:/var/lib/ceph/

# Step 3, start a OSD daemon on each VM.
# On core-01, core-02, and core-03
docker run -d --net=host -v /etc/ceph:/etc/ceph -v /var/lib/ceph:/var/lib/ceph \
           -v /dev:/dev --privileged=true -e OSD_FORCE_ZAP=1 \
           -e OSD_DEVICE=/dev/sdb ceph/daemon osd_ceph_disk

# Step 4, bootstrap a MDS server
# On core-01
docker run -d --net=host -v /etc/ceph:/etc/ceph -v /var/lib/ceph:/var/lib/ceph \
           -e CEPHFS_CREATE=1 ceph/daemon mds

# Step 5, bootstrap a RadosGW
# On core-01
docker run -d -p 80:80 -v /etc/ceph:/etc/ceph -v /var/lib/ceph:/var/lib/ceph \
           ceph/daemon rgw
