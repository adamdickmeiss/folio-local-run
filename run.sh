#!/bin/bash

set -e
U=http://localhost:9130
T=testlib1
username=testing_admin
password=admin
curl -d"{\"id\":\"$T\"}" $U/_/proxy/tenants
curl -d'{"name":"DB_HOST","value":"localhost"}' $U/_/env
curl -d'{"name":"DB_PORT","value":"5432"}' $U/_/env
curl -d'{"name":"DB_USERNAME","value":"folio"}' $U/_/env
curl -d'{"name":"DB_PASSWORD","value":"folio"}' $U/_/env
curl -d'{"name":"DB_DATABASE","value":"folio_modules"}' $U/_/env
curl -d'{"name":"KAFKA_PORT","value":"9092"}' $U/_/env
curl -d'{"name":"KAFKA_HOST","value":"localhost"}' $U/_/env
curl -d"{\"name\":\"OKAPI_URL\",\"value\":\"$U\"}" $U/_/env
curl -d'{"name":"ELASTICSEARCH_URL","value":"http://localhost:9200"}' $U/_/env

# Set of modules that are necessary to bootstrap admin user
CORE_MODULES="mod-users mod-login mod-permissions mod-configuration"

# TEST_MODULES="mod-pubsub"

TEST_MODULES="mod-inventory-storage mod-password-validator mod-event-config mod-pubsub mod-circulation-storage mod-template-engine mod-email mod-sender mod-notify mod-users-bl mod-search"

compile_module() {
	local m=$1
	if test ! -d $m; then	
		git clone --recurse-submodules git@github.com:folio-org/$m

	fi
	if test ! -d $m; then
		echo "$m missing. git clone failed?"
		exit 1
	fi
	cd $m
	mvn -DskipTests -Dmaven.test.skip=true verify
	cd ..
}
register_module() {
	local m=$2
	echo "Register module $m"
	local md=$m/target/ModuleDescriptor.json
	if test ! -f $md; then
		compile_module $m
	fi
	if test ! -f $md; then
		echo "$md missing pwd=`pwd`"
		exit 1
	fi
	if test "$1" != "x"; then
		OPT=-HX-Okapi-Token:$1
	else
		OPT=""
	fi
	curl -s $OPT -d@$md $U/_/proxy/modules -o /dev/null
}

deploy_module() {
	local m=$2
	echo "Deploy module $m"
	if test "$1" != "x"; then
		OPT=-HX-Okapi-Token:$1
	else
		OPT=""
	fi
	local dd=$m/target/DeploymentDescriptor.json
	curl -s $OPT -d@$dd $U/_/deployment/modules -o /dev/null
}

deploy_modules() {
	for m in $2; do
		register_module $1 $m
	done
	for m in $2; do
		deploy_module $1 $m
	done
}

install_modules() {
	local j="["
	local sep=""
	for m in $3; do
		j="$j $sep {\"action\":\"$2\",\"id\":\"$m\"}"
		sep=","
	done
	j="$j]"
	if test "$1" != "x"; then
		OPT=-HX-Okapi-Token:$1
	else
		OPT=""
	fi
	curl -s $OPT "-d$j" "$U/_/proxy/tenants/$T/install?purge=true"
}

okapi_curl() {
	if test "$1" != "x"; then
		local OPT="-HX-Okapi-Token:$1"
	else
		local OPT="-HX-Okapi-Tenant:$T"
	fi
	shift
	curl -s $OPT -HContent-Type:application/json $*
}

make_adminuser() {
	local username=$2
	local password=$3
	
	uid=`uuidgen`
	okapi_curl $1 -XDELETE "$U/users?query=username%3D%3D$username"
	okapi_curl $1 -d"{\"username\":\"$username\",\"id\":\"$uid\",\"active\":true}" $U/users
	okapi_curl $1 -d"{\"username\":\"$username\",\"userId\":\"$uid\",\"password\":\"$password\"}" $U/authn/credentials
	puid=`uuidgen`
	okapi_curl $1 -d"{\"id\":\"$puid\",\"userId\":\"$uid\",\"permissions\":[\"okapi.all\",\"perms.all\",\"users.all\",\"login.item.post\",\"perms.users.assign.immutable\"]}" $U/perms/users
}

login_admin() {
	curl -s -Dheaders -HX-Okapi-Tenant:$T -HContent-Type:application/json -d"{\"username\":\"$username\",\"password\":\"$password\"}" $U/authn/login
token=`awk '/x-okapi-token/ {print $2}' <headers|tr -d '[:space:]'`
}

deploy_modules x "$CORE_MODULES"

deploy_modules x mod-authtoken

install_modules x enable "$CORE_MODULES"
install_modules x enable okapi

make_adminuser x $username $password

install_modules x enable mod-authtoken

login_admin

deploy_modules $token "$TEST_MODULES"

install_modules $token enable "$TEST_MODULES"

okapi_curl $token $U/perms/users/$puid/permissions -d'{"permissionName":"users-bl.all"}'

login_admin

okapi_curl $token $U/bl-users/password-reset/link -d"{\"userId\":\"$uid\"}" -o reset.json

token2=`jq -r '.link' < reset.json |sed -e 's@.*reset-password/@@'`

curl -s -HX-Okapi-Token:$token2 $U/bl-users/password-reset/validate -d'{}'

