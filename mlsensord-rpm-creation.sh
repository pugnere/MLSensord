#/bin/sh
# 
# ce script permet de creer un RPM pour MLSensor
#

export ARCH=`uname -m`
export generationdir=$(basename $(mktemp -d -p .))
export mlsensor_path=usr/local
export MLSensorSPECfile="MLSensor.spec"
export RPMBUILDDIR="$HOME/rpmbuild"

# URL where to download the MLSensor
url_file_ml_tgz=http://monalisa.cern.ch/MLSensor/MLSensor.tgz
# URL where to download the deploy_mlsensor configuration script
url_file_deploy_mlsensor=https://raw.githubusercontent.com/adriansev/alicexrd/master/deploy_mlsensor

# verification de rpmbuild et installation si necessaire
if [ ! -x "/usr/bin/rpmbuild" ]
then
  echo "/bin/rpmbuild est absent, installation du rpm rpm-build"
  yum install -y rpm-build
fi

if [ ! -x "/usr/bin/curl" ]
then
  echo "/usr/bin/curl est absent, installation du rpm curl"
  yum install -y curl
fi

OLD_PWD=$PWD

# Creation de l'arborescence pour les binaires de MLSensor
cd $generationdir

# download the MLSensor soft
mkdir -p $mlsensor_path
## first download the MLSensor software
rm -rf /tmp/MLSensor.tgz
echo "Downloading $url_file_ml_tgz ..."
/usr/bin/curl -fsSL -o /tmp/MLSensor.tgz $url_file_ml_tgz || { echo "Could not download MLSensor.tgz" && exit 1; }
echo "Unarchiving MLSensor.tgz ..."
(cd $mlsensor_path ; tar xzf /tmp/MLSensor.tgz)

echo "Downloading $url_file_deploy_mlsensor ..."
/usr/bin/curl -fsSL -o $mlsensor_path/MLSensor/deploy_mlsensor $url_file_deploy_mlsensor
chmod +x $mlsensor_path/MLSensor/deploy_mlsensor

echo "Downloading the sysconfig config file ..."
mkdir -p etc/sysconfig
mlsensord_sysconfig_script=etc/sysconfig/mlsensord
/usr/bin/curl -fsSLk -o $mlsensord_sysconfig_script https://www.ipnl.in2p3.fr/perso/pugnere/alice/mlsensord-sysconfig
#cp mlsensord-sysconfig $mlsensord_sysconfig_script
if [ ! -e $mlsensord_sysconfig_script ]; then
	echo "Problem : the file $mlsensord_sysconfig_script is not there."
	exit 1;
fi
chmod +x $mlsensord_sysconfig_script

mkdir -p etc/rc.d/init.d
echo "Downloading the sysinit file ..."
mlsensord_sysinit_script=etc/rc.d/init.d/MLSensord
/usr/bin/curl -fsSLk -o $mlsensord_sysinit_script  https://www.ipnl.in2p3.fr/perso/pugnere/alice/MLSensord-sysinit
# curl -fsSLk https://raw.githubusercontent.com/adriansev/alicexrd/master/deploy_alicexrd 
#cp MLSensord-sysinit $mlsensord_sysinit_script
if [ ! -e $mlsensord_sysinit_script ]; then
	echo "Problem : the file $mlsensord_sysinit_script is not there."
	exit 1
fi
chmod +x $mlsensord_sysinit_script

tmpMLsensor_VERS=$(${mlsensor_path}/MLSensor/bin/MLSensor version)
export MLsensor_VERS=$(echo $tmpMLsensor_VERS|sed -e "s/-.*//")
export MLsensor_VERS_UPDATE=$(echo $tmpMLsensor_VERS|sed -e "s/.*-//")

mkdir -p $RPMBUILDDIR/SOURCES

echo "Building $RPMBUILDDIR/SOURCES/MLSensor.tar.gz ..."
rm -f $RPMBUILDDIR/SOURCES/MLSensor.tar.gz
tar czf $RPMBUILDDIR/SOURCES/MLSensor.tar.gz *

cd $OLD_PWD

echo "Spec file creation ..."
cat > $MLSensorSPECfile << EOF_SPEC
Summary: MonaLisa Sensor for ALICE xrootd storage
Name: MLSensor
Version: $MLsensor_VERS
Release: $MLsensor_VERS_UPDATE
License: LGPLv3+
Group: Applications/Internet
Source: MLSensor.tar.gz
URL: http://monalisa.cern.ch/MLSensor/MLSensor.tgz
Packager: The LHC ALICE Project
AutoReqProv: no
Requires: java >= 1:1.6.0, xrootd-server >= 1:4.0.0

%description
This is the MonALISA sensor for ALICE xrootd storage

%prep
%setup -c MLSensor

%install
%__cp -a . "\${RPM_BUILD_ROOT-/}"

%clean
[ "\$RPM_BUILD_ROOT" != "/" ] && rm -rf "\$RPM_BUILD_ROOT"

%pre
# pre-install
# 
## if MLSensor in place, try to stop it
#MLSENSOR_FOUND_HOME=\$(ps -C java -o args= | awk '/MLSENSOR_HOME/ { for ( x = 1; x <= NF; x++ ) { if (\$x ~ "-DMLSENSOR_HOME"){ n=split(\$x,home,"="); print home[n];}}}')
#[[ -n "\${MLSENSOR_FOUND_HOME}" ]] && service MLSensor stop

%post
# post-install
# 
# Add the MLSensor service
chkconfig --add MLSensor

# Turn on the MLSensor service
chkconfig MLSensor on

# TODO : first of all, need to check if xrootd server is already running

grep "cluster.name=MLSensor" /${mlsensor_path}/MLSensor/etc/mlsensor.properties > /dev/null
if [[ $? == 0 ]]; then
	echo "Before starting MLSensor, you need to configure :"
	echo "  - the file /etc/sysconfig/mlsensor"
	echo "  - /${mlsensor_path}/MLSensor/etc/mlsensor.properties"
	echo "  - /${mlsensor_path}/MLSensor/etc/mlsensor_env"
	echo 
	echo "You can use the /${mlsensor_path}/MLSensor/deploy_mlsensor script"
	
else
	# If MLSensor isn't running, start it
	service MLSensor start
fi

%preun
# pre-uninstall
# 
# If we're uninstalling the last copy of MLSensor...
# if [ $1 -eq 0 ] ; then
#    MLSENSOR_FOUND_HOME=\$(ps -C java -o args= | awk '/MLSENSOR_HOME/ { for ( x = 1; x <= NF; x++ ) { if (\$x ~ "-DMLSENSOR_HOME"){ n=split(\$x,home,"="); print home[n];}}}')
#    [[ -n "\${MLSENSOR_FOUND_HOME}" ]] && service MLSensor stop
# 
#   # Remove the MLSensor service
#   chkconfig --del MLSensor
# fi
service MLSensor stop
chkconfig --del MLSensor

%postun
echo "MLSensor removed !"

%changelog

%files
EOF_SPEC


tar tzvf $RPMBUILDDIR/SOURCES/MLSensor.tar.gz | while read line
do
	# cas speciaux
	# %readme /samples/util/README      
	# %dir %{_mandir}/man1/
	# %doc %{_mandir}/man1/mmputacl.1.gz
	# %config /src/config/def.mk.proto

	# chaque ligne est de la forme
	# -r--r--r-- root/root 355743 2013-11-06 09:10 /messages/mmfs.cat
	droits=`echo $line|awk '{print $1}'`
	user=`echo $line|awk '{print $2}'`
	fichier=`echo $line|awk '{print $6}'`
	# utilisation d'une regex en bash
	if [[ "$droits" =~ d.* ]]
	then 
		echo -n ""
		# si c'est un repertoire
		#echo "%dir /$fichier" >> $MLSensorSPECfile
	else
		# si c'est un fichier
		case "$fichier" in
			etc/rc.d/init.d/MLSensor |	etc/sysconfig/mlsensor | */MLSensor/etc/mlsensor.properties |	*/MLSensor/etc/mlsensor_env )
				echo "%config(noreplace) /$fichier" >> $MLSensorSPECfile
				;;
			* ) echo "/$fichier" >> $MLSensorSPECfile ;;
		esac
	fi
done

echo "" >> $MLSensorSPECfile

rm -f $RPMBUILDDIR/RPMS/$ARCH/MLSensor-${tmpMLsensor_VERS}.$ARCH.rpm
echo "RPM file creation ..."
rpmbuild -bb --quiet $MLSensorSPECfile

rm -rf $generationdir $MLSensorSPECfile

if [ -f $RPMBUILDDIR/RPMS/$ARCH/MLSensor-${tmpMLsensor_VERS}.$ARCH.rpm ]; then
	echo "The RPM file is $RPMBUILDDIR/RPMS/$ARCH/MLSensor-${tmpMLsensor_VERS}.$ARCH.rpm"
else
	echo "Error, the RPM file is not built !"
fi

